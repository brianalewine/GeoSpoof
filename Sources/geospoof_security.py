"""Application-scoped security adapters for the pinned pymobiledevice3 release.

These adapters intentionally fail closed. Re-test them when updating pymobiledevice3.
They do not alter the installed library or other processes.
"""
from __future__ import annotations

import asyncio
import os
import plistlib
import shutil
import ssl
import tempfile
from functools import partial
from importlib.metadata import version
from pathlib import Path

import requests
import truststore

TSS_URL = "https://gs.apple.com/TSS/controller?action=2"
MAX_TSS_RESPONSE = 8 * 1024 * 1024


def private_directory(path: Path) -> Path:
    """Refuse a substituted leaf or another user's directory before changing permissions."""
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        if info.st_uid != os.getuid():
            raise PermissionError("GeoSpoof storage must belong to the current user")
        os.fchmod(fd, 0o700)
    finally:
        os.close(fd)
    return path


def initialize_storage() -> None:
    if os.geteuid() == 0:
        raise PermissionError("Run GeoSpoof as your normal user, not with sudo")
    os.umask(0o077)
    from pymobiledevice3 import common
    # Keep credentials separate from shared CLI caches. Apple's usbmux pairing records
    # remain available, so existing trusted USB/Wi-Fi phones need not be unpaired.
    root = private_directory(Path.home() / "Library/Application Support/GeoSpoof")
    common._HOMEFOLDER = private_directory(root / "device-support")


class SystemTrustAdapter(requests.adapters.HTTPAdapter):
    """Use macOS trust evaluation for Apple's private PKI, with hostname verification."""
    def build_connection_pool_key_attributes(self, request, verify, cert=None):
        if verify is not True:
            raise ValueError("TLS verification cannot be disabled")
        host, options = super().build_connection_pool_key_attributes(request, verify, cert)
        options["ssl_context"] = truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        return host, options


def signing_request(payload: bytes) -> bytes:
    # Never inherit proxy, .netrc, or CA overrides from the launching shell.
    with requests.Session() as session:
        session.trust_env = False
        session.mount("https://gs.apple.com/", SystemTrustAdapter())
        with session.post(
            TSS_URL, data=payload,
            headers={"Content-Type": "text/xml; charset=utf-8", "User-Agent": "GeoSpoof/1"},
            verify=True, timeout=(10, 30), allow_redirects=False, stream=True,
        ) as response:
            if response.status_code != 200:
                raise requests.HTTPError("Apple signing service returned an unexpected HTTP status")
            result = bytearray()
            for chunk in response.iter_content(64 * 1024):
                result.extend(chunk)
                if len(result) > MAX_TSS_RESPONSE:
                    raise ValueError("Apple signing response exceeded the size limit")
            return bytes(result)


async def secure_send_receive(self):
    from pymobiledevice3.exceptions import TSSError
    from pymobiledevice3.restore.tss import TSSResponse
    content = await asyncio.to_thread(signing_request, plistlib.dumps(self._request))
    header, separator, payload = content.partition(b"REQUEST_STRING=")
    fields = dict(part.split(b"=", 1) for part in header.rstrip(b"&").split(b"&") if b"=" in part)
    if not separator or fields.get(b"MESSAGE") != b"SUCCESS":
        raise TSSError("Apple did not return a successful signing response")
    return TSSResponse(plistlib.loads(payload))


async def unix_only_enter(self):
    from pymobiledevice3.remote.userspace_tunnel import _bind_listener
    # No TCP fallback: a bind failure must not expose the device relay to other users.
    self._socket_dir = tempfile.mkdtemp(prefix="geospoof-relay-")
    path = str(Path(self._socket_dir) / "relay.sock")
    try:
        self._server = await _bind_listener(asyncio.start_unix_server(self._handle, path))
        self._opener = partial(asyncio.open_unix_connection, path)
        return self
    except BaseException:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
        shutil.rmtree(self._socket_dir)
        self._socket_dir = None
        raise


def install() -> None:
    if version("pymobiledevice3") != "11.32.0":
        raise RuntimeError("Revalidate GeoSpoof security adapters for this pymobiledevice3 version")
    from pymobiledevice3.restore import tss
    from pymobiledevice3.remote import userspace_tunnel
    tss.TSS_CONTROLLER_ACTION_URL = TSS_URL
    tss.TSSRequest.send_receive = secure_send_receive
    userspace_tunnel.UserspaceDialPlane.__aenter__ = unix_only_enter
