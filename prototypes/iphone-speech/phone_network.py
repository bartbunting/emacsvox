# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""Select the private IPv4 endpoints shared by the speech and SSH listeners."""
import argparse
import ipaddress
import json
import subprocess

VPN_NETWORKS = tuple(ipaddress.IPv4Network(prefix) for prefix in
                     ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10"))


def vpn_address(value):
    address = ipaddress.IPv4Address(value)
    if not any(address in network for network in VPN_NETWORKS):
        raise ValueError("Use a private or shared IPv4 address assigned by your VPN.")
    return str(address)


def host_for_phone(phone, vpn_host=None):
    """Return the local bind address for exactly this phone."""
    phone = vpn_address(phone)
    if vpn_host is None:
        try:
            status = json.loads(subprocess.check_output(["tailscale", "status", "--json"]))
            peers = (status.get("Peer") or {}).values()
            if not any(phone in peer["TailscaleIPs"] and peer["OS"].lower() == "ios" for peer in peers):
                raise ValueError("Choose the Tailscale IPv4 address of a paired iPhone.")
            vpn_host = subprocess.check_output(["tailscale", "ip", "-4"], text=True).strip()
        except (OSError, subprocess.CalledProcessError) as error:
            raise ValueError("Tailscale discovery failed. For another private VPN, pass --vpn-host HOST_IP.") from error
    host = vpn_address(vpn_host)
    if host == phone:
        raise ValueError("The Emacs host and iPhone must have distinct VPN addresses.")
    return host


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phone")
    parser.add_argument("--vpn-host", metavar="HOST_IP")
    args = parser.parse_args()
    try:
        print(host_for_phone(args.phone, args.vpn_host))
    except ValueError as error:
        parser.error(str(error))
