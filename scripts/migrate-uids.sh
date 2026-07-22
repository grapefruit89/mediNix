#!/usr/bin/env bash
# migrate-uids.sh — feste UIDs/GID nach ADR-8000 auf ein BESTEHENDES System bringen.
#
# WOZU
# NixOS nummeriert bestehende Benutzer nicht um (mutableUsers = true). Setzt man
# in der Config feste UIDs (grapefruitMedia.wireFixedUids = true), bleiben die
# laufenden Benutzer auf ihren alten Zahlen — der Switch meldet nur
# "not applying UID change of user 'X' (alt -> neu)". Die State-Dateien gehören
# dann noch der alten UID -> beim Start "permission denied". (Runbook Abschnitt 4.)
#
# Dieses Skript gleicht die laufenden UIDs/GID EINMALIG an die Config an und
# übereignet die Dateien (usermod/groupmod + chown).
#
# NICHT nötig bei einer FRISCHEN Installation — dort werden die Benutzer sofort
# mit der richtigen UID angelegt. Nur beim Migrieren eines bestehenden Systems.
#
#   migrate-uids.sh check    zeigt Ist vs. Soll, ändert NICHTS
#   migrate-uids.sh apply    führt die Migration aus (braucht root/sudo)
#
# Quelle der Soll-Werte: lib/registry.nix (UID = Nummer × 10, GID 5000).
# Der `dezimalrahmen`-Check (nix flake check) pinnt die Registry-Konsistenz.
# jellyseerr/seerr ist ausgenommen — läuft als systemd-DynamicUser.
set -uo pipefail

declare -A UID_OF=(
  [prowlarr]=5310 [sonarr]=5320 [radarr]=5330 [lidarr]=5340 [readarr]=5350
  [sabnzbd]=5410 [jellyfin]=5510 [audiobookshelf]=5520 [navidrome]=5530
)
GID_MEDIA=5000
SVCS="${!UID_OF[*]} seerr"

check() {
  local drift=0
  printf "  %-16s %-8s %-8s %s\n" "Dienst" "Ist" "Soll" "Status"
  for u in $(printf '%s\n' "${!UID_OF[@]}" | sort); do
    cur=$(id -u "$u" 2>/dev/null || echo "-")
    if [ "$cur" = "${UID_OF[$u]}" ]; then st="ok"; else st="ÄNDERN"; drift=1; fi
    printf "  %-16s %-8s %-8s %s\n" "$u" "$cur" "${UID_OF[$u]}" "$st"
  done
  gc=$(getent group media | cut -d: -f3)
  if [ "$gc" = "$GID_MEDIA" ]; then echo "  media-gid $gc  ok"; else echo "  media-gid $gc -> $GID_MEDIA  ÄNDERN"; drift=1; fi
  [ "$drift" = 0 ] && echo "  => alles auf Soll, keine Migration nötig." \
                   || echo "  => Abweichung. 'apply' bringt es in Ordnung."
}

apply() {
  echo "1/5 Dienste stoppen ..."
  systemctl stop $SVCS 2>/dev/null || true
  sleep 3
  echo "2/5 Gruppe media -> $GID_MEDIA"
  groupmod -g "$GID_MEDIA" media
  echo "3/5 Benutzer umnummerieren"
  for u in "${!UID_OF[@]}"; do
    id "$u" >/dev/null 2>&1 && usermod -u "${UID_OF[$u]}" "$u" && echo "     $u -> ${UID_OF[$u]}"
  done
  echo "4/5 State-Verzeichnisse übereignen (chown)"
  for u in "${!UID_OF[@]}"; do
    for d in "/var/lib/$u" "/var/cache/$u"; do
      [ -d "$d" ] && chown -R "${UID_OF[$u]}":media "$d" && echo "     $d"
    done
  done
  [ -d /data ] && chgrp -R media /data && echo "     /data -> Gruppe media"
  echo "5/5 Dienste starten ..."
  systemctl start $SVCS
  sleep 5
  echo ""
  echo "Kontrolle:"
  check
}

case "${1:-}" in
  check) check ;;
  apply)
    [ "$(id -u)" = 0 ] || { echo "apply braucht root — mit sudo aufrufen."; exit 1; }
    apply
    ;;
  *)
    echo "Aufruf: $0 check|apply"
    echo "  check  Ist vs. Soll anzeigen (ändert nichts)"
    echo "  apply  Migration ausführen (root)"
    exit 1
    ;;
esac
