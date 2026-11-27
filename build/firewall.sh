#!/bin/bash
# Egress firewall for the container's own network namespace (not the host's).
# Rules see the original destination (before the host's DNAT), so exceptions
# are plain host:port.
#   SANDBOX_ALLOW  space-separated TCP exceptions into blocked ranges, e.g. "192.168.1.10:3000"
#   SANDBOX_BLOCK  extra IPv4 CIDRs to block (e.g. a LAN on public addresses)
set -euo pipefail

ipt=iptables
$ipt -S OUTPUT >/dev/null 2>&1 || ipt=iptables-legacy
$ipt -S OUTPUT >/dev/null

BLOCK="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10 224.0.0.0/4 ${SANDBOX_BLOCK:-}"

$ipt -F OUTPUT
$ipt -A OUTPUT -o lo -j ACCEPT
$ipt -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# DNS to the configured resolvers only (on the default bridge that's often the router).
for ns in $(awk '/^nameserver/ {print $2}' /etc/resolv.conf); do
  case $ns in *:*) continue ;; esac
  for proto in udp tcp; do
    $ipt -A OUTPUT -d "$ns" -p "$proto" --dport 53 -j ACCEPT
  done
done

for entry in ${SANDBOX_ALLOW:-}; do
  $ipt -A OUTPUT -d "${entry%:*}" -p tcp --dport "${entry##*:}" -j ACCEPT
done

for net in $BLOCK; do
  $ipt -A OUTPUT -d "$net" -j REJECT
done

# IPv6: loopback only. LAN hosts often have global IPv6 addresses we can't tell
# apart from the internet, so IPv6 is off; everything falls back to IPv4.
ip6=ip6tables
$ip6 -S OUTPUT >/dev/null 2>&1 || ip6=ip6tables-legacy
if $ip6 -S OUTPUT >/dev/null 2>&1; then
  $ip6 -F OUTPUT
  $ip6 -A OUTPUT -o lo -j ACCEPT
  $ip6 -A OUTPUT -j REJECT
elif grep -qv ' lo$' /proc/net/if_inet6 2>/dev/null; then
  echo "firewall: IPv6 is active but ip6tables is unusable" >&2
  exit 1
fi

echo "firewall: rules applied ($ipt)"
$ipt -S OUTPUT
