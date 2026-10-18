"""Live reset timing; sets the known test coordinate, then explicitly clears it."""
import asyncio
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Sources"))
from geospoof_helper import Helper

started = time.perf_counter()
def log(label, **fields):
    print(json.dumps(dict(elapsed=round(time.perf_counter() - started, 3), stage=label, **fields)), flush=True)

async def main():
    helper = Helper(lambda event: log("event", message=event.get("message")))
    devices = (await helper.discover({}))["devices"]
    if len(devices) != 1:
        raise RuntimeError("Expected exactly one phone; select explicitly before testing.")
    udid = devices[0]["id"]
    log("device", transport=devices[0]["transport"])
    try:
        for delay in (0, 12):
            await helper.set(dict(udid=udid, latitude=38.0544087, longitude=-78.499656))
            log("location_set", hold_connection_after_clear=delay)
            await asyncio.sleep(3)
            session = helper.session
            before = time.perf_counter()
            log("clear_start")
            await session.location.clear()
            log("clear_sent", seconds=round(time.perf_counter() - before, 4))
            if delay:
                await asyncio.sleep(delay)
                log("connection_hold_finished")
            before = time.perf_counter()
            await helper.close_session()
            log("cleanup_finished", seconds=round(time.perf_counter() - before, 4))
            await asyncio.sleep(10)
    finally:
        if helper.session is not None:
            try:
                await helper.session.location.clear()
            finally:
                await helper.close_session()
    log("finished")

asyncio.run(asyncio.wait_for(main(), 150))
