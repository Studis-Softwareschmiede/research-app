#!/usr/bin/env bash
# run_tests.sh — Self-Test fuer skills/research/ (/research-Skill-Grundgeruest,
# S-007: Discovery-/Thema-Modus, last30days-Aufruf, Persistenz ueber die
# Data-Access-Schicht, Quellen-Resilienz; S-011: Voraussetzungs-Ueberblick --
# Meilenstein-Liste je Thema + Schutzrechte-Klaerungspunkt).
#
# Rein mechanisches Shell-Test-Artefakt (M2-Grundgeruest, kein App-Layer im
# profile.md-Sinn -- language: md). Erfuellt die Spec-Vertragszeile "Tests
# taggen @trace research-skill#AC<n>" (docs/specs/research-skill.md
# "Verträge").
#
# Covers (research-skill): AC1 (Zwei Modi discovery/thema, last30days-Aufruf
# ueber --emit=json/--save-dir/--store, last30days_client.sh
# resolve/invoke-Funktionen), AC5 (Voraussetzungs-Ueberblick, S-011:
# db_scripts/lib/milestone.sh#create_milestone/list_milestones/
# set_milestone_status -- Meilenstein-Liste je Thema erzeugen/aktualisieren,
# Status+Zustaendigkeit extern/eigen inkl. Watchlist-Ref-Pflicht bei extern;
# orchestrator.sh#print_milestone_overview rendert die Liste im Brief + fixen
# Schutzrechte-Klaerungspunkt, kein Rechtsmodul, C-004; research_thema bindet
# den Ueberblick automatisch ein), AC6 (Themen-Anlage/-Wiederverwendung
# ausschliesslich ueber db_scripts/lib/topic.sh -- resolve_or_create_topic,
# BR-109-Praezisierung), AC7 (Quellen-Resilienz -- extract_missing_sources,
# Brief weist ausgefallene Quellen aus, Lauf laeuft mit den verbleibenden
# durch), E1 (last30days nicht installiert / eigener Store fehlt -> klarer
# Abbruch VOR jedem last30days-Aufruf, kein last30days-Call im
# Sentinel-Beleg), E3 (gleichzeitiger Lauf auf dasselbe Thema -> Advisory-Lock
# verweigert/ueberspringt mit Klartext, BR-019, kein Doppel-Lauf).
#
# last30days selbst ist in diesem Test-Environment nicht installiert (externe,
# API-/Netzwerk-abhaengige Installation) -- alle last30days-Aufrufe laufen
# gegen tests/fixtures/fake-last30days.sh (RA_LAST30DAYS_CMD-Override, exakt
# der vom Skill selbst vorgesehene Erweiterungspunkt, kein Test-Sonderpfad im
# Produktivcode).
#
# Aufruf: skills/research/tests/run_tests.sh
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESEARCH_DIR="$(dirname "$TEST_DIR")"
REPO_ROOT="$(cd "$RESEARCH_DIR/../.." && pwd)"
FAKE_L30D="$TEST_DIR/fixtures/fake-last30days.sh"

# shellcheck source=../scripts/lib/last30days_client.sh
source "$RESEARCH_DIR/scripts/lib/last30days_client.sh"
# shellcheck source=../../../db_scripts/lib/apply_migrations.sh
source "$REPO_ROOT/db_scripts/lib/apply_migrations.sh"
# shellcheck source=../../../db_scripts/lib/topic.sh
source "$REPO_ROOT/db_scripts/lib/topic.sh"
# shellcheck source=../../../db_scripts/lib/topic_lock.sh
source "$REPO_ROOT/db_scripts/lib/topic_lock.sh"
# shellcheck source=../../../db_scripts/lib/milestone.sh
source "$REPO_ROOT/db_scripts/lib/milestone.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  OK:   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# orchestrator.sh sourcen (main() feuert wegen des BASH_SOURCE-Guards nicht).
# shellcheck source=../scripts/orchestrator.sh
source "$RESEARCH_DIR/scripts/orchestrator.sh"

# new_migrated_db <db-path>
# Wendet die Migrationen direkt an (wie db_scripts/tests/run_tests.sh) -- BEWUSST
# ohne require_sqlite_version_or_die davor: der Guard ist eine vom S-007-Scope
# unabhaengige, bereits in db_scripts/tests/run_tests.sh abgedeckte Sorge
# (sqlite/R10); apply_migrations() selbst ruft ihn laut eigenem Datei-Header nie
# selbst auf (gezieltes Testen der Anwendungs-Logik unabhaengig vom
# Guard-Ergebnis der jeweiligen Testumgebung, siehe apply_migrations.sh-Header).
new_migrated_db() {
  local db="$1"
  apply_migrations "$db" "$REPO_ROOT/db_scripts" > /dev/null
  printf '%s' "$db"
}

echo "== @trace research-skill#AC1,E1 -- resolve_last30days_cmd: nicht installiert bricht klar ab =="
ERR="$TMP/resolve1.err"
if RA_LAST30DAYS_CMD="ra-definitiv-nicht-installiert-$$" resolve_last30days_cmd > /dev/null 2> "$ERR"; then
  bad "resolve_last30days_cmd haette fuer ein nicht existentes Kommando fehlschlagen muessen"
else
  if grep -q "FATAL.*nicht installiert" "$ERR" && grep -q "E1" "$ERR"; then
    ok "nicht aufloesbares Kommando bricht mit FATAL + Handlungsanweisung ab (E1)"
  else
    bad "FATAL-Meldung fehlt/unklar: $(cat "$ERR")"
  fi
fi

echo "== @trace research-skill#AC1 -- resolve_last30days_cmd: Override aufloesbar =="
GOT="$(RA_LAST30DAYS_CMD="$FAKE_L30D" resolve_last30days_cmd)"
if [ "$GOT" = "$FAKE_L30D" ]; then
  ok "RA_LAST30DAYS_CMD-Override wird aufgeloest, wenn ausfuehrbar"
else
  bad "erwartet '$FAKE_L30D', war '$GOT'"
fi

echo "== @trace research-skill#AC1 -- invoke_last30days_thema ruft last30days mit --emit=json/--save-dir/--store auf =="
ARGS_FILE="$TMP/thema.args"
SAVE_DIR="$TMP/save-thema"
JSON_OUT="$TMP/thema.stdout"
FAKE_L30D_JSON_FILE="$TEST_DIR/fixtures/thema_ok.json" FAKE_L30D_ARGS_FILE="$ARGS_FILE" \
  invoke_last30days_thema "$FAKE_L30D" "AI coding agents" "$SAVE_DIR" > "$JSON_OUT"
if [ -d "$SAVE_DIR" ] \
  && grep -qx "AI coding agents" "$ARGS_FILE" \
  && grep -qx "\-\-emit=json" "$ARGS_FILE" \
  && grep -qx "\-\-save-dir" "$ARGS_FILE" \
  && grep -qx "$SAVE_DIR" "$ARGS_FILE" \
  && grep -qx "\-\-store" "$ARGS_FILE"; then
  ok "Thema-Modus: save-dir angelegt + Topic-String/--emit=json/--save-dir/--store korrekt uebergeben"
else
  bad "Argumente/Save-Dir unerwartet: $(cat "$ARGS_FILE" 2>/dev/null), save-dir-exists=$([ -d "$SAVE_DIR" ] && echo yes || echo no)"
fi
if diff -q "$TEST_DIR/fixtures/thema_ok.json" "$JSON_OUT" > /dev/null 2>&1; then
  ok "last30days-JSON-Export landet unveraendert auf stdout"
else
  bad "stdout-JSON weicht von der Fixture ab"
fi

echo "== @trace research-skill#AC1 -- invoke_last30days_discovery ruft last30days mit --discover auf, kein positionelles Thema =="
ARGS_FILE2="$TMP/disc.args"
SAVE_DIR2="$TMP/save-disc"
FAKE_L30D_JSON_FILE="$TEST_DIR/fixtures/discovery_ok.json" FAKE_L30D_ARGS_FILE="$ARGS_FILE2" \
  invoke_last30days_discovery "$FAKE_L30D" "$SAVE_DIR2" > "$TMP/disc.stdout"
if grep -qx -- "--discover" "$ARGS_FILE2" && ! grep -qi "^AI " "$ARGS_FILE2"; then
  ok "Discovery-Modus: --discover gesetzt, kein positionelles Thema"
else
  bad "unerwartete Argumente: $(cat "$ARGS_FILE2")"
fi

echo "== @trace research-skill#AC1 -- last30days-Fehler-Exitcode wird als FATAL gemeldet, kein stiller Schluck =="
ERR2="$TMP/thema_fail.err"
if FAKE_L30D_EXIT_CODE=3 FAKE_L30D_STDERR="simulierter last30days-Fehler" \
  invoke_last30days_thema "$FAKE_L30D" "Failing Topic" "$TMP/save-fail" > /dev/null 2> "$ERR2"; then
  bad "invoke_last30days_thema haette bei last30days-Exitcode 3 fehlschlagen muessen"
else
  if grep -q "FATAL" "$ERR2" && grep -q "simulierter last30days-Fehler" "$ERR2"; then
    ok "last30days-Fehler-Exitcode fuehrt zu FATAL inkl. last30days-eigener Fehlermeldung"
  else
    bad "FATAL-Meldung unvollstaendig: $(cat "$ERR2")"
  fi
fi

echo "== @trace research-skill#AC7 -- extract_missing_sources klassifiziert source_status korrekt =="
MISSING="$(extract_missing_sources "$TEST_DIR/fixtures/thema_ok.json")"
EXPECTED_MISSING="$(printf 'hackernews|rate-limited\nx|auth-failed')"
if [ "$MISSING" = "$EXPECTED_MISSING" ]; then
  ok "auth-failed/rate-limited als ausgefallen erkannt; ok/no-results/partial/skipped-unconfigured NICHT (AC7)"
else
  bad "erwartet [$EXPECTED_MISSING], war [$MISSING]"
fi

echo "== @trace research-skill#AC7 -- extract_missing_sources: keine ausgefallene Quelle liefert leere Ausgabe =="
ALL_OK_JSON="$TMP/all_ok.json"
cat > "$ALL_OK_JSON" <<'JSON'
{"schema_version":"1.2","query":"x","generated_at":"2026-07-27T00:00:00Z","window_days":30,
 "source_status":{"reddit":"ok","x":"no-results","grounding":"partial"},
 "clusters":[],"results":[]}
JSON
MISSING_NONE="$(extract_missing_sources "$ALL_OK_JSON")"
if [ -z "$MISSING_NONE" ]; then
  ok "ok/no-results/partial ergeben eine leere Missing-Liste"
else
  bad "erwartet leere Ausgabe, war [$MISSING_NONE]"
fi

echo "== @trace research-skill#AC1,AC7 -- extract_discovery_topics liest results[].topic in Ranking-Reihenfolge =="
TOPICS="$(extract_discovery_topics "$TEST_DIR/fixtures/discovery_ok.json")"
EXPECTED_TOPICS="$(printf 'Topic Alpha\nTopic Beta')"
if [ "$TOPICS" = "$EXPECTED_TOPICS" ]; then
  ok "Discovery-Kandidaten werden in Ranking-Reihenfolge extrahiert"
else
  bad "erwartet [$EXPECTED_TOPICS], war [$TOPICS]"
fi

echo "== @trace research-skill#AC1 -- extract_discovery_topics: 'nothing-solid' liefert leere Kandidatenliste =="
NONE_TOPICS="$(extract_discovery_topics "$TEST_DIR/fixtures/discovery_nothing_solid.json")"
if [ -z "$NONE_TOPICS" ]; then
  ok "leeres results[] (outcome=nothing-solid) liefert leere Kandidatenliste, kein Fehler"
else
  bad "erwartet leere Ausgabe, war [$NONE_TOPICS]"
fi

echo "== @trace research-skill#AC6,BR-109 -- resolve_or_create_topic legt neues Thema an, wenn kein exakter Treffer existiert =="
DB1="$(new_migrated_db "$TMP/ac6-new.sqlite")"
NEW_ID="$(resolve_or_create_topic "$DB1" "Ganz neues Thema" 2>/dev/null)"
COUNT_NEW="$(sqlite3 "$DB1" "SELECT COUNT(*) FROM ra_topic WHERE title = 'Ganz neues Thema';")"
if [ -n "$NEW_ID" ] && [ "$COUNT_NEW" = "1" ]; then
  ok "kein Treffer -> neues Thema wird ueber create_topic angelegt (AC6)"
else
  bad "erwartet genau 1 neue Zeile mit gueltiger ID, war COUNT=$COUNT_NEW ID=[$NEW_ID]"
fi

echo "== @trace research-skill#AC6,BR-109 -- resolve_or_create_topic verwendet EXAKT identisches Thema wieder =="
REUSED_ID="$(resolve_or_create_topic "$DB1" "Ganz neues Thema" 2>/dev/null)"
COUNT_AFTER="$(sqlite3 "$DB1" "SELECT COUNT(*) FROM ra_topic WHERE title = 'Ganz neues Thema';")"
if [ "$REUSED_ID" = "$NEW_ID" ] && [ "$COUNT_AFTER" = "1" ]; then
  ok "exakt gleicher Titel wird wiederverwendet (gleiche ID, keine zweite Zeile, BR-109-Praezisierung)"
else
  bad "erwartet Reuse der ID '$NEW_ID' ohne neue Zeile, war ID=[$REUSED_ID] COUNT=$COUNT_AFTER"
fi

echo "== @trace research-skill#AC6,OF-02 -- mehrere bestehende Treffer: resolve_or_create_topic legt neues Thema an (kein Rate-Guess) =="
DB2="$(new_migrated_db "$TMP/ac6-ambiguous.sqlite")"
create_topic "$DB2" "Mehrdeutiger Titel" > /dev/null 2>&1
create_topic "$DB2" "Mehrdeutiger Titel" > /dev/null 2>&1
COUNT_BEFORE="$(sqlite3 "$DB2" "SELECT COUNT(*) FROM ra_topic WHERE title = 'Mehrdeutiger Titel';")"
THIRD_ID="$(resolve_or_create_topic "$DB2" "Mehrdeutiger Titel" 2>/dev/null)"
COUNT_AFTER2="$(sqlite3 "$DB2" "SELECT COUNT(*) FROM ra_topic WHERE title = 'Mehrdeutiger Titel';")"
if [ "$COUNT_BEFORE" = "2" ] && [ "$COUNT_AFTER2" = "3" ] && [ -n "$THIRD_ID" ]; then
  ok "bei 2 bestehenden Treffern legt resolve_or_create_topic ein WEITERES Thema an statt zu raten (OF-02 bleibt Warnungs-Pfad)"
else
  bad "erwartet 2 -> 3 Zeilen, war $COUNT_BEFORE -> $COUNT_AFTER2 (ID=[$THIRD_ID])"
fi

echo "== @trace research-skill#E1 -- check_store_or_die: fehlende research-app.sqlite bricht klar ab, last30days wird NICHT aufgerufen =="
MISSING_DB="$TMP/does-not-exist.sqlite"
ERR3="$TMP/store_missing.err"
if check_store_or_die "$MISSING_DB" 2> "$ERR3"; then
  bad "check_store_or_die haette fuer eine fehlende DB-Datei fehlschlagen muessen"
else
  if grep -q "FATAL.*Store fehlt" "$ERR3" && grep -q "E1" "$ERR3" && grep -q "migrate.sh" "$ERR3"; then
    ok "fehlende research-app.sqlite bricht mit FATAL + Handlungsanweisung ab (E1)"
  else
    bad "FATAL-Meldung unklar: $(cat "$ERR3")"
  fi
fi

echo "== @trace research-skill#E1 -- check_store_or_die: nicht migrierte DB (Tabelle ra_topic fehlt) bricht klar ab =="
UNMIGRATED_DB="$TMP/unmigrated.sqlite"
sqlite3 "$UNMIGRATED_DB" "CREATE TABLE dummy (id INTEGER);" > /dev/null
ERR4="$TMP/store_unmigrated.err"
if check_store_or_die "$UNMIGRATED_DB" 2> "$ERR4"; then
  bad "check_store_or_die haette fuer eine nicht migrierte DB fehlschlagen muessen"
else
  if grep -q "FATAL.*nicht migriert" "$ERR4"; then
    ok "nicht migrierte research-app.sqlite bricht mit FATAL ab"
  else
    bad "FATAL-Meldung unklar: $(cat "$ERR4")"
  fi
fi

echo "== @trace research-skill#E1 -- research_thema bricht VOR last30days ab, wenn der Store fehlt (kein Halb-Lauf) =="
SENTINEL1="$TMP/sentinel-e1.touched"
rm -f "$SENTINEL1"
ERR5="$TMP/research_thema_e1.err"
if RA_LAST30DAYS_CMD="$FAKE_L30D" FAKE_L30D_SENTINEL="$SENTINEL1" \
  research_thema "$TMP/kein-store.sqlite" "Irgendein Thema" "$TMP/save-e1" 2> "$ERR5" > /dev/null; then
  bad "research_thema haette ohne migrierten Store fehlschlagen muessen"
else
  if [ ! -f "$SENTINEL1" ] && grep -q "FATAL.*Store fehlt" "$ERR5"; then
    ok "research_thema bricht ab, BEVOR last30days aufgerufen wird (last30days-Sentinel fehlt, kein Halb-Lauf)"
  else
    bad "last30days wurde trotzdem aufgerufen (sentinel exists=$([ -f "$SENTINEL1" ] && echo yes || echo no)) oder Meldung unklar: $(cat "$ERR5")"
  fi
fi

echo "== @trace research-skill#AC1,AC6,AC7 -- research_thema Ende-zu-Ende: Thema angelegt, Brief weist fehlende Quelle aus =="
DB3="$(new_migrated_db "$TMP/e2e-thema.sqlite")"
SENTINEL2="$TMP/sentinel-e2e.touched"
OUT_E2E="$TMP/thema_e2e.out"
if RA_LAST30DAYS_CMD="$FAKE_L30D" FAKE_L30D_SENTINEL="$SENTINEL2" \
  FAKE_L30D_JSON_FILE="$TEST_DIR/fixtures/thema_ok.json" \
  research_thema "$DB3" "AI coding agents" "$TMP/save-e2e" > "$OUT_E2E" 2>/dev/null; then
  TOPIC_COUNT="$(sqlite3 "$DB3" "SELECT COUNT(*) FROM ra_topic WHERE title = 'AI coding agents';")"
  LOCK_COUNT="$(sqlite3 "$DB3" "SELECT COUNT(*) FROM ra_topic_lock;")"
  if [ -f "$SENTINEL2" ] && [ "$TOPIC_COUNT" = "1" ] && [ "$LOCK_COUNT" = "0" ] \
    && grep -q "Themen-ID:" "$OUT_E2E" \
    && grep -q "Fehlende Quellen" "$OUT_E2E" \
    && grep -q "x: auth-failed" "$OUT_E2E" \
    && grep -q "hackernews: rate-limited" "$OUT_E2E"; then
    ok "Thema angelegt (genau 1 Zeile), Lock nach Lauf wieder frei, Brief weist beide ausgefallenen Quellen aus (AC1/AC6/AC7)"
  else
    bad "Ende-zu-Ende-Ergebnis unerwartet: topic_count=$TOPIC_COUNT lock_count=$LOCK_COUNT sentinel=$([ -f "$SENTINEL2" ] && echo yes || echo no); Brief: $(cat "$OUT_E2E")"
  fi
else
  bad "research_thema (E2E) schlug unerwartet fehl: $(cat "$OUT_E2E" 2>/dev/null)"
fi

echo "== @trace research-skill#E3,BR-019 -- research_thema verweigert einen zweiten Lauf auf ein bereits gesperrtes Thema (Klartext, kein Doppel-Lauf) =="
DB4="$(new_migrated_db "$TMP/e3.sqlite")"
LOCKED_TOPIC_ID="$(create_topic "$DB4" "Gesperrtes Thema" 2>/dev/null)"
acquire_topic_lock "$DB4" "$LOCKED_TOPIC_ID" "watchlist" 1800 > /dev/null
SENTINEL3="$TMP/sentinel-e3.touched"
rm -f "$SENTINEL3"
ERR6="$TMP/research_thema_e3.err"
if RA_LAST30DAYS_CMD="$FAKE_L30D" FAKE_L30D_SENTINEL="$SENTINEL3" \
  FAKE_L30D_JSON_FILE="$TEST_DIR/fixtures/thema_ok.json" \
  research_thema "$DB4" "Gesperrtes Thema" "$TMP/save-e3" 2> "$ERR6" > /dev/null; then
  bad "research_thema haette auf ein bereits gesperrtes Thema mit FATAL abbrechen muessen"
else
  if [ ! -f "$SENTINEL3" ] && grep -qi "bereits gesperrt" "$ERR6"; then
    ok "zweiter Lauf auf dasselbe (bereits gesperrte) Thema wird mit Klartext abgelehnt, last30days wird NICHT aufgerufen (E3/BR-019)"
  else
    bad "last30days wurde trotzdem aufgerufen oder Meldung unklar: sentinel=$([ -f "$SENTINEL3" ] && echo yes || echo no) err=$(cat "$ERR6")"
  fi
fi
release_topic_lock "$DB4" "$LOCKED_TOPIC_ID" "watchlist" > /dev/null

echo "== @trace research-skill#AC1,AC6,AC7,E3 -- research_discovery Ende-zu-Ende: mehrere Themen angelegt, ein gesperrtes Thema wird uebersprungen =="
DB5="$(new_migrated_db "$TMP/e2e-disc.sqlite")"
PRELOCKED_ID="$(create_topic "$DB5" "Topic Beta" 2>/dev/null)"
acquire_topic_lock "$DB5" "$PRELOCKED_ID" "watchlist" 1800 > /dev/null
OUT_DISC="$TMP/disc_e2e.out"
if RA_LAST30DAYS_CMD="$FAKE_L30D" FAKE_L30D_JSON_FILE="$TEST_DIR/fixtures/discovery_ok.json" \
  research_discovery "$DB5" "$TMP/save-disc-e2e" > "$OUT_DISC" 2>"$TMP/disc_e2e.err"; then
  ALPHA_COUNT="$(sqlite3 "$DB5" "SELECT COUNT(*) FROM ra_topic WHERE title = 'Topic Alpha';")"
  BETA_COUNT="$(sqlite3 "$DB5" "SELECT COUNT(*) FROM ra_topic WHERE title = 'Topic Beta';")"
  if [ "$ALPHA_COUNT" = "1" ] && [ "$BETA_COUNT" = "1" ] \
    && grep -q "Topic Alpha" "$OUT_DISC" \
    && grep -qi "UEBERSPRUNGEN.*Topic Beta" "$TMP/disc_e2e.err"; then
    ok "Discovery legt neues Thema an, ueberspringt bereits gesperrtes Thema mit Klartext, restlicher Lauf laeuft durch (E3, kein Gesamt-Abbruch)"
  else
    bad "unerwartetes Ergebnis: alpha=$ALPHA_COUNT beta=$BETA_COUNT brief=$(cat "$OUT_DISC") err=$(cat "$TMP/disc_e2e.err")"
  fi
else
  bad "research_discovery (E2E) schlug unerwartet fehl: $(cat "$OUT_DISC" 2>/dev/null) $(cat "$TMP/disc_e2e.err" 2>/dev/null)"
fi
release_topic_lock "$DB5" "$PRELOCKED_ID" "watchlist" > /dev/null

echo "== @trace research-skill#AC5 -- create_milestone legt Meilenstein 'offen' an (eigen, ohne watch_ref) =="
DB6="$(new_migrated_db "$TMP/ac5-milestones.sqlite")"
TOPIC6="$(create_topic "$DB6" "Voraussetzungs-Thema" 2>/dev/null)"
MS_ID_1="$(create_milestone "$DB6" "$TOPIC6" "Pilotkunde bestaetigt" "eigen" 2> "$TMP/ms1.err")"
if [ -n "$MS_ID_1" ]; then
  MS1_ROW="$(sqlite3 -separator '|' "$DB6" "SELECT description, responsibility, status, watch_ref FROM ra_milestone WHERE id = $MS_ID_1;")"
  if [ "$MS1_ROW" = "Pilotkunde bestaetigt|eigen|offen|" ]; then
    ok "create_milestone legt Meilenstein mit Status 'offen', responsibility 'eigen', watch_ref NULL an"
  else
    bad "unerwartete Zeile nach create_milestone: '$MS1_ROW'"
  fi
else
  bad "create_milestone haette eine Meilenstein-ID liefern muessen: $(cat "$TMP/ms1.err")"
fi

echo "== @trace research-skill#AC5,BR-015 -- create_milestone: 'extern' erfordert watch_ref, 'eigen' verbietet ihn =="
set +e
NO_REF_OUT="$(create_milestone "$DB6" "$TOPIC6" "Externe Zusage" "extern" 2> "$TMP/ms-noref.err")"
NO_REF_RC=$?
set -e
if [ "$NO_REF_RC" -ne 0 ] && [ -z "$NO_REF_OUT" ] && grep -qi "BR-015" "$TMP/ms-noref.err"; then
  ok "responsibility='extern' ohne watch_ref wird vor der SQL-Interpolation abgelehnt (BR-015)"
else
  bad "erwartete Ablehnung, rc=$NO_REF_RC out='$NO_REF_OUT': $(cat "$TMP/ms-noref.err")"
fi

set +e
EXTRA_REF_OUT="$(create_milestone "$DB6" "$TOPIC6" "Eigene Aufgabe" "eigen" "watchlist-item-x" 2> "$TMP/ms-extraref.err")"
EXTRA_REF_RC=$?
set -e
if [ "$EXTRA_REF_RC" -ne 0 ] && [ -z "$EXTRA_REF_OUT" ] && grep -qi "BR-015" "$TMP/ms-extraref.err"; then
  ok "responsibility='eigen' MIT watch_ref wird vor der SQL-Interpolation abgelehnt (BR-015)"
else
  bad "erwartete Ablehnung, rc=$EXTRA_REF_RC out='$EXTRA_REF_OUT': $(cat "$TMP/ms-extraref.err")"
fi

MS_ID_2="$(create_milestone "$DB6" "$TOPIC6" "Watchlist prueft API-Zugang" "extern" "watchlist-item-1" 2> "$TMP/ms2.err")"
if [ -n "$MS_ID_2" ]; then
  MS2_ROW="$(sqlite3 -separator '|' "$DB6" "SELECT responsibility, watch_ref FROM ra_milestone WHERE id = $MS_ID_2;")"
  if [ "$MS2_ROW" = "extern|watchlist-item-1" ]; then
    ok "responsibility='extern' MIT watch_ref wird korrekt angelegt"
  else
    bad "unerwartete Zeile fuer extern-Meilenstein: '$MS2_ROW'"
  fi
else
  bad "create_milestone (extern, mit watch_ref) haette eine ID liefern muessen: $(cat "$TMP/ms2.err")"
fi

echo "== @trace research-skill#AC5,security/R03 -- create_milestone: ungueltige Themen-ID wird vor SQL-Interpolation abgelehnt =="
set +e
INJECT_MS_OUT="$(create_milestone "$DB6" "x'; DROP TABLE ra_milestone; --" "Injektion" "eigen" 2> "$TMP/ms-inject.err")"
INJECT_MS_RC=$?
set -e
STILL_THERE_MS="$(sqlite3 "$DB6" "SELECT name FROM sqlite_master WHERE type='table' AND name='ra_milestone';")"
if [ "$INJECT_MS_RC" -ne 0 ] && [ -z "$INJECT_MS_OUT" ] && [ "$STILL_THERE_MS" = "ra_milestone" ] && grep -qi "FATAL" "$TMP/ms-inject.err"; then
  ok "manipulierte Themen-ID wird per Format-Check FATAL abgelehnt, ra_milestone bleibt unangetastet (security/R03)"
else
  bad "erwartete Ablehnung, rc=$INJECT_MS_RC out='$INJECT_MS_OUT' table='$STILL_THERE_MS': $(cat "$TMP/ms-inject.err")"
fi

echo "== @trace research-skill#AC5 -- list_milestones liefert die Meilenstein-Liste sortiert nach Anlage (Unit-Separator 0x1f) =="
LIST_OUT="$(list_milestones "$DB6" "$TOPIC6")"
US=$'\x1f'
EXPECTED_LIST="$(printf '%s%sPilotkunde bestaetigt%seigen%soffen%s\n%s%sWatchlist prueft API-Zugang%sextern%soffen%swatchlist-item-1' \
  "$MS_ID_1" "$US" "$US" "$US" "$US" "$MS_ID_2" "$US" "$US" "$US" "$US")"
if [ "$LIST_OUT" = "$EXPECTED_LIST" ]; then
  ok "list_milestones gibt beide Meilensteine mit Status+Zustaendigkeit(+watch_ref) in Anlage-Reihenfolge aus (Unit-Separator statt '|')"
else
  bad "erwartet [$EXPECTED_LIST], war [$LIST_OUT]"
fi

echo "== @trace research-skill#AC5 -- list_milestones/print_milestone_overview: '|' IN der Beschreibung verschiebt KEINE Folgefelder (DBA-Review Iteration 2, Regression) =="
TOPIC_PIPE="$(create_topic "$DB6" "Thema mit Pipe-Beschreibung" 2>/dev/null)"
MS_ID_PIPE="$(create_milestone "$DB6" "$TOPIC_PIPE" "Vertrag A|B unterschreiben" "extern" "watchlist-item-pipe" 2> "$TMP/ms-pipe.err")"
if [ -z "$MS_ID_PIPE" ]; then
  bad "create_milestone haette fuer eine Beschreibung mit '|' eine ID liefern muessen: $(cat "$TMP/ms-pipe.err")"
else
  PIPE_LIST_OUT="$(list_milestones "$DB6" "$TOPIC_PIPE")"
  EXPECTED_PIPE_LIST="$(printf '%s%sVertrag A|B unterschreiben%sextern%soffen%swatchlist-item-pipe' "$MS_ID_PIPE" "$US" "$US" "$US" "$US")"
  if [ "$PIPE_LIST_OUT" = "$EXPECTED_PIPE_LIST" ]; then
    ok "list_milestones haelt eine Beschreibung mit '|' als EIN Feld zusammen (Unit-Separator statt '|' als Trennzeichen)"
  else
    bad "erwartet [$EXPECTED_PIPE_LIST], war [$PIPE_LIST_OUT] -- '|' in der Beschreibung haette KEINE Folgefelder verschieben duerfen"
  fi

  PIPE_OVERVIEW="$(print_milestone_overview "$DB6" "$TOPIC_PIPE")"
  if echo "$PIPE_OVERVIEW" | grep -qF "[offen] Vertrag A|B unterschreiben (Zustaendigkeit: extern, Watchlist-Ref: watchlist-item-pipe)"; then
    ok "print_milestone_overview zeigt Status 'offen'/Zustaendigkeit 'extern'/Watchlist-Ref korrekt an, obwohl die Beschreibung ein '|' enthaelt (AC5-Kernzweck: Status/Zustaendigkeit bleiben korrekt zugeordnet)"
  else
    bad "print_milestone_overview zeigte bei '|' in der Beschreibung ein falsch verschobenes Feld: $PIPE_OVERVIEW"
  fi
fi

echo "== @trace research-skill#AC5,BR-016 -- set_milestone_status aktualisiert Status, setzt fulfilled_at nur bei 'erfuellt' =="
if set_milestone_status "$DB6" "$MS_ID_1" "erfuellt" 2> "$TMP/ms-status.err"; then
  MS1_AFTER="$(sqlite3 -separator '|' "$DB6" "SELECT status, (fulfilled_at IS NOT NULL) FROM ra_milestone WHERE id = $MS_ID_1;")"
  if [ "$MS1_AFTER" = "erfuellt|1" ]; then
    ok "set_milestone_status setzt Status auf 'erfuellt' und befuellt fulfilled_at"
  else
    bad "unerwarteter Stand nach set_milestone_status: '$MS1_AFTER'"
  fi
else
  bad "set_milestone_status haette durchgehen sollen: $(cat "$TMP/ms-status.err")"
fi

set +e
BAD_STATUS_OUT="$(set_milestone_status "$DB6" "$MS_ID_2" "unbekannt" 2> "$TMP/ms-bad-status.err")"
BAD_STATUS_RC=$?
set -e
if [ "$BAD_STATUS_RC" -ne 0 ] && [ -z "$BAD_STATUS_OUT" ] && grep -qi "BR-016" "$TMP/ms-bad-status.err"; then
  ok "ungueltiger Zielstatus wird von set_milestone_status abgelehnt (BR-016)"
else
  bad "erwartete Ablehnung, rc=$BAD_STATUS_RC: $(cat "$TMP/ms-bad-status.err")"
fi

set +e
UNKNOWN_MS_OUT="$(set_milestone_status "$DB6" "999999" "offen" 2> "$TMP/ms-unknown.err")"
UNKNOWN_MS_RC=$?
set -e
if [ "$UNKNOWN_MS_RC" -ne 0 ] && [ -z "$UNKNOWN_MS_OUT" ] && grep -qi "existiert nicht" "$TMP/ms-unknown.err"; then
  ok "Statuswechsel auf eine nicht existierende Meilenstein-ID wird abgelehnt"
else
  bad "erwartete Ablehnung, rc=$UNKNOWN_MS_RC: $(cat "$TMP/ms-unknown.err")"
fi

echo "== @trace research-skill#AC5 -- print_milestone_overview rendert Liste + Schutzrechte-Klaerungspunkt (leer + befuellt) =="
DB7="$(new_migrated_db "$TMP/ac5-overview-empty.sqlite")"
TOPIC7="$(create_topic "$DB7" "Thema ohne Meilensteine" 2>/dev/null)"
OVERVIEW_EMPTY="$(print_milestone_overview "$DB7" "$TOPIC7")"
if echo "$OVERVIEW_EMPTY" | grep -qi "Noch keine Meilensteine" \
  && echo "$OVERVIEW_EMPTY" | grep -q "Klaerungspunkt Schutzrechte.*kein automatisiertes Rechtsmodul.*C-004"; then
  ok "ohne Meilensteine: 'Noch keine Meilensteine'-Hinweis + Schutzrechte-Klaerungspunkt erscheinen trotzdem (C-004)"
else
  bad "unerwartete Ausgabe ohne Meilensteine: $OVERVIEW_EMPTY"
fi

OVERVIEW_FULL="$(print_milestone_overview "$DB6" "$TOPIC6")"
if echo "$OVERVIEW_FULL" | grep -q "\[erfuellt\] Pilotkunde bestaetigt (Zustaendigkeit: eigen)" \
  && echo "$OVERVIEW_FULL" | grep -q "\[offen\] Watchlist prueft API-Zugang (Zustaendigkeit: extern, Watchlist-Ref: watchlist-item-1)" \
  && echo "$OVERVIEW_FULL" | grep -q "Klaerungspunkt Schutzrechte.*kein automatisiertes Rechtsmodul.*C-004"; then
  ok "mit Meilensteinen: Status+Zustaendigkeit(+watch_ref bei extern) je Zeile + Schutzrechte-Klaerungspunkt (AC5)"
else
  bad "unerwartete Ausgabe mit Meilensteinen: $OVERVIEW_FULL"
fi

echo "== @trace research-skill#AC5,AC1,AC6,AC7 -- research_thema bindet den Voraussetzungs-Ueberblick automatisch in den Brief ein =="
DB8="$(new_migrated_db "$TMP/ac5-e2e-thema.sqlite")"
OUT_AC5_E2E="$TMP/ac5_e2e.out"
if RA_LAST30DAYS_CMD="$FAKE_L30D" FAKE_L30D_JSON_FILE="$TEST_DIR/fixtures/thema_ok.json" \
  research_thema "$DB8" "Thema mit Ueberblick" "$TMP/save-ac5-e2e" > "$OUT_AC5_E2E" 2>/dev/null; then
  if grep -q "Voraussetzungs-Ueberblick" "$OUT_AC5_E2E" \
    && grep -qi "Noch keine Meilensteine" "$OUT_AC5_E2E" \
    && grep -q "Klaerungspunkt Schutzrechte.*C-004" "$OUT_AC5_E2E"; then
    ok "research_thema-Brief enthaelt den Voraussetzungs-Ueberblick inkl. Schutzrechte-Klaerungspunkt (AC5, kein Rechtsmodul)"
  else
    bad "Voraussetzungs-Ueberblick fehlt im Brief oder unvollstaendig: $(cat "$OUT_AC5_E2E")"
  fi
else
  bad "research_thema (AC5-E2E) schlug unerwartet fehl: $(cat "$OUT_AC5_E2E" 2>/dev/null)"
fi

echo
echo "Ergebnis: $pass OK, $fail FAIL"
[ "$fail" -eq 0 ]
