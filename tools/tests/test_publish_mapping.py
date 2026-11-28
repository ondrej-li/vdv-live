"""Tests for the deferral in tools/publish-mapping.py.

The publisher runs from a timer against a ministry server that answers 500 for
hours at a time. What matters is which failures it retries, which it reports as
"ask again next hour" (so the unit is not marked failed), and which it leaves as
a real failure for someone to look at.
"""

import importlib.util
import pathlib
import sys
import unittest
import urllib.error

HERE = pathlib.Path(__file__).resolve().parent
TOOLS = HERE.parent
sys.path.insert(0, str(TOOLS))

spec = importlib.util.spec_from_file_location(
    "publish_mapping", TOOLS / "publish-mapping.py")
publish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publish)


def http_error(code):
    return urllib.error.HTTPError(
        "https://portal.example/JDF.zip", code, "boom", {}, None)


def transient_code(code):
    """`transient()` for one HTTP status, closing the error object it is given."""
    error = http_error(code)
    try:
        return publish.transient(error)
    finally:
        error.close()


class ClassificationTests(unittest.TestCase):
    def test_a_broken_portal_is_transient(self):
        for code in (500, 502, 503, 504, 429, 408):
            with self.subTest(code=code):
                self.assertTrue(transient_code(code))

    def test_a_wrong_request_is_not_transient(self):
        for code in (400, 403, 404, 410):
            with self.subTest(code=code):
                self.assertFalse(transient_code(code))

    def test_network_failures_are_transient(self):
        for error in (urllib.error.URLError("timed out"),
                      ConnectionResetError("reset"),
                      TimeoutError("timed out")):
            with self.subTest(error=type(error).__name__):
                self.assertTrue(publish.transient(error))

    def test_a_bug_is_not_transient(self):
        self.assertFalse(publish.transient(KeyError("Linky.txt")))
        self.assertFalse(publish.transient(ValueError("bad etag")))


class AttemptTests(unittest.TestCase):
    def setUp(self):
        self.original = publish.BACKOFF
        publish.BACKOFF = (0, 0)

    def tearDown(self):
        publish.BACKOFF = self.original

    def test_a_transient_failure_is_retried_then_deferred(self):
        calls = []

        def operation():
            calls.append(1)
            error = http_error(500)
            self.addCleanup(error.close)
            raise error

        with self.assertRaises(publish.Defer) as caught:
            publish.attempt("polling", operation)
        self.assertEqual(len(calls), publish.ATTEMPTS)
        self.assertIn("HTTP Error 500", str(caught.exception))

    def test_a_retry_that_succeeds_is_used(self):
        calls = []

        def operation():
            calls.append(1)
            if len(calls) < 2:
                raise urllib.error.URLError("temporary")
            return "ok"

        self.assertEqual(publish.attempt("polling", operation), "ok")
        self.assertEqual(len(calls), 2)

    def test_a_real_failure_is_not_retried(self):
        calls = []

        def operation():
            calls.append(1)
            error = http_error(404)
            self.addCleanup(error.close)
            raise error

        with self.assertRaises(urllib.error.HTTPError):
            publish.attempt("polling", operation)
        self.assertEqual(len(calls), 1)


class ExitCodeTests(unittest.TestCase):
    def test_deferred_is_ex_tempfail(self):
        self.assertEqual(publish.DEFERRED, 75)


if __name__ == "__main__":
    unittest.main()
