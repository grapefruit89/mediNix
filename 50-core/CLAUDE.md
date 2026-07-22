# docs — ADRs, Referenzen, Topologie

Ausfuehrliche Regeln in `.claude/rules/docs-adr.md` (laedt automatisch bei
Pfaden unter `docs/`).

## Das Wichtigste in drei Saetzen

1. Ein ADR haelt fest **warum**, nicht was. Das Was steht im Code.
2. `error_pattern` im Frontmatter ist maschinenlesbar — ohne das Feld ist ein ADR
   bei der Fehlersuche unauffindbar.
3. Widerlegtes wird **nicht geloescht**, sondern auf `superseded` gesetzt. Ein
   geloeschtes ADR laedt ein, denselben Fehler nochmal zu machen.

## api-reference.md hat einen Verifikationsstand

Die Tabelle mit ✅ / ⚠️ / ❌ je Quelle ist kein Schmuck. Wenn eine OpenAPI-Spec in
ein Groessenlimit laeuft, wird das **markiert** — nicht geraten und weitergemacht.

Die Quell-URLs dort sind Architektur, kein Kommentar-Ballast. Wer sie bei einem
Refactoring entfernt, nimmt dem naechsten Bearbeiter die Moeglichkeit zu
verifizieren und zwingt ihn zum Raten.

## Was in docs/ liegt

| Datei | Rolle |
|---|---|
| `ONBOARDING.md` | Von der leeren Maschine bis elf laufende Dienste, mit Prüfung je Schritt |
| `ARCHITEKTUR.md` | Wie devNIX, mediNix, q958 und Claude Code zusammenhängen |
| `RUNBOOK.md` | Fehler → Diagnose → Behebung, je Abschnitt ein `error_pattern` |
| `adr/` | Entscheidungen mit Begründung |
| `api-reference.md` | Endpunkte samt Verifikationsstand (✅/⚠️/❌) |
| `network-topology.md` | Erreichbarkeit LAN/WAN/VPN, TLS |
| `archiv/` | **Überholt.** Aufgehoben, weil Code-Kommentare auf Befunde darin verweisen (K2, K4, H4.2). Kein Zielzustand mehr — jede „SSoT"-Aussage darin gilt nicht |

## Neuen Runbook-Eintrag anlegen

Vier Pflichtteile, sonst ist er wertlos:

1. `error_pattern` — maschinenlesbar, sonst findet ihn niemand
2. Das Symptom **wörtlich**, nicht umschrieben
3. Die **widerlegte Erstannahme** — der am häufigsten weggelassene Teil
4. Der Gegentest, der die Ursache belegt
