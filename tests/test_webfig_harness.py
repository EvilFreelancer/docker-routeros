import os
import subprocess
import unittest
from unittest.mock import Mock, patch

import test_webfig


class WebFigHarnessTests(unittest.TestCase):
    def test_boot_timeout_has_a_default(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(test_webfig.boot_timeout(), 300)

    def test_boot_timeout_can_be_overridden(self):
        with patch.dict(os.environ, {"ROUTEROS_TEST_TIMEOUT": "450"}):
            self.assertEqual(test_webfig.boot_timeout(), 450)

    def test_boot_timeout_rejects_invalid_values(self):
        for value in ("0", "-1", "nan", "inf", "invalid"):
            with self.subTest(value=value):
                with patch.dict(os.environ, {"ROUTEROS_TEST_TIMEOUT": value}):
                    with self.assertRaises(ValueError):
                        test_webfig.boot_timeout()

    def test_log_failure_keeps_the_webfig_failure(self):
        case = test_webfig.WebFigSmokeTests()
        self.addCleanup(case.doCleanups)

        def docker(*args):
            if args[0] == "logs":
                raise subprocess.TimeoutExpired(["docker", "logs"], 30)
            return "127.0.0.1:12345"

        case.docker = Mock(side_effect=docker)
        with patch.object(test_webfig.time, "monotonic", side_effect=(0, 1000)):
            with self.assertRaisesRegex(AssertionError, "WebFig unavailable:.*RouterOS did not respond"):
                case.check_webfig(two_networks=False)


if __name__ == "__main__":
    unittest.main()
