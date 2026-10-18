#!/usr/bin/env python3
"""Stand-in for Sources/geospoof_helper.py: same JSON-lines protocol, no phone. Used by scripts/test.sh."""
import json
import sys

active = None
for line in sys.stdin:
    try:
        req = json.loads(line)
    except ValueError:
        continue
    cmd, udid, ok, result, error = req.get("cmd"), req.get("udid"), True, {}, None
    if cmd == "hello":
        result = {"protocol": 1}
    elif cmd == "discover":
        result = {"devices": [{"id": "stub-phone", "name": "Stub iPhone", "productType": "iPhone14,2",
                               "productVersion": "27.2", "transport": "USB"}]}
    elif cmd in ("verify", "set") and udid != "stub-phone":
        ok, error = False, "Your iPhone wasn't found."
    elif cmd == "verify":
        result = {"transport": "USB"}
    elif cmd == "set":
        active = udid
        print(json.dumps({"event": "progress", "message": "stub"}), flush=True)  # events have no id
    elif cmd == "clear":
        result, active = {"wasActive": active is not None}, None
    elif cmd == "status":
        result = {"active": active is not None, "udid": active}
    elif cmd == "quit":
        print(json.dumps({"id": req.get("id"), "ok": True, "result": {}}), flush=True)
        break
    reply = {"id": req.get("id"), "ok": ok}
    reply.update({"result": result} if ok else {"error": error, "code": "no_device"})
    print(json.dumps(reply), flush=True)
