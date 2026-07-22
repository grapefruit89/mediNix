# 521-usenet-confinement — Netzwerk-Einsperrung

Kein Dienst, sondern ein Mechanismus: er zwingt den Downloader durch den
VPN-Tunnel. Nummer 591, quer zu allem — deshalb am Ende der Blockfolge.

## Fail-closed ist hier keine Meinung

`vpn.dns` stand einmal auf `1.1.1.1` als Default. Wer den VPN-Resolver vergass,
bekam **funktionierendes DNS am Tunnel vorbei** — der Fehler war unsichtbar,
genau weil alles zu funktionieren schien.

Heute: Default `[ ]` plus Assertion, die den Build abbricht.

> Ein stiller Default, der im Fehlerfall „irgendwie funktioniert", ist schlimmer
> als gar keiner. Der Fehler wird nie sichtbar. (AGENTS.md Regel 4)

Wer hier einen Default setzt, muss beantworten: *was passiert, wenn der Betreiber
diesen Wert vergisst?* Lautet die Antwort „es laeuft trotzdem", ist der Default falsch.

## Bekannt offen

Nicht aktiv — es ist kein WireGuard-Key hinterlegt. Bewusst so, Secrets gehoeren
nicht ins Repo. Die Prowlarr-Synchronisation wird uebersprungen, solange der
Tunnel inaktiv ist.

## `repeated_keys` ist hier abgeschaltet

`statix.toml` deaktiviert die Regel repo-weit, und dieser Ordner ist der Grund:
ueber jeder `systemd.*`-Zuweisung steht ein mehrzeiliger Kommentar, der genau
diese eine Zuweisung erklaert. Zusammenfassen wuerde die Kommentare von ihren
Zeilen trennen.
