#!/usr/bin/env bash
# run_tests.sh — Self-Test fuer db_scripts (Migrations-Grundgeruest + Fremd-Store-Schutz
# + ra_topic: Themen-Anlage + Zustandsautomat, S-002 + ra_run: versionierte Laeufe +
# result_hash, S-003 + ra_milestone: Status/Zustaendigkeit/Watchlist-Ref-Pflicht,
# S-005 + ra_divergence: Divergenz-Berechnung + Materialisierung, S-004 +
# ra_topic_lock: Advisory-Serialisierungssperre je Thema, S-006 + Parken-Gate auf
# EXTERNE Meilensteine verschaerft, S-012 + ra_swot_item: strukturierte SWOT-Items +
# kontrolliertes claim_key-Vokabular, S-008).
#
# Rein mechanisches SQL/Shell-Test-Artefakt (M1 ist sprach-neutral, kein App-Layer
# existiert -- profile.md: language: md). Erfuellt die Spec-Vertragszeile
# "Tests taggen @trace research-datenmodell#AC<n>[,BR-NNN]" (coder.md-Lesson
# 2026-07-26: reines SQL/Shell-Test-Transkript reicht, solange es committet ist).
#
# Covers (wiedervorlage-meilensteine): AC1 (Parken nur mit >=1 EXTERNEM Meilenstein,
# BR-004 -- rein 'eigen'e Meilensteine reichen NICHT; Verwerfen (aktiv -> verworfen)
# verlangt explizit KEINEN Meilenstein; S-012). AC2 (Watchlist-Kopplung) + AC6
# (Nebenlaeufigkeit) sind seit S-013 implementiert (Watchlist-Pass,
# db_scripts/lib/milestone.sh#list_watchlist_candidates,
# skills/research/scripts/watchlist_pass.sh) -- getestet in
# skills/research/tests/run_tests.sh (dort eigener "Covers
# (wiedervorlage-meilensteine)"-Block, gleiches Muster wie milestone.sh#
# create_milestone/list_milestones/set_milestone_status, die ebenfalls NICHT
# hier, sondern dort getestet werden). AC5 (verworfen bleibt verworfen, OF-10-
# Kaskade "geparkt -> verworfen setzt offene Meilensteine auf 'hinfaellig'")
# ist HIER als Teil des ra_topic-Zustandsautomaten getestet (siehe "Covers
# (research-datenmodell): AC5" unten, gleicher Testfall, seit S-014
# zusaetzlich als wiedervorlage-meilensteine#AC5 getaggt); die strukturelle
# Ausschluss-Garantie "verworfen erscheint nie als Watchlist-Kandidat" ist in
# skills/research/tests/run_tests.sh getestet (list_watchlist_candidates-
# Filter). AC3 (automatische Wiedervorlage bei Delta/Erfuellung, S-014) ist
# ausschliesslich in skills/research/tests/run_tests.sh Gegenstand (lebt in
# watchlist_pass.sh, nicht in dieser Data-Access-Schicht). AC4 (nicht
# pruefbare Meilensteine bleiben sichtbar "manuell zu pruefen" markiert,
# S-015) ist ebenfalls ausschliesslich in skills/research/tests/run_tests.sh
# Gegenstand (lebt in watchlist_pass.sh#report_watchlist_result).
#
# Covers (research-datenmodell): AC1 (Themen-Anlage, BR-001/BR-002, OF-02),
# AC2 (Versionierte Laeufe: ra_run, BR-007/BR-008/BR-009/BR-013/BR-014, OF-04,
# §5-Hash-Bildungsregel, security/R03), AC3 (Divergenz: ra_divergence,
# BR-010 is_empty gdw. gleicher Hash + nativer CHECK-Backstop (is_empty=1 erzwingt
# swot_delta/milestone_status_delta=NULL, 005_ra_divergence.sql), BR-011 nur
# gleiches Thema+gleiche Art, BR-019 create_divergence setzt PRAGMA busy_timeout VOR
# BEGIN IMMEDIATE (inkl. Leak-Freiheit der per RETURNING eingesammelten id, Reviewer-
# Fund Iteration 2), SWOT-Item-Delta (category,claim_key) + Kategorie-Rollup,
# Meilenstein-Status-Delta, UNIQUE(from_run_id,to_run_id), security/R03 -- SWOT-/
# Meilenstein-Tupel werden wie bei compute_result_hash direkt uebergeben, kein
# ra_swot_item-Tabellenzugriff, siehe divergence.sh-Datei-Header), AC4 (Meilenstein-Entitaet: BR-015
# Zustaendigkeit extern/eigen + watch_ref-Pflicht bei extern, BR-016 Status-Enum --
# alles als rohe CHECK-Constraints getestet, kein Data-Access-Wrapper noetig, siehe
# 004_ra_milestone.sql-Header), AC5 (Zustandsautomat, BR-003/BR-004/BR-005/
# BR-006, OF-10, sqlite/R02-Verbindungs-Idiom, BR-019-busy_timeout-Vorbereitung --
# BR-004-Gate/OF-10-Kaskade jetzt gegen die echte ra_milestone-Tabelle aus S-005
# statt einer Test-lokalen Ersatztabelle; BR-004-Gate seit S-012 auf
# responsibility='extern' verschaerft, siehe Covers (wiedervorlage-meilensteine)
# oben), AC6 (Migrationen, aus S-001), AC7
# (Nebenlaeufigkeit: ra_topic_lock, BR-019 Advisory-Lock je Thema + atomare
# ON CONFLICT..WHERE-Uebernahme, E2 Stale-Ablauf via expires_at (kein Dauer-Deadlock),
# BEGIN IMMEDIATE+busy_timeout-Reihenfolge, security/R03 -- inkl. echtem Test mit ZWEI
# parallelen OS-Prozessen (Watchlist-Job + /research-Lauf simuliert) auf dasselbe
# Thema), AC8 (Fremd-Store-Schutz, aus S-001).
#
# Covers (research-skill): AC2 (ra_swot_item, S-008 -- 007_ra_swot_item.sql: category/
# evidence_source als rohe CHECK-Constraints, claim_key nicht-leer, UNIQUE(run_id,
# category,claim_key), ON DELETE CASCADE via ra_run; db_scripts/lib/swot_item.sh:
# create_swot_item/list_swot_items, kontrolliertes claim_key-Vokabular (BR-012/OF-06)
# inkl. Normalisierung (trim+lowercase) + Zurueckweisung ausserhalb des Vokabulars als
# "unmapped" ohne Persistenz (E2), security/R03 vor jeder SQL-Interpolation;
# db_scripts/lib/run.sh#get_run als Lesefunktion fuer die Bewertungsschicht-Anzeige).
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
# shellcheck source=../lib/run.sh
source "$DB_SCRIPTS_DIR/lib/run.sh"
# shellcheck source=../lib/divergence.sh
source "$DB_SCRIPTS_DIR/lib/divergence.sh"
# shellcheck source=../lib/topic_lock.sh
source "$DB_SCRIPTS_DIR/lib/topic_lock.sh"
# shellcheck source=../lib/swot_item.sh
source "$DB_SCRIPTS_DIR/lib/swot_item.sh"

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
# responsibility='extern' (statt 'eigen'): seit S-012 verlangt das BR-004-Gate
# mindestens einen EXTERNEN Meilenstein (wiedervorlage-meilensteine#AC1).
sqlite3 "$TOPIC_DB" "INSERT INTO ra_milestone (topic_id, description, responsibility, status, watch_ref) VALUES ('$TID_C', 'Meilenstein fuer Thema C', 'extern', 'offen', 'watchlist-item-c');"
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

echo "== @trace research-datenmodell#AC5,OF-10,wiedervorlage-meilensteine#AC5 -- geparkt -> verworfen setzt offene Meilensteine auf 'hinfaellig' =="
TID_E="$(create_topic "$TOPIC_DB" "Fuenftes Thema")"
# 'Offener Meilenstein' ist bewusst 'extern' (statt 'eigen'): seit S-012 verlangt das
# BR-004-Gate mindestens einen EXTERNEN Meilenstein zum Parken (AC1); die OF-10-
# Kaskade selbst bleibt responsibility-agnostisch (prueft nur status='offen').
sqlite3 "$TOPIC_DB" "INSERT INTO ra_milestone (topic_id, description, responsibility, status, watch_ref) VALUES ('$TID_E', 'Offener Meilenstein', 'extern', 'offen', 'watchlist-item-e'), ('$TID_E', 'Erfuellter Meilenstein', 'eigen', 'erfuellt', NULL);"
set_topic_status "$TOPIC_DB" "$TID_E" "geparkt" > /dev/null
set_topic_status "$TOPIC_DB" "$TID_E" "verworfen" > /dev/null
MS_STATUSES="$(sqlite3 "$TOPIC_DB" "SELECT status FROM ra_milestone WHERE topic_id = '$TID_E' ORDER BY status;")"
if [ "$MS_STATUSES" = "$(printf 'erfuellt\nhinfaellig')" ]; then
  ok "geparkt -> verworfen setzt nur den offenen Meilenstein auf 'hinfaellig', der erfuellte bleibt unveraendert (OF-10)"
else
  bad "erwartete Meilenstein-Staende 'erfuellt'+'hinfaellig', bekam: $MS_STATUSES"
fi

echo "== @trace research-datenmodell#AC5,BR-004,wiedervorlage-meilensteine#AC1 -- aktiv -> geparkt Gate lehnt ab ohne mindestens 1 Meilenstein =="
TID_F="$(create_topic "$TOPIC_DB" "Sechstes Thema")"
set +e
set_topic_status "$TOPIC_DB" "$TID_F" "geparkt" > /dev/null 2> "$TMP/gate-f.err"
GATE_F_RC=$?
set -e
STATUS_F="$(sqlite3 "$TOPIC_DB" "SELECT status FROM ra_topic WHERE id = '$TID_F';")"
if [ "$GATE_F_RC" -ne 0 ] && [ "$STATUS_F" = "aktiv" ] && grep -qi "BR-004" "$TMP/gate-f.err"; then
  ok "aktiv -> geparkt ohne jeden Meilenstein wird abgelehnt (BR-004)"
else
  bad "aktiv -> geparkt ohne Meilenstein haette abgelehnt werden muessen, rc=$GATE_F_RC status='$STATUS_F': $(cat "$TMP/gate-f.err")"
fi

echo "== @trace wiedervorlage-meilensteine#AC1 -- aktiv -> geparkt mit NUR 'eigen'-Meilenstein(en) wird abgelehnt (0 externe) =="
TID_G="$(create_topic "$TOPIC_DB" "Siebtes Thema")"
sqlite3 "$TOPIC_DB" "INSERT INTO ra_milestone (topic_id, description, responsibility, status) VALUES ('$TID_G', 'Nur eigener Meilenstein', 'eigen', 'offen');"
set +e
set_topic_status "$TOPIC_DB" "$TID_G" "geparkt" > /dev/null 2> "$TMP/gate-g.err"
GATE_G_RC=$?
set -e
STATUS_G="$(sqlite3 "$TOPIC_DB" "SELECT status FROM ra_topic WHERE id = '$TID_G';")"
if [ "$GATE_G_RC" -ne 0 ] && [ "$STATUS_G" = "aktiv" ] && grep -qi "BR-004" "$TMP/gate-g.err"; then
  ok "aktiv -> geparkt mit nur 'eigen'-Meilenstein (0 externe) wird abgelehnt (AC1/BR-004)"
else
  bad "aktiv -> geparkt mit nur 'eigen'-Meilenstein haette abgelehnt werden muessen, rc=$GATE_G_RC status='$STATUS_G': $(cat "$TMP/gate-g.err")"
fi

echo "== @trace wiedervorlage-meilensteine#AC1 -- aktiv -> geparkt mit >=1 externem Meilenstein wird angenommen =="
TID_H="$(create_topic "$TOPIC_DB" "Achtes Thema")"
sqlite3 "$TOPIC_DB" "INSERT INTO ra_milestone (topic_id, description, responsibility, status, watch_ref) VALUES ('$TID_H', 'Externer Meilenstein', 'extern', 'offen', 'watchlist-item-h');"
if set_topic_status "$TOPIC_DB" "$TID_H" "geparkt" 2> "$TMP/gate-h.err"; then
  ok "aktiv -> geparkt mit >=1 externem Meilenstein wird angenommen (AC1)"
else
  bad "aktiv -> geparkt mit externem Meilenstein haette angenommen werden sollen: $(cat "$TMP/gate-h.err")"
fi
STATUS_H="$(sqlite3 "$TOPIC_DB" "SELECT status FROM ra_topic WHERE id = '$TID_H';")"
if [ "$STATUS_H" = "geparkt" ]; then
  ok "Status von Thema H ist nach dem Wechsel tatsaechlich 'geparkt'"
else
  bad "Status von Thema H war '$STATUS_H', erwartet 'geparkt'"
fi

echo "== @trace wiedervorlage-meilensteine#AC1 -- aktiv -> verworfen (Verwerfen) verlangt KEINEN Meilenstein =="
TID_I="$(create_topic "$TOPIC_DB" "Neuntes Thema")"
if set_topic_status "$TOPIC_DB" "$TID_I" "verworfen" 2> "$TMP/discard-i.err"; then
  ok "aktiv -> verworfen ohne jeden Meilenstein wird angenommen -- Verwerfen ist NICHT an Meilensteine gekoppelt (AC1)"
else
  bad "aktiv -> verworfen ohne Meilenstein haette angenommen werden sollen: $(cat "$TMP/discard-i.err")"
fi
STATUS_I="$(sqlite3 "$TOPIC_DB" "SELECT status FROM ra_topic WHERE id = '$TID_I';")"
if [ "$STATUS_I" = "verworfen" ]; then
  ok "Status von Thema I ist nach dem Verwerfen tatsaechlich 'verworfen'"
else
  bad "Status von Thema I war '$STATUS_I', erwartet 'verworfen'"
fi

echo "== @trace research-datenmodell#AC4,BR-015 -- responsibility='extern' erfordert watch_ref (CHECK, roh) =="
EXTERN_NO_REF_ERR="$TMP/extern-no-ref.err"
if sqlite3 "$TOPIC_DB" "INSERT INTO ra_milestone (topic_id, description, responsibility, status) VALUES ('$TID_F', 'Extern ohne Ref', 'extern', 'offen');" 2> "$EXTERN_NO_REF_ERR"; then
  bad "responsibility='extern' ohne watch_ref wurde NICHT von der CHECK-Constraint abgelehnt (BR-015)"
else
  if grep -qi "CHECK constraint failed" "$EXTERN_NO_REF_ERR"; then
    ok "CHECK-Constraint lehnt 'extern' ohne watch_ref ab (BR-015)"
  else
    bad "Insert schlug fehl, aber nicht wegen der watch_ref-Pflicht-Invariante: $(cat "$EXTERN_NO_REF_ERR")"
  fi
fi

if sqlite3 "$TOPIC_DB" "INSERT INTO ra_milestone (topic_id, description, responsibility, status, watch_ref) VALUES ('$TID_F', 'Extern mit Ref', 'extern', 'offen', 'watchlist-item-1');"; then
  ok "responsibility='extern' MIT watch_ref wird angenommen (BR-015)"
else
  bad "responsibility='extern' mit gesetztem watch_ref haette angenommen werden muessen"
fi

echo "== @trace research-datenmodell#AC4,BR-015 -- responsibility='eigen' verbietet watch_ref (CHECK, roh) =="
EIGEN_WITH_REF_ERR="$TMP/eigen-with-ref.err"
if sqlite3 "$TOPIC_DB" "INSERT INTO ra_milestone (topic_id, description, responsibility, status, watch_ref) VALUES ('$TID_F', 'Eigen mit Ref', 'eigen', 'offen', 'watchlist-item-2');" 2> "$EIGEN_WITH_REF_ERR"; then
  bad "responsibility='eigen' MIT watch_ref wurde NICHT von der CHECK-Constraint abgelehnt (BR-015)"
else
  if grep -qi "CHECK constraint failed" "$EIGEN_WITH_REF_ERR"; then
    ok "CHECK-Constraint lehnt 'eigen' mit gesetztem watch_ref ab (BR-015)"
  else
    bad "Insert schlug fehl, aber nicht wegen der watch_ref-Verbots-Invariante: $(cat "$EIGEN_WITH_REF_ERR")"
  fi
fi

echo "== @trace research-datenmodell#AC4,BR-015 -- responsibility-Enum als CHECK-Constraint (roh) =="
BAD_RESP_ERR="$TMP/bad-resp.err"
if sqlite3 "$TOPIC_DB" "INSERT INTO ra_milestone (topic_id, description, responsibility, status) VALUES ('$TID_F', 'Unbekannte Zustaendigkeit', 'unbekannt', 'offen');" 2> "$BAD_RESP_ERR"; then
  bad "ungueltiger responsibility-Wert 'unbekannt' wurde NICHT von der CHECK-Constraint abgelehnt (BR-015)"
else
  if grep -qi "CHECK constraint failed" "$BAD_RESP_ERR"; then
    ok "CHECK-Constraint lehnt einen responsibility-Wert ausserhalb des Enums ab (BR-015)"
  else
    bad "Insert schlug fehl, aber nicht wegen der responsibility-CHECK-Constraint: $(cat "$BAD_RESP_ERR")"
  fi
fi

echo "== @trace research-datenmodell#AC4,BR-016 -- status-Enum als CHECK-Constraint (roh) =="
BAD_MS_STATUS_ERR="$TMP/bad-ms-status.err"
if sqlite3 "$TOPIC_DB" "INSERT INTO ra_milestone (topic_id, description, responsibility, status) VALUES ('$TID_F', 'Unbekannter Status', 'eigen', 'unbekannt');" 2> "$BAD_MS_STATUS_ERR"; then
  bad "ungueltiger status-Wert 'unbekannt' wurde NICHT von der CHECK-Constraint abgelehnt (BR-016)"
else
  if grep -qi "CHECK constraint failed" "$BAD_MS_STATUS_ERR"; then
    ok "CHECK-Constraint lehnt einen status-Wert ausserhalb des Enums ab (BR-016)"
  else
    bad "Insert schlug fehl, aber nicht wegen der status-CHECK-Constraint: $(cat "$BAD_MS_STATUS_ERR")"
  fi
fi

echo "== @trace research-datenmodell#AC4,sqlite/R06 -- leere Beschreibung wird abgelehnt (CHECK, roh) =="
EMPTY_DESC_ERR="$TMP/empty-desc.err"
if sqlite3 "$TOPIC_DB" "INSERT INTO ra_milestone (topic_id, description, responsibility, status) VALUES ('$TID_F', '   ', 'eigen', 'offen');" 2> "$EMPTY_DESC_ERR"; then
  bad "leere/nur-Whitespace-Beschreibung wurde NICHT von der CHECK-Constraint abgelehnt"
else
  if grep -qi "CHECK constraint failed" "$EMPTY_DESC_ERR"; then
    ok "CHECK-Constraint lehnt eine leere Meilenstein-Beschreibung ab"
  else
    bad "Insert schlug fehl, aber nicht wegen der description-CHECK-Constraint: $(cat "$EMPTY_DESC_ERR")"
  fi
fi

echo "== @trace research-datenmodell#AC2,BR-007,OF-04 -- monotone Version je (Thema,Art), getrennt gezaehlt =="
RUN_TOPIC="$(create_topic "$TOPIC_DB" "Lauf-Thema")"
HASH_1="$(compute_result_hash "weiterverfolgen" "" "" 2> "$TMP/hash1.err")"
RUN_A="$(create_run "$TOPIC_DB" "$RUN_TOPIC" "recherche" "$HASH_1" "weiterverfolgen" 1 0 2> "$TMP/run-a.err")"
RUN_B="$(create_run "$TOPIC_DB" "$RUN_TOPIC" "recherche" "$HASH_1" "weiterverfolgen" 1 0 2> "$TMP/run-b.err")"
VER_A="${RUN_A#*|}"
VER_B="${RUN_B#*|}"
if [ "$VER_A" = "1" ] && [ "$VER_B" = "2" ]; then
  ok "zwei Laeufe desselben Themas+Art erhalten die Versionen 1 und 2 (BR-007)"
else
  bad "erwartete Versionen 1,2 fuer kind=recherche, bekam '$VER_A','$VER_B' ($(cat "$TMP/run-a.err") $(cat "$TMP/run-b.err"))"
fi

RUN_PM="$(create_run "$TOPIC_DB" "$RUN_TOPIC" "pm" "$HASH_1" "weiterverfolgen" 1 0 2> "$TMP/run-pm.err")"
VER_PM="${RUN_PM#*|}"
if [ "$VER_PM" = "1" ]; then
  ok "kind='pm' zaehlt unabhaengig von kind='recherche' -- erste PM-Version ist 1 (OF-04)"
else
  bad "erwartete Version 1 fuer den ersten pm-Lauf, bekam '$VER_PM': $(cat "$TMP/run-pm.err")"
fi

echo "== @trace research-datenmodell#AC2,BR-007 -- UNIQUE(topic_id,kind,version) ist der native Backstop =="
set +e
sqlite3 "$TOPIC_DB" "PRAGMA foreign_keys = ON; INSERT INTO ra_run (topic_id, kind, version, result_hash, recommendation, has_deep_research, momentum_only) VALUES ('$RUN_TOPIC', 'recherche', 1, '$HASH_1', 'weiterverfolgen', 1, 0);" > /dev/null 2>"$TMP/dup-ver.err"
DUP_VER_RC=$?
set -e
if [ "$DUP_VER_RC" -ne 0 ] && grep -qi "UNIQUE" "$TMP/dup-ver.err"; then
  ok "doppelte Version fuer dasselbe (topic_id,kind) wird per UNIQUE-Constraint abgelehnt (BR-007)"
else
  bad "doppelte Version haette per UNIQUE abgelehnt werden muessen, rc=$DUP_VER_RC: $(cat "$TMP/dup-ver.err")"
fi

echo "== @trace research-datenmodell#AC2,BR-008 -- ra_run.kind nur enum{recherche,pm} =="
set +e
BAD_KIND_OUT="$(create_run "$TOPIC_DB" "$RUN_TOPIC" "sonstiges" "$HASH_1" "weiterverfolgen" 1 0 2>"$TMP/bad-kind.err")"
BAD_KIND_RC=$?
set -e
if [ "$BAD_KIND_RC" -ne 0 ] && [ -z "$BAD_KIND_OUT" ] && grep -qi "BR-008" "$TMP/bad-kind.err"; then
  ok "unbekannte Lauf-Art wird vor der SQL-Interpolation abgelehnt (BR-008)"
else
  bad "unbekannte Lauf-Art haette abgelehnt werden muessen, rc=$BAD_KIND_RC out='$BAD_KIND_OUT'"
fi

echo "== @trace research-datenmodell#AC2,BR-013 -- ra_run.recommendation nur enum{weiterverfolgen,parken,verwerfen} =="
set +e
BAD_REC_OUT="$(create_run "$TOPIC_DB" "$RUN_TOPIC" "recherche" "$HASH_1" "vielleicht" 1 0 2>"$TMP/bad-rec.err")"
BAD_REC_RC=$?
set -e
if [ "$BAD_REC_RC" -ne 0 ] && [ -z "$BAD_REC_OUT" ] && grep -qi "BR-013" "$TMP/bad-rec.err"; then
  ok "unbekannte Empfehlung wird abgelehnt (BR-013)"
else
  bad "unbekannte Empfehlung haette abgelehnt werden muessen, rc=$BAD_REC_RC out='$BAD_REC_OUT'"
fi

echo "== @trace research-datenmodell#AC2,BR-014 -- has_deep_research/momentum_only-Konsistenz (gdw.) =="
set +e
MISMATCH_OUT_1="$(create_run "$TOPIC_DB" "$RUN_TOPIC" "recherche" "$HASH_1" "weiterverfolgen" 0 0 2>"$TMP/mismatch1.err")"
MISMATCH_RC_1=$?
MISMATCH_OUT_2="$(create_run "$TOPIC_DB" "$RUN_TOPIC" "recherche" "$HASH_1" "weiterverfolgen" 1 1 2>"$TMP/mismatch2.err")"
MISMATCH_RC_2=$?
set -e
if [ "$MISMATCH_RC_1" -ne 0 ] && [ -z "$MISMATCH_OUT_1" ] && grep -qi "BR-014" "$TMP/mismatch1.err" \
  && [ "$MISMATCH_RC_2" -ne 0 ] && [ -z "$MISMATCH_OUT_2" ] && grep -qi "BR-014" "$TMP/mismatch2.err"; then
  ok "has_deep_research=0/momentum_only=0 UND has_deep_research=1/momentum_only=1 werden beide abgelehnt (BR-014 'gdw.')"
else
  bad "BR-014-Inkonsistenz haette in beide Richtungen abgelehnt werden muessen: rc1=$MISMATCH_RC_1 out1='$MISMATCH_OUT_1' rc2=$MISMATCH_RC_2 out2='$MISMATCH_OUT_2'"
fi

RUN_MOMENTUM="$(create_run "$TOPIC_DB" "$RUN_TOPIC" "recherche" "$HASH_1" "weiterverfolgen" 0 1 2> "$TMP/momentum.err")"
if [ -n "$RUN_MOMENTUM" ]; then
  ok "has_deep_research=0 + momentum_only=1 ist die gueltige Momentum-Signal-Kombination (BR-014)"
else
  bad "gueltige Momentum-Kombination haette durchgehen sollen: $(cat "$TMP/momentum.err")"
fi

echo "== @trace research-datenmodell#AC2,BR-009 -- result_hash ist deterministisch ueber strukturierte Felder =="
HASH_X1="$(compute_result_hash "weiterverfolgen" "$(printf 'strength|marktfuehrer\nopportunity|neue_regulierung')" "$(printf 'patentanmeldung|offen|extern')")"
HASH_X2="$(compute_result_hash "WEITERVERFOLGEN" "$(printf 'opportunity|neue_regulierung  \n  Strength|Marktfuehrer')" "$(printf '  PATENTANMELDUNG | OFFEN | Extern')")"
if [ -n "$HASH_X1" ] && [ "$HASH_X1" = "$HASH_X2" ]; then
  ok "gleicher strukturierter Ergebnisstand erzeugt denselben Hash unabhaengig von Feld-Reihenfolge/Gross-Klein-Schreibung/Whitespace (BR-009, §5 Normalisierung+Sortierung)"
else
  bad "identischer strukturierter Ergebnisstand haette denselben Hash erzeugen muessen: '$HASH_X1' vs '$HASH_X2'"
fi
if [[ "$HASH_X1" =~ ^[0-9a-f]{64}$ ]]; then
  ok "compute_result_hash liefert einen 64-stelligen SHA-256-Hex-Digest"
else
  bad "compute_result_hash lieferte kein gueltiges SHA-256-Hex-Format: '$HASH_X1'"
fi

HASH_Y="$(compute_result_hash "parken" "$(printf 'strength|marktfuehrer\nopportunity|neue_regulierung')" "$(printf 'patentanmeldung|offen|extern')")"
if [ "$HASH_X1" != "$HASH_Y" ]; then
  ok "geaenderte Empfehlung (sonst identischer Stand) erzeugt einen anderen Hash (BR-009 -- Empfehlung fliesst ein)"
else
  bad "unterschiedliche Empfehlung haette zu unterschiedlichem Hash fuehren muessen"
fi

echo "== @trace research-datenmodell#AC2,security/R03 -- result_hash-Format wird vor der SQL-Interpolation validiert =="
set +e
BAD_HASH_OUT="$(create_run "$TOPIC_DB" "$RUN_TOPIC" "recherche" "'; DROP TABLE ra_run;--" "weiterverfolgen" 1 0 2>"$TMP/bad-hash.err")"
BAD_HASH_RC=$?
set -e
TABLE_STILL_THERE="$(sqlite3 "$TOPIC_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='ra_run';")"
if [ "$BAD_HASH_RC" -ne 0 ] && [ -z "$BAD_HASH_OUT" ] && grep -qi "security/R03" "$TMP/bad-hash.err" && [ "$TABLE_STILL_THERE" = "ra_run" ]; then
  ok "manipulierter result_hash wird per Formatpruefung abgelehnt, bevor er ins SQL interpoliert wird (security/R03)"
else
  bad "manipulierter result_hash haette abgelehnt werden muessen, rc=$BAD_HASH_RC out='$BAD_HASH_OUT' table='$TABLE_STILL_THERE'"
fi

echo "== @trace research-datenmodell#AC2 -- l30d_source_ref ist optional (soft-Referenz, kein FK) =="
RUN_NO_REF="$(create_run "$TOPIC_DB" "$RUN_TOPIC" "recherche" "$HASH_1" "weiterverfolgen" 1 0 2> "$TMP/no-ref.err")"
RUN_NO_REF_ID="${RUN_NO_REF%%|*}"
REF_VAL="$(sqlite3 "$TOPIC_DB" "SELECT l30d_source_ref FROM ra_run WHERE id = $RUN_NO_REF_ID;")"
if [ -z "$REF_VAL" ]; then
  ok "ohne uebergebene l30d_source_ref bleibt die Spalte NULL"
else
  bad "erwartete NULL l30d_source_ref, bekam '$REF_VAL'"
fi

echo "== @trace research-datenmodell#AC3,BR-012 -- compute_swot_delta bildet Einzel-Item-Differenz + Kategorie-Rollup =="
SWOT_FROM="$(printf 'strength|marktfuehrer\nopportunity|regulierung')"
SWOT_TO="$(printf 'strength|marktfuehrer\nthreat|wettbewerb\nthreat|preisdruck')"
SWOT_DELTA="$(compute_swot_delta "$SWOT_FROM" "$SWOT_TO" 2> "$TMP/swot-delta.err")"
if echo "$SWOT_DELTA" | grep -q '"added":\[\["threat","preisdruck"\],\["threat","wettbewerb"\]\]' \
  && echo "$SWOT_DELTA" | grep -q '"removed":\[\["opportunity","regulierung"\]\]' \
  && echo "$SWOT_DELTA" | grep -q '"opportunity":{"added":0,"removed":1}' \
  && echo "$SWOT_DELTA" | grep -q '"threat":{"added":2,"removed":0}'; then
  ok "compute_swot_delta liefert added/removed (category,claim_key)-Paare sortiert + Kategorie-Rollup (AC3, BR-012)"
else
  bad "compute_swot_delta lieferte unerwartetes JSON: $SWOT_DELTA ($(cat "$TMP/swot-delta.err"))"
fi

UNCHANGED_ITEM_CATEGORY="$(echo "$SWOT_DELTA" | grep -o '"strength"[^}]*}' || true)"
if [ -z "$UNCHANGED_ITEM_CATEGORY" ]; then
  ok "unveraenderter SWOT-Claim (strength|marktfuehrer, in beiden Laeufen identisch) erscheint NICHT im by_category-Rollup"
else
  bad "by_category haette 'strength' nicht enthalten sollen (kein Delta dort): $SWOT_DELTA"
fi

EMPTY_SWOT_DELTA="$(compute_swot_delta "$SWOT_FROM" "$SWOT_FROM")"
if [ "$EMPTY_SWOT_DELTA" = '{"added":[],"removed":[],"by_category":{}}' ]; then
  ok "identische SWOT-Staende erzeugen ein leeres Delta (added/removed=[], by_category={})"
else
  bad "identische SWOT-Staende haetten ein leeres Delta erzeugen muessen, bekam: $EMPTY_SWOT_DELTA"
fi

echo "== @trace research-datenmodell#AC3 -- compute_milestone_delta bildet geaenderte (milestone_stable_key,status)-Tripel =="
MS_FROM="$(printf '1|offen|eigen\n2|offen|extern')"
MS_TO="$(printf '1|erfuellt|eigen\n2|offen|extern\n3|offen|eigen')"
MS_DELTA="$(compute_milestone_delta "$MS_FROM" "$MS_TO" 2> "$TMP/ms-delta.err")"
if echo "$MS_DELTA" | grep -q '{"milestone_stable_key":"1","from_status":"offen","to_status":"erfuellt"}' \
  && echo "$MS_DELTA" | grep -q '{"milestone_stable_key":"3","from_status":null,"to_status":"offen"}' \
  && ! echo "$MS_DELTA" | grep -q '"milestone_stable_key":"2"'; then
  ok "compute_milestone_delta zeigt geaenderten (id=1) + neu hinzugekommenen (id=3) Meilenstein, unveraenderten (id=2) NICHT (AC3)"
else
  bad "compute_milestone_delta lieferte unerwartetes JSON: $MS_DELTA ($(cat "$TMP/ms-delta.err"))"
fi

EMPTY_MS_DELTA="$(compute_milestone_delta "$MS_FROM" "$MS_FROM")"
if [ "$EMPTY_MS_DELTA" = '{"changed":[]}' ]; then
  ok "identischer Meilenstein-Stand erzeugt ein leeres Delta (changed=[])"
else
  bad "identischer Meilenstein-Stand haette ein leeres Delta erzeugen muessen, bekam: $EMPTY_MS_DELTA"
fi

echo "== @trace research-datenmodell#AC3,BR-019 -- create_divergence setzt PRAGMA busy_timeout VOR BEGIN IMMEDIATE (Reviewer-Fund Iteration 2, Critical) =="
DIVERGENCE_SRC="$(declare -f create_divergence)"
if echo "$DIVERGENCE_SRC" | grep -q "PRAGMA busy_timeout"; then
  ok "create_divergence() setzt PRAGMA busy_timeout auf der BEGIN IMMEDIATE-Verbindung"
else
  bad "create_divergence() sollte PRAGMA busy_timeout an der BEGIN IMMEDIATE-Verbindung setzen -- Regression des Critical-Fundes (Reviewer Iteration 2)"
fi

DIV_BUSY_ORDER_CHECK="$(echo "$DIVERGENCE_SRC" | grep -n "PRAGMA busy_timeout\|BEGIN IMMEDIATE")"
DIV_BUSY_LINE="$(echo "$DIV_BUSY_ORDER_CHECK" | grep "PRAGMA busy_timeout" | head -1 | cut -d: -f1)"
DIV_BEGIN_LINE="$(echo "$DIV_BUSY_ORDER_CHECK" | grep "BEGIN IMMEDIATE" | head -1 | cut -d: -f1)"
if [ -n "$DIV_BUSY_LINE" ] && [ -n "$DIV_BEGIN_LINE" ] && [ "$DIV_BUSY_LINE" -lt "$DIV_BEGIN_LINE" ]; then
  ok "PRAGMA busy_timeout steht VOR BEGIN IMMEDIATE in derselben Verbindung (create_divergence)"
else
  bad "PRAGMA busy_timeout muss VOR BEGIN IMMEDIATE stehen (create_divergence, busy_line=$DIV_BUSY_LINE begin_line=$DIV_BEGIN_LINE)"
fi

echo "== @trace research-datenmodell#AC3,BR-010 -- create_divergence: gleicher Hash ergibt is_empty=1 =="
DIV_TOPIC="$(create_topic "$TOPIC_DB" "Divergenz-Thema")"
DIV_HASH="$(compute_result_hash "weiterverfolgen" "$SWOT_FROM" "$MS_FROM")"
DIV_RUN_1="$(create_run "$TOPIC_DB" "$DIV_TOPIC" "recherche" "$DIV_HASH" "weiterverfolgen" 1 0)"
DIV_RUN_1_ID="${DIV_RUN_1%%|*}"
DIV_RUN_2="$(create_run "$TOPIC_DB" "$DIV_TOPIC" "recherche" "$DIV_HASH" "weiterverfolgen" 1 0)"
DIV_RUN_2_ID="${DIV_RUN_2%%|*}"
DIV_ID_EMPTY="$(create_divergence "$TOPIC_DB" "$DIV_RUN_1_ID" "$DIV_RUN_2_ID" "" "" 2> "$TMP/div-empty.err")"
if [ -n "$DIV_ID_EMPTY" ]; then
  ok "create_divergence legt eine Zeile fuer zwei Laeufe mit identischem Hash an"
else
  bad "create_divergence haette eine Zeile anlegen sollen: $(cat "$TMP/div-empty.err")"
fi
if [[ "$DIV_ID_EMPTY" =~ ^[0-9]+$ ]]; then
  ok "create_divergence-Rueckgabewert ist eine reine Zahl -- der per '.output /dev/null' unterdrueckte PRAGMA-busy_timeout-Rueckgabewert (5000) leakt nicht in die eingesammelte id"
else
  bad "create_divergence-Rueckgabewert haette eine reine Zahl sein sollen, bekam '$DIV_ID_EMPTY' -- PRAGMA-Rueckgabewert-Leak?"
fi
DIV_ROW_EMPTY="$(sqlite3 -separator '|' "$TOPIC_DB" "SELECT is_empty, recommendation_changed FROM ra_divergence WHERE id = $DIV_ID_EMPTY;")"
if [ "$DIV_ROW_EMPTY" = "1|0" ]; then
  ok "identischer result_hash ergibt is_empty=1 und recommendation_changed=0 (BR-010, idempotenter Wiederholungslauf)"
else
  bad "erwartete is_empty=1|recommendation_changed=0, bekam '$DIV_ROW_EMPTY'"
fi

echo "== @trace research-datenmodell#AC3,BR-010 -- create_divergence: geaenderter Hash + Empfehlung ergibt is_empty=0 =="
DIV_HASH_2="$(compute_result_hash "parken" "$SWOT_TO" "$MS_TO")"
DIV_RUN_3="$(create_run "$TOPIC_DB" "$DIV_TOPIC" "recherche" "$DIV_HASH_2" "parken" 1 0)"
DIV_RUN_3_ID="${DIV_RUN_3%%|*}"
DIV_ID_CHANGED="$(create_divergence "$TOPIC_DB" "$DIV_RUN_2_ID" "$DIV_RUN_3_ID" "$SWOT_DELTA" "$MS_DELTA" 2> "$TMP/div-changed.err")"
DIV_ROW_CHANGED="$(sqlite3 -separator '|' "$TOPIC_DB" "SELECT is_empty, recommendation_changed, swot_delta, milestone_status_delta FROM ra_divergence WHERE id = $DIV_ID_CHANGED;")"
EXPECTED_CHANGED="0|1|$SWOT_DELTA|$MS_DELTA"
if [ "$DIV_ROW_CHANGED" = "$EXPECTED_CHANGED" ]; then
  ok "unterschiedlicher Hash+Empfehlung ergibt is_empty=0/recommendation_changed=1, swot_delta/milestone_status_delta werden unveraendert materialisiert (BR-010, AC3)"
else
  bad "erwartete '$EXPECTED_CHANGED', bekam '$DIV_ROW_CHANGED' ($(cat "$TMP/div-changed.err"))"
fi

echo "== @trace research-datenmodell#AC3,BR-011 -- Divergenz nur zwischen Laeufen desselben Themas =="
OTHER_TOPIC="$(create_topic "$TOPIC_DB" "Anderes Thema")"
OTHER_RUN="$(create_run "$TOPIC_DB" "$OTHER_TOPIC" "recherche" "$DIV_HASH" "weiterverfolgen" 1 0)"
OTHER_RUN_ID="${OTHER_RUN%%|*}"
set +e
CROSS_TOPIC_OUT="$(create_divergence "$TOPIC_DB" "$DIV_RUN_1_ID" "$OTHER_RUN_ID" "" "" 2> "$TMP/cross-topic.err")"
CROSS_TOPIC_RC=$?
set -e
if [ "$CROSS_TOPIC_RC" -ne 0 ] && [ -z "$CROSS_TOPIC_OUT" ] && grep -qi "BR-011" "$TMP/cross-topic.err"; then
  ok "Laeufe zweier verschiedener Themen werden abgelehnt (BR-011)"
else
  bad "themenuebergreifende Divergenz haette abgelehnt werden muessen, rc=$CROSS_TOPIC_RC out='$CROSS_TOPIC_OUT': $(cat "$TMP/cross-topic.err")"
fi

echo "== @trace research-datenmodell#AC3,BR-011 -- Divergenz nur zwischen Laeufen derselben Art =="
DIV_RUN_PM="$(create_run "$TOPIC_DB" "$DIV_TOPIC" "pm" "$DIV_HASH" "weiterverfolgen" 1 0)"
DIV_RUN_PM_ID="${DIV_RUN_PM%%|*}"
set +e
CROSS_KIND_OUT="$(create_divergence "$TOPIC_DB" "$DIV_RUN_1_ID" "$DIV_RUN_PM_ID" "" "" 2> "$TMP/cross-kind.err")"
CROSS_KIND_RC=$?
set -e
if [ "$CROSS_KIND_RC" -ne 0 ] && [ -z "$CROSS_KIND_OUT" ] && grep -qi "BR-011" "$TMP/cross-kind.err"; then
  ok "Laeufe unterschiedlicher Art (recherche vs. pm) werden abgelehnt (BR-011)"
else
  bad "artuebergreifende Divergenz haette abgelehnt werden muessen, rc=$CROSS_KIND_RC out='$CROSS_KIND_OUT': $(cat "$TMP/cross-kind.err")"
fi

echo "== @trace research-datenmodell#AC3 -- UNIQUE(from_run_id,to_run_id) ist der native Backstop gegen doppelte Divergenz =="
set +e
DUP_DIV_OUT="$(create_divergence "$TOPIC_DB" "$DIV_RUN_1_ID" "$DIV_RUN_2_ID" "" "" 2> "$TMP/dup-div.err")"
DUP_DIV_RC=$?
set -e
if [ "$DUP_DIV_RC" -ne 0 ] && [ -z "$DUP_DIV_OUT" ]; then
  ok "erneute Divergenz-Anlage fuer dasselbe Laufpaar wird per UNIQUE(from_run_id,to_run_id) abgelehnt"
else
  bad "doppelte Divergenz-Anlage haette abgelehnt werden muessen, rc=$DUP_DIV_RC out='$DUP_DIV_OUT'"
fi

echo "== @trace research-datenmodell#AC3,security/R03 -- ungueltige/fremde run-id wird vor SQL-Interpolation abgelehnt =="
set +e
INJECT_DIV_OUT="$(create_divergence "$TOPIC_DB" "1; DROP TABLE ra_divergence;--" "$DIV_RUN_2_ID" "" "" 2> "$TMP/inject-div.err")"
INJECT_DIV_RC=$?
set -e
DIV_TABLE_STILL_THERE="$(sqlite3 "$TOPIC_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='ra_divergence';")"
if [ "$INJECT_DIV_RC" -ne 0 ] && [ -z "$INJECT_DIV_OUT" ] && grep -qi "security/R03" "$TMP/inject-div.err" && [ "$DIV_TABLE_STILL_THERE" = "ra_divergence" ]; then
  ok "manipulierte from-run-id wird per Formatpruefung abgelehnt, bevor sie ins SQL interpoliert wird (security/R03)"
else
  bad "manipulierte from-run-id haette abgelehnt werden muessen, rc=$INJECT_DIV_RC out='$INJECT_DIV_OUT' table='$DIV_TABLE_STILL_THERE': $(cat "$TMP/inject-div.err")"
fi

echo "== @trace research-datenmodell#AC3 -- nicht existierende run-id wird abgelehnt =="
set +e
MISSING_RUN_OUT="$(create_divergence "$TOPIC_DB" "999999" "$DIV_RUN_2_ID" "" "" 2> "$TMP/missing-run.err")"
MISSING_RUN_RC=$?
set -e
if [ "$MISSING_RUN_RC" -ne 0 ] && [ -z "$MISSING_RUN_OUT" ] && grep -qi "existiert nicht" "$TMP/missing-run.err"; then
  ok "nicht existierende from-run-id wird abgelehnt"
else
  bad "nicht existierende from-run-id haette abgelehnt werden muessen, rc=$MISSING_RUN_RC out='$MISSING_RUN_OUT': $(cat "$TMP/missing-run.err")"
fi

echo "== @trace research-datenmodell#AC3,BR-010 -- nativer CHECK-Backstop: is_empty=1 erzwingt swot_delta/milestone_status_delta=NULL (Reviewer-Fund Iteration 2, Important) =="
set +e
CHECK_BACKSTOP_ERR="$(sqlite3 "$TOPIC_DB" "INSERT INTO ra_divergence (topic_id, kind, from_run_id, to_run_id, is_empty, recommendation_changed, swot_delta, milestone_status_delta) VALUES ('$DIV_TOPIC', 'recherche', $DIV_RUN_1_ID, $DIV_RUN_3_ID, 1, 0, '{}', NULL);" 2>&1)"
CHECK_BACKSTOP_RC=$?
set -e
if [ "$CHECK_BACKSTOP_RC" -ne 0 ] && echo "$CHECK_BACKSTOP_ERR" | grep -qi "CHECK"; then
  ok "nativer CHECK in 005_ra_divergence.sql lehnt is_empty=1 mit gesetztem swot_delta ab (Konsistenz-Backstop, BR-010)"
else
  bad "CHECK-Backstop haette is_empty=1 + gesetztes swot_delta ablehnen sollen, rc=$CHECK_BACKSTOP_RC: $CHECK_BACKSTOP_ERR"
fi

set +e
CHECK_BACKSTOP_MS_ERR="$(sqlite3 "$TOPIC_DB" "INSERT INTO ra_divergence (topic_id, kind, from_run_id, to_run_id, is_empty, recommendation_changed, swot_delta, milestone_status_delta) VALUES ('$DIV_TOPIC', 'recherche', $DIV_RUN_1_ID, $DIV_RUN_3_ID, 1, 0, NULL, '{}');" 2>&1)"
CHECK_BACKSTOP_MS_RC=$?
set -e
if [ "$CHECK_BACKSTOP_MS_RC" -ne 0 ] && echo "$CHECK_BACKSTOP_MS_ERR" | grep -qi "CHECK"; then
  ok "nativer CHECK in 005_ra_divergence.sql lehnt is_empty=1 mit gesetztem milestone_status_delta ab (Konsistenz-Backstop, BR-010)"
else
  bad "CHECK-Backstop haette is_empty=1 + gesetztes milestone_status_delta ablehnen sollen, rc=$CHECK_BACKSTOP_MS_RC: $CHECK_BACKSTOP_MS_ERR"
fi

echo "== @trace research-datenmodell#AC7,BR-019 -- acquire_topic_lock erwirbt eine freie Sperre =="
LOCK_TOPIC="$(create_topic "$TOPIC_DB" "Lock-Thema")"
if acquire_topic_lock "$TOPIC_DB" "$LOCK_TOPIC" "research" 30 2> "$TMP/lock-a.err"; then
  ok "acquire_topic_lock erwirbt eine bislang freie Sperre (rc=0)"
else
  bad "acquire_topic_lock haette eine freie Sperre erwerben sollen: $(cat "$TMP/lock-a.err")"
fi
LOCK_ROW="$(sqlite3 -separator '|' "$TOPIC_DB" "SELECT holder FROM ra_topic_lock WHERE topic_id = '$LOCK_TOPIC';")"
if [ "$LOCK_ROW" = "research" ]; then
  ok "ra_topic_lock traegt den erwartenden Halter 'research' nach dem Erwerb"
else
  bad "erwartete Halter 'research', bekam '$LOCK_ROW'"
fi

echo "== @trace research-datenmodell#AC7,BR-019 -- zweiter Erwerb derselben, noch gueltigen Sperre wird abgelehnt =="
set +e
acquire_topic_lock "$TOPIC_DB" "$LOCK_TOPIC" "watchlist" 30 > /dev/null 2> "$TMP/lock-b.err"
LOCK_B_RC=$?
set -e
LOCK_ROW_AFTER="$(sqlite3 -separator '|' "$TOPIC_DB" "SELECT holder FROM ra_topic_lock WHERE topic_id = '$LOCK_TOPIC';")"
if [ "$LOCK_B_RC" -ne 0 ] && [ "$LOCK_ROW_AFTER" = "research" ] && grep -qi "BR-019" "$TMP/lock-b.err"; then
  ok "ein zweiter Halter wird abgelehnt, solange die bestehende Sperre nicht abgelaufen ist (BR-019), Halter bleibt unveraendert"
else
  bad "zweiter Erwerb haette abgelehnt werden muessen, rc=$LOCK_B_RC holder='$LOCK_ROW_AFTER': $(cat "$TMP/lock-b.err")"
fi

echo "== @trace research-datenmodell#AC7,BR-019 -- release_topic_lock lehnt Freigabe durch falschen Halter ab, gibt fuer den echten Halter frei =="
set +e
release_topic_lock "$TOPIC_DB" "$LOCK_TOPIC" "watchlist" > /dev/null 2> "$TMP/release-wrong.err"
RELEASE_WRONG_RC=$?
set -e
STILL_LOCKED="$(sqlite3 "$TOPIC_DB" "SELECT COUNT(*) FROM ra_topic_lock WHERE topic_id = '$LOCK_TOPIC';")"
if [ "$RELEASE_WRONG_RC" -ne 0 ] && [ "$STILL_LOCKED" = "1" ]; then
  ok "Freigabe durch einen Nicht-Halter wird abgelehnt, die Sperre bleibt bestehen"
else
  bad "Freigabe durch falschen Halter haette abgelehnt werden muessen, rc=$RELEASE_WRONG_RC rows=$STILL_LOCKED: $(cat "$TMP/release-wrong.err")"
fi

if release_topic_lock "$TOPIC_DB" "$LOCK_TOPIC" "research" 2> "$TMP/release-ok.err"; then
  ok "release_topic_lock gibt die Sperre durch den tatsaechlichen Halter frei"
else
  bad "release_topic_lock haette durch den echten Halter freigeben sollen: $(cat "$TMP/release-ok.err")"
fi
RELEASED_COUNT="$(sqlite3 "$TOPIC_DB" "SELECT COUNT(*) FROM ra_topic_lock WHERE topic_id = '$LOCK_TOPIC';")"
if [ "$RELEASED_COUNT" = "0" ]; then
  ok "nach Freigabe existiert keine Lock-Zeile mehr fuer das Thema"
else
  bad "nach Freigabe haette keine Lock-Zeile mehr existieren sollen, gefunden: $RELEASED_COUNT"
fi

echo "== @trace research-datenmodell#AC7,E2 -- abgelaufene Sperre wird uebernommen, kein Dauer-Deadlock =="
acquire_topic_lock "$TOPIC_DB" "$LOCK_TOPIC" "watchlist" 1 > /dev/null
sleep 2
if acquire_topic_lock "$TOPIC_DB" "$LOCK_TOPIC" "research" 30 2> "$TMP/lock-stale.err"; then
  ok "eine abgelaufene Sperre (expires_at in der Vergangenheit) wird von einem anderen Halter uebernommen (E2)"
else
  bad "abgelaufene Sperre haette uebernommen werden sollen: $(cat "$TMP/lock-stale.err")"
fi
STALE_HOLDER="$(sqlite3 -separator '|' "$TOPIC_DB" "SELECT holder FROM ra_topic_lock WHERE topic_id = '$LOCK_TOPIC';")"
if [ "$STALE_HOLDER" = "research" ]; then
  ok "nach Uebernahme traegt die Zeile den neuen Halter 'research', kein doppelter Row entstanden (PK topic_id)"
else
  bad "erwartete Halter 'research' nach Uebernahme, bekam '$STALE_HOLDER'"
fi
release_topic_lock "$TOPIC_DB" "$LOCK_TOPIC" "research" > /dev/null

echo "== @trace research-datenmodell#AC7,BR-019 -- BEGIN IMMEDIATE-Verbindungen setzen PRAGMA busy_timeout VOR Transaktionsstart =="
ACQUIRE_SRC="$(declare -f acquire_topic_lock)"
RELEASE_SRC="$(declare -f release_topic_lock)"
for pair in "acquire_topic_lock:$ACQUIRE_SRC" "release_topic_lock:$RELEASE_SRC"; do
  fn_name="${pair%%:*}"
  fn_src="${pair#*:}"
  if echo "$fn_src" | grep -q "PRAGMA busy_timeout"; then
    ok "$fn_name() setzt PRAGMA busy_timeout auf der BEGIN IMMEDIATE-Verbindung"
  else
    bad "$fn_name() sollte PRAGMA busy_timeout an der BEGIN IMMEDIATE-Verbindung setzen (BR-019)"
  fi
  order_check="$(echo "$fn_src" | grep -n "PRAGMA busy_timeout\|BEGIN IMMEDIATE")"
  busy_line="$(echo "$order_check" | grep "PRAGMA busy_timeout" | head -1 | cut -d: -f1)"
  begin_line="$(echo "$order_check" | grep "BEGIN IMMEDIATE" | head -1 | cut -d: -f1)"
  if [ -n "$busy_line" ] && [ -n "$begin_line" ] && [ "$busy_line" -lt "$begin_line" ]; then
    ok "$fn_name(): PRAGMA busy_timeout steht VOR BEGIN IMMEDIATE in derselben Verbindung"
  else
    bad "$fn_name(): PRAGMA busy_timeout muss VOR BEGIN IMMEDIATE stehen (busy_line=$busy_line begin_line=$begin_line)"
  fi
done

echo "== @trace research-datenmodell#AC7,security/R03 -- ungueltige Eingaben werden vor SQL-Interpolation abgelehnt =="
set +e
BAD_TOPIC_OUT="$(acquire_topic_lock "$TOPIC_DB" "x'; DROP TABLE ra_topic_lock; --" "research" 30 2> "$TMP/inject-lock.err")"
BAD_TOPIC_RC=$?
set -e
LOCK_TABLE_STILL_THERE="$(sqlite3 "$TOPIC_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='ra_topic_lock';")"
if [ "$BAD_TOPIC_RC" -ne 0 ] && [ -z "$BAD_TOPIC_OUT" ] && grep -qi "security/R03" "$TMP/inject-lock.err" && [ "$LOCK_TABLE_STILL_THERE" = "ra_topic_lock" ]; then
  ok "manipulierte Themen-ID wird per Format-Check FATAL abgelehnt, ra_topic_lock bleibt unangetastet (security/R03)"
else
  bad "manipulierte Themen-ID haette abgelehnt werden muessen, rc=$BAD_TOPIC_RC out='$BAD_TOPIC_OUT' table='$LOCK_TABLE_STILL_THERE': $(cat "$TMP/inject-lock.err")"
fi

set +e
BAD_HOLDER_OUT="$(acquire_topic_lock "$TOPIC_DB" "$LOCK_TOPIC" "sonstwer" 30 2> "$TMP/bad-holder.err")"
BAD_HOLDER_RC=$?
set -e
if [ "$BAD_HOLDER_RC" -ne 0 ] && [ -z "$BAD_HOLDER_OUT" ] && grep -qi "BR-019" "$TMP/bad-holder.err"; then
  ok "unbekannter Halter wird abgelehnt (BR-019)"
else
  bad "unbekannter Halter haette abgelehnt werden muessen, rc=$BAD_HOLDER_RC out='$BAD_HOLDER_OUT'"
fi

set +e
BAD_TTL_OUT="$(acquire_topic_lock "$TOPIC_DB" "$LOCK_TOPIC" "research" "30; DROP TABLE ra_topic_lock;--" 2> "$TMP/bad-ttl.err")"
BAD_TTL_RC=$?
set -e
if [ "$BAD_TTL_RC" -ne 0 ] && [ -z "$BAD_TTL_OUT" ] && grep -qi "security/R03" "$TMP/bad-ttl.err"; then
  ok "manipulierter TTL-Wert wird vor der SQL-Interpolation abgelehnt (security/R03)"
else
  bad "manipulierter TTL-Wert haette abgelehnt werden muessen, rc=$BAD_TTL_RC out='$BAD_TTL_OUT': $(cat "$TMP/bad-ttl.err")"
fi

echo "== @trace research-datenmodell#AC7,BR-019 -- FK: Sperre auf nicht existierendes Thema wird abgelehnt =="
set +e
FK_LOCK_ERR="$(acquire_topic_lock "$TOPIC_DB" "00000000-0000-7000-8000-0000000000ee" "research" 30 2>&1)"
FK_LOCK_RC=$?
set -e
if [ "$FK_LOCK_RC" -ne 0 ]; then
  ok "Sperre auf ein nicht existierendes Thema wird per FK-Constraint abgelehnt"
else
  bad "Sperre auf nicht existierendes Thema haette abgelehnt werden muessen: $FK_LOCK_ERR"
fi

echo "== @trace research-datenmodell#AC7,BR-019 -- zwei ECHTE parallele Schreiber (Watchlist-Job + /research-Lauf) auf dasselbe Thema korrumpieren nichts =="
CONCURRENT_TOPIC="$(create_topic "$TOPIC_DB" "Nebenlaeufigkeits-Thema")"
CONCURRENT_ROUNDS=5
CONCURRENT_OK_TOTAL=0
for round in $(seq 1 "$CONCURRENT_ROUNDS"); do
  (
    set +e
    acquire_topic_lock "$TOPIC_DB" "$CONCURRENT_TOPIC" "watchlist" 30 > "$TMP/conc-w-$round.out" 2> "$TMP/conc-w-$round.err"
    echo $? > "$TMP/conc-w-$round.rc"
  ) &
  (
    set +e
    acquire_topic_lock "$TOPIC_DB" "$CONCURRENT_TOPIC" "research" 30 > "$TMP/conc-r-$round.out" 2> "$TMP/conc-r-$round.err"
    echo $? > "$TMP/conc-r-$round.rc"
  ) &
  wait
  RC_W="$(cat "$TMP/conc-w-$round.rc")"
  RC_R="$(cat "$TMP/conc-r-$round.rc")"
  ROWS_AFTER="$(sqlite3 "$TOPIC_DB" "SELECT COUNT(*) FROM ra_topic_lock WHERE topic_id = '$CONCURRENT_TOPIC';")"
  if [ "$ROWS_AFTER" != "1" ]; then
    bad "Runde $round: nach zwei gleichzeitigen Erwerbsversuchen haette genau 1 Lock-Zeile existieren muessen (BR-019, kein korrupter Doppel-Erwerb), gefunden: $ROWS_AFTER"
  fi
  if { [ "$RC_W" = "0" ] && [ "$RC_R" != "0" ]; } || { [ "$RC_W" != "0" ] && [ "$RC_R" = "0" ]; }; then
    CONCURRENT_OK_TOTAL=$((CONCURRENT_OK_TOTAL + 1))
  else
    bad "Runde $round: erwartet genau EIN erfolgreicher Erwerb unter zwei echten parallelen OS-Prozessen, bekam rc_watchlist=$RC_W rc_research=$RC_R"
  fi
  sqlite3 "$TOPIC_DB" "DELETE FROM ra_topic_lock WHERE topic_id = '$CONCURRENT_TOPIC';"
done
if [ "$CONCURRENT_OK_TOTAL" = "$CONCURRENT_ROUNDS" ]; then
  ok "$CONCURRENT_ROUNDS/$CONCURRENT_ROUNDS Runden: unter zwei echten parallelen Schreiber-Prozessen (Watchlist-Job + /research-Lauf simuliert, jeweils per '&' als eigener OS-Prozess gestartet) gewinnt in jeder Runde genau einer, nie beide/keiner, nie mehr als 1 Zeile (AC7, BR-019)"
else
  bad "nur $CONCURRENT_OK_TOTAL/$CONCURRENT_ROUNDS Runden hatten exakt einen Gewinner -- Nebenlaeufigkeits-Serialisierung unzuverlaessig"
fi

echo "== @trace research-skill#AC2,BR-012 -- ra_swot_item: category/evidence_source-Enum als CHECK-Constraint (roh) =="
SWOT_TOPIC="$(create_topic "$TOPIC_DB" "SWOT-Thema")"
SWOT_HASH="$(compute_result_hash "weiterverfolgen" "" "")"
SWOT_RUN="$(create_run "$TOPIC_DB" "$SWOT_TOPIC" "recherche" "$SWOT_HASH" "weiterverfolgen" 0 1)"
SWOT_RUN_ID="${SWOT_RUN%%|*}"

BAD_CAT_ERR="$TMP/swot-bad-cat.err"
if sqlite3 "$TOPIC_DB" "INSERT INTO ra_swot_item (run_id, category, claim_key, evidence_source) VALUES ($SWOT_RUN_ID, 'unbekannt', 'marktgroesse', 'last30days');" 2> "$BAD_CAT_ERR"; then
  bad "ungueltige category 'unbekannt' wurde NICHT von der CHECK-Constraint abgelehnt (BR-012)"
else
  if grep -qi "CHECK constraint failed" "$BAD_CAT_ERR"; then
    ok "CHECK-Constraint lehnt eine category ausserhalb des Enums ab (BR-012)"
  else
    bad "Insert schlug fehl, aber nicht wegen der category-CHECK-Constraint: $(cat "$BAD_CAT_ERR")"
  fi
fi

BAD_EVID_ERR="$TMP/swot-bad-evid.err"
if sqlite3 "$TOPIC_DB" "INSERT INTO ra_swot_item (run_id, category, claim_key, evidence_source) VALUES ($SWOT_RUN_ID, 'strength', 'marktgroesse', 'quelle_x');" 2> "$BAD_EVID_ERR"; then
  bad "ungueltige evidence_source 'quelle_x' wurde NICHT von der CHECK-Constraint abgelehnt"
else
  if grep -qi "CHECK constraint failed" "$BAD_EVID_ERR"; then
    ok "CHECK-Constraint lehnt evidence_source ausserhalb des Enums ab"
  else
    bad "Insert schlug fehl, aber nicht wegen der evidence_source-CHECK-Constraint: $(cat "$BAD_EVID_ERR")"
  fi
fi

EMPTY_CLAIM_ERR="$TMP/swot-empty-claim.err"
if sqlite3 "$TOPIC_DB" "INSERT INTO ra_swot_item (run_id, category, claim_key, evidence_source) VALUES ($SWOT_RUN_ID, 'strength', '   ', 'last30days');" 2> "$EMPTY_CLAIM_ERR"; then
  bad "leerer/nur-Whitespace claim_key wurde NICHT von der CHECK-Constraint abgelehnt"
else
  if grep -qi "CHECK constraint failed" "$EMPTY_CLAIM_ERR"; then
    ok "CHECK-Constraint lehnt einen leeren claim_key ab"
  else
    bad "Insert schlug fehl, aber nicht wegen der claim_key-CHECK-Constraint: $(cat "$EMPTY_CLAIM_ERR")"
  fi
fi

echo "== @trace research-skill#AC2,BR-012 -- UNIQUE(run_id,category,claim_key) ist der native Backstop =="
sqlite3 "$TOPIC_DB" "PRAGMA foreign_keys = ON; INSERT INTO ra_swot_item (run_id, category, claim_key, evidence_source) VALUES ($SWOT_RUN_ID, 'strength', 'marktgroesse', 'last30days');"
set +e
DUP_SWOT_ERR="$TMP/swot-dup.err"
sqlite3 "$TOPIC_DB" "PRAGMA foreign_keys = ON; INSERT INTO ra_swot_item (run_id, category, claim_key, evidence_source) VALUES ($SWOT_RUN_ID, 'strength', 'marktgroesse', 'deep_research');" > /dev/null 2> "$DUP_SWOT_ERR"
DUP_SWOT_RC=$?
set -e
if [ "$DUP_SWOT_RC" -ne 0 ] && grep -qi "UNIQUE" "$DUP_SWOT_ERR"; then
  ok "doppelter (run_id,category,claim_key) wird per UNIQUE-Constraint abgelehnt (BR-012)"
else
  bad "doppelter (run_id,category,claim_key) haette per UNIQUE abgelehnt werden muessen, rc=$DUP_SWOT_RC: $(cat "$DUP_SWOT_ERR")"
fi

echo "== @trace research-skill#AC2,BR-018 -- ra_swot_item CASCADE-Loeschung mit ra_run =="
CASCADE_TOPIC="$(create_topic "$TOPIC_DB" "Cascade-SWOT-Thema")"
CASCADE_HASH="$(compute_result_hash "parken" "" "")"
CASCADE_RUN="$(create_run "$TOPIC_DB" "$CASCADE_TOPIC" "recherche" "$CASCADE_HASH" "parken" 1 0)"
CASCADE_RUN_ID="${CASCADE_RUN%%|*}"
sqlite3 "$TOPIC_DB" "PRAGMA foreign_keys = ON; INSERT INTO ra_swot_item (run_id, category, claim_key, evidence_source) VALUES ($CASCADE_RUN_ID, 'threat', 'wettbewerbsintensitaet', 'last30days');"
sqlite3 "$TOPIC_DB" "PRAGMA foreign_keys = ON; DELETE FROM ra_run WHERE id = $CASCADE_RUN_ID;"
CASCADE_REMAINING="$(sqlite3 "$TOPIC_DB" "SELECT COUNT(*) FROM ra_swot_item WHERE run_id = $CASCADE_RUN_ID;")"
if [ "$CASCADE_REMAINING" = "0" ]; then
  ok "Loeschen des Laufs kaskadiert auf dessen SWOT-Items (ON DELETE CASCADE, data-model.md §2.3)"
else
  bad "nach Loeschen des Laufs haetten keine SWOT-Items mehr uebrig sein sollen, gefunden: $CASCADE_REMAINING"
fi

echo "== @trace research-skill#AC2,BR-012,OF-06 -- create_swot_item: gueltige Kombination aus category+Vokabular-claim_key wird persistiert =="
NEW_SWOT_ID="$(create_swot_item "$TOPIC_DB" "$SWOT_RUN_ID" "opportunity" "regulierung" "deep_research" "Neue Foerderrichtlinie" 2> "$TMP/swot-create.err")"
if [[ "$NEW_SWOT_ID" =~ ^[0-9]+$ ]]; then
  ok "create_swot_item liefert eine neue SWOT-Item-ID fuer einen Vokabular-Begriff"
else
  bad "create_swot_item haette eine ID liefern muessen: '$NEW_SWOT_ID' ($(cat "$TMP/swot-create.err"))"
fi
STORED_RATIONALE="$(sqlite3 "$TOPIC_DB" "SELECT rationale FROM ra_swot_item WHERE id = $NEW_SWOT_ID;")"
if [ "$STORED_RATIONALE" = "Neue Foerderrichtlinie" ]; then
  ok "rationale (Freitext) wird unveraendert mitgespeichert"
else
  bad "erwartete rationale 'Neue Foerderrichtlinie', bekam '$STORED_RATIONALE'"
fi

echo "== @trace research-skill#AC2,BR-012,OF-06 -- create_swot_item: Normalisierung (Gross-/Kleinschreibung, Whitespace) mappt auf das Vokabular =="
NORM_SWOT_ID="$(create_swot_item "$TOPIC_DB" "$SWOT_RUN_ID" "weakness" "  TeamKompetenz  " "last30days" 2> "$TMP/swot-norm.err")"
NORM_STORED_KEY="$(sqlite3 "$TOPIC_DB" "SELECT claim_key FROM ra_swot_item WHERE id = $NORM_SWOT_ID;")"
if [ "$NORM_STORED_KEY" = "teamkompetenz" ]; then
  ok "claim_key wird vor der Vokabular-Pruefung getrimmt+kleingeschrieben und normalisiert persistiert (E2-Mapping)"
else
  bad "erwartete normalisierten claim_key 'teamkompetenz', bekam '$NORM_STORED_KEY' ($(cat "$TMP/swot-norm.err"))"
fi

echo "== @trace research-skill#AC2,BR-012,OF-06,E2 -- claim_key ausserhalb des Vokabulars wird als 'unmapped' zurueckgewiesen, nie ein freier Slug persistiert =="
set +e
UNMAPPED_OUT="$(create_swot_item "$TOPIC_DB" "$SWOT_RUN_ID" "threat" "ein-frei-erfundener-slug" "last30days" 2> "$TMP/swot-unmapped.err")"
UNMAPPED_RC=$?
set -e
UNMAPPED_ROWS="$(sqlite3 "$TOPIC_DB" "SELECT COUNT(*) FROM ra_swot_item WHERE claim_key = 'ein-frei-erfundener-slug';")"
if [ "$UNMAPPED_RC" -ne 0 ] && [ -z "$UNMAPPED_OUT" ] && grep -qi "unmapped" "$TMP/swot-unmapped.err" && [ "$UNMAPPED_ROWS" = "0" ]; then
  ok "claim_key ausserhalb des kontrollierten Vokabulars wird abgelehnt, nichts wird persistiert (BR-012/OF-06/E2)"
else
  bad "unbekannter claim_key haette als 'unmapped' abgelehnt werden muessen ohne Persistenz, rc=$UNMAPPED_RC out='$UNMAPPED_OUT' rows=$UNMAPPED_ROWS: $(cat "$TMP/swot-unmapped.err")"
fi

echo "== @trace research-skill#AC2,BR-012 -- create_swot_item: unbekannte category/evidence_source werden vor der SQL-Interpolation abgelehnt =="
set +e
BAD_CAT_OUT="$(create_swot_item "$TOPIC_DB" "$SWOT_RUN_ID" "sonstiges" "regulierung" "last30days" 2>"$TMP/swot-bad-cat-fn.err")"
BAD_CAT_RC=$?
set -e
if [ "$BAD_CAT_RC" -ne 0 ] && [ -z "$BAD_CAT_OUT" ] && grep -qi "BR-012" "$TMP/swot-bad-cat-fn.err"; then
  ok "create_swot_item lehnt eine unbekannte category vor der SQL-Interpolation ab"
else
  bad "unbekannte category haette abgelehnt werden muessen, rc=$BAD_CAT_RC out='$BAD_CAT_OUT'"
fi

set +e
BAD_EVID_OUT="$(create_swot_item "$TOPIC_DB" "$SWOT_RUN_ID" "opportunity" "regulierung" "quelle_x" 2>"$TMP/swot-bad-evid-fn.err")"
BAD_EVID_RC=$?
set -e
if [ "$BAD_EVID_RC" -ne 0 ] && [ -z "$BAD_EVID_OUT" ]; then
  ok "create_swot_item lehnt eine unbekannte evidence_source vor der SQL-Interpolation ab"
else
  bad "unbekannte evidence_source haette abgelehnt werden muessen, rc=$BAD_EVID_RC out='$BAD_EVID_OUT'"
fi

set +e
BAD_RUNID_OUT="$(create_swot_item "$TOPIC_DB" "1; DROP TABLE ra_swot_item;--" "strength" "regulierung" "last30days" 2>"$TMP/swot-bad-runid.err")"
BAD_RUNID_RC=$?
set -e
SWOT_TABLE_STILL_THERE="$(sqlite3 "$TOPIC_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='ra_swot_item';")"
if [ "$BAD_RUNID_RC" -ne 0 ] && [ -z "$BAD_RUNID_OUT" ] && grep -qi "security/R03" "$TMP/swot-bad-runid.err" && [ "$SWOT_TABLE_STILL_THERE" = "ra_swot_item" ]; then
  ok "manipulierte run_id wird per Formatpruefung abgelehnt, bevor sie ins SQL interpoliert wird (security/R03)"
else
  bad "manipulierte run_id haette abgelehnt werden muessen, rc=$BAD_RUNID_RC out='$BAD_RUNID_OUT' table='$SWOT_TABLE_STILL_THERE'"
fi

echo "== @trace research-skill#AC2 -- list_swot_items liefert (category,claim_key)-Zeilen sortiert, kompatibel zu compute_result_hash/compute_swot_delta =="
LIST_TOPIC="$(create_topic "$TOPIC_DB" "List-SWOT-Thema")"
LIST_HASH="$(compute_result_hash "weiterverfolgen" "" "")"
LIST_RUN="$(create_run "$TOPIC_DB" "$LIST_TOPIC" "recherche" "$LIST_HASH" "weiterverfolgen" 0 1)"
LIST_RUN_ID="${LIST_RUN%%|*}"
create_swot_item "$TOPIC_DB" "$LIST_RUN_ID" "threat" "wettbewerbsintensitaet" "last30days" > /dev/null
create_swot_item "$TOPIC_DB" "$LIST_RUN_ID" "strength" "marktgroesse" "last30days" > /dev/null
LISTED="$(list_swot_items "$TOPIC_DB" "$LIST_RUN_ID")"
EXPECTED_LISTED="$(printf 'strength|marktgroesse\nthreat|wettbewerbsintensitaet')"
if [ "$LISTED" = "$EXPECTED_LISTED" ]; then
  ok "list_swot_items liefert 'category|claim_key'-Zeilen sortiert nach (category,claim_key)"
else
  bad "erwartete '$EXPECTED_LISTED', bekam '$LISTED'"
fi

LISTED_HASH="$(compute_result_hash "weiterverfolgen" "$LISTED" "")"
if [[ "$LISTED_HASH" =~ ^[0-9a-f]{64}$ ]]; then
  ok "list_swot_items-Ausgabe ist direkt als <swot-pairs>-Parameter fuer compute_result_hash verwendbar (run.sh-Datei-Header-Vertrag)"
else
  bad "compute_result_hash mit list_swot_items-Ausgabe haette einen gueltigen Hash liefern muessen: '$LISTED_HASH'"
fi

EMPTY_RUN="$(create_run "$TOPIC_DB" "$LIST_TOPIC" "recherche" "$(compute_result_hash "parken" "" "")" "parken" 1 0)"
EMPTY_RUN_ID="${EMPTY_RUN%%|*}"
EMPTY_LIST="$(list_swot_items "$TOPIC_DB" "$EMPTY_RUN_ID")"
if [ -z "$EMPTY_LIST" ]; then
  ok "list_swot_items liefert leere Ausgabe fuer einen Lauf ohne SWOT-Items (kein Fehlerfall)"
else
  bad "erwartete leere Ausgabe fuer einen Lauf ohne SWOT-Items, bekam '$EMPTY_LIST'"
fi

echo "== @trace research-skill#AC2 -- get_run liest recommendation+momentum_only fuer die Bewertungsschicht-Anzeige =="
GET_RUN_OUT="$(get_run "$TOPIC_DB" "$SWOT_RUN_ID" 2> "$TMP/get-run.err")"
if [ "$GET_RUN_OUT" = "weiterverfolgen|1" ]; then
  ok "get_run liefert 'recommendation|momentum_only' fuer einen bestehenden Lauf"
else
  bad "erwartete 'weiterverfolgen|1', bekam '$GET_RUN_OUT' ($(cat "$TMP/get-run.err"))"
fi

set +e
MISSING_RUN_OUT="$(get_run "$TOPIC_DB" "999999" 2> "$TMP/get-run-missing.err")"
MISSING_RUN_RC=$?
set -e
if [ "$MISSING_RUN_RC" -ne 0 ] && [ -z "$MISSING_RUN_OUT" ]; then
  ok "get_run bricht fuer eine nicht existierende run_id mit FATAL ab"
else
  bad "get_run haette fuer eine nicht existierende run_id fehlschlagen sollen: rc=$MISSING_RUN_RC out='$MISSING_RUN_OUT'"
fi

echo
echo "Ergebnis: $pass OK, $fail FAIL"
[ "$fail" -eq 0 ]
