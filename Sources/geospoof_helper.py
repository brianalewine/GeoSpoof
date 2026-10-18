#!/usr/bin/env python3
"""GeoSpoof device helper (no Xcode needed).

Protocol: one JSON object per line on stdin, one JSON reply per line on stdout.
    request : {"id": 1, "cmd": "set", "udid": "...", "latitude": 38.05, "longitude": -78.49}
    reply   : {"id": 1, "ok": true, "result": {...}}  or  {"id": 1, "ok": false, "error": "...", "code": "..."}
    event   : {"event": "progress", "message": "..."}   (no id; safe to ignore)

Commands: hello, discover, verify, set, clear, status, quit.

iOS drops a simulated location the moment the connection that set it closes, so this process
keeps one session open from `set` until `clear`, `quit`, EOF on stdin, or SIGTERM/SIGINT.
After a disconnect, reconnect and explicitly clear to confirm restoration.

Manual test (no app needed):
    python Sources/geospoof_helper.py --demo            # first iPhone found
    python Sources/geospoof_helper.py --demo <UDID>
"""
from __future__ import annotations

import asyncio
import json
import math
import os
import signal
import sys
from contextlib import AsyncExitStack
from pathlib import Path
from typing import Any, Optional

from geospoof_security import initialize_storage, install

install()
PROTOCOL_VERSION = 1


from urllib.error import URLError  # noqa: E402

from pymobiledevice3 import usbmux  # noqa: E402
from pymobiledevice3.exceptions import (  # noqa: E402
    AlreadyMountedError,
    ConnectionFailedToUsbmuxdError,
    DeveloperDiskImageNotFoundError,
    DeveloperModeIsNotEnabledError,
    NoDeviceConnectedError,
    NotPairedError,
    NotTrustedError,
    PairingError,
    TSSError,
)
from pymobiledevice3.lockdown import create_using_usbmux  # noqa: E402
from pymobiledevice3.remote.userspace_tunnel import UserspaceRsdTunnel  # noqa: E402
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider  # noqa: E402
from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation  # noqa: E402
from pymobiledevice3.services.mobile_image_mounter import auto_mount  # noqa: E402


class HelperError(Exception):
    def __init__(self, message: str, code: str = "error") -> None:
        super().__init__(message)
        self.message = message
        self.code = code


def describe(error: BaseException) -> HelperError:
    """Turn a library exception into a short message a person can act on."""
    if isinstance(error, HelperError):
        return error
    if isinstance(error, DeveloperModeIsNotEnabledError):
        return HelperError("Turn on Developer Mode on your iPhone: Settings > Privacy & Security > Developer Mode.", "developer_mode")
    if isinstance(error, (NotTrustedError, NotPairedError, PairingError)):
        return HelperError("Unlock your iPhone and tap Trust, then try again.", "not_trusted")
    if isinstance(error, NoDeviceConnectedError):
        return HelperError("Your iPhone wasn't found. Connect it by USB, or keep it unlocked on the same Wi-Fi.", "no_device")
    if isinstance(error, ConnectionFailedToUsbmuxdError):
        return HelperError("Couldn't reach this Mac's device service. Reconnect the iPhone and try again.", "usbmuxd")
    if isinstance(error, (TSSError, URLError)):
        return HelperError("Couldn't reach Apple to prepare your iPhone for the first time. Check your internet connection.", "network")
    if isinstance(error, DeveloperDiskImageNotFoundError):
        return HelperError("No developer support image is available for this iOS version yet.", "no_image")
    if isinstance(error, PermissionError):
        return HelperError(f"Couldn't write to {error.filename}. Check the folder's permissions.", "permission")
    if isinstance(error, (asyncio.TimeoutError, TimeoutError)):
        return HelperError("The iPhone did not respond. Unlock it and check the connection.", "timeout")
    text = str(error).strip()
    return HelperError(text or type(error).__name__, "error")


class Session:
    """An open tunnel + location-simulation channel for one iPhone."""

    def __init__(self, udid: str, transport: str, stack: AsyncExitStack, tunnel: UserspaceRsdTunnel,
                 location: LocationSimulation) -> None:
        self.udid = udid
        self.transport = transport
        self.stack = stack
        self.tunnel = tunnel
        self.location = location
        self.coordinate: Optional[tuple[float, float]] = None

    @property
    def alive(self) -> bool:
        # The tunnel tears itself down (rsd becomes None) when the device connection is lost.
        return self.tunnel.rsd is not None


class Helper:
    def __init__(self, emit) -> None:
        self.emit = emit
        self.session: Optional[Session] = None

    # ---- devices -------------------------------------------------------------------------

    async def _mux_device(self, udid: str):
        device = await usbmux.select_device(udid)
        if device is None:
            raise HelperError("Your iPhone wasn't found. Connect it by USB, or keep it unlocked on the same Wi-Fi.", "no_device")
        return device

    async def discover(self, _req: dict) -> dict:
        by_udid: dict[str, list] = {}
        for device in await usbmux.list_devices():
            by_udid.setdefault(device.serial, []).append(device)
        phones = []
        for udid, devices in by_udid.items():
            device = next((d for d in devices if d.is_usb), devices[0])
            info: dict[str, Any] = {"id": udid, "name": "iPhone", "productType": "", "productVersion": "",
                                    "transport": "USB" if device.is_usb else "Wi-Fi"}
            try:
                lockdown = await asyncio.wait_for(
                    create_using_usbmux(udid, autopair=False, connection_type=device.connection_type), 8)
                try:
                    short = lockdown.short_info
                    if short.get("DeviceClass") not in (None, "iPhone"):
                        continue
                    info["name"] = short.get("DeviceName", "iPhone")
                    info["productType"] = short.get("ProductType", "")
                    info["productVersion"] = short.get("ProductVersion", "")
                finally:
                    await lockdown.close()
            except Exception as error:  # still list it; verify will explain what is wrong
                info["warning"] = describe(error).message
            phones.append(info)
        return {"devices": phones}

    async def verify(self, req: dict) -> dict:
        udid = req["udid"]
        device = await self._mux_device(udid)
        try:
            lockdown = await asyncio.wait_for(
                create_using_usbmux(udid, autopair=True, connection_type=device.connection_type), 10)
        except Exception as error:
            raise describe(error)
        try:
            # Enable network discovery during the initial trusted USB connection.
            if device.is_usb:
                await lockdown.set_enable_wifi_connections(True)
            developer_mode: Optional[bool] = None
            try:
                developer_mode = await lockdown.get_developer_mode_status()
            except Exception:
                pass
        finally:
            await lockdown.close()
        if developer_mode is False:
            raise HelperError("Turn on Developer Mode on your iPhone: Settings > Privacy & Security > Developer Mode.", "developer_mode")
        return {"transport": "USB" if device.is_usb else "Wi-Fi", "developerMode": developer_mode}

    # ---- session -------------------------------------------------------------------------

    async def _open_session(self, udid: str) -> Session:
        device = await self._mux_device(udid)
        stack = AsyncExitStack()
        try:
            tunnel = UserspaceRsdTunnel(serial=udid, autopair=True)
            rsd = await stack.enter_async_context(tunnel)
            self.emit({"event": "progress", "message": "Checking developer support on the iPhone"})
            try:
                await auto_mount(rsd)  # no-op when already installed; first time needs internet
            except AlreadyMountedError:
                pass
            # Newly installed developer services can take time to register.
            for attempt in range(7):
                channel = AsyncExitStack()
                try:
                    dvt = await channel.enter_async_context(DvtProvider(rsd))
                    location = await channel.enter_async_context(LocationSimulation(dvt))
                    stack.push_async_callback(channel.aclose)
                    break
                except Exception:
                    await self._aclose(channel)
                    if attempt == 6:
                        raise
                    self.emit({"event": "progress", "message": "Waiting for iPhone developer services"})
                    await asyncio.sleep(5)
        except BaseException as error:
            await self._aclose(stack)
            if isinstance(error, (asyncio.CancelledError, KeyboardInterrupt)):
                raise
            raise describe(error)
        return Session(udid, "USB" if device.is_usb else "Wi-Fi", stack, tunnel, location)

    @staticmethod
    async def _aclose(stack: AsyncExitStack) -> None:
        try:
            await asyncio.wait_for(stack.aclose(), 8)
        except BaseException:
            pass

    async def close_session(self) -> None:
        session, self.session = self.session, None
        if session is not None:
            await self._aclose(session.stack)

    async def set(self, req: dict) -> dict:
        udid = req["udid"]
        latitude, longitude = float(req["latitude"]), float(req["longitude"])
        if not (math.isfinite(latitude) and math.isfinite(longitude)
                and -90 <= latitude <= 90 and -180 <= longitude <= 180):
            raise HelperError("Choose a valid location on the map.", "bad_coordinate")
        if self.session is not None and (self.session.udid != udid or not self.session.alive):
            await self.close_session()
        reused = self.session is not None
        if self.session is None:
            self.session = await self._open_session(udid)
        try:
            await self.session.location.set(latitude, longitude)
        except Exception as error:
            await self.close_session()
            if not reused:
                raise describe(error)
            self.session = await self._open_session(udid)  # the old session had gone stale; retry once
            try:
                await self.session.location.set(latitude, longitude)
            except Exception as retry_error:
                await self.close_session()
                raise describe(retry_error)
        self.session.coordinate = (latitude, longitude)
        return {"transport": self.session.transport}

    async def clear(self, req: dict) -> dict:
        session = self.session
        udid = req.get("udid")
        if session is not None and udid and session.udid != udid:
            raise HelperError("The active session belongs to a different iPhone.", "wrong_device")
        if session is None or not session.alive:
            # Explicitly clear on the requested phone after reconnect/relaunch.
            # A missing channel is not proof that the phone has restored real GPS.
            await self.close_session()
            if not udid:
                return {"wasActive": False}
            self.session = session = await self._open_session(udid)
        if not session.alive:
            await self.close_session()
            raise HelperError("The iPhone disconnected before reset. Reconnect and try again.", "disconnected")
        try:
            await session.location.clear()
        except Exception as error:
            await self.close_session()
            raise describe(error)
        await self.close_session()
        return {"wasActive": True}

    async def status(self, _req: dict) -> dict:
        session = self.session
        if session is not None and not session.alive:
            await self.close_session()
            session = None
        if session is None:
            return {"active": False}
        latitude, longitude = session.coordinate or (None, None)
        return {"active": True, "udid": session.udid, "transport": session.transport,
                "latitude": latitude, "longitude": longitude}

    async def hello(self, _req: dict) -> dict:
        try:
            from pymobiledevice3._version import __version__ as pmd_version
        except Exception:
            pmd_version = "unknown"
        return {"protocol": PROTOCOL_VERSION, "pymobiledevice3": pmd_version, "python": sys.version.split()[0]}

    async def quit(self, _req: dict) -> dict:
        await self.close_session()
        return {}

    async def handle(self, req: dict) -> dict:
        if not isinstance(req, dict):
            raise HelperError("Expected a request object", "bad_request")
        command = req.get("cmd")
        if not isinstance(command, str):
            raise HelperError("Expected a command name", "bad_request")
        if command in ("verify", "set", "clear"):
            udid = req.get("udid")
            if not isinstance(udid, str) or not 1 <= len(udid) <= 128 or any(
                char not in "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-" for char in udid
            ):
                raise HelperError("Invalid device identifier", "bad_request")
        handler = {"hello": self.hello, "discover": self.discover, "verify": self.verify, "set": self.set,
                   "clear": self.clear, "status": self.status, "quit": self.quit}.get(command)
        if handler is None:
            raise HelperError(f"Unknown command: {command}", "bad_request")
        return await handler(req)


async def serve() -> None:
    loop = asyncio.get_running_loop()
    # Keep stdout for the protocol only; anything else that prints goes to stderr.
    out = os.fdopen(os.dup(1), "w", buffering=1, encoding="utf-8")
    os.dup2(2, 1)

    def emit(obj: dict) -> None:
        out.write(json.dumps(obj, separators=(",", ":"), allow_nan=False) + "\n")

    helper = Helper(emit)
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        loop.add_signal_handler(sig, stop.set)

    reader = asyncio.StreamReader(limit=1 << 20)
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    stop_wait = asyncio.create_task(stop.wait())
    quitting = False
    try:
        while not quitting:
            read = asyncio.create_task(reader.readline())
            done, _ = await asyncio.wait({read, stop_wait}, return_when=asyncio.FIRST_COMPLETED)
            if read not in done:
                read.cancel()
                break
            line = read.result()
            if not line:
                break  # the app closed our stdin
            try:
                req = json.loads(line)
                request_id = req.get("id")
            except (ValueError, AttributeError):
                emit({"ok": False, "error": "Malformed request", "code": "bad_request"})
                continue
            work = asyncio.create_task(helper.handle(req))
            done, _ = await asyncio.wait({work, stop_wait}, return_when=asyncio.FIRST_COMPLETED)
            if work not in done:
                work.cancel()
                await asyncio.gather(work, return_exceptions=True)
                break
            try:
                emit({"id": request_id, "ok": True, "result": work.result()})
            except Exception as error:
                problem = describe(error)
                emit({"id": request_id, "ok": False, "error": problem.message, "code": problem.code})
            quitting = req.get("cmd") == "quit"
    finally:
        stop_wait.cancel()
        await asyncio.gather(stop_wait, return_exceptions=True)
        await helper.close_session()


async def demo(udid: Optional[str]) -> None:
    """Interactive check of the whole path: discover, verify, set Barracks Road, wait, clear."""
    helper = Helper(lambda obj: print("  ...", obj.get("message", obj)))
    print("hello:", await helper.hello({}))
    devices = (await helper.discover({}))["devices"]
    print("devices:", json.dumps(devices, indent=2))
    if udid is None:
        if not devices:
            print("No iPhone found.")
            return
        udid = devices[0]["id"]
    try:
        print("verify:", await helper.verify({"udid": udid}))
        result = await helper.set({"udid": udid, "latitude": 38.0544087, "longitude": -78.499656})
        print(f"set: {result}\nCheck Apple Maps on the phone. (transport above is how this Mac reached it)")
        await asyncio.get_running_loop().run_in_executor(None, input, "Press Return to clear the location... ")
        print("status:", await helper.status({}))
        print("clear:", await helper.clear({"udid": udid}))
    except Exception as error:
        problem = describe(error)
        print(f"FAILED [{problem.code}]: {problem.message}")
    finally:
        await helper.close_session()


async def check_connection() -> None:
    """Read-only diagnostic usable from the packaged executable."""
    import plistlib
    from geospoof_security import signing_request
    await asyncio.to_thread(signing_request, plistlib.dumps({}))
    print("PASS: verified HTTPS signing endpoint", flush=True)
    helper = Helper(lambda event: print(event.get("message", ""), flush=True))
    devices = (await helper.discover({}))["devices"]
    if len(devices) != 1:
        raise HelperError("Connect exactly one iPhone for this diagnostic.", "no_device")
    try:
        helper.session = await helper._open_session(devices[0]["id"])
        print("PASS: private Unix relay and developer channel over " + devices[0]["transport"], flush=True)
    finally:
        await helper.close_session()


if __name__ == "__main__":
    initialize_storage()
    if sys.argv[1:] == ["--check-connection"]:
        asyncio.run(asyncio.wait_for(check_connection(), 120))
    elif "--demo" in sys.argv:
        rest = [a for a in sys.argv[1:] if a != "--demo"]
        asyncio.run(demo(rest[0] if rest else None))
    else:
        asyncio.run(serve())
