# RETIRED (Review K5 — 2026-07-15)
# Python-Inline-Prototyp entfernt: unauthentifizierte Write-Endpoints,
# Permissions-Deadlock (secretsDir root:0700 vs. User nobody),
# ExecStart mit mehrzeiligem Inline-Python (systemd-Unit wahrscheinlich nicht ladbar),
# Duplikat zu modules/20-security/2029-secrets-portal.nix (natives Go-Modul).
# q958: my.services.secrets-portal.enable = true nutzt bereits das native Modul.
{ ... }: { }
