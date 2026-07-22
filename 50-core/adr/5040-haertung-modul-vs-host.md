# ---
# id: 5040
# title: "Härtung: was mediNix absichert und was dem Host gehört"
# status: "accepted"
# date: "2026-07-20"
# related: [5030]
# tags: ["security", "hardening", "portability", "boundaries"]
# error_pattern: "hardening|sysctl|kernel\\.|MemoryDenyWriteExecute"
# ---

# ADR-5040 — Härtung: Modul-Grenze

## Die Frage

> „Wenn jemand das als Flake importiert, soll er nicht in Unterhosen dastehen.
> Aber ich will ihm auch nicht den Server absichern — ich will nur meine
> Arbeit, also den mediNix-Ordner, absichern."

## Entscheidung

**mediNix härtet seine eigenen Dienste. mediNix fasst den Host nicht an.**

| Zuständig ist… | …für |
|---|---|
| **mediNix** | systemd-Härtung der eigenen Units, Bind auf Loopback, `.local` ohne Auth, Rechte auf eigenen Zustandsverzeichnissen, Confinement der Usenet-Kette |
| **Der Host** | Kernel-Sysctls, `kexec`, User-Namespaces, journald-Grenzen, Firewall-Grundregeln, SSH, Benutzerverwaltung |

## Warum diese Grenze — dasselbe Muster wie beim Ingress

Der Ingress löst genau dieses Problem bereits, und zwar richtig:

```
ingress.mode = "auto"    # Host hat Caddy?  → vHosts dort eintragen
                         # Host hat keinen? → eigenen caddy-media starten
```

Das Modul **erkennt die Umgebung und passt sich an**, statt sie umzubauen. Es
reißt keinen fremden Reverse-Proxy ab und erzwingt keinen eigenen.

Härtung folgt derselben Logik. Ein `kernel.kexec_load_disabled = 1` in mediNix
wäre ein Übergriff: jemand importiert einen Medienstack und bekommt ungefragt
seinen Kernel umkonfiguriert — womöglich gegen die Richtlinie seines Hosters
oder gegen andere Dienste auf derselben Maschine.

> **Faustregel:** Alles, was über den Prozessbaum der eigenen Dienste
> hinausreicht, gehört nicht in dieses Modul.

## Was das konkret heißt

### mediNix härtet — und tut das bereits

- `lib/service-factory.nix` mit vier Profilen (`full`, `dotnet`, `node`, `streamer`)
- Bind auf `127.0.0.1`, nie `0.0.0.0`
- `RestrictAddressFamilies`, `ProtectSystem=strict`, `NoNewPrivileges`
- `.local` bewusst ohne forward_auth (LAN-Zone), Domain mit
- `590-usenet-confinement` als fail-closed VPN-Käfig

### mediNix setzt **nicht**

- `boot.kernel.sysctl.*`
- `boot.kernelParams`
- `security.*` auf Systemebene
- `services.journald.*`
- `networking.firewall.*` über die eigenen Ports hinaus

### Wenn ein Nutzer Host-Härtung will

Dann bekommt er sie **dokumentiert, nicht aufgezwungen**. Eine Beispiel-Datei
in der README, die er übernehmen *kann*:

```nix
# Optional, gehört in die Host-Konfiguration — nicht in mediNix
boot.kernel.sysctl = {
  "kernel.kexec_load_disabled" = 1;
  "net.ipv4.conf.all.accept_redirects" = 0;
  "net.ipv4.conf.all.send_redirects" = 0;
  "net.ipv4.conf.all.accept_source_route" = 0;
};
services.journald.extraConfig = ''
  SystemMaxUse=1G
  SystemKeepFree=2G
'';
```

Diese vier laufen seit 2026-07-20 auf q958 und sind dort **gemessen wirksam**.

## Was ein Nutzer trotzdem mitbringen muss

Damit niemand „in Unterhosen dasteht", nennt die README die Voraussetzungen,
die mediNix **nicht** selbst herstellen kann:

| Voraussetzung | Warum es nicht ins Modul gehört |
|---|---|
| Firewall aktiv | Der Host entscheidet, welche Ports offen sind |
| SSH nur mit Key | Zugangsverwaltung ist Host-Sache |
| `allowUnfreePredicate` für `unrar` | SABnzbd braucht es; Lizenzentscheidung trifft der Nutzer |
| WireGuard-Key, falls `usenet-confinement` | Secret — darf nie im Modul liegen |
| Reverse-Proxy **oder** freier Port 80 | sonst kann der Chamäleon-Ingress nicht greifen |

## Warum aus dem Härtungsreview vom 2026-07-20 nur vier Punkte übernommen wurden

Vorgeschlagen wurden dreizehn. Übernommen wurden die vier, die drei Bedingungen
erfüllen: **der Schalter existiert**, **er bricht keinen Dienst**, und **er
kostet keine Diagnosemöglichkeit**, solange der Stack unfertig ist.

Abgelehnt und warum:

| Vorschlag | Befund |
|---|---|
| `kernel.unprivileged_userns_clone` | **existiert nicht** auf Mainline — Debian/Ubuntu-Patch. Auf 6.18.33 nachgeprüft. Wirkungslos, täuscht Sicherheit vor |
| `systemd.services.defaultHardening` | erzeugt eine **Unit** dieses Namens, keine Vorlage. Wäre ein toter Dienst |
| `MemoryDenyWriteExecute = true` global | würde Jellyfin, alle fünf *arr, Audiobookshelf und Navidrome killen — JIT braucht W+X. Gemessen: alle stehen bewusst auf `no` |
| `SystemCallFilter ~@resources` global | Node braucht Teile davon. Genau so ein Filter hat Audiobookshelf mit SIGSYS getötet (LEARNINGS L4) |
| `UsePAM = no` | bricht auf NixOS Session-Einrichtung und `systemd-logind` |
| `systemd.timers = lib.mkForce {}` | legt das System lahm |
| `PermitEmptyPasswords = no` | Syntaxfehler — `no` ist in Nix keine Konstante, es muss `false` heißen |
| `ChallengeResponseAuthentication` | seit OpenSSH 8.x umbenannt zu `KbdInteractiveAuthentication` |
| Impermanence ab Stufe 8 | widerspricht einer ausdrücklichen Entscheidung des Eigentümers |
| `user.max_user_namespaces = 0` | bricht die Nix-Build-Sandbox |

> **Lehre:** Ein Härtungsvorschlag ohne Messung ist eine Vermutung. Vier der
> dreizehn Punkte wären wirkungslos gewesen, fünf hätten laufende Dienste
> zerstört. Jeder Schalter gehört gegen das Zielsystem geprüft, bevor er
> gesetzt wird — `sysctl <name>` kostet eine Sekunde.

## Und der wichtigste Einwand

**Härtung kommt nach Funktion, nicht davor.** Am 2026-07-20 lagen zwei von fünf
Startfehlern *an der Härtung* selbst (LEARNINGS L4: seccomp tötete
Audiobookshelf; L2/L5: Verzeichnisrechte). Eine strenge Konfiguration über einem
unfertigen Stack macht die Fehlersuche schwerer, nicht das System sicherer.

Solange Jellyfin nicht startet, `exporters` nichts erzeugt und Provisioning nie
lief, ist zusätzliche Härtung verfrüht.
