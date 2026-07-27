#!/usr/bin/env bash
# version_guard.sh — SQLite-Version-Guard gegen den WAL-Reset-Data-Race (sqlite/R10).
#
# AC6 (docs/specs/research-datenmodell.md): die tatsaechlich GEBUNDENE SQLite-Version
# muss vor JEDEM Schreibzugriff geprueft werden. Betroffen sind alle Versionen
# 3.7.0..3.51.2 (Korruptionsrisiko bei >=2 gleichzeitigen schreibenden Verbindungen,
# hier gegeben: Watchlist-Job + /research-Lauf, BR-019). Fix ab 3.51.3; Backports
# fuer 3.44.6 und 3.50.7 verfuegbar (knowledge/sql-sqlite.md sqlite/R10).
#
# Gedacht zum Sourcen (nicht nur von migrate.sh, auch von spaeterem M2-Skill-Code,
# sobald dieser eine eigene Sprache/einen eigenen Treiber bindet -- dann MUSS die dort
# tatsaechlich gebundene Treiber-Version erneut gegen sqlite_version_ok geprueft werden,
# der aktuelle Check deckt nur den `sqlite3`-CLI-Prozess ab, der db_scripts anwendet).

# sqlite_version_ok <version-string "X.Y.Z">
# Rueckgabe 0 = ok (Migration/Write darf laufen), 1 = Verstoss (muss abbrechen).
sqlite_version_ok() {
  local v="$1"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$v"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"

  # Backport-Ausnahmen: exakte Branches, ab dem gepatchten Punkt-Release (coder.md-Lesson 2026-07-26).
  if [ "$major" -eq 3 ] && [ "$minor" -eq 44 ] && [ "$patch" -ge 6 ]; then
    return 0
  fi
  if [ "$major" -eq 3 ] && [ "$minor" -eq 50 ] && [ "$patch" -ge 7 ]; then
    return 0
  fi

  # Haupt-Linie: Fix ab 3.51.3 (und alles danach: 3.52.x, 4.x, ...).
  if [ "$major" -gt 3 ]; then
    return 0
  fi
  if [ "$major" -eq 3 ] && [ "$minor" -gt 51 ]; then
    return 0
  fi
  if [ "$major" -eq 3 ] && [ "$minor" -eq 51 ] && [ "$patch" -ge 3 ]; then
    return 0
  fi

  return 1
}

# require_sqlite_version_or_die <db-path-nur-fuer-fehlermeldung>
# Prueft die ueber die `sqlite3`-CLI tatsaechlich gebundene Library-Version.
# Schlaegt der Guard fehl: klare Fehlermeldung auf stderr + exit 2 -- KEIN stiller
# Betrieb, KEIN Schreibzugriff gegen die Ziel-DB (Query laeuft gegen ':memory:').
require_sqlite_version_or_die() {
  local db_for_message="${1:-<unbekannt>}"
  local current
  current="$(sqlite3 ':memory:' 'select sqlite_version();')"
  if ! sqlite_version_ok "$current"; then
    {
      echo "FATAL: gebundene SQLite-Version ${current} erfuellt den WAL-Reset-Guard nicht (sqlite/R10)."
      echo "  Erforderlich: >= 3.51.3, oder Backport 3.44.6 / 3.50.7."
      echo "  Siehe knowledge/sql-sqlite.md sqlite/R10 (WAL-Reset-Data-Race, Korruptionsrisiko bei Multi-Writer)."
      echo "  Migration abgebrochen -- kein Schreibzugriff gegen '${db_for_message}' erfolgt."
    } >&2
    return 2
  fi
  return 0
}

# Direkt ausfuehrbar (nicht nur sourcebar): CLI-Version pruefen und Ergebnis melden.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  if require_sqlite_version_or_die "(direkter Guard-Check, keine Ziel-DB)"; then
    echo "OK: gebundene SQLite-Version $(sqlite3 ':memory:' 'select sqlite_version();') erfuellt sqlite/R10."
    exit 0
  else
    exit 2
  fi
fi
