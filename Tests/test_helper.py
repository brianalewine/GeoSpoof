import importlib.util
from pathlib import Path
import unittest
import sys
sys.path.insert(0, str(Path(__file__).parents[1] / "Sources"))
from unittest.mock import AsyncMock

spec = importlib.util.spec_from_file_location("helper", Path(__file__).parents[1] / "Sources/geospoof_helper.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Session:
    def __init__(self, udid):
        self.udid = udid
        self.transport = "Wi-Fi"
        self.alive = True
        self.coordinate = None
        self.location = AsyncMock()
        self.stack = AsyncMock()


class HelperTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.helper = module.Helper(lambda event: None)
        self.session = Session("phone")
        self.helper._open_session = AsyncMock(return_value=self.session)

    async def test_reuses_channel_and_clears(self):
        req = dict(udid="phone", latitude=38, longitude=-78)
        await self.helper.set(req)
        await self.helper.set(dict(req, longitude=-79))
        self.helper._open_session.assert_awaited_once_with("phone")
        self.assertEqual((await self.helper.status({}))["longitude"], -79)
        await self.helper.clear({"udid": "phone"})
        self.session.location.clear.assert_awaited_once()
        self.session.stack.aclose.assert_awaited_once()
        self.assertFalse((await self.helper.status({}))["active"])

    async def test_clear_after_restart_contacts_phone(self):
        await self.helper.clear({"udid": "phone"})
        self.helper._open_session.assert_awaited_once_with("phone")
        self.session.location.clear.assert_awaited_once()

    async def test_wrong_phone_cannot_clear(self):
        self.helper.session = self.session
        with self.assertRaises(module.HelperError):
            await self.helper.clear({"udid": "other"})
        self.session.location.clear.assert_not_awaited()

    async def test_bad_coordinates_do_not_connect(self):
        for latitude, longitude in [(float("nan"), 0), (91, 0), (0, -181)]:
            with self.assertRaises(module.HelperError):
                await self.helper.set(dict(udid="phone", latitude=latitude, longitude=longitude))
        self.helper._open_session.assert_not_awaited()

    async def test_failed_set_releases_session(self):
        self.session.location.set.side_effect = ConnectionError("lost")
        with self.assertRaises(module.HelperError):
            await self.helper.set(dict(udid="phone", latitude=38, longitude=-78))
        self.assertIsNone(self.helper.session)
        self.session.stack.aclose.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
