{ lib, config ? {} }:
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
