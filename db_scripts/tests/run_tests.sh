#!/usr/bin/env bash
# run_tests.sh — Self-Test fuer db_scripts (Migrations-Grundgeruest + Fremd-Store-Schutz).
#
# Rein mechanisches SQL/Shell-Test-Artefakt (M1 ist sprach-neutral, kein App-Layer
# existiert -- profile.md: language: md). Erfuellt die Spec-Vertragszeile
# "Tests taggen @trace research-datenmodell#AC<n>[,BR-NNN]" (coder.md-Lesson
# 2026-07-26: reines SQL/Shell-Test-Transkript reicht, solange es committet ist).
#
# Aufruf: db_scripts/tests/run_tests.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/version_guard.sh
source "$DB_SCRIPTS_DIR/lib/version_guard.sh"
# shellcheck source=../lib/apply_migrations.sh
source "$DB_SCRIPTS_DIR/lib/apply_migrations.sh"
# shellcheck source=../lib/attach_l30d_readonly.sh
source "$DB_SCRIPTS_DIR/lib/attach_l30d_readonly.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  OK:   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

echo "== @trace research-datenmodell#AC6 -- Migration frisch + idempotent =="
DB="$TMP/research-app.sqlite"
apply_migrations "$DB" "$DB_SCRIPTS_DIR" > "$TMP/run1.log"
apply_migrations "$DB" "$DB_SCRIPTS_DIR" > "$TMP/run2.log"
if [ -s "$TMP/run1.log" ] && [ ! -s "$TMP/run2.log" ]; then
  ok "erster Lauf wendet 001_init.sql an, zweiter Lauf ist no-op (Marker-Idempotenz, sqlite/R06)"
else
  bad "Idempotenz verletzt: run1=[$(cat "$TMP/run1.log")] run2=[$(cat "$TMP/run2.log")]"
fi

COUNT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM _schema_migrations;")"
if [ "$COUNT" = "1" ]; then
  ok "_schema_migrations enthaelt genau 1 Eintrag nach zwei Laeufen"
else
  bad "erwartet 1 Migrationseintrag, war $COUNT"
fi

JOURNAL="$(sqlite3 "$DB" "PRAGMA journal_mode;")"
if [ "$JOURNAL" = "wal" ]; then
  ok "journal_mode=wal persistiert (sqlite/R03)"
else
  bad "journal_mode war '$JOURNAL', erwartet wal"
fi

echo "== @trace research-datenmodell#AC6,sqlite/R02 -- foreign_keys=ON je Verbindung =="
FK_ERR="$TMP/fk.err"
if sqlite3 "$DB" <<'SQL' 2> "$FK_ERR"
PRAGMA foreign_keys = ON;
CREATE TEMP TABLE t_parent (id INTEGER PRIMARY KEY);
CREATE TEMP TABLE t_child (id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES t_parent(id));
INSERT INTO t_child (id, parent_id) VALUES (1, 999);
SQL
then
  bad "FK-Verletzung (Waisen-Insert) wurde NICHT abgelehnt -- foreign_keys-Pragma griff nicht"
else
  if grep -qi "FOREIGN KEY constraint failed" "$FK_ERR"; then
    ok "foreign_keys=ON lehnt Waisen-Insert innerhalb derselben Verbindung ab (sqlite/R02)"
  else
    bad "Insert schlug fehl, aber nicht wegen FK: $(cat "$FK_ERR")"
  fi
fi

echo "== @trace research-datenmodell#AC6,sqlite/R10 -- Versions-Guard-Vergleichslogik =="
check_case() {
  local v="$1" expect="$2" label="$3"
  local got
  if sqlite_version_ok "$v"; then got="ok"; else got="reject"; fi
  if [ "$got" = "$expect" ]; then
    ok "$label ($v -> $got)"
  else
    bad "$label ($v -> $got, erwartet $expect)"
  fi
}
check_case "3.51.3" "ok"     "Hauptlinien-Fix-Version"
check_case "3.51.2" "reject" "letzte verwundbare Hauptlinien-Version"
check_case "3.52.0" "ok"     "spaetere Hauptlinien-Version"
check_case "4.0.0"  "ok"     "zukuenftige Major-Version"
check_case "3.44.6" "ok"     "Backport-Punkt-Release 3.44.6"
check_case "3.44.5" "reject" "Backport-Branch vor dem Patch"
check_case "3.50.7" "ok"     "Backport-Punkt-Release 3.50.7"
check_case "3.50.6" "reject" "Backport-Branch vor dem Patch"

echo "== @trace research-datenmodell#AC6 -- migrate.sh: Guard laeuft VOR jedem Write =="
CLI_VERSION="$(sqlite3 ':memory:' 'select sqlite_version();')"
GUARD_DB="$TMP/guard-test.sqlite"
set +e
"$DB_SCRIPTS_DIR/migrate.sh" "$GUARD_DB" > "$TMP/guard.out" 2> "$TMP/guard.err"
RC=$?
set -e
if sqlite_version_ok "$CLI_VERSION"; then
  if [ "$RC" -eq 0 ] && [ -e "$GUARD_DB" ]; then
    ok "gebundene CLI-Version ($CLI_VERSION) erfuellt den Guard -- migrate.sh wendet an"
  else
    bad "Guard haette durchlassen sollen (Version $CLI_VERSION ok), rc=$RC: $(cat "$TMP/guard.err")"
  fi
else
  if [ "$RC" -ne 0 ] && [ ! -e "$GUARD_DB" ] && grep -qi "FATAL" "$TMP/guard.err"; then
    ok "gebundene CLI-Version ($CLI_VERSION) verletzt sqlite/R10 -- migrate.sh verweigert, DB-Datei bleibt ungeschrieben"
  else
    bad "Guard haette ablehnen sollen (Version $CLI_VERSION zu alt), rc=$RC db_exists=$([ -e "$GUARD_DB" ] && echo yes || echo no): $(cat "$TMP/guard.err")"
  fi
fi

echo "== @trace research-datenmodell#AC6,sqlite/R06 -- kaputte Migrationsdatei: Transaktion wird zurueckgerollt, Retry moeglich =="
BROKEN_TMP="$TMP/mig-broken-dir"
mkdir -p "$BROKEN_TMP"
cat > "$BROKEN_TMP/001_broken.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS _schema_migrations (
  version     TEXT NOT NULL PRIMARY KEY,
  applied_at  TEXT NOT NULL DEFAULT (datetime('now')),
  checksum    TEXT
) STRICT;
CREATE TABLE ok_table (id INTEGER PRIMARY KEY) STRICT;
CREATE TABLE broken_table (id INTEGER PRIMARY KEY) STRCT;
SQL
BROKEN_DB="$TMP/broken.sqlite"
BROKEN_ERR="$TMP/broken.err"
set +e
apply_migrations "$BROKEN_DB" "$BROKEN_TMP" > "$TMP/broken-run1.log" 2> "$BROKEN_ERR"
BROKEN_RC=$?
set -e
if [ "$BROKEN_RC" -ne 0 ]; then
  ok "kaputte Migrationsdatei (Typo 'STRCT') laesst apply_migrations mit rc!=0 abbrechen"
else
  bad "kaputte Migrationsdatei haette apply_migrations abbrechen lassen muessen, rc=$BROKEN_RC"
fi

BROKEN_TABLES="$(sqlite3 "$BROKEN_DB" "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null || true)"
if [ -z "$BROKEN_TABLES" ]; then
  ok "kein Teil-Schema zurueckgeblieben (weder ok_table noch _schema_migrations, Rollback griff, sqlite/R06)"
else
  bad "Teil-Schema haette vollstaendig zurueckgerollt sein muessen, gefunden: $BROKEN_TABLES"
fi

# Datei korrigieren (Typo entfernen) -- ein Retry mit derselben DB muss sauber durchgehen,
# da weder Teil-Schema noch Marker-Zeile vom fehlgeschlagenen Lauf zurueckblieben.
cat > "$BROKEN_TMP/001_broken.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS _schema_migrations (
  version     TEXT NOT NULL PRIMARY KEY,
  applied_at  TEXT NOT NULL DEFAULT (datetime('now')),
  checksum    TEXT
) STRICT;
CREATE TABLE ok_table (id INTEGER PRIMARY KEY) STRICT;
CREATE TABLE broken_table (id INTEGER PRIMARY KEY) STRICT;
SQL
apply_migrations "$BROKEN_DB" "$BROKEN_TMP" > "$TMP/broken-run2.log"
RETRY_TABLES="$(sqlite3 "$BROKEN_DB" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")"
if [ -s "$TMP/broken-run2.log" ] && echo "$RETRY_TABLES" | grep -qx "broken_table" && echo "$RETRY_TABLES" | grep -qx "ok_table"; then
  ok "Retry mit korrigierter Datei geht sauber durch (kein falscher Checksum-/forward-only-Verstoss)"
else
  bad "Retry haette durchgehen sollen, Tabellen: $RETRY_TABLES, Log: $(cat "$TMP/broken-run2.log")"
fi

echo "== @trace research-datenmodell#AC6,sqlite/R06 -- Checksum-Mismatch bei editierter Migration wird erkannt =="
MIG_TMP="$TMP/mig-checksum-dir"
mkdir -p "$MIG_TMP"
cat > "$MIG_TMP/001_first.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS _schema_migrations (
  version     TEXT NOT NULL PRIMARY KEY,
  applied_at  TEXT NOT NULL DEFAULT (datetime('now')),
  checksum    TEXT
) STRICT;
CREATE TABLE t_a (id INTEGER PRIMARY KEY) STRICT;
SQL
MISMATCH_DB="$TMP/mismatch.sqlite"
apply_migrations "$MISMATCH_DB" "$MIG_TMP" > "$TMP/mismatch-run1.log"
if [ -s "$TMP/mismatch-run1.log" ]; then
  ok "erster Lauf wendet 001_first.sql im isolierten Test-Verzeichnis an"
else
  bad "erster Lauf haette 001_first.sql anwenden muessen, Log war leer"
fi

# Datei nachtraeglich editieren (forward-only-Verstoss simulieren) -- Checksum aendert sich.
printf '\n-- edited\n' >> "$MIG_TMP/001_first.sql"

MISMATCH_ERR="$TMP/mismatch.err"
set +e
apply_migrations "$MISMATCH_DB" "$MIG_TMP" > "$TMP/mismatch-run2.log" 2> "$MISMATCH_ERR"
MISMATCH_RC=$?
set -e
if [ "$MISMATCH_RC" -ne 0 ] && grep -qi "Checksum-Mismatch" "$MISMATCH_ERR"; then
  ok "editierte, bereits angewandte Migration wird per Checksum-Mismatch FATAL erkannt (sqlite/R06)"
else
  bad "Checksum-Mismatch haette FATAL abbrechen muessen, rc=$MISMATCH_RC: $(cat "$MISMATCH_ERR")"
fi

echo "== @trace research-datenmodell#AC8,BR-018 -- last30days ausschliesslich read-only ATTACHt =="
L30D="$TMP/last30days-store.sqlite"
sqlite3 "$L30D" "CREATE TABLE plugin_table (id INTEGER PRIMARY KEY, val TEXT); INSERT INTO plugin_table VALUES (1, 'original');"

ATTACH_SQL="$(attach_l30d_readonly_sql "$L30D")"
RESEARCH_DB="$TMP/research-app-attach-test.sqlite"

READ_OUT="$(sqlite3 "$RESEARCH_DB" "$ATTACH_SQL
SELECT val FROM l30d.plugin_table WHERE id = 1;")"
if [ "$READ_OUT" = "original" ]; then
  ok "read-only ATTACH erlaubt SELECT gegen den last30days-Store"
else
  bad "SELECT lieferte '$READ_OUT', erwartet 'original'"
fi

WRITE_ERR="$TMP/write.err"
if sqlite3 "$RESEARCH_DB" "$ATTACH_SQL
UPDATE l30d.plugin_table SET val = 'mutated' WHERE id = 1;" 2> "$WRITE_ERR"; then
  bad "Schreibversuch gegen read-only-ge-ATTACHten last30days-Store wurde NICHT abgelehnt (BR-018 verletzt)"
else
  if grep -qi "readonly" "$WRITE_ERR"; then
    ok "Engine lehnt Schreibversuch gegen l30d.* selbst ab ('readonly database', BR-018)"
  else
    bad "Schreibversuch schlug fehl, aber nicht wegen readonly: $(cat "$WRITE_ERR")"
  fi
fi

UNCHANGED="$(sqlite3 "$L30D" "SELECT val FROM plugin_table WHERE id = 1;")"
if [ "$UNCHANGED" = "original" ]; then
  ok "last30days-Store-Inhalt bleibt nach dem Schreibversuch unveraendert"
else
  bad "last30days-Store wurde veraendert: '$UNCHANGED'"
fi

echo "== @trace research-datenmodell#AC8,security/R03 -- Pfad mit Apostroph wird SQL-escaped =="
L30D_QUOTE_DIR="$TMP/it's a dir"
mkdir -p "$L30D_QUOTE_DIR"
L30D_QUOTE="$L30D_QUOTE_DIR/last30days-store.sqlite"
sqlite3 "$L30D_QUOTE" "CREATE TABLE plugin_table (id INTEGER PRIMARY KEY, val TEXT); INSERT INTO plugin_table VALUES (1, 'quoted-path-ok');"

QUOTE_ATTACH_SQL="$(attach_l30d_readonly_sql "$L30D_QUOTE")"
QUOTE_RESEARCH_DB="$TMP/research-app-quote-test.sqlite"
QUOTE_READ_OUT="$(sqlite3 "$QUOTE_RESEARCH_DB" "$QUOTE_ATTACH_SQL
SELECT val FROM l30d.plugin_table WHERE id = 1;")"
if [ "$QUOTE_READ_OUT" = "quoted-path-ok" ]; then
  ok "ATTACH gegen einen Pfad mit Apostroph escaped korrekt und liest den richtigen Store (security/R03)"
else
  bad "ATTACH mit Apostroph-Pfad lieferte '$QUOTE_READ_OUT', erwartet 'quoted-path-ok'"
fi

echo "== @trace research-datenmodell#AC8,security/R03 -- ungueltiger Alias wird abgelehnt =="
set +e
BAD_ALIAS_OUT="$(attach_l30d_readonly_sql "$L30D" "l30d; DROP TABLE plugin_table;--" 2>"$TMP/bad-alias.err")"
BAD_ALIAS_RC=$?
set -e
if [ "$BAD_ALIAS_RC" -ne 0 ] && [ -z "$BAD_ALIAS_OUT" ] && grep -qi "FATAL" "$TMP/bad-alias.err"; then
  ok "Alias mit unzulaessigen Zeichen wird vor der SQL-Interpolation FATAL abgelehnt (security/R03)"
else
  bad "unzulaessiger Alias haette abgelehnt werden muessen, rc=$BAD_ALIAS_RC out='$BAD_ALIAS_OUT'"
fi

echo
echo "Ergebnis: $pass OK, $fail FAIL"
[ "$fail" -eq 0 ]
