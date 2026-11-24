#!/usr/bin/env python3
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise the address selection used by the relay and the SSH listener."""
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from phone_network import host_for_phone


class PhoneNetworkTest(unittest.TestCase):
    def test_explicit_vpn_works_without_tailscale(self):
        with patch("subprocess.check_output", side_effect=AssertionError("unexpected discovery")):
            for host in ("10.8.0.1", "172.31.0.1", "192.168.42.1", "100.64.0.1"):
                self.assertEqual(host_for_phone("10.8.0.2", host), host)

    def test_reject_invalid_endpoints(self):
        for value in ("", "0.0.0.0", "127.0.0.1", "203.0.113.9", "172.32.0.1",
                      "100.128.0.1", "010.8.0.1", "10.8.0.256", "vpn.example", "::1", "10.8.0.2"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                host_for_phone("10.8.0.2", value)
            with self.subTest(peer=value), self.assertRaises(ValueError):
                host_for_phone(value, "10.8.0.2")

    def test_discovery_verifies_the_phone(self):
        status = json.dumps({"Peer": {"pending": {}, "one": {"OS": "iOS", "TailscaleIPs": ["100.64.0.2"]},
                                      "two": {"OS": "linux", "TailscaleIPs": ["100.64.0.3"]}}})
        with patch("subprocess.check_output", side_effect=[status, "100.64.0.1\n"]):
            self.assertEqual(host_for_phone("100.64.0.2"), "100.64.0.1")
        with patch("subprocess.check_output", return_value=status):
            for peer in ("100.64.0.3", "100.64.0.4"):
                with self.assertRaisesRegex(ValueError, "iPhone"):
                    host_for_phone(peer)
        with patch("subprocess.check_output", side_effect=FileNotFoundError):
            with self.assertRaisesRegex(ValueError, "Tailscale discovery failed"):
                host_for_phone("100.64.0.2")


if __name__ == "__main__":
    unittest.main()
