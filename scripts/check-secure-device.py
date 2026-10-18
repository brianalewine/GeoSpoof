"""Read-only live connection check: opens developer services, never sets a location."""
import asyncio
import plistlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Sources"))
from geospoof_helper import Helper
from geospoof_security import initialize_storage, signing_request

async def main():
    initialize_storage()
    # No phone identifiers in this probe; validates HTTPS reachability and CA validation.
    reply = await asyncio.to_thread(signing_request, plistlib.dumps({}))
    print("PASS: HTTPS signing endpoint reached with certificate verification", flush=True)
    helper = Helper(lambda event: print(event.get("message", ""), flush=True))
    devices = (await helper.discover({}))["devices"]
    if len(devices) != 1:
        print("SKIP: live device check requires exactly one connected phone")
        return
    try:
        helper.session = await helper._open_session(devices[0]["id"])
        print("PASS: private Unix relay and developer channel connected over " + devices[0]["transport"], flush=True)
    finally:
        await helper.close_session()

asyncio.run(asyncio.wait_for(main(), 120))
