#!/usr/bin/env bash
# apply_migrations.sh — forward-only Migrations-Anwendung (sqlite/R06).
#
# WICHTIG (coder.md-Lesson 2026-07-27): diese Funktion fuehrt NIE selbst den
# Version-Guard aus und darf NICHT der alleinige Einstiegspunkt sein -- der
# Guard (version_guard.sh) MUSS vorher separat laufen. migrate.sh ruft beide in
# der richtigen Reihenfolge (Guard, dann apply_migrations). Diese Trennung
# erlaubt ausserdem gezieltes Testen der Anwendungs-Logik (Idempotenz, WAL,
# Marker-Tabelle) unabhaengig vom Guard-Ergebnis der jeweiligen Testumgebung.

# apply_migrations <db-path> <db_scripts-dir>
# Wendet alle db_scripts/<NNN>_name.sql an, die noch nicht in _schema_migrations
# vermerkt sind (Marker-Tabelle wird durch 001_init.sql selbst angelegt -- kein
# separater Bootstrap-Write vor dem Guard noetig). Gibt je angewandter Migration
# eine Zeile "applied: <version>" aus (leere Ausgabe = alles bereits angewandt =
# idempotenter no-op).
apply_migrations() {
  local db="$1"
  local script_dir="$2"
  local applied=""
  local have_marker_table=0

  if sqlite3 "$db" \
    "SELECT name FROM sqlite_master WHERE type='table' AND name='_schema_migrations';" \
    | grep -qx "_schema_migrations"; then
    have_marker_table=1
    applied="$(sqlite3 "$db" "SELECT version FROM _schema_migrations ORDER BY version;")"
  fi

  local file version checksum stored_checksum
  for file in "$script_dir"/[0-9][0-9][0-9]_*.sql; do
    [ -e "$file" ] || continue
    version="$(basename "$file" .sql)"

    if ! [[ "$version" =~ ^[0-9]{3}_[A-Za-z0-9_]+$ ]]; then
      echo "FATAL: Migrationsdateiname '$version' verletzt die Konvention <NNN>_name (sqlite/R06)." >&2
      return 1
    fi

    checksum="$(shasum -a 256 "$file" | awk '{print $1}')"

    if ! [[ "$checksum" =~ ^[0-9a-f]{64}$ ]]; then
      echo "FATAL: berechneter Checksum fuer '$version' verletzt das Muster ^[0-9a-f]{64}\$ (security/R03)." >&2
      return 1
    fi

    if [ "$have_marker_table" -eq 1 ] && [ -n "$applied" ] && echo "$applied" | grep -qx "$version"; then
      # Bereits angewandt: gespeicherten Checksum gegen den aktuell berechneten
      # pruefen -- eine nachtraeglich editierte (forward-only verbotene)
      # Migrationsdatei muss FATAL auffallen statt still uebersprungen zu werden
      # (sqlite/R06, Review-Fund Iteration 1).
      stored_checksum="$(sqlite3 "$db" "SELECT checksum FROM _schema_migrations WHERE version = '$version';")"
      if [ "$stored_checksum" != "$checksum" ]; then
        echo "FATAL: Checksum-Mismatch fuer bereits angewandte Migration '$version' (gespeichert: '$stored_checksum', aktuell: '$checksum'). Migrationsdatei wurde nachtraeglich editiert -- forward-only verletzt (sqlite/R06)." >&2
        return 1
      fi
      continue
    fi

    # Atomarität (sqlite/R06, DBA-Review-Fund Iteration 2): .read $file + der
    # Marker-INSERT laufen in EINER expliziten Transaktion mit '.bail on' --
    # schlaegt ein Statement in der Migrationsdatei fehl (z.B. Typo), bricht
    # sqlite3 sofort ab und die gesamte (noch offene, nicht committete)
    # Transaktion wird beim Verbindungsende zurueckgerollt: weder Teil-Schema
    # noch Marker-Zeile bleiben zurueck, ein Retry mit korrigierter Datei ist
    # moeglich (kein falscher Checksum-/forward-only-Verstoss).
    #
    # Vorab-Schritt AUSSERHALB der Transaktion: journal_mode auf WAL setzen.
    # Grund: 'PRAGMA journal_mode=WAL' laesst sich NICHT innerhalb einer
    # offenen Transaktion aendern (SQLite lehnt das mit einem Runtime-Error
    # ab) -- 001_init.sql enthaelt genau dieses PRAGMA. Ist der Modus hier
    # schon WAL gesetzt, ist die identische PRAGMA-Zeile in der Migrationsdatei
    # innerhalb der Transaktion ein no-op (kein Fehler, keine Aenderung).
    sqlite3 "$db" "PRAGMA journal_mode = WAL;" > /dev/null

    if ! sqlite3 "$db" <<SQL
.bail on
BEGIN;
PRAGMA foreign_keys = ON;
.read $file
INSERT INTO _schema_migrations (version, checksum) VALUES ('$version', '$checksum');
COMMIT;
SQL
    then
      echo "FATAL: Migration '$version' schlug fehl -- die Transaktion (Migrations-DDL + Marker-INSERT) wurde beim Verbindungsende zurueckgerollt, weder Teil-Schema noch Marker-Zeile wurden uebernommen (sqlite/R06). Datei korrigieren und erneut anwenden." >&2
      return 1
    fi

    echo "applied: $version"
  done
}
