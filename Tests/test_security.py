import asyncio
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, MagicMock, patch
sys.path.insert(0, str(Path(__file__).parents[1] / "Sources"))
import geospoof_security as security
from geospoof_helper import Helper, HelperError


class TransportSecurity(unittest.TestCase):
    def response(self, status=200, chunks=(b"ok",)):
        session = MagicMock()
        response = session.post.return_value.__enter__.return_value
        response.status_code = status
        response.iter_content.return_value = iter(chunks)
        return session

    def test_https_verification_and_no_proxy_or_redirect(self):
        session = self.response()
        with patch.object(security.requests, "Session") as factory:
            factory.return_value.__enter__.return_value = session
            self.assertEqual(security.signing_request(b"request"), b"ok")
        self.assertFalse(session.trust_env)
        args, kwargs = session.post.call_args
        self.assertEqual(args[0], "https://gs.apple.com/TSS/controller?action=2")
        self.assertTrue(kwargs["verify"])
        self.assertFalse(kwargs["allow_redirects"])
        self.assertEqual(kwargs["timeout"], (10, 30))

    def test_redirect_rejected(self):
        session = self.response(status=302)
        with patch.object(security.requests, "Session") as factory:
            factory.return_value.__enter__.return_value = session
            with self.assertRaises(security.requests.HTTPError):
                security.signing_request(b"request")

    def test_response_size_bound(self):
        session = self.response(chunks=(b"x" * 9,))
        with patch.object(security, "MAX_TSS_RESPONSE", 8), patch.object(security.requests, "Session") as factory:
            factory.return_value.__enter__.return_value = session
            with self.assertRaises(ValueError):
                security.signing_request(b"request")

    def test_private_directory_and_symlink_rejection(self):
        with tempfile.TemporaryDirectory() as root:
            target = security.private_directory(Path(root) / "private")
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o700)
            link = Path(root) / "link"
            link.symlink_to(target, target_is_directory=True)
            with self.assertRaises(OSError):
                security.private_directory(link)


class AsyncSecurity(unittest.IsolatedAsyncioTestCase):
    async def test_socket_failure_never_falls_back_to_tcp(self):
        relay = MagicMock()
        relay._server = None
        with patch.object(asyncio, "start_unix_server", AsyncMock(side_effect=OSError("bind failed"))), patch.object(
            asyncio, "start_server", AsyncMock()
        ) as tcp:
            with self.assertRaises(OSError):
                await security.unix_only_enter(relay)
            tcp.assert_not_awaited()
        self.assertIsNone(relay._socket_dir)

    async def test_malformed_and_path_identifiers_rejected(self):
        helper = Helper(lambda event: None)
        for req in ([], {"cmd": []}, {"cmd": "set", "udid": "../../secret"},
                    {"cmd": "clear"}, {"cmd": "verify", "udid": "x" * 129}):
            with self.assertRaises(HelperError):
                await helper.handle(req)

    async def test_signing_parser_rejects_failure(self):
        request = MagicMock()
        request._request = {}
        with patch.object(security, "signing_request", return_value=b"MESSAGE=FAIL"):
            with self.assertRaises(Exception):
                await security.secure_send_receive(request)
