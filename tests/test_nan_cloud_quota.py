#!/usr/bin/env python3
"""Unit tests for ``bin/nan-cloud-quota``.

Every credential and every external dependency is synthetic: the tests use a
fake wallet value, a fake session value, a temporary SQLite database, and a
fake HTTPS connection. No live cookie, wallet entry, network call, or secret is
used, and no real secret is written into any fixture.
"""

import contextlib
import hashlib
import importlib.util
import io
import json
import os
import sqlite3
import sys
import tempfile
import time
import unittest
from importlib.machinery import SourceFileLoader
from unittest import mock

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPER_PATH = os.path.join(REPO_ROOT, "bin", "nan-cloud-quota")

_spec = importlib.util.spec_from_loader(
    "nan_cloud_quota", SourceFileLoader("nan_cloud_quota", HELPER_PATH)
)
if _spec is None or _spec.loader is None:
    raise RuntimeError("unable to load the helper module for testing")
helper = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = helper
_spec.loader.exec_module(helper)

WALLET_VALUE = "unit-test-wallet-value"
SESSION_VALUE = "unit-test-session-value"
WALLET_MARKER = "unit-test-wallet-marker"
SESSION_MARKER = "unit-test-session-marker"
COOKIE_COLUMNS = (
    "host_key",
    "name",
    "value",
    "encrypted_value",
    "expires_utc",
    "last_access_utc",
    "is_secure",
    "is_httponly",
)
FUTURE_EXPIRY = int((time.time() + 3600 + helper.CHROME_EPOCH_OFFSET_SECONDS) * 1_000_000)
PAST_EXPIRY = int((time.time() - 3600 + helper.CHROME_EPOCH_OFFSET_SECONDS) * 1_000_000)


def aes_cbc_encrypt(plaintext, key):
    pad = helper.AES_BLOCK_SIZE_BYTES - (len(plaintext) % helper.AES_BLOCK_SIZE_BYTES)
    padded = plaintext + bytes([pad]) * pad
    encryptor = Cipher(algorithms.AES(key), modes.CBC(helper.CBC_IV)).encryptor()
    return encryptor.update(padded) + encryptor.finalize()


def build_encrypted_cookie(
    version=b"v11",
    cookie=SESSION_VALUE,
    host_key=helper.COOKIE_HOST_KEY,
    wallet=WALLET_VALUE,
    prefix=None,
):
    if prefix is None:
        prefix = hashlib.sha256(host_key.encode("utf-8")).digest()
    key = helper.derive_key(wallet)
    return version + aes_cbc_encrypt(prefix + cookie.encode("utf-8"), key)


def cookie_row(**overrides):
    row = {
        "host_key": helper.COOKIE_HOST_KEY,
        "name": helper.COOKIE_NAME,
        "value": "",
        "encrypted_value": build_encrypted_cookie(),
        "expires_utc": FUTURE_EXPIRY,
        "last_access_utc": 10,
        "is_secure": 1,
        "is_httponly": 1,
    }
    row.update(overrides)
    return row


def valid_quota_payload():
    return {
        "periodStart": "2026-09-01T00:00:00.000Z",
        "models": [
            {
                "model": "unit-test-model",
                "tokensUsed": 1234,
                "cap": 10000,
                "remaining": 8766,
                "periodEnd": "2026-10-01T00:00:00.000Z",
            }
        ],
    }


class FakeResponse:
    def __init__(self, status, body):
        self.status = status
        self._body = body

    def read(self, amount=-1):
        if amount is None or amount < 0:
            return self._body
        return self._body[:amount]


class FakeConnection:
    def __init__(self, status=200, body=b"{}", error=None):
        self.status = status
        self.body = body
        self.error = error
        self.calls = []
        self.closed = False

    def request(self, method, path, headers=None):
        if self.error is not None:
            raise self.error
        self.calls.append((method, path, dict(headers or {})))

    def getresponse(self):
        return FakeResponse(self.status, self.body)

    def close(self):
        self.closed = True


class DeriveAndDecryptTests(unittest.TestCase):
    def test_derive_key_is_sixteen_bytes_and_deterministic(self):
        first = helper.derive_key(WALLET_VALUE)
        second = helper.derive_key(WALLET_VALUE)
        self.assertEqual(len(first), helper.AES_KEY_LENGTH_BYTES)
        self.assertEqual(first, second)
        self.assertNotEqual(first, helper.derive_key(WALLET_VALUE + "-other"))

    def test_v11_round_trip_strips_domain_prefix(self):
        encrypted = build_encrypted_cookie()
        self.assertEqual(
            helper.decrypt_cookie_value(encrypted, helper.COOKIE_HOST_KEY, WALLET_VALUE),
            SESSION_VALUE,
        )

    def test_v11_foreign_domain_prefix_is_rejected(self):
        encrypted = build_encrypted_cookie(
            prefix=hashlib.sha256(b".other.example").digest()
        )
        with self.assertRaises(helper.QuotaError) as raised:
            helper.decrypt_cookie_value(encrypted, helper.COOKIE_HOST_KEY, WALLET_VALUE)
        self.assertEqual(str(raised.exception), helper.MSG_COOKIE_UNDECRYPTABLE)

    def test_v11_without_host_prefix_is_rejected(self):
        key = helper.derive_key(WALLET_VALUE)
        encrypted = b"v11" + aes_cbc_encrypt(SESSION_VALUE.encode("utf-8"), key)
        with self.assertRaises(helper.QuotaError) as raised:
            helper.decrypt_cookie_value(encrypted, helper.COOKIE_HOST_KEY, WALLET_VALUE)
        self.assertEqual(str(raised.exception), helper.MSG_COOKIE_UNDECRYPTABLE)

    def test_v10_is_rejected(self):
        encrypted = build_encrypted_cookie(version=b"v10")
        with self.assertRaises(helper.QuotaError):
            helper.decrypt_cookie_value(encrypted, helper.COOKIE_HOST_KEY, WALLET_VALUE)

    def test_unknown_crypto_version_is_rejected(self):
        encrypted = build_encrypted_cookie(version=b"v12")
        with self.assertRaises(helper.QuotaError):
            helper.decrypt_cookie_value(encrypted, helper.COOKIE_HOST_KEY, WALLET_VALUE)

    def test_bad_padding_is_rejected(self):
        encrypted = build_encrypted_cookie()
        corrupted = encrypted[:-1] + bytes([encrypted[-1] ^ 0xFF])
        with self.assertRaises(helper.QuotaError):
            helper.decrypt_cookie_value(corrupted, helper.COOKIE_HOST_KEY, WALLET_VALUE)

    def test_other_wallet_value_is_rejected(self):
        encrypted = build_encrypted_cookie()
        with self.assertRaises(helper.QuotaError):
            helper.decrypt_cookie_value(
                encrypted, helper.COOKIE_HOST_KEY, "unit-test-other-wallet"
            )

    def test_non_utf8_plaintext_is_rejected(self):
        key = helper.derive_key(WALLET_VALUE)
        prefix = hashlib.sha256(helper.COOKIE_HOST_KEY.encode("utf-8")).digest()
        raw = b"v11" + aes_cbc_encrypt(prefix + b"\xff\xfe\xfd", key)
        with self.assertRaises(helper.QuotaError):
            helper.decrypt_cookie_value(raw, helper.COOKIE_HOST_KEY, WALLET_VALUE)

    def test_short_payload_is_rejected(self):
        with self.assertRaises(helper.QuotaError):
            helper.decrypt_cookie_value(b"v1", helper.COOKIE_HOST_KEY, WALLET_VALUE)
        with self.assertRaises(helper.QuotaError):
            helper.decrypt_cookie_value(b"v11short", helper.COOKIE_HOST_KEY, WALLET_VALUE)


class ExpiryTests(unittest.TestCase):
    def test_session_and_future_cookies_are_not_expired(self):
        self.assertFalse(helper._is_expired(0))
        self.assertFalse(helper._is_expired(None))
        self.assertFalse(helper._is_expired(FUTURE_EXPIRY))

    def test_past_expiry_is_expired(self):
        self.assertTrue(helper._is_expired(PAST_EXPIRY))

    def test_unparseable_expiry_is_treated_as_expired(self):
        self.assertTrue(helper._is_expired("not-an-integer"))


class CookieDatabaseTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self._tmp.name, "Cookies")

    def tearDown(self):
        self._tmp.cleanup()

    def _write_db(self, rows):
        connection = sqlite3.connect(self.db_path)
        connection.execute(
            "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, expires_utc INTEGER, last_access_utc INTEGER, is_secure INTEGER, is_httponly INTEGER)"
        )
        connection.executemany(
            "INSERT INTO cookies (host_key, name, value, encrypted_value, expires_utc, last_access_utc, is_secure, is_httponly) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            [tuple(row[column] for column in COOKIE_COLUMNS) for row in rows],
        )
        connection.commit()
        connection.close()

    def test_encrypted_v11_cookie_is_read_and_decrypted(self):
        self._write_db([cookie_row()])
        self.assertEqual(
            helper.read_nan_session_cookie(WALLET_VALUE, self.db_path), SESSION_VALUE
        )

    def test_plaintext_value_is_not_accepted(self):
        self._write_db([cookie_row(value=SESSION_VALUE, encrypted_value=b"")])
        with self.assertRaises(helper.QuotaError) as raised:
            helper.read_nan_session_cookie(WALLET_VALUE, self.db_path)
        self.assertEqual(str(raised.exception), helper.MSG_COOKIE_UNDECRYPTABLE)

    def test_non_secure_cookie_is_rejected(self):
        self._write_db([cookie_row(is_secure=0)])
        with self.assertRaises(helper.QuotaError) as raised:
            helper.read_nan_session_cookie(WALLET_VALUE, self.db_path)
        self.assertEqual(str(raised.exception), helper.MSG_COOKIE_INSECURE)

    def test_non_httponly_cookie_is_rejected(self):
        self._write_db([cookie_row(is_httponly=0)])
        with self.assertRaises(helper.QuotaError) as raised:
            helper.read_nan_session_cookie(WALLET_VALUE, self.db_path)
        self.assertEqual(str(raised.exception), helper.MSG_COOKIE_INSECURE)

    def test_expired_cookie_is_rejected(self):
        self._write_db([cookie_row(expires_utc=PAST_EXPIRY)])
        with self.assertRaises(helper.QuotaError) as raised:
            helper.read_nan_session_cookie(WALLET_VALUE, self.db_path)
        self.assertEqual(str(raised.exception), helper.MSG_COOKIE_EXPIRED)

    def test_other_domain_or_name_is_ignored(self):
        self._write_db(
            [cookie_row(host_key="example.com"), cookie_row(name="other-name")]
        )
        with self.assertRaises(helper.QuotaError) as raised:
            helper.read_nan_session_cookie(WALLET_VALUE, self.db_path)
        self.assertEqual(str(raised.exception), helper.MSG_COOKIE_UNAVAILABLE)

    def test_most_recent_row_wins(self):
        self._write_db(
            [
                cookie_row(
                    encrypted_value=build_encrypted_cookie(cookie="old-value"),
                    last_access_utc=1,
                ),
                cookie_row(
                    encrypted_value=build_encrypted_cookie(cookie="new-value"),
                    last_access_utc=99,
                ),
            ]
        )
        self.assertEqual(
            helper.read_nan_session_cookie(WALLET_VALUE, self.db_path), "new-value"
        )

    def test_missing_database_is_rejected(self):
        with self.assertRaises(helper.QuotaError) as raised:
            helper.read_nan_session_cookie(
                WALLET_VALUE, os.path.join(self._tmp.name, "absent")
            )
        self.assertEqual(str(raised.exception), helper.MSG_COOKIE_UNAVAILABLE)

    def test_database_connection_is_read_only(self):
        self._write_db([cookie_row()])
        connection = helper._open_cookie_db(self.db_path)
        try:
            with self.assertRaises(sqlite3.OperationalError):
                connection.execute(
                    "INSERT INTO cookies (host_key, name) VALUES ('x', 'y')"
                )
        finally:
            connection.close()


class ParseResponseTests(unittest.TestCase):
    def _reject(self, payload):
        with self.assertRaises(helper.QuotaError) as raised:
            helper.parse_quota_response(json.dumps(payload).encode("utf-8"))
        self.assertEqual(str(raised.exception), helper.MSG_RESPONSE_INVALID)

    def test_valid_payload_is_accepted(self):
        payload = valid_quota_payload()
        self.assertEqual(
            helper.parse_quota_response(json.dumps(payload).encode("utf-8")), payload
        )

    def test_empty_models_array_is_accepted(self):
        payload = {"periodStart": "2026-09-01T00:00:00.000Z", "models": []}
        self.assertEqual(
            helper.parse_quota_response(json.dumps(payload).encode("utf-8")), payload
        )

    def test_malformed_json_is_rejected(self):
        for raw in (b"{not json", b"", b'{"a":', b"\xff\xfe"):
            with self.subTest(raw=raw), self.assertRaises(helper.QuotaError) as raised:
                helper.parse_quota_response(raw)
            self.assertEqual(str(raised.exception), helper.MSG_RESPONSE_INVALID)

    def test_non_object_json_is_rejected(self):
        for raw in (b"[1, 2, 3]", b"null", b'"text"', b"42", b"true", b"{}"):
            with self.subTest(raw=raw), self.assertRaises(helper.QuotaError):
                helper.parse_quota_response(raw)

    def test_period_start_is_required_and_string(self):
        payload = valid_quota_payload()
        del payload["periodStart"]
        self._reject(payload)
        payload = valid_quota_payload()
        payload["periodStart"] = 20260901
        self._reject(payload)

    def test_models_must_be_a_list(self):
        payload = valid_quota_payload()
        del payload["models"]
        self._reject(payload)
        for bad in ({"model": "x"}, "models", 3, None):
            with self.subTest(bad=bad):
                payload = valid_quota_payload()
                payload["models"] = bad
                self._reject(payload)

    def test_model_entry_must_be_an_object(self):
        for bad in ("not-an-object", 3, None, []):
            with self.subTest(bad=bad):
                payload = valid_quota_payload()
                payload["models"] = [bad]
                self._reject(payload)

    def test_model_name_must_be_a_string(self):
        payload = valid_quota_payload()
        del payload["models"][0]["model"]
        self._reject(payload)
        payload = valid_quota_payload()
        payload["models"][0]["model"] = 7
        self._reject(payload)

    def test_numeric_model_fields_are_required_finite_nonnegative_integers(self):
        for field in ("tokensUsed", "cap", "remaining"):
            with self.subTest(field=field, case="missing"):
                payload = valid_quota_payload()
                del payload["models"][0][field]
                self._reject(payload)
            for bad in (
                "10",
                None,
                True,
                [1],
                {},
                10.5,
                0.0,
                -1,
                float("nan"),
                float("inf"),
            ):
                with self.subTest(field=field, bad=bad):
                    payload = valid_quota_payload()
                    payload["models"][0][field] = bad
                    self._reject(payload)

    def test_numeric_model_fields_accept_zero(self):
        payload = valid_quota_payload()
        payload["models"][0]["tokensUsed"] = 0
        payload["models"][0]["cap"] = 0
        payload["models"][0]["remaining"] = 0
        self.assertEqual(
            helper.parse_quota_response(json.dumps(payload).encode("utf-8")), payload
        )

    def test_period_end_must_be_a_string(self):
        payload = valid_quota_payload()
        del payload["models"][0]["periodEnd"]
        self._reject(payload)
        payload = valid_quota_payload()
        payload["models"][0]["periodEnd"] = 20261001
        self._reject(payload)

    def test_extra_top_level_fields_are_stripped(self):
        payload = valid_quota_payload()
        payload.update(
            {
                "email": "unit-test-extra-value-one",
                "sessionToken": "unit-test-extra-value-two",
                "accountId": "unit-test-extra-value-three",
                "internalDebug": {"nested": "unit-test-extra-value-four"},
                "updatedAt": "2026-09-21T16:11:42.000Z",
                "fullWindowTokens": 930278,
                "windowHours": 720,
            }
        )
        self.assertEqual(
            helper.parse_quota_response(json.dumps(payload).encode("utf-8")),
            valid_quota_payload(),
        )

    def test_extra_model_fields_are_stripped(self):
        payload = valid_quota_payload()
        payload["models"][0].update(
            {
                "apiKey": "unit-test-extra-value-five",
                "accountEmail": "unit-test-extra-value-six",
            }
        )
        self.assertEqual(
            helper.parse_quota_response(json.dumps(payload).encode("utf-8")),
            valid_quota_payload(),
        )

    def test_non_finite_json_constants_are_rejected(self):
        cases = (
            b'{"periodStart": NaN, "models": []}',
            b'{"periodStart": "x", "models": [], "fullWindowTokens": Infinity}',
            b'{"periodStart": "x", "models": [{"model": "m", "tokensUsed": Infinity, "cap": 1, "remaining": 1, "periodEnd": "y"}]}',
            b'{"periodStart": "x", "models": [{"model": "m", "tokensUsed": -Infinity, "cap": 1, "remaining": 1, "periodEnd": "y"}]}',
        )
        for raw in cases:
            with self.subTest(raw=raw), self.assertRaises(helper.QuotaError) as raised:
                helper.parse_quota_response(raw)
            self.assertEqual(str(raised.exception), helper.MSG_RESPONSE_INVALID)

    def test_overflowing_float_is_rejected(self):
        raw = b'{"periodStart": "x", "models": [{"model": "m", "tokensUsed": 1e999, "cap": 1, "remaining": 1, "periodEnd": "y"}]}'
        with self.assertRaises(helper.QuotaError) as raised:
            helper.parse_quota_response(raw)
        self.assertEqual(str(raised.exception), helper.MSG_RESPONSE_INVALID)

    def test_optional_per_model_fields_are_validated_and_preserved(self):
        payload = valid_quota_payload()
        payload["models"][0]["updatedAt"] = "2026-09-21T16:11:42.000Z"
        payload["models"][0]["fullWindowTokens"] = 930278
        payload["models"][0]["windowHours"] = 720
        self.assertEqual(
            helper.parse_quota_response(json.dumps(payload).encode("utf-8")), payload
        )

    def test_optional_per_model_fields_reject_wrong_types(self):
        cases = (
            ("updatedAt", 20260921),
            ("updatedAt", None),
            ("fullWindowTokens", "930278"),
            ("fullWindowTokens", 930278.0),
            ("fullWindowTokens", -1),
            ("fullWindowTokens", True),
            ("windowHours", 720.0),
            ("windowHours", -3),
            ("windowHours", None),
        )
        for field, bad in cases:
            with self.subTest(field=field, bad=bad):
                payload = valid_quota_payload()
                payload["models"][0][field] = bad
                self._reject(payload)


class FetchQuotaTests(unittest.TestCase):
    def _fetch(self, connection):
        with mock.patch.object(helper, "_new_connection", return_value=connection):
            return helper.fetch_quota(SESSION_VALUE)

    def test_success_sends_fixed_host_request(self):
        connection = FakeConnection(status=200, body=b'{"models":[]}')
        self.assertEqual(self._fetch(connection), b'{"models":[]}')
        self.assertEqual(len(connection.calls), 1)
        method, path, headers = connection.calls[0]
        self.assertEqual(method, "GET")
        self.assertEqual(path, helper.QUOTA_PATH)
        self.assertEqual(headers["Origin"], helper.DASHBOARD_ORIGIN)
        self.assertEqual(headers["Referer"], helper.DASHBOARD_REFERER)
        self.assertEqual(headers["User-Agent"], helper.USER_AGENT)
        self.assertEqual(headers["Cookie"], f"{helper.COOKIE_NAME}={SESSION_VALUE}")
        self.assertTrue(connection.closed)

    def test_redirect_is_rejected(self):
        connection = FakeConnection(status=302, body=b"")
        with self.assertRaises(helper.QuotaError) as raised:
            self._fetch(connection)
        self.assertEqual(str(raised.exception), helper.MSG_REDIRECTED)
        self.assertTrue(connection.closed)

    def test_non_200_status_is_rejected(self):
        for status in (400, 401, 403, 500, 503):
            with self.subTest(status=status):
                with self.assertRaises(helper.QuotaError) as raised:
                    self._fetch(FakeConnection(status=status, body=b"{}"))
                self.assertEqual(str(raised.exception), helper.MSG_REQUEST_FAILED)

    def test_oversized_body_is_rejected(self):
        connection = FakeConnection(
            status=200, body=b"a" * (helper.MAX_RESPONSE_BYTES + 8)
        )
        with self.assertRaises(helper.QuotaError) as raised:
            self._fetch(connection)
        self.assertEqual(str(raised.exception), helper.MSG_RESPONSE_INVALID)

    def test_network_error_is_sanitized(self):
        connection = FakeConnection(error=OSError("connection reset by peer"))
        with self.assertRaises(helper.QuotaError) as raised:
            self._fetch(connection)
        self.assertEqual(str(raised.exception), helper.MSG_REQUEST_FAILED)

    def test_connection_creation_failure_is_sanitized(self):
        with mock.patch.object(
            helper, "_new_connection", side_effect=OSError("tls failure")
        ), self.assertRaises(helper.QuotaError) as raised:
            helper.fetch_quota(SESSION_VALUE)
        self.assertEqual(str(raised.exception), helper.MSG_REQUEST_FAILED)


class MainTests(unittest.TestCase):
    def _run_main(self, argv=None):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = helper.main([] if argv is None else argv)
        return code, stdout.getvalue(), stderr.getvalue()

    def test_success_prints_only_quota_json(self):
        payload = valid_quota_payload()
        with mock.patch.object(
            helper, "read_safe_storage_password", return_value=WALLET_VALUE
        ), mock.patch.object(
            helper, "read_nan_session_cookie", return_value=SESSION_VALUE
        ), mock.patch.object(
            helper, "fetch_quota", return_value=json.dumps(payload).encode("utf-8")
        ):
            code, stdout, stderr = self._run_main()

        self.assertEqual(code, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(json.loads(stdout), payload)
        self.assertTrue(stdout.endswith("\n"))
        self.assertEqual(stdout.count("\n"), 1)
        self.assertNotIn(SESSION_VALUE, stdout)
        self.assertNotIn(WALLET_VALUE, stdout)

    def test_request_failure_is_sanitized_without_secrets(self):
        with mock.patch.object(
            helper, "read_safe_storage_password", return_value=WALLET_MARKER
        ), mock.patch.object(
            helper, "read_nan_session_cookie", return_value=SESSION_MARKER
        ), mock.patch.object(
            helper,
            "fetch_quota",
            side_effect=helper.QuotaError(helper.MSG_REQUEST_FAILED),
        ):
            code, stdout, stderr = self._run_main()

        self.assertEqual(code, 1)
        self.assertEqual(stdout, "")
        self.assertIn(helper.MSG_REQUEST_FAILED, stderr)
        self.assertNotIn(WALLET_MARKER, stderr)
        self.assertNotIn(SESSION_MARKER, stderr)

    def test_decrypt_failure_does_not_leak_wallet_value(self):
        with mock.patch.object(
            helper, "read_safe_storage_password", return_value=WALLET_MARKER
        ), mock.patch.object(
            helper,
            "read_nan_session_cookie",
            side_effect=helper.QuotaError(helper.MSG_COOKIE_UNDECRYPTABLE),
        ):
            code, stdout, stderr = self._run_main()

        self.assertEqual(code, 1)
        self.assertEqual(stdout, "")
        self.assertIn(helper.MSG_COOKIE_UNDECRYPTABLE, stderr)
        self.assertNotIn(WALLET_MARKER, stderr)

    def test_unexpected_exception_is_generic_and_sanitized(self):
        with mock.patch.object(
            helper,
            "read_safe_storage_password",
            side_effect=RuntimeError(WALLET_MARKER),
        ):
            code, stdout, stderr = self._run_main()

        self.assertEqual(code, 1)
        self.assertEqual(stdout, "")
        self.assertEqual(stderr, "nan-cloud-quota: unexpected failure\n")
        self.assertNotIn(WALLET_MARKER, stderr)

    def test_unexpected_arguments_are_rejected(self):
        code, stdout, stderr = self._run_main(["--verbose"])
        self.assertEqual(code, 2)
        self.assertEqual(stdout, "")
        self.assertIn(helper.MSG_UNEXPECTED_ARGUMENTS, stderr)


class ChromePathTests(unittest.TestCase):
    def test_default_path_uses_xdg_config_home(self):
        with mock.patch.dict(
            os.environ, {"XDG_CONFIG_HOME": os.path.join(os.sep, "tmp", "cfg")}
        ):
            self.assertEqual(
                helper.chrome_cookie_db_path(),
                os.path.join(
                    os.sep, "tmp", "cfg", "google-chrome", "Default", "Cookies"
                ),
            )


if __name__ == "__main__":
    unittest.main()
