#!/bin/sh
# Subarchy (ADR 0020): a Wi-Fi or Ethernet connection that is neither
# trusted nor untrusted becomes untrusted when it comes up, so the network's
# DNS is ignored and the global provider answers over strict DNS-over-TLS.
# Trusted connections (routing domain ~.), WireGuard, VPN and Tailscale
# links are left alone; subcult-dns decides. NetworkManager.conf cannot set
# ipv4/ipv6.ignore-auto-dns as a [connection] default, hence this script.
# Installed to /usr/lib/NetworkManager/dispatcher.d/50-subarchy-dns.
[ "$2" = up ] || exit 0
[ -n "$CONNECTION_UUID" ] && [ -n "$DEVICE_IFACE" ] || exit 0
exec /usr/bin/subcult-dns apply-default "$CONNECTION_UUID" "$DEVICE_IFACE"
