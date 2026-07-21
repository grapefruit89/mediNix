# 540-audiobookshelf — Hoerbuecher und Podcasts

Port 5420. Antwortet mit **200**.

## Der seccomp-Fehler, der wortlos toetet

Das war L4. `SystemCallFilter` toetet den Prozess per **SIGSYS**, wenn ein
verbotener Syscall kommt — ohne Log, ohne Fehlermeldung, ohne Hinweis worauf.
Man sieht nur einen Dienst, der stirbt.

```nix
SystemCallErrorNumber = "EPERM";
```

Damit gibt der Kernel `EPERM` **zurueck**, statt zu toeten. Die Anwendung sieht
einen normalen Fehler, protokolliert ihn, und man weiss endlich welcher Syscall
das Problem ist.

> **Diese Zeile gehoert in jede seccomp-Haertung.** Ohne sie debuggst du blind.

## Warum 200 und nicht 302

Audiobookshelf liefert seine SPA direkt aus, ohne Login-Redirect. Ein 200 ist
hier also erwartbar — bei den *arr waere es verdaechtig.
