# ---
# id: "network-cidrs"
# domain: "50"
# status: "active"
# layer: 5
# role: lib
# purpose: "CIDR-Konstanten fuer IP-Allowlists (loopback, private RFC-1918)"
# tags: [lib, network, cidrs]
# ---
# Nimmt bewusst jedes Argument an und wertet keines aus: die Datei
# braucht kein lib, die AUFRUFER uebergeben aber weiterhin
# "{ inherit lib; }". Ein Attributset-Muster ohne ... waere strikt und
# wuerde mit "unexpected argument 'lib'" scheitern; _ ist die knappere
# und von statix bevorzugte Form dafuer.
_:
let
  loopbackV4 = "127.0.0.0/8";
  loopbackV6 = "::1/128";
  trustedPrivateCidrs = [
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
  ];
in
{
  inherit loopbackV4 loopbackV6 trustedPrivateCidrs;
}
