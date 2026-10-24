import json
import math
import os
from pathlib import Path
import platform
import subprocess
import time
import unittest
import urllib.error
import urllib.request
import uuid


IMAGE = os.environ.get("ROUTEROS_TEST_IMAGE")


def boot_timeout():
    message = "ROUTEROS_TEST_TIMEOUT must be a positive finite number of seconds"
    try:
        value = float(os.environ.get("ROUTEROS_TEST_TIMEOUT", "300"))
    except ValueError as error:
        raise ValueError(message) from error
    if not math.isfinite(value) or value <= 0:
        raise ValueError(message)
    return value


@unittest.skipUnless(IMAGE, "set ROUTEROS_TEST_IMAGE to run Docker/WebFig smoke tests")
class WebFigSmokeTests(unittest.TestCase):
    def docker(self, *args):
        result = subprocess.run(
            ["docker", *args], check=True, capture_output=True, text=True, timeout=30,
        )
        return result.stdout.strip()

    def check_webfig(self, *, two_networks):
        timeout = boot_timeout()
        name = "routeros-webfig-test-" + uuid.uuid4().hex[:12]
        front = name + "-front"
        self.docker("network", "create", front)
        self.addCleanup(self.docker, "network", "rm", front)
        if two_networks:
            back = name + "-back"
            self.docker("network", "create", back)
            self.addCleanup(self.docker, "network", "rm", back)

        args = [
            "create", "-it", "--name", name, "--network", front,
            "-p", "127.0.0.1::80",
        ]
        if two_networks:
            args += ["--cap-add", "NET_ADMIN", "--device", "/dev/net/tun"]
        if platform.machine() == "x86_64" and Path("/dev/kvm").exists():
            args += ["--device", "/dev/kvm"]
        self.docker(*args, IMAGE)
        self.addCleanup(self.docker, "rm", "-f", name)
        if two_networks:
            self.docker("network", "connect", back, name)
        self.docker("start", name)
        port = self.docker("port", name, "80/tcp").rsplit(":", 1)[1]
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        deadline = time.monotonic() + timeout
        error = "RouterOS did not respond"
        while time.monotonic() < deadline:
            try:
                with opener.open(f"http://127.0.0.1:{port}/", timeout=2) as response:
                    body = response.read().decode("utf-8")
                    self.assertEqual(response.status, 200)
                    self.assertIn("RouterOS", body)
                    break
            except (OSError, urllib.error.URLError) as exc:
                error = str(exc)
                time.sleep(1)
        else:
            try:
                logs = self.docker("logs", name)
            except subprocess.SubprocessError as diagnostic_error:
                logs = f"Could not collect Docker logs: {diagnostic_error}"
            self.fail(f"WebFig unavailable: {error}\n{logs}")

        routes = json.loads(self.docker("exec", name, "ip", "-4", "-json", "route", "show", "default"))
        self.assertTrue(routes, "container lost its IPv4 default route")
        uplink = routes[0]["dev"]
        addresses = json.loads(self.docker("exec", name, "ip", "-json", "addr", "show", uplink))
        self.assertTrue(any(info["family"] == "inet" for info in addresses[0]["addr_info"]))
        links = json.loads(self.docker("exec", name, "ip", "-json", "link"))
        management = next(link for link in links if link["ifname"] == uplink)
        self.assertNotIn("master", management)
        if two_networks:
            secondary = "eth1" if uplink == "eth0" else "eth0"
            bridge_port = next(link for link in links if link["ifname"] == secondary)
            self.assertEqual(bridge_port.get("master"), "qemubr1")
        else:
            self.assertFalse(any(link["ifname"] == "qemubr1" for link in links))

    def test_webfig_with_one_network(self):
        self.check_webfig(two_networks=False)

    def test_webfig_with_two_networks(self):
        self.check_webfig(two_networks=True)


if __name__ == "__main__":
    unittest.main()
