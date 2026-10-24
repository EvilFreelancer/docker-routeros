import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]


class EntrypointNetworkingTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.routeros = self.root / "routeros"
        self.routeros.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands.jsonl"
        self.stub = textwrap.dedent(f"""\
            #!{sys.executable}
            import json
            import os
            from pathlib import Path
            import sys

            name = Path(sys.argv[0]).name
            with open(os.environ['COMMAND_LOG'], 'a') as log:
                log.write(json.dumps([name, *sys.argv[1:]]) + '\\n')
            if name == 'ip' and sys.argv[1:] == ['link', 'show', 'eth1']:
                sys.exit(0 if os.environ['HAS_ETH1'] == '1' else 1)
            if name == 'ip' and sys.argv[1:] == ['-4', 'route', 'show', 'default']:
                interface = os.environ['DEFAULT_INTERFACE']
                if interface == 'error':
                    sys.exit(1)
                if interface != 'none':
                    print('default via 172.18.0.1 dev ' + interface)
            if name == 'generate-dhcpd-conf.py':
                print('interface qemubr1')
            """)
        for name in ("ip", "udhcpd", "qemu-system-x86_64"):
            self.write_stub(self.bin / name)
        self.write_stub(self.routeros / "generate-dhcpd-conf.py")

        # Redirect container paths only; execute the complete entrypoint unchanged.
        source = (ROOT / "scripts/entrypoint.sh").read_text()
        self.entrypoint = self.root / "entrypoint.sh"
        self.entrypoint.write_text(source.replace("/routeros", str(self.routeros)))

    def write_stub(self, path):
        path.write_text(self.stub)
        path.chmod(0o755)

    def run_entrypoint(self, *, two_networks=False, promisc="1", extra_args=(),
                       default_interface="eth0", expected_returncode=0):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("ROUTEROS_")}
        env.update(
            PATH=f"{self.bin}:{env.get('PATH', '')}",
            COMMAND_LOG=str(self.log),
            HAS_ETH1="1" if two_networks else "0",
            DEFAULT_INTERFACE=default_interface,
            ROUTEROS_IMAGE="chr-test.vdi",
            ROUTEROS_DATA_DIR=str(self.root / "no-volume"),
            ROUTEROS_NIC_MAC="02:00:00:00:00:85",
            ROUTEROS_DHCP_DNS="1.1.1.1 1.0.0.1",
            ROUTEROS_ETH_PROMISC=promisc,
        )
        result = subprocess.run(
            ["bash", str(self.entrypoint), *extra_args], env=env,
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, expected_returncode, result.stdout + result.stderr)
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def qemu_nics(self, commands):
        launches = [args for name, *args in commands if name == "qemu-system-x86_64"]
        self.assertEqual(len(launches), 1)
        args = launches[0]
        return [args[index + 1] for index, arg in enumerate(args) if arg == "-nic"]

    def test_single_network_preserves_container_interface(self):
        commands = self.run_entrypoint()
        ip_commands = [args for name, *args in commands if name == "ip"]
        self.assertEqual(ip_commands, [["link", "show", "eth1"]])

    def test_single_network_forwards_management_ports_without_tap(self):
        nics = self.qemu_nics(self.run_entrypoint())
        self.assertEqual(len(nics), 1)
        self.assertTrue(nics[0].startswith("user,"), nics)
        for port in (21, 22, 23, 80, 443, 8291, 8728, 8729):
            with self.subTest(port=port):
                self.assertIn(f"hostfwd=tcp::{port}-:{port}", nics[0].split(","))

    def test_single_network_does_not_start_bridge_dhcp(self):
        commands = self.run_entrypoint()
        names = [name for name, *args in commands]
        self.assertNotIn("generate-dhcpd-conf.py", names)
        self.assertNotIn("udhcpd", names)

    def test_two_networks_bridge_only_secondary_interface(self):
        commands = self.run_entrypoint(two_networks=True)
        ip_commands = [args for name, *args in commands if name == "ip"]
        self.assertIn(["addr", "flush", "dev", "eth1"], ip_commands)
        self.assertIn(["link", "set", "dev", "eth1", "master", "qemubr1"], ip_commands)
        self.assertIn(["link", "set", "dev", "eth1", "address", "02:00:00:00:00:85"], ip_commands)
        self.assertIn(["link", "set", "dev", "eth1", "promisc", "on"], ip_commands)
        self.assertFalse(any("eth0" in args for args in ip_commands))
        self.assertIn(
            ["generate-dhcpd-conf.py", "qemubr1", "--addr-from", "eth1", "1.1.1.1", "1.0.0.1"],
            commands,
        )
        self.assertIn(
            ["udhcpd", "-I", "10.0.0.1", "-f", str(self.routeros / "dhcpd.conf")],
            commands,
        )

    def test_two_networks_keep_user_and_tap_nics(self):
        nics = self.qemu_nics(self.run_entrypoint(two_networks=True))
        self.assertEqual(len(nics), 2)
        self.assertTrue(nics[0].startswith("user,"), nics)
        self.assertIn("hostfwd=tcp::80-:80", nics[0].split(","))
        self.assertEqual(
            nics[1],
            f"tap,id=qemu1,mac=02:00:00:00:00:85,script={self.routeros}/qemu-ifup,"
            f"downscript={self.routeros}/qemu-ifdown",
        )

    def test_two_networks_preserve_default_route_on_eth1(self):
        commands = self.run_entrypoint(two_networks=True, default_interface="eth1")
        ip_commands = [args for name, *args in commands if name == "ip"]
        self.assertIn(["addr", "flush", "dev", "eth0"], ip_commands)
        self.assertIn(["link", "set", "dev", "eth0", "master", "qemubr1"], ip_commands)
        self.assertNotIn(["addr", "flush", "dev", "eth1"], ip_commands)
        self.assertIn(
            ["generate-dhcpd-conf.py", "qemubr1", "--addr-from", "eth0", "1.1.1.1", "1.0.0.1"],
            commands,
        )
        self.assertEqual(len(self.qemu_nics(commands)), 2)

    def test_two_networks_do_not_mutate_interfaces_without_a_known_uplink(self):
        for interface in ("error", "none", "ens3"):
            with self.subTest(default_interface=interface):
                self.log.unlink(missing_ok=True)
                commands = self.run_entrypoint(
                    two_networks=True, default_interface=interface, expected_returncode=1,
                )
                ip_commands = [args for name, *args in commands if name == "ip"]
                self.assertFalse(any("flush" in args or "set" in args for args in ip_commands))
                self.assertNotIn("qemu-system-x86_64", [name for name, *args in commands])

    def test_two_networks_respect_disabled_promiscuous_mode(self):
        commands = self.run_entrypoint(two_networks=True, promisc="0")
        self.assertFalse(any(name == "ip" and "promisc" in args for name, *args in commands))

    def test_extra_qemu_arguments_are_preserved_in_both_modes(self):
        for two_networks in (False, True):
            with self.subTest(two_networks=two_networks):
                self.log.unlink(missing_ok=True)
                commands = self.run_entrypoint(
                    two_networks=two_networks, extra_args=("-name", "test router"),
                )
                args = next(args for name, *args in commands if name == "qemu-system-x86_64")
                self.assertEqual(args[-2:], ["-name", "test router"])


if __name__ == "__main__":
    unittest.main()
