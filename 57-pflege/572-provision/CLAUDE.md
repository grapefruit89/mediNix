# 572-provision — Erstkonfiguration der Dienste

Traegt API-Keys ein, verbindet Prowlarr mit den *arr, setzt Pfade.

## Acht oneshot-Units, kein Ueber-Skript

Begruendung in ADR-5035, und sie ist eine Anwendung von AGENTS.md Regel 5:
**systemd besitzt Lebenszyklus und Orchestrierung.** Reihenfolge, Wiederholung,
Teilerfolge und Sichtbarkeit macht systemd besser als jeder selbstgeschriebene
Orchestrator — und `systemctl status` zeigt genau, welcher Schritt haengt.

Ein Skript, das alle acht Schritte macht, gibt dir bei Fehler 3 nur „exit 1".

## Secrets ausschliesslich als Dateipfade

Niemals als Env-Wert, niemals als Kommandozeilenargument. Beides landet in
`/proc/<pid>/environ` bzw. in der Prozessliste und ist fuer jeden lokalen
Benutzer lesbar.

```nix
apiKeyFile = "/var/lib/secrets/prowlarr.key";   # richtig
apiKey     = "abc123";                          # verboten
```

## Der Zustand hier ist unvollstaendig — ehrlich bleiben

`provision` ist **nicht aktiviert**, weil die API-Keys fehlen. Wer den Ordner
anfasst, kann ihn nicht end-to-end pruefen. Das gehoert in jede Aussage dazu.

## API-Felder niemals aus dem Gedaechtnis

`docs/api-reference.md` fuehrt den Verifikationsstand je Endpunkt (✅ / ⚠️ / ❌).
Eine falsch erinnerte Feldbezeichnung faellt **nicht beim Bauen** auf, sondern
Wochen spaeter beim ersten echten Download. Die Quell-URLs dort sind Architektur
und duerfen bei Refactorings nicht entfernt werden.
