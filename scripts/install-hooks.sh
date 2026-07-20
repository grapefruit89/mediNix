#!/usr/bin/env bash
# Pre-Commit-Hook installieren.
#
#   ./scripts/install-hooks.sh
#
# Bewusst ein einfaches Shell-Skript statt des pre-commit-Frameworks:
# das braucht Python, eine YAML-Konfiguration und einen eigenen Cache — für
# drei Prüfungen ist das mehr Maschinerie als Nutzen. Hier hängt alles an
# `nix`, das ohnehin vorhanden sein muss.
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
HOOK="$REPO/.git/hooks/pre-commit"

cat > "$HOOK" <<'HOOKEOF'
#!/usr/bin/env bash
# mediNix Pre-Commit — schnelle Prüfungen VOR dem Commit.
#
# Gedanke dahinter: nur was Sekunden dauert. Ein Hook, der eine Minute
# braucht, wird umgangen (git commit --no-verify) und ist damit wertlos.
# Der vollständige Lauf gehört in CI, nicht hierher.
set -uo pipefail

# Nur geänderte, zum Commit vorgemerkte .nix-Dateien prüfen.
FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.nix$' || true)
[ -z "$FILES" ] && exit 0

FAIL=0

echo "pre-commit: prüfe $(echo "$FILES" | wc -l) Nix-Datei(en)"

# 1. Syntax — der billigste und wichtigste Test.
for f in $FILES; do
  if ! nix-instantiate --parse "$f" >/dev/null 2>&1; then
    echo "  SYNTAXFEHLER: $f"
    FAIL=1
  fi
done

# 2. Formatierung.
if command -v nixfmt >/dev/null 2>&1; then
  for f in $FILES; do
    if ! nixfmt --check "$f" >/dev/null 2>&1; then
      echo "  NICHT FORMATIERT: $f"
      FAIL=1
    fi
  done
else
  echo "  (nixfmt nicht im PATH — übersprungen. 'nix develop' bringt es mit)"
fi

# 3. Toter Code.
if command -v deadnix >/dev/null 2>&1; then
  for f in $FILES; do
    if ! deadnix --fail "$f" >/dev/null 2>&1; then
      echo "  TOTER CODE: $f"
      FAIL=1
    fi
  done
fi

if [ "$FAIL" -ne 0 ]; then
  cat <<'MSG'

Commit abgebrochen.

  Beheben:   nix fmt              (Formatierung)
             deadnix --edit .     (toter Code)

  Umgehen:   git commit --no-verify
             — nur wenn du weißt, warum. CI prüft es ohnehin nochmal.

MSG
  exit 1
fi

echo "pre-commit: in Ordnung"
HOOKEOF

chmod +x "$HOOK"
echo "Hook installiert: $HOOK"
echo ""
echo "Werkzeuge bereitstellen mit:  nix develop"
