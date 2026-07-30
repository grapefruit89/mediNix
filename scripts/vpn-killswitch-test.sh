#!/usr/bin/env bash
# vpn-killswitch-test.sh -- prueft den SABnzbd-VPN-Kill-Switch REAL. Als root.
# Voraussetzung: killswitch aktiv + VPN-Interface existiert.
set -uo pipefail
IFACE="${1:-privado}"; SAB=sabnzbd
sab() { sudo -u "$SAB" "$@"; }
echo "== 1. SABnzbd-UID (muss 5410 sein) =="; id "$SAB"
echo "== 2. nftables Kill-Switch =="; nft list table inet medinix-killswitch 2>/dev/null || echo "  FEHLT!"
echo "== 3. Policy-Routing =="; ip rule show | grep 5410 || echo "  keine rule"; ip route show table 5410 || echo "  leer"
echo "== 4. VPN OBEN -> Traffic (sollte VPN-IP zeigen) =="
sab curl -s --max-time 8 https://ipv4.icanhazip.com && echo || echo "  kein Traffic (VPN unten?)"
echo "== 5. DNS-Aufloesung SABnzbd =="; sab getent hosts example.com || echo "  keine Aufloesung"
echo; echo "== 6. VPN RUNTER: 'sudo ip link set $IFACE down' -- dann Enter =="; read -r _
echo "== 7. VPN UNTEN -> NICHTS darf raus =="
if sab curl -s --max-time 8 https://ipv4.icanhazip.com; then echo "  !!! LEAK !!!"; else echo "  OK: fail-closed, kein Byte raus"; fi
echo "== 8. Drop-Zaehler =="; nft list table inet medinix-killswitch 2>/dev/null | grep -A1 drop
echo "== 9. DNS unten -> darf nicht aufloesen =="
sab getent hosts example.com && echo "  !!! DNS-LEAK !!!" || echo "  OK: DNS auch tot"
