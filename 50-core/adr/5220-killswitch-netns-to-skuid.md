# ---
# id: 5220
# title: "Kill-Switch für SABnzbd (Modul 522): von Network Namespaces über eBPF zu nftables skuid + Policy-Routing"
# status: "accepted"
# note: "Code eval-grün und opt-in; realer Leak-Test steht aus. Ersetzt netns-usenet-confinement (deprecated)."
# date: "2026-07-30"
# related: [5043, 5310]
# supersedes: [5310]
# tags: ["vpn", "killswitch", "nftables", "skuid", "policy-routing", "leak-protection", "sabnzbd", "security"]
# error_pattern: "killswitch|kill-switch|vpn.*leak|skuid|policy.?routing|fwmark|netns|usenet-confinement|wg-media|privado|dns.?leak"
# ---

# ADR-5220 — Kill-Switch für SABnzbd: von Network Namespaces über eBPF zu nftables skuid + Policy-Routing

Diese ADR ist die Dokumentationsspur zum Modul `52-security/522-killswitch.nix`
(3-stellig künftig `520-security/522-killswitch.nix`). Sie hält den vollständigen
Denk- und Entscheidungsweg fest — netns → eBPF → skuid — damit die Wahl später
nachvollziehbar bleibt und nicht erneut aufgerollt wird.

Bezug: die Ableitungsregeln stammen aus **ADR-0000/5043 (Dezimalrahmen)**
(`Port = UID = Nummer × 10`, `GID = 5000`), die funktionalen Vorgaben aus der
**mediNix-Anforderungsspezifikation** (Abschnitt I: „Egress — da darf nichts
leaken"). Diese ADR ersetzt die netns-Lösung aus ADR-5310.

---

## 1. Kontext & Problem

SABnzbd lädt über das Usenet — hohes Volumen, NNTP, und der einzige Dienst im
Stack mit echtem Datenschutz-Bedarf. Seine ausgehenden Verbindungen dürfen die
reale IP des Hosts niemals offenbaren.

**Ursprüngliche Lösung (ADR-5310): Network Namespaces (`usenet-confinement`).**
SABnzbd (und Prowlarr) liefen in einem eigenen Netzwerk-Namespace, der nur das
WireGuard-Interface sah. Technisch dicht, aber betrieblich unangenehm:

- **Die direkte Erreichbarkeit bricht.** Ein Dienst in einem netns bindet nicht
  mehr einfach auf dem Host — man braucht `socat`/veth/Port-Forwarding-Tricks,
  um von LAN oder `.local` an die Weboberfläche zu kommen. Genau das, was der
  Betreiber täglich tun will (SABnzbd im Browser öffnen), wird umständlich.
- **Viele Fußangeln.** veth-Paare, Routing-innerhalb-des-Namespace, DNS-Mounts,
  Reihenfolge der Units — jede Stelle ist eine potenzielle Fehlerquelle.
- **Confinement zu breit.** Die Lösung sperrte auch Prowlarr ein, obwohl der
  Indexer keine Medien lädt und nicht denselben Schutz braucht.

**Anforderung (unverrückbar):**

- Nur **SABnzbd** absichern, nicht der ganze Stack.
- **100 % fail-closed Kill-Switch:** VPN weg → kein einziges Byte von SABnzbd
  verlässt den Host. Keine Leaks — auch nicht bei DNS oder IPv6.
- Der Dienst bleibt **normal per LAN / `.local`** erreichbar (kein netns).
- **Per Assertion erzwungen** (fail-closed am Build, nicht nur zur Laufzeit).

---

## 2. Bewertete Alternativen

| Ansatz | Rolle | Bewertung |
|---|---|---|
| **Network Namespaces** (Ist, ADR-5310) | verworfen | Dicht, aber bricht direkte Erreichbarkeit; viele bewegliche Teile; confinet zu breit. |
| **eBPF** (cgroup/tc egress + Mark/Drop) | verworfen | „Speerspitze" — aber für dieses Problem die falsche Abstraktionsebene (siehe §3). |
| **nftables `meta skuid` + Policy-Routing + Drop** | **gewählt** | Direkte Kernel-Primitive für „Owner darf nur über Interface Y"; deklarativ, prüfbar, fail-closed. |

---

## 3. Warum eBPF hier nicht die bessere Wahl war

eBPF ist die Speerspitze für **programmierbare** Kernel-Logik: feingranulare,
zustandsbehaftete, L7-nahe Entscheidungen, massive Skalierung (Cilium, Tetragon).
Für die Probleme, für die es gemacht ist, ist es überlegen.

Dieses Problem ist aber kein programmierbares, sondern ein klassisches
**Owner-+-Interface-Policy-Problem**: „UID 5410 darf nur über `cfg.vpn.interface`,
sonst droppen." Dafür hat der Linux-Kernel bereits eine direkte, seit Jahren
erprobte Primitive — netfilter **`meta skuid` / owner-matching**.

Ein eBPF-Weg hätte bedeutet: ein Programm schreiben/generieren, das
`bpf_get_current_uid_gid()` liest und markt/dropt; laden und pinnen; Lifecycle,
Verifikation, Updates und Debugging selbst absichern. Also mit **mehr Code, mehr
Angriffsfläche und schlechterer Prüfbarkeit** etwas nachbauen, was nftables
direkt und deklarativ kann — **ohne Sicherheitsgewinn** für genau diesen Fall.

Sicherheits-Leitsatz, der hier greift: *die einfachste korrekte Lösung, die man
leicht prüfen kann, ist der komplexeren „moderneren" vorzuziehen.* Ein kurzer,
lesbarer nftables-Block plus eine Assertion, die dieselbe Invariante prüft, ist
härter und zuverlässiger als ein selbstgepflegtes eBPF-Programm.

---

## 4. Die gewählte Architektur

Drei Schichten plus drei geschlossene Leak-Vektoren.

### 4.1 Marking — `type route`-Chain (der kritische Punkt)

```nft
chain mark {
  type route hook output priority mangle; policy accept;
  meta skuid 5410 meta mark set 5410
}
```

`type route` ist entscheidend: nur dieser Hook signalisiert dem Kernel „ein
routing-relevantes Feld hat sich geändert, route neu". Ein Mark in einer normalen
Filter-Chain käme **nach** der Routing-Entscheidung und würde keine Neu-Routung
auslösen — SABnzbd ginge weiter über die Default-Route und träfe den Drop. Das
ist der Fehler, an dem naive „nur accept+drop"-Varianten scheitern.

### 4.2 Policy-Routing — fwmark → eigene Tabelle → VPN

```
ip rule add    fwmark 5410 table 5410      (v4 + v6)
ip route replace default dev ${vpn.interface} table 5410
```

Deklarativ als geordnete `oneshot`-Unit (`medinix-killswitch-route`,
`RemainAfterExit`), die **vor** SABnzbd läuft. Markierte Pakete werden aktiv
durch das VPN geschickt — unabhängig von der normalen Default-Route des Hosts
(nur SABnzbd über VPN, der Rest direkt).

### 4.3 Fail-closed Drop — v4 + v6

```nft
chain killswitch {
  type filter hook output priority 0; policy accept;
  meta skuid 5410 oifname "${vpn.interface}" accept
  meta skuid 5410 drop
}
```

Der eigentliche Kill-Switch. Fällt Route oder Interface weg, matcht `accept`
nicht mehr → jedes Paket von UID 5410 wird verworfen. `family = "inet"` deckt
**IPv4 und IPv6** ab (sonst leakt v6 vorbei). Der Drop ist der ultimative
Backstop: selbst wenn das Routing versagt, fängt der Filter jedes Byte ab.

### 4.4 DNS-Leak-Prävention

Der häufigste Leak ist nicht der Daten-Traffic, sondern die DNS-Anfrage über
den System-Resolver (`systemd-resolved`, **andere UID** → an der skuid-Regel
vorbei). Gegenmaßnahme: SABnzbd bekommt ein **privates `resolv.conf`**, das nur
die VPN-DNS-Server (`cfg.vpn.dns`) enthält:

```nix
environment.etc."medinix-killswitch-resolv.conf".text = "nameserver …";
systemd.services.sabnzbd.serviceConfig.BindReadOnlyPaths =
  [ "/etc/medinix-killswitch-resolv.conf:/etc/resolv.conf" ];
```

Da diese DNS-IPs nur über die VPN-Tabelle erreichbar sind, greift der Kill-Switch
automatisch auch für DNS. Zusätzlich system-weites **DoT** (opt-in, `medinix.
security.dnsOverTls`), damit im ganzen Stack kein Klartext-DNS mehr läuft.

### 4.5 Boot-Race-Vermeidung

```nix
systemd.services.sabnzbd.after    = [ "nftables.service" "medinix-killswitch-route.service" ];
systemd.services.sabnzbd.requires = [ "medinix-killswitch-route.service" ];
```

SABnzbd startet nachweislich erst, wenn Regeln und Route stehen — kein Startfenster
mit Leak. Scheitert das Routing (Interface unten), failt die Unit → SABnzbd startet
gar nicht (fail-closed).

### 4.6 Nur SABnzbd

Anders als das netns-Modul (das auch Prowlarr einsperrte) betrifft der Kill-Switch
**ausschließlich** SABnzbd (UID 5410). Der Rest des Stacks — Player, Arrs, Requests —
läuft direkt und bleibt normal erreichbar.

---

## 5. Verhältnis zur Identity-Architektur

Der Kill-Switch baut direkt auf dem Dezimalrahmen (ADR-0000/5043) auf:

- **`Port = UID = Nummer × 10`** → SABnzbd (Dateinummer `541`) ist **UID 5410**.
- Die nftables-`skuid`-Regel, der fwmark und die Routing-Tabelle nutzen **exakt
  diese `5410`** — die Identität *ist* die Firewall-Adresse. Ohne die Invariante
  gäbe es kein stabiles Ziel für `meta skuid`.
- Deshalb ist die schärfste Assertion: **SABnzbd muss real UID 5410 tragen.**
  Läuft der Dienst (etwa bei abgeschaltetem `wireFixedUids`) auf einer anderen UID,
  greift die skuid-Regel ins Leere und *alles* leakt unbemerkt — der Build bricht
  dann fail-closed ab. Die Canonical ID ist damit nicht Kosmetik, sondern die
  tragende Voraussetzung des Kill-Switches.

---

## 6. Migrationspfad

1. **netns-Modul (`521-usenet-confinement`) bleibt vorerst**, ist aber
   `status: deprecated` und wirft zur Laufzeit eine `warnings`-Meldung, die auf
   den Kill-Switch verweist.
2. **Neuer Kill-Switch ist opt-in und inert:** `grapefruitMedia.vpn.killswitch.
   enable`, Default aus. Solange er aus ist, ändert sich nichts am laufenden System.
3. **Gegenseitiger Ausschluss als harte Assertion:** killswitch und netns dürfen
   nicht gleichzeitig aktiv sein — beim Scharfschalten *muss* `usenet-confinement.
   enable = false` gesetzt werden, sonst bricht der Build.
4. **Scharfschaltung erst nach realem Leak-Test:** WireGuard-Interface + Privado-Key
   einrichten → `killswitch.enable = true` (+ netns aus) → `nixos-rebuild switch`
   → `scripts/vpn-killswitch-test.sh` fahren (VPN oben = Traffic über Tunnel,
   VPN unten = kein Byte, DNS-Leak-Check). Erst dann gilt es als bewiesen dicht.

---

## 7. Was bewusst nicht getan wird

- **Kein netns mehr** — die direkte Erreichbarkeit ist eine harte Anforderung.
- **Kein eBPF** für diesen Kill-Switch — falsche Abstraktionsebene, kein Gewinn (§3).
- **Kein Zwang des gesamten Media-Stacks durch das VPN** — nur SABnzbd. Player,
  Arrs und Requests laufen direkt; sie brauchen keinen Tunnel und würden durch VPN
  nur Latenz und Erreichbarkeitsprobleme bekommen.
- **Kein Auto-Aktivieren auf q958**, solange kein realer Key + Leak-Test vorliegt.

---

## 8. Status & offene Punkte

- **Code eval-grün:** das Modul evaluiert aktiviert zu einer gültigen Systemableitung;
  `format`/`statix`/`deadnix`/`dezimalrahmen` grün. Die Ausschluss-Assertion ist
  gegengetestet (killswitch + netns → Build bricht).
- **Assertions vorhanden:** UID-5410-Invariante, netns-Ausschluss, nftables-Tabelle
  `family=inet` (v4+v6), Policy-Routing-Unit, Start-Reihenfolge, privates resolv.conf,
  `interface`/`dns` nicht leer.
- **Realer Leak-Test steht aus** — kein Privado-Key auf q958 aktiv. Die reinen
  Laufzeit-Fakten (echte `ip rule`, Drop-Zähler, tatsächliches Verhalten bei VPN-weg)
  prüft `scripts/vpn-killswitch-test.sh`, nicht die Build-Assertion.
- **System-weites DoT** ist host-seitig teilweise bereits vorhanden (q958 nutzt
  `systemd-resolved` mit DoT); die neue Option `medinix.security.dnsOverTls` macht
  es für den Stack explizit und wiederholbar.

---

## 9. Entscheidungstabelle

| Entscheidung | Chosen | Rejected | Grund |
|---|---|---|---|
| Confinement-Mechanismus | nftables `skuid` + Policy-Routing + Drop | Network Namespaces | Direkte Erreichbarkeit erhalten, weniger bewegliche Teile |
| Enforcement-Technologie | netfilter/nftables (deklarativ) | eBPF | Direkte Kernel-Primitive; weniger Code/Angriffsfläche; prüfbar |
| Marking-Hook | `type route`, priority mangle | Filter-Chain-Mark | Nur `type route` löst die Neu-Routung aus |
| IP-Version | inet (v4 + v6) | nur v4 | v6 würde sonst vorbei-leaken |
| DNS | privates resolv.conf + VPN-DNS + DoT | System-Resolver | System-Resolver läuft unter anderer UID → Leak |
| Scope | nur SABnzbd (UID 5410) | ganzer Stack / auch Prowlarr | Nur der Downloader braucht den Tunnel |
| Aktivierung | opt-in, fail-closed, nach Leak-Test | sofort scharf | Ohne realen Tunnel nicht beweisbar dicht |
| Interface-Bezug | `cfg.vpn.interface` (Default „privado") | hardcodiertes „wg-media" | Portabilität fürs öffentliche Flake |
