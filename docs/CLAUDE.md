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
