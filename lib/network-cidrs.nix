# ---
# id: "network-cidrs"
# domain: "50"
# status: "active"
# layer: 5
# role: lib
# purpose: "CIDR-Konstanten fuer IP-Allowlists (loopback, private RFC-1918)"
# tags: [lib, network, cidrs]
# ---
{ lib }:
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
