#!/usr/bin/env bash
# run_tests.sh — Self-Test fuer db_scripts (Migrations-Grundgeruest + Fremd-Store-Schutz
# + ra_topic: Themen-Anlage + Zustandsautomat, S-002).
#
# Rein mechanisches SQL/Shell-Test-Artefakt (M1 ist sprach-neutral, kein App-Layer
# existiert -- profile.md: language: md). Erfuellt die Spec-Vertragszeile
# "Tests taggen @trace research-datenmodell#AC<n>[,BR-NNN]" (coder.md-Lesson
# 2026-07-26: reines SQL/Shell-Test-Transkript reicht, solange es committet ist).
#
# Covers (research-datenmodell): AC1 (Themen-Anlage, BR-001/BR-002, OF-02),
# AC5 (Zustandsautomat, BR-003/BR-004/BR-005/BR-006, OF-10, sqlite/R02-Verbindungs-
# Idiom, BR-019-busy_timeout-Vorbereitung), AC6 (Migrationen, aus S-001), AC8
# (Fremd-Store-Schutz, aus S-001). AC4-Meilenstein-Kanten (BR-004-Gate,
# OF-10-Kaskade) sind hier nur bis zur Grenze "ra_milestone existiert nicht"
# getestet -- die volle Kopplung folgt mit S-005. Der volle AC7/BR-019-
# Nebenlaeufigkeits-Ausbau (Advisory-Lock ra_topic_lock, Zwei-Schreiber-Test)
# bleibt S-006 -- hier nur die busy_timeout-Absicherung der bestehenden
# BEGIN IMMEDIATE-Verbindung (DBA-Review Iteration 2, Important-Fund).
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
# shellcheck source=../lib/topic.sh
source "$DB_SCRIPTS_DIR/lib/topic.sh"

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
  ok "erster Lauf wendet alle db_scripts/<NNN>_*.sql an, zweiter Lauf ist no-op (Marker-Idempotenz, sqlite/R06)"
else
  bad "Idempotenz verletzt: run1=[$(cat "$TMP/run1.log")] run2=[$(cat "$TMP/run2.log")]"
fi

EXPECTED_MIGRATION_COUNT="$(ls "$DB_SCRIPTS_DIR"/[0-9][0-9][0-9]_*.sql | wc -l | tr -d ' ')"
COUNT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM _schema_migrations;")"
if [ "$COUNT" = "$EXPECTED_MIGRATION_COUNT" ]; then
  ok "_schema_migrations enthaelt genau $EXPECTED_MIGRATION_COUNT Eintraege (= Anzahl Migrationsdateien) nach zwei Laeufen"
else
  bad "erwartet $EXPECTED_MIGRATION_COUNT Migrationseintraege, war $COUNT"
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

echo "== @trace research-datenmodell#AC1,BR-001 -- create_topic erzeugt gueltige UUIDv7 =="
TOPIC_DB="$TMP/topic.sqlite"
apply_migrations "$TOPIC_DB" "$DB_SCRIPTS_DIR" > /dev/null
TID_A="$(create_topic "$TOPIC_DB" "Erstes Thema" 2> "$TMP/create-a.err")"
if [[ "$TID_A" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
  ok "create_topic liefert eine formal gueltige UUIDv7 (Version-Nibble 7, Variant 8-b) -- $TID_A"
else
  bad "create_topic lieferte kein gueltiges UUIDv7-Format: '$TID_A' ($(cat "$TMP/create-a.err"))"
fi

STATUS_A="$(sqlite3 "$TOPIC_DB" "SELECT status FROM ra_topic WHERE id = '$TID_A';")"
if [ "$STATUS_A" = "aktiv" ]; then
  ok "neu angelegtes Thema startet im Status 'aktiv' (Anlage-Kante §7)"
else
  bad "neu angelegtes Thema hatte Status '$STATUS_A', erwartet 'aktiv'"
fi

TID_B="$(create_topic "$TOPIC_DB" "Zweites Thema")"
if [ -n "$TID_B" ] && [ "$TID_A" != "$TID_B" ]; then
  ok "zwei Anlagen erzeugen zwei verschiedene IDs (Duplikat-ID technisch unmoeglich, BR-001)"
else
  bad "erwartete zwei unterschiedliche IDs, bekam '$TID_A' und '$TID_B'"
fi

echo "== @trace research-datenmodell#AC1,BR-002,E1 -- leerer Titel wird abgelehnt =="
set +e
EMPTY_OUT="$(create_topic "$TOPIC_DB" "" 2> "$TMP/empty.err")"
EMPTY_RC=$?
set -e
COUNT_BEFORE_AFTER="$(sqlite3 "$TOPIC_DB" "SELECT COUNT(*) FROM ra_topic;")"
if [ "$EMPTY_RC" -ne 0 ] && [ -z "$EMPTY_OUT" ] && [ "$COUNT_BEFORE_AFTER" = "2" ]; then
  ok "leerer Titel wird per CHECK-Constraint abgelehnt (BR-002), keine Zeile angelegt"
else
  bad "leerer Titel haette abgelehnt werden muessen, rc=$EMPTY_RC out='$EMPTY_OUT' count=$COUNT_BEFORE_AFTER: $(cat "$TMP/empty.err")"
fi

set +e
WHITESPACE_OUT="$(create_topic "$TOPIC_DB" "   " 2> "$TMP/ws.err")"
WHITESPACE_RC=$?
set -e
if [ "$WHITESPACE_RC" -ne 0 ] && [ -z "$WHITESPACE_OUT" ]; then
  ok "nur-Whitespace-Titel wird ebenfalls abgelehnt ('trim(title)>=1', BR-002)"
else
  bad "Whitespace-Titel haette abgelehnt werden muessen, rc=$WHITESPACE_RC out='$WHITESPACE_OUT'"
fi

echo "== @trace research-datenmodell#AC1,OF-02 -- Duplikat-Titel: Warnung, aber nicht blockierend =="
TID_DUP1="$(create_topic "$TOPIC_DB" "Doppelter Titel" 2> /dev/null)"
DUP_WARN="$(create_topic "$TOPIC_DB" "Doppelter Titel" 2> "$TMP/dup.err")"
TID_DUP2="$DUP_WARN"
if [ -n "$TID_DUP1" ] && [ -n "$TID_DUP2" ] && [ "$TID_DUP1" != "$TID_DUP2" ] && grep -qi "WARNUNG" "$TMP/dup.err"; then
  ok "gleicher Titel legt trotzdem ein zweites Thema an (blockiert nicht) und warnt auf stderr (OF-02)"
else
  bad "Duplikat-Titel-Verhalten falsch: tid1='$TID_DUP1' tid2='$TID_DUP2' warn=$(cat "$TMP/dup.err")"
fi
if grep -q "$TID_DUP1" "$TMP/dup.err"; then
  ok "Warnung nennt die bestehende Themen-ID als Merge-Vorschlag (OF-02)"
else
  bad "Warnung haette die bestehende ID '$TID_DUP1' als Merge-Vorschlag nennen sollen: $(cat "$TMP/dup.err")"
fi

echo "== @trace research-datenmodell#AC1,security/R03 -- Apostroph im Titel wird SQL-escaped =="
TID_QUOTE="$(create_topic "$TOPIC_DB" "Bob's Idee" 2> "$TMP/quote.err")"
STORED_TITLE="$(sqlite3 "$TOPIC_DB" "SELECT title FROM ra_topic WHERE id = '$TID_QUOTE';")"
if [ "$STORED_TITLE" = "Bob's Idee" ]; then
  ok "Titel mit Apostroph wird korrekt escaped gespeichert, ohne das SQL-Statement zu brechen (security/R03)"
else
  bad "Titel mit Apostroph wurde falsch gespeichert: '$STORED_TITLE' ($(cat "$TMP/quote.err"))"
fi

echo "== @trace research-datenmodell#AC5,BR-006 -- alle gueltigen Kanten des Zustandsautomaten (§7, OF-10) =="
check_transition() {
  local from="$1" to="$2" label="$3"
  local got
  if ra_topic_valid_transition "$from" "$to"; then got="ok"; else got="reject"; fi
  if [ "$got" = "ok" ]; then
    ok "$label ($from -> $to erlaubt)"
  else
    bad "$label ($from -> $to haette erlaubt sein muessen)"
  fi
}
check_transition "aktiv"   "geparkt"   "aktiv -> geparkt (Parken)"
check_transition "aktiv"   "im_pm"     "aktiv -> im_pm (Gate + PM-Anstoss)"
check_transition "aktiv"   "verworfen" "aktiv -> verworfen (Verwerfen ohne Meilenstein)"
check_transition "geparkt" "aktiv"     "geparkt -> aktiv (Wiedervorlage)"
check_transition "geparkt" "verworfen" "geparkt -> verworfen (OF-10)"
check_transition "im_pm"   "aktiv"     "im_pm -> aktiv (OF-10, nach PM-Lauf)"

echo "== @trace research-datenmodell#AC5,BR-006 -- alle anderen Uebergaenge werden abgelehnt =="
check_rejected() {
  local from="$1" to="$2" label="$3"
  if ra_topic_valid_transition "$from" "$to"; then
    bad "$label ($from -> $to haette abgelehnt werden muessen)"
  else
    ok "$label ($from -> $to abgelehnt)"
  fi
}
check_rejected "verworfen" "aktiv"   "verworfen ist terminal (kein Zurueck)"
check_rejected "im_pm"     "geparkt" "im_pm -> geparkt nicht im Automaten vorgesehen"
check_rejected "im_pm"     "verworfen" "im_pm -> verworfen nicht im Automaten vorgesehen"
check_rejected "geparkt"   "im_pm"   "geparkt -> im_pm nicht im Automaten vorgesehen"
check_rejected "aktiv"     "aktiv"   "Selbst-Uebergang ist keine der gesicherten Kanten"
check_rejected "verworfen" "verworfen" "verworfen -> verworfen ebenfalls kein gesicherter Uebergang"

echo "== @trace research-datenmodell#AC5,BR-006 -- set_topic_status fuehrt den Wechsel end-to-end aus =="
TID_C="$(create_topic "$TOPIC_DB" "Drittes Thema")"
if set_topic_status "$TOPIC_DB" "$TID_C" "geparkt" 2> "$TMP/set-c.err"; then
  ok "set_topic_status fuehrt die erlaubte Kante aktiv -> geparkt aus"
else
  bad "aktiv -> geparkt haette durchgehen sollen: $(cat "$TMP/set-c.err")"
fi
STATUS_C="$(sqlite3 "$TOPIC_DB" "SELECT status FROM ra_topic WHERE id = '$TID_C';")"
if [ "$STATUS_C" = "geparkt" ]; then
  ok "Status von Thema C ist nach dem Wechsel tatsaechlich 'geparkt'"
else
  bad "Status von Thema C war '$STATUS_C', erwartet 'geparkt'"
fi

set +e
set_topic_status "$TOPIC_DB" "$TID_C" "im_pm" > /dev/null 2> "$TMP/set-c-bad.err"
SET_C_BAD_RC=$?
set -e
STATUS_C_AFTER="$(sqlite3 "$TOPIC_DB" "SELECT status FROM ra_topic WHERE id = '$TID_C';")"
if [ "$SET_C_BAD_RC" -ne 0 ] && [ "$STATUS_C_AFTER" = "geparkt" ] && grep -qi "BR-006" "$TMP/set-c-bad.err"; then
  ok "geparkt -> im_pm wird von set_topic_status abgelehnt, Status bleibt unveraendert (BR-006)"
else
  bad "geparkt -> im_pm haette abgelehnt werden muessen, rc=$SET_C_BAD_RC status='$STATUS_C_AFTER': $(cat "$TMP/set-c-bad.err")"
fi

echo "== @trace research-datenmodell#AC5,sqlite/R02 -- jede Schreib-Verbindung in topic.sh setzt PRAGMA foreign_keys=ON (DBA-Review Iteration 2) =="
CREATE_TOPIC_SRC="$(declare -f create_topic)"
if echo "$CREATE_TOPIC_SRC" | grep -q "PRAGMA foreign_keys = ON"; then
  ok "create_topic() setzt PRAGMA foreign_keys=ON auf seiner INSERT-Verbindung (das PRAGMA aus der Migration gilt nur fuer DIESE Verbindung, nicht dauerhaft fuer die Datei)"
else
  bad "create_topic() hat keine PRAGMA foreign_keys=ON-Anweisung auf der INSERT-Verbindung -- Regression des sqlite/R02-Fixes (DBA-Review Iteration 2)"
fi

SET_STATUS_SRC="$(declare -f set_topic_status)"
FK_PRAGMA_COUNT="$(echo "$SET_STATUS_SRC" | grep -c "PRAGMA foreign_keys = ON")"
if [ "$FK_PRAGMA_COUNT" -ge 2 ]; then
  ok "set_topic_status() setzt PRAGMA foreign_keys=ON auf der Haupt-UPDATE- UND der Meilenstein-Kaskaden-Verbindung ($FK_PRAGMA_COUNT Fundstellen)"
else
  bad "set_topic_status() sollte PRAGMA foreign_keys=ON auf mind. 2 Schreib-Verbindungen setzen, gefunden: $FK_PRAGMA_COUNT -- Regression des sqlite/R02-Fixes (DBA-Review Iteration 2)"
fi

echo "== @trace research-datenmodell#AC5,BR-019 -- BEGIN IMMEDIATE-Verbindung setzt PRAGMA busy_timeout VOR Transaktionsstart (DBA-Review Iteration 2) =="
if echo "$SET_STATUS_SRC" | grep -q "PRAGMA busy_timeout"; then
  ok "set_topic_status() setzt PRAGMA busy_timeout auf derselben Verbindung wie BEGIN IMMEDIATE"
else
  bad "set_topic_status() sollte PRAGMA busy_timeout an der BEGIN IMMEDIATE-Verbindung setzen -- Regression des Important-Fundes (DBA-Review Iteration 2)"
fi

BUSY_ORDER_CHECK="$(echo "$SET_STATUS_SRC" | grep -n "PRAGMA busy_timeout\|BEGIN IMMEDIATE")"
BUSY_LINE="$(echo "$BUSY_ORDER_CHECK" | grep "PRAGMA busy_timeout" | head -1 | cut -d: -f1)"
BEGIN_LINE="$(echo "$BUSY_ORDER_CHECK" | grep "BEGIN IMMEDIATE" | head -1 | cut -d: -f1)"
if [ -n "$BUSY_LINE" ] && [ -n "$BEGIN_LINE" ] && [ "$BUSY_LINE" -lt "$BEGIN_LINE" ]; then
  ok "PRAGMA busy_timeout steht VOR BEGIN IMMEDIATE in derselben Verbindung (muss vor Transaktionsstart gesetzt sein, um zu greifen)"
else
  bad "PRAGMA busy_timeout muss VOR BEGIN IMMEDIATE stehen (busy_line=$BUSY_LINE begin_line=$BEGIN_LINE)"
fi

echo "== @trace research-datenmodell#AC5,BR-005 -- discarded_at wird bei 'verworfen' gesetzt, sonst NULL =="
TID_D="$(create_topic "$TOPIC_DB" "Viertes Thema")"
set_topic_status "$TOPIC_DB" "$TID_D" "verworfen" > /dev/null
DISCARDED_D="$(sqlite3 "$TOPIC_DB" "SELECT discarded_at FROM ra_topic WHERE id = '$TID_D';")"
if [ -n "$DISCARDED_D" ]; then
  ok "aktiv -> verworfen setzt discarded_at (BR-005)"
else
  bad "discarded_at haette nach 'verworfen' gesetzt sein muessen"
fi

echo "== @trace research-datenmodell#AC5,BR-003 -- status-Enum als CHECK-Constraint (roh, ausserhalb der Data-Access-Funktionen) =="
BAD_STATUS_ERR="$TMP/bad-status.err"
if sqlite3 "$TOPIC_DB" "INSERT INTO ra_topic (id, title, status) VALUES ('00000000-0000-7000-8000-000000000001', 'x', 'unbekannt');" 2> "$BAD_STATUS_ERR"; then
  bad "ungueltiger status-Wert 'unbekannt' wurde NICHT von der CHECK-Constraint abgelehnt (BR-003)"
else
  if grep -qi "CHECK constraint failed" "$BAD_STATUS_ERR"; then
    ok "CHECK-Constraint lehnt einen status-Wert ausserhalb des Enums ab (BR-003)"
  else
    bad "Insert schlug fehl, aber nicht wegen der status-CHECK-Constraint: $(cat "$BAD_STATUS_ERR")"
  fi
fi

echo "== @trace research-datenmodell#AC5,BR-005 -- discarded_at-Invariante als CHECK-Constraint (roh) =="
INVARIANT_ERR="$TMP/invariant.err"
if sqlite3 "$TOPIC_DB" "INSERT INTO ra_topic (id, title, status, discarded_at) VALUES ('00000000-0000-7000-8000-000000000002', 'x', 'aktiv', datetime('now'));" 2> "$INVARIANT_ERR"; then
  bad "'aktiv' mit gesetztem discarded_at wurde NICHT von der Invarianten-CHECK-Constraint abgelehnt (BR-005)"
else
  if grep -qi "CHECK constraint failed" "$INVARIANT_ERR"; then
    ok "CHECK-Constraint lehnt 'aktiv' + gesetztes discarded_at ab (BR-005-Invariante)"
  else
    bad "Insert schlug fehl, aber nicht wegen der discarded_at-Invariante: $(cat "$INVARIANT_ERR")"
  fi
fi

echo "== @trace research-datenmodell#AC5,security/R03 -- ungueltige/fremde Themen-ID wird vor SQL-Interpolation abgelehnt =="
set +e
set_topic_status "$TOPIC_DB" "x'; DROP TABLE ra_topic; --" "aktiv" > /dev/null 2> "$TMP/inject.err"
INJECT_RC=$?
set -e
STILL_THERE="$(sqlite3 "$TOPIC_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='ra_topic';")"
if [ "$INJECT_RC" -ne 0 ] && [ "$STILL_THERE" = "ra_topic" ] && grep -qi "FATAL" "$TMP/inject.err"; then
  ok "manipulierte Themen-ID wird per Format-Check FATAL abgelehnt, ra_topic bleibt unangetastet (security/R03)"
else
  bad "manipulierte Themen-ID haette abgelehnt werden muessen, rc=$INJECT_RC table='$STILL_THERE': $(cat "$TMP/inject.err")"
fi

set +e
set_topic_status "$TOPIC_DB" "00000000-0000-7000-8000-0000000000ff" "aktiv" > /dev/null 2> "$TMP/unknown.err"
UNKNOWN_RC=$?
set -e
if [ "$UNKNOWN_RC" -ne 0 ] && grep -qi "existiert nicht" "$TMP/unknown.err"; then
  ok "Statuswechsel auf ein nicht existierendes Thema wird abgelehnt"
else
  bad "nicht existierendes Thema haette abgelehnt werden muessen, rc=$UNKNOWN_RC: $(cat "$TMP/unknown.err")"
fi

echo "== @trace research-datenmodell#AC5,OF-10 -- geparkt -> verworfen setzt offene Meilensteine auf 'hinfaellig' (sobald ra_milestone existiert) =="
sqlite3 "$TOPIC_DB" "CREATE TABLE ra_milestone (id INTEGER PRIMARY KEY, topic_id TEXT NOT NULL, status TEXT NOT NULL) STRICT;"
TID_E="$(create_topic "$TOPIC_DB" "Fuenftes Thema")"
sqlite3 "$TOPIC_DB" "INSERT INTO ra_milestone (topic_id, status) VALUES ('$TID_E', 'offen'), ('$TID_E', 'erfuellt');"
set_topic_status "$TOPIC_DB" "$TID_E" "geparkt" > /dev/null
set_topic_status "$TOPIC_DB" "$TID_E" "verworfen" > /dev/null
MS_STATUSES="$(sqlite3 "$TOPIC_DB" "SELECT status FROM ra_milestone WHERE topic_id = '$TID_E' ORDER BY status;")"
if [ "$MS_STATUSES" = "$(printf 'erfuellt\nhinfaellig')" ]; then
  ok "geparkt -> verworfen setzt nur den offenen Meilenstein auf 'hinfaellig', der erfuellte bleibt unveraendert (OF-10)"
else
  bad "erwartete Meilenstein-Staende 'erfuellt'+'hinfaellig', bekam: $MS_STATUSES"
fi

echo "== @trace research-datenmodell#AC5,BR-004 -- aktiv -> geparkt Gate greift, sobald ra_milestone existiert; ohne Tabelle: dokumentierter No-op =="
TID_F="$(create_topic "$TOPIC_DB" "Sechstes Thema")"
set +e
set_topic_status "$TOPIC_DB" "$TID_F" "geparkt" > /dev/null 2> "$TMP/gate-f.err"
GATE_F_RC=$?
set -e
STATUS_F="$(sqlite3 "$TOPIC_DB" "SELECT status FROM ra_topic WHERE id = '$TID_F';")"
if [ "$GATE_F_RC" -ne 0 ] && [ "$STATUS_F" = "aktiv" ] && grep -qi "BR-004" "$TMP/gate-f.err"; then
  ok "aktiv -> geparkt ohne jeden Meilenstein wird abgelehnt, sobald ra_milestone existiert (BR-004)"
else
  bad "aktiv -> geparkt ohne Meilenstein haette abgelehnt werden muessen (ra_milestone existiert bereits in diesem TOPIC_DB), rc=$GATE_F_RC status='$STATUS_F': $(cat "$TMP/gate-f.err")"
fi

NO_MS_DB="$TMP/topic-no-milestone.sqlite"
apply_migrations "$NO_MS_DB" "$DB_SCRIPTS_DIR" > /dev/null
TID_G="$(create_topic "$NO_MS_DB" "Siebtes Thema")"
if set_topic_status "$NO_MS_DB" "$TID_G" "geparkt" 2> "$TMP/gate-g.err"; then
  ok "ohne ra_milestone-Tabelle (vor S-005) degradiert das BR-004-Gate dokumentiert zum No-op -- aktiv -> geparkt geht durch"
else
  bad "ohne ra_milestone haette der degradierte Pfad durchgehen sollen: $(cat "$TMP/gate-g.err")"
fi

echo
echo "Ergebnis: $pass OK, $fail FAIL"
[ "$fail" -eq 0 ]
