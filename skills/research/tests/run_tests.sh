#!/usr/bin/env bash
# run_tests.sh — Self-Test fuer skills/research/ (/research-Skill-Grundgeruest,
# S-007: Discovery-/Thema-Modus, last30days-Aufruf, Persistenz ueber die
# Data-Access-Schicht, Quellen-Resilienz).
#
# Rein mechanisches Shell-Test-Artefakt (M2-Grundgeruest, kein App-Layer im
# profile.md-Sinn -- language: md). Erfuellt die Spec-Vertragszeile "Tests
# taggen @trace research-skill#AC<n>" (docs/specs/research-skill.md
# "Verträge").
#
# Covers (research-skill): AC1 (Zwei Modi discovery/thema, last30days-Aufruf
# ueber --emit=json/--save-dir/--store, last30days_client.sh
# resolve/invoke-Funktionen), AC6 (Themen-Anlage/-Wiederverwendung
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

echo
echo "Ergebnis: $pass OK, $fail FAIL"
[ "$fail" -eq 0 ]
