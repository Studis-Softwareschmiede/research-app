#!/usr/bin/env bash
# run_tests.sh — Self-Test fuer skills/research/ (/research-Skill-Grundgeruest,
# S-007: Discovery-/Thema-Modus, last30days-Aufruf, Persistenz ueber die
# Data-Access-Schicht, Quellen-Resilienz; S-011: Voraussetzungs-Ueberblick --
# Meilenstein-Liste je Thema + Schutzrechte-Klaerungspunkt; S-008:
# Bewertungsschicht-Anzeige -- SWOT-Zusammenfassung + Empfehlung +
# Businessplan-Template; S-013: Watchlist-Pass -- Watchlist-Kopplung +
# Nebenlaeufigkeits-Serialisierung).
#
# Rein mechanisches Shell-Test-Artefakt (M2/M3-Grundgeruest, kein App-Layer im
# profile.md-Sinn -- language: md). Erfuellt die Spec-Vertragszeile "Tests
# taggen @trace research-skill#AC<n>" (docs/specs/research-skill.md
# "Verträge") bzw. "@trace wiedervorlage-meilensteine#AC<n>"
# (docs/specs/wiedervorlage-meilensteine.md "Verträge").
#
# Covers (research-skill): AC1 (Zwei Modi discovery/thema, last30days-Aufruf
# ueber --emit=json/--save-dir/--store, last30days_client.sh
# resolve/invoke-Funktionen), AC2 (Bewertungsschicht-Anzeige, S-008:
# orchestrator.sh#print_swot_summary/print_recommendation/
# print_businessplan_template/render_evaluation -- rendern den bereits ueber
# db_scripts/lib/swot_item.sh#create_swot_item + db_scripts/lib/run.sh#create_run
# persistierten Stand eines Laufs; Businessplan-Template erscheint nur bei
# `recommendation=weiterverfolgen` (BR-107); main()-Subbefehl `evaluation
# <run-id>` ist der reachability-Pfad, AC2-Bewertung selbst -- claim_key-
# Vokabular/E2-Zurueckweisung, UNIQUE/CASCADE -- wird in
# db_scripts/tests/run_tests.sh getestet, hier NUR die Anzeige-Verdrahtung),
# AC4 (Empfehlungs-Kopplung, S-010: orchestrator.sh#derive_recommendation --
# deterministische Ableitung aus dem Meilenstein-Status (data-model.md §8,
# S-010-Praezisierung): >=1 offener externer Meilenstein -> parken, sonst ->
# weiterverfolgen (offene 'eigen'-Meilensteine blockieren allein nicht, da
# parallel geschaffen); 'verwerfen' bleibt der Ableitungsfunktion bewusst
# nicht zugaenglich (Hybrid, OF-09). print_recommendation_derivation rendert
# Empfehlung+Begruendung+'verwerfen'-Hinweis; main()-Subbefehl `recommend
# <topic-id>` ist der Reachability-Pfad, coder/R07),
# AC5 (Voraussetzungs-Ueberblick, S-011:
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
# Covers (wiedervorlage-meilensteine): AC2 (Watchlist-Kopplung, S-013:
# db_scripts/lib/milestone.sh#list_watchlist_candidates -- liefert nur
# offene EXTERNE Meilensteine mit watch_ref eines GEPARKTEN Themas;
# watchlist_client.sh#resolve_last30days_watchlist_cmd/check_watchlist_delta
# -- last30days-Watchlist-Delta-Abfrage per Array-Aufruf, JSON 1:1
# durchgereicht, kein eigenes Delta-Scoring; watchlist_pass.sh#
# fetch_watchlist_delta/report_watchlist_result: fetch_watchlist_delta haelt
# den Themen-Lock nur waehrend des externen Aufrufs (Minimal-Halte-Prinzip,
# Reviewer-Fund Iteration 1), report_watchlist_result interpretiert danach
# lock-frei den bereits eingesammelten last30days-eigenen status/new-Wert fuer
# den Report-Text), AC3 (Automatische Wiedervorlage, S-014:
# watchlist_pass.sh#_reactivate_topic_on_delta -- wird ein Delta erkannt
# (status=ok, new>0), setzt report_watchlist_result den geprueften externen
# Meilenstein auf 'erfuellt' (db_scripts/lib/milestone.sh#set_milestone_status)
# UND das Thema 'geparkt -> aktiv' (BR-020, db_scripts/lib/topic.sh#
# set_topic_status), geschuetzt durch eine erneut kurz gehaltene Themen-Sperre
# (BR-019); mutiert NUR, wenn das Thema noch 'geparkt' ist (Idempotenz-Guard);
# ist das Thema anderweitig gesperrt, wird die Reaktivierung fuer diesen
# Durchlauf ausgelassen, kein Crash), AC5 (verworfen bleibt verworfen,
# S-012/S-014: list_watchlist_candidates filtert strukturell auf
# t.status='geparkt' -- ein 'verworfen'es Thema kann NIE als Wiedervorlage-
# Kandidat erscheinen, unabhaengig vom Meilenstein-Stand; die OF-10-Kaskade
# 'geparkt -> verworfen setzt offene Meilensteine auf hinfaellig' ist bereits
# in db_scripts/tests/run_tests.sh#"research-datenmodell#AC5,OF-10" getestet
# -- selbe Codepfad, hier zusaetzlich als wiedervorlage-meilensteine#AC5
# getaggt), AC6 (Nebenlaeufigkeit, S-013: watchlist_pass.sh#run_watchlist_pass
# erwirbt/gibt ra_topic_lock (holder='watchlist', BR-019) je Themenwechsel
# frei; ein bereits durch 'research' gesperrtes Thema wird uebersprungen --
# kein Doppel-Lauf, kein Abbruch des Gesamt-Passes), E2 (last30days-Watchlist
# nicht erreichbar -> jeder betroffene Meilenstein wird als "manuell zu
# pruefen" gemeldet, kein Absturz des Passes). AC1/AC4 dieser Spec sind NICHT
# Gegenstand dieser Story (AC1 ist S-012/Done, AC4 ist S-015-Folgestory).
#
# last30days selbst ist in diesem Test-Environment nicht installiert (externe,
# API-/Netzwerk-abhaengige Installation) -- alle last30days-Aufrufe laufen
# gegen tests/fixtures/fake-last30days.sh (RA_LAST30DAYS_CMD-Override, exakt
# der vom Skill selbst vorgesehene Erweiterungspunkt, kein Test-Sonderpfad im
# Produktivcode). Die last30days-Watchlist-CLI (separates Skript im
# last30days-Projekt) laeuft analog gegen
# tests/fixtures/fake-last30days-watchlist.sh (RA_LAST30DAYS_WATCHLIST_CMD-
# Override).
#
# Aufruf: skills/research/tests/run_tests.sh
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESEARCH_DIR="$(dirname "$TEST_DIR")"
REPO_ROOT="$(cd "$RESEARCH_DIR/../.." && pwd)"
FAKE_L30D="$TEST_DIR/fixtures/fake-last30days.sh"
FAKE_L30D_WATCHLIST="$TEST_DIR/fixtures/fake-last30days-watchlist.sh"

# shellcheck source=../scripts/lib/last30days_client.sh
source "$RESEARCH_DIR/scripts/lib/last30days_client.sh"
# shellcheck source=../scripts/lib/watchlist_client.sh
source "$RESEARCH_DIR/scripts/lib/watchlist_client.sh"
# shellcheck source=../../../db_scripts/lib/apply_migrations.sh
source "$REPO_ROOT/db_scripts/lib/apply_migrations.sh"
# shellcheck source=../../../db_scripts/lib/topic.sh
source "$REPO_ROOT/db_scripts/lib/topic.sh"
# shellcheck source=../../../db_scripts/lib/topic_lock.sh
source "$REPO_ROOT/db_scripts/lib/topic_lock.sh"
# shellcheck source=../../../db_scripts/lib/milestone.sh
source "$REPO_ROOT/db_scripts/lib/milestone.sh"
# shellcheck source=../../../db_scripts/lib/run.sh
source "$REPO_ROOT/db_scripts/lib/run.sh"
# shellcheck source=../../../db_scripts/lib/swot_item.sh
source "$REPO_ROOT/db_scripts/lib/swot_item.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  OK:   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# orchestrator.sh/watchlist_pass.sh sourcen (main()/watchlist_pass_main()
# feuern wegen des BASH_SOURCE-Guards jeweils nicht; die beiden Funktionen
# tragen bewusst unterschiedliche Namen, siehe watchlist_pass.sh-Header --
# Namenskollision-Fund S-013 Iteration 1).
# shellcheck source=../scripts/orchestrator.sh
source "$RESEARCH_DIR/scripts/orchestrator.sh"
# shellcheck source=../scripts/watchlist_pass.sh
source "$RESEARCH_DIR/scripts/watchlist_pass.sh"

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

echo "== @trace research-skill#AC4,BR-013 -- derive_recommendation: keine Meilensteine -> weiterverfolgen =="
DB_AC4="$(new_migrated_db "$TMP/ac4-recommend.sqlite")"
TOPIC_AC4_NONE="$(create_topic "$DB_AC4" "Thema ohne Meilensteine (AC4)" 2>/dev/null)"
REC_NONE="$(derive_recommendation "$DB_AC4" "$TOPIC_AC4_NONE" 2>"$TMP/ac4-none.err")"
if [ "${REC_NONE%%|*}" = "weiterverfolgen" ] && [ -n "${REC_NONE#*|}" ]; then
  ok "ohne Meilensteine leitet derive_recommendation 'weiterverfolgen' samt Begruendung ab (data-model.md Sec.8)"
else
  bad "erwartet 'weiterverfolgen|<Begruendung>', war [$REC_NONE]: $(cat "$TMP/ac4-none.err")"
fi

echo "== @trace research-skill#AC4,BR-013 -- derive_recommendation: nur 'eigen'-Meilensteine (offen) -> weiterverfolgen (S-010-Praezisierung data-model.md Sec.8) =="
TOPIC_AC4_EIGEN="$(create_topic "$DB_AC4" "Thema nur eigen offen (AC4)" 2>/dev/null)"
create_milestone "$DB_AC4" "$TOPIC_AC4_EIGEN" "Eigene Aufgabe offen" "eigen" > /dev/null
REC_EIGEN="$(derive_recommendation "$DB_AC4" "$TOPIC_AC4_EIGEN" 2>"$TMP/ac4-eigen.err")"
if [ "${REC_EIGEN%%|*}" = "weiterverfolgen" ]; then
  ok "ein offener 'eigen'-Meilenstein blockiert die Ableitung allein NICHT -- 'eigen' wird parallel geschaffen, blockiert nicht (§8-Praezisierung)"
else
  bad "erwartet 'weiterverfolgen' trotz offenem eigen-Meilenstein, war [$REC_EIGEN]: $(cat "$TMP/ac4-eigen.err")"
fi

echo "== @trace research-skill#AC4,BR-013,BR-015 -- derive_recommendation: >=1 offener externer Meilenstein -> parken =="
TOPIC_AC4_EXT="$(create_topic "$DB_AC4" "Thema mit offenem externem MS (AC4)" 2>/dev/null)"
create_milestone "$DB_AC4" "$TOPIC_AC4_EXT" "Watchlist-Zusage offen" "extern" "watchlist-item-ac4" > /dev/null
REC_EXT="$(derive_recommendation "$DB_AC4" "$TOPIC_AC4_EXT" 2>"$TMP/ac4-ext.err")"
if [ "${REC_EXT%%|*}" = "parken" ] && echo "$REC_EXT" | grep -q "1 offene"; then
  ok "ein offener externer Meilenstein leitet 'parken' samt Begruendung (Anzahl) ab"
else
  bad "erwartet 'parken|1 offene(r)...', war [$REC_EXT]: $(cat "$TMP/ac4-ext.err")"
fi

echo "== @trace research-skill#AC4,BR-013 -- derive_recommendation: externer Meilenstein erfuellt (nicht offen) -> weiterverfolgen =="
TOPIC_AC4_FULFILLED="$(create_topic "$DB_AC4" "Thema mit erfuelltem externem MS (AC4)" 2>/dev/null)"
MS_AC4_FULFILLED="$(create_milestone "$DB_AC4" "$TOPIC_AC4_FULFILLED" "Watchlist-Zusage erfuellt" "extern" "watchlist-item-ac4-b")"
set_milestone_status "$DB_AC4" "$MS_AC4_FULFILLED" "erfuellt" > /dev/null
REC_FULFILLED="$(derive_recommendation "$DB_AC4" "$TOPIC_AC4_FULFILLED" 2>"$TMP/ac4-fulfilled.err")"
if [ "${REC_FULFILLED%%|*}" = "weiterverfolgen" ]; then
  ok "ein erfuellter (nicht offener) externer Meilenstein blockiert die Ableitung nicht -> weiterverfolgen"
else
  bad "erwartet 'weiterverfolgen', war [$REC_FULFILLED]: $(cat "$TMP/ac4-fulfilled.err")"
fi

echo "== @trace research-skill#AC4,security/R03 -- derive_recommendation: ungueltige Themen-ID wird vor SQL-Interpolation abgelehnt =="
set +e
REC_INJECT="$(derive_recommendation "$DB_AC4" "x'; DROP TABLE ra_milestone; --" 2>"$TMP/ac4-inject.err")"
REC_INJECT_RC=$?
set -e
STILL_THERE_AC4="$(sqlite3 "$DB_AC4" "SELECT name FROM sqlite_master WHERE type='table' AND name='ra_milestone';")"
if [ "$REC_INJECT_RC" -ne 0 ] && [ -z "$REC_INJECT" ] && [ "$STILL_THERE_AC4" = "ra_milestone" ]; then
  ok "manipulierte Themen-ID wird per Format-Check FATAL abgelehnt (delegiert an list_milestones, security/R03)"
else
  bad "erwartete Ablehnung, rc=$REC_INJECT_RC out='$REC_INJECT' table='$STILL_THERE_AC4': $(cat "$TMP/ac4-inject.err")"
fi

echo "== @trace research-skill#AC4 -- print_recommendation_derivation rendert Empfehlung + Begruendung + 'verwerfen'-Hinweis =="
RENDER_EXT="$(print_recommendation_derivation "$DB_AC4" "$TOPIC_AC4_EXT")"
if echo "$RENDER_EXT" | grep -q "Empfehlung (Default): parken" \
  && echo "$RENDER_EXT" | grep -q "^Begruendung:" \
  && echo "$RENDER_EXT" | grep -qi "verwerfen.*keine automatisch ableitbare Empfehlung"; then
  ok "print_recommendation_derivation zeigt Default-Empfehlung, Begruendung und den 'verwerfen ist nicht automatisch ableitbar'-Hinweis (Hybrid, OF-09)"
else
  bad "unerwartete Ausgabe: $RENDER_EXT"
fi

echo "== @trace research-skill#AC4 -- main('recommend', <topic-id>) ist ueber die CLI erreichbar (coder/R07, Mount-Reachability) =="
RECOMMEND_CLI_OUT="$(RA_DB_PATH="$DB_AC4" main recommend "$TOPIC_AC4_EXT")"
if echo "$RECOMMEND_CLI_OUT" | grep -q "Empfehlung (Default): parken"; then
  ok "main() dispatcht den 'recommend'-Subbefehl korrekt an print_recommendation_derivation"
else
  bad "unerwartete CLI-Ausgabe: $RECOMMEND_CLI_OUT"
fi

echo "== @trace research-skill#AC2 -- print_swot_summary: leer + gruppiert nach Kategorie =="
DB9="$(new_migrated_db "$TMP/ac2-swot.sqlite")"
TOPIC9="$(create_topic "$DB9" "AC2-Thema")"
HASH9_EMPTY="$(compute_result_hash "parken" "" "")"
RUN9_EMPTY="$(create_run "$DB9" "$TOPIC9" "recherche" "$HASH9_EMPTY" "parken" 1 0)"
RUN9_EMPTY_ID="${RUN9_EMPTY%%|*}"
SWOT_EMPTY_OUT="$(print_swot_summary "$DB9" "$RUN9_EMPTY_ID")"
if echo "$SWOT_EMPTY_OUT" | grep -qi "Noch keine SWOT-Items"; then
  ok "print_swot_summary zeigt ohne SWOT-Items einen klaren Leer-Hinweis"
else
  bad "unerwartete Ausgabe ohne SWOT-Items: $SWOT_EMPTY_OUT"
fi

create_swot_item "$DB9" "$RUN9_EMPTY_ID" "strength" "marktgroesse" "last30days" > /dev/null
create_swot_item "$DB9" "$RUN9_EMPTY_ID" "threat" "wettbewerbsintensitaet" "last30days" > /dev/null
create_swot_item "$DB9" "$RUN9_EMPTY_ID" "threat" "regulierung" "deep_research" > /dev/null
SWOT_FULL_OUT="$(print_swot_summary "$DB9" "$RUN9_EMPTY_ID")"
if echo "$SWOT_FULL_OUT" | grep -A1 "^Staerken:" | grep -q "marktgroesse" \
  && echo "$SWOT_FULL_OUT" | grep -A1 "^Schwaechen:" | grep -q "(keine)" \
  && echo "$SWOT_FULL_OUT" | grep -A2 "^Risiken:" | grep -q "regulierung" \
  && echo "$SWOT_FULL_OUT" | grep -A2 "^Risiken:" | grep -q "wettbewerbsintensitaet"; then
  ok "print_swot_summary gruppiert persistierte SWOT-Items nach Kategorie, leere Kategorien zeigen '(keine)'"
else
  bad "unerwartete Ausgabe mit SWOT-Items: $SWOT_FULL_OUT"
fi

echo "== @trace research-skill#AC2,BR-107 -- print_recommendation: Businessplan-Template NUR bei 'weiterverfolgen' =="
HASH9_WV="$(compute_result_hash "weiterverfolgen" "" "")"
RUN9_WV="$(create_run "$DB9" "$TOPIC9" "recherche" "$HASH9_WV" "weiterverfolgen" 1 0)"
RUN9_WV_ID="${RUN9_WV%%|*}"
REC_WV_OUT="$(print_recommendation "$DB9" "$RUN9_WV_ID")"
if echo "$REC_WV_OUT" | grep -q "Empfehlung: weiterverfolgen" \
  && echo "$REC_WV_OUT" | grep -q "Businessplan-Template"; then
  ok "recommendation='weiterverfolgen': Businessplan-Template wird ausgegeben (BR-107)"
else
  bad "erwartete Empfehlung + Businessplan-Template, bekam: $REC_WV_OUT"
fi

HASH9_PARK="$(compute_result_hash "parken" "" "" 2>/dev/null)"
RUN9_PARK="$(create_run "$DB9" "$TOPIC9" "recherche" "$HASH9_PARK" "parken" 0 1)"
RUN9_PARK_ID="${RUN9_PARK%%|*}"
REC_PARK_OUT="$(print_recommendation "$DB9" "$RUN9_PARK_ID")"
if echo "$REC_PARK_OUT" | grep -q "Empfehlung: parken (Momentum-Signal" \
  && ! echo "$REC_PARK_OUT" | grep -q "Businessplan-Template"; then
  ok "recommendation='parken' + momentum_only=1: Momentum-Hinweis, KEIN Businessplan-Template (coder/R01, BR-107 nur bei weiterverfolgen)"
else
  bad "erwartete Momentum-Hinweis ohne Businessplan-Template, bekam: $REC_PARK_OUT"
fi

echo "== @trace research-skill#AC2 -- render_evaluation/main('evaluation'): SWOT + Empfehlung als ein Block =="
create_swot_item "$DB9" "$RUN9_WV_ID" "opportunity" "kundennachfrage" "last30days" > /dev/null
EVAL_OUT="$(RA_DB_PATH="$DB9" main evaluation "$RUN9_WV_ID")"
if echo "$EVAL_OUT" | grep -q "Bewertungsschicht (research-skill#AC2)" \
  && echo "$EVAL_OUT" | grep -q "SWOT (strukturiert, BR-012)" \
  && echo "$EVAL_OUT" | grep -q "kundennachfrage" \
  && echo "$EVAL_OUT" | grep -q "Empfehlung: weiterverfolgen" \
  && echo "$EVAL_OUT" | grep -q "Businessplan-Template"; then
  ok "main('evaluation', <run-id>) rendert SWOT-Zusammenfassung + Empfehlung + Businessplan-Template ueber render_evaluation"
else
  bad "unerwartete evaluation-Ausgabe: $EVAL_OUT"
fi

echo "== @trace research-skill#AC2,security/R03 -- render_evaluation lehnt eine ungueltige run-id ab =="
set +e
BAD_EVAL_OUT="$(render_evaluation "$DB9" "abc; DROP TABLE ra_run;--" 2> "$TMP/eval-bad.err")"
BAD_EVAL_RC=$?
set -e
if [ "$BAD_EVAL_RC" -ne 0 ] && [ -z "$BAD_EVAL_OUT" ]; then
  ok "render_evaluation weist eine nicht-numerische run-id ab, bevor irgendeine Data-Access-Funktion sie interpoliert"
else
  bad "erwartete Ablehnung, rc=$BAD_EVAL_RC out='$BAD_EVAL_OUT'"
fi


echo "== @trace wiedervorlage-meilensteine#AC2 -- resolve_last30days_watchlist_cmd: nicht installiert bricht klar ab (E2) =="
ERR_WL1="$TMP/resolve_wl1.err"
if RA_LAST30DAYS_WATCHLIST_CMD="ra-watchlist-definitiv-nicht-installiert-$$" resolve_last30days_watchlist_cmd > /dev/null 2> "$ERR_WL1"; then
  bad "resolve_last30days_watchlist_cmd haette fuer ein nicht existentes Kommando fehlschlagen muessen"
else
  if grep -q "FATAL.*nicht installiert" "$ERR_WL1" && grep -q "E2" "$ERR_WL1"; then
    ok "nicht aufloesbares Watchlist-Kommando bricht mit FATAL + Handlungsanweisung ab (E2)"
  else
    bad "FATAL-Meldung fehlt/unklar: $(cat "$ERR_WL1")"
  fi
fi

echo "== @trace wiedervorlage-meilensteine#AC2 -- resolve_last30days_watchlist_cmd: Override aufloesbar =="
GOT_WL="$(RA_LAST30DAYS_WATCHLIST_CMD="$FAKE_L30D_WATCHLIST" resolve_last30days_watchlist_cmd)"
if [ "$GOT_WL" = "$FAKE_L30D_WATCHLIST" ]; then
  ok "RA_LAST30DAYS_WATCHLIST_CMD-Override wird aufgeloest, wenn ausfuehrbar"
else
  bad "erwartet '$FAKE_L30D_WATCHLIST', war '$GOT_WL'"
fi

echo "== @trace wiedervorlage-meilensteine#AC2 -- resolve_last30days_watchlist_cmd: OHNE Override wird watchlist.py an einem realen last30days-Installationsort gefunden und ueber LAST30DAYS_PYTHON ausgefuehrt (Reviewer-Fund Iteration 1: realistische Default-Aufloesung statt PATH-Fiktion) =="
FAKE_HOME_AC2="$TMP/fake-home-ac2"
mkdir -p "$FAKE_HOME_AC2/.claude/skills/last30days/scripts"
FAKE_WL_SCRIPT="$FAKE_HOME_AC2/.claude/skills/last30days/scripts/watchlist.py"
printf '#!/usr/bin/env python3\n# Test-Double -- wird im Test nie als echtes Python ausgefuehrt (LAST30DAYS_PYTHON zeigt auf den Fake-Interpreter-Stub).\n' > "$FAKE_WL_SCRIPT"

RESOLVE_AUTO_ERR="$TMP/wl_auto_resolve.err"
GOT_AUTO_CMD="$(unset RA_LAST30DAYS_WATCHLIST_CMD; HOME="$FAKE_HOME_AC2" LAST30DAYS_PYTHON="$FAKE_L30D_WATCHLIST" resolve_last30days_watchlist_cmd 2>"$RESOLVE_AUTO_ERR")"
RESOLVE_AUTO_RC=$?
if [ "$RESOLVE_AUTO_RC" -eq 0 ] && [ -n "$GOT_AUTO_CMD" ] && [ -x "$GOT_AUTO_CMD" ]; then
  WL_AUTO_ARGS="$TMP/wl_auto.args"
  FAKE_L30D_WATCHLIST_ARGS_FILE="$WL_AUTO_ARGS" "$GOT_AUTO_CMD" delta "watchlist-item-auto" > /dev/null
  if grep -qF "$FAKE_WL_SCRIPT" "$WL_AUTO_ARGS" && grep -qx "delta" "$WL_AUTO_ARGS" && grep -qx "watchlist-item-auto" "$WL_AUTO_ARGS"; then
    ok "ohne RA_LAST30DAYS_WATCHLIST_CMD-Override wird watchlist.py automatisch unter ~/.claude/skills/last30days gefunden und via LAST30DAYS_PYTHON als '<python> <script> delta <watch-ref>' ausgefuehrt"
  else
    bad "der aufgeloeste Shim ruft 'LAST30DAYS_PYTHON <script> delta <watch-ref>' nicht korrekt auf: $(cat "$WL_AUTO_ARGS" 2>/dev/null)"
  fi
else
  bad "resolve_last30days_watchlist_cmd (Auto-Discovery) schlug unerwartet fehl: rc=$RESOLVE_AUTO_RC cmd='$GOT_AUTO_CMD' err=$(cat "$RESOLVE_AUTO_ERR")"
fi

echo "== @trace wiedervorlage-meilensteine#AC2,E2 -- resolve_last30days_watchlist_cmd: kein Installationsort gefunden -> FATAL (E2), kein Crash =="
FAKE_HOME_NONE="$TMP/fake-home-none"
mkdir -p "$FAKE_HOME_NONE"
ERR_NOTFOUND="$TMP/wl_notfound.err"
if (unset RA_LAST30DAYS_WATCHLIST_CMD; HOME="$FAKE_HOME_NONE" resolve_last30days_watchlist_cmd) > /dev/null 2> "$ERR_NOTFOUND"; then
  bad "resolve_last30days_watchlist_cmd haette ohne jede Installation fehlschlagen muessen"
else
  if grep -qi "FATAL" "$ERR_NOTFOUND" && grep -q "E2" "$ERR_NOTFOUND"; then
    ok "kein last30days-Installationsort gefunden -> FATAL mit Handlungsanweisung (E2), kein Crash"
  else
    bad "FATAL-Meldung fehlt/unklar: $(cat "$ERR_NOTFOUND")"
  fi
fi

echo "== @trace wiedervorlage-meilensteine#AC2 -- check_watchlist_delta ruft 'delta <watch-ref>' auf und reicht die last30days-JSON-Antwort unveraendert durch =="
WL_ARGS_FILE="$TMP/wl_delta.args"
WL_JSON_OUT="$TMP/wl_delta.stdout"
FAKE_L30D_WATCHLIST_JSON_FILE="$TEST_DIR/fixtures/watchlist_delta_new.json" FAKE_L30D_WATCHLIST_ARGS_FILE="$WL_ARGS_FILE" \
  check_watchlist_delta "$FAKE_L30D_WATCHLIST" "watchlist-item-1" > "$WL_JSON_OUT"
if grep -qx "delta" "$WL_ARGS_FILE" && grep -qx "watchlist-item-1" "$WL_ARGS_FILE"; then
  ok "check_watchlist_delta ruft 'delta <watch-ref>' auf (Array-Aufruf, AC2)"
else
  bad "unerwartete Argumente: $(cat "$WL_ARGS_FILE" 2>/dev/null)"
fi
if diff -q "$TEST_DIR/fixtures/watchlist_delta_new.json" "$WL_JSON_OUT" > /dev/null 2>&1; then
  ok "last30days-Watchlist-JSON-Antwort landet unveraendert auf stdout (kein eigenes Delta-Scoring, Nicht-Ziel)"
else
  bad "stdout-JSON weicht von der Fixture ab"
fi

echo "== @trace wiedervorlage-meilensteine#AC2,E2 -- check_watchlist_delta: last30days-Watchlist-Fehler-Exitcode wird als FATAL gemeldet =="
ERR_WL2="$TMP/wl_delta_fail.err"
if FAKE_L30D_WATCHLIST_EXIT_CODE=2 FAKE_L30D_WATCHLIST_STDERR="simulierter last30days-Watchlist-Fehler" \
  check_watchlist_delta "$FAKE_L30D_WATCHLIST" "watchlist-item-1" > /dev/null 2> "$ERR_WL2"; then
  bad "check_watchlist_delta haette bei Exitcode 2 fehlschlagen muessen"
else
  if grep -q "FATAL" "$ERR_WL2" && grep -q "E2" "$ERR_WL2" && grep -q "simulierter last30days-Watchlist-Fehler" "$ERR_WL2"; then
    ok "last30days-Watchlist-Fehler-Exitcode fuehrt zu FATAL inkl. last30days-eigener Fehlermeldung (E2)"
  else
    bad "FATAL-Meldung unvollstaendig: $(cat "$ERR_WL2")"
  fi
fi

echo "== @trace wiedervorlage-meilensteine#AC2,E2 -- check_watchlist_delta: last30days-Watchlist meldet Fehler als JSON auf STDOUT (Exit 1, stderr leer) -- Meldung nimmt stdout mit auf (Reviewer-Fund Iteration 1: Diagnose-Verlust) =="
ERR_WL_STDOUT_ERR="$TMP/wl_delta_stdout_error.err"
if FAKE_L30D_WATCHLIST_EXIT_CODE=1 FAKE_L30D_WATCHLIST_JSON_FILE="$TEST_DIR/fixtures/watchlist_delta_error.json" \
  check_watchlist_delta "$FAKE_L30D_WATCHLIST" "watchlist-item-missing" > /dev/null 2> "$ERR_WL_STDOUT_ERR"; then
  bad "check_watchlist_delta haette bei Exitcode 1 fehlschlagen muessen"
else
  if grep -q "FATAL" "$ERR_WL_STDOUT_ERR" && grep -q "E2" "$ERR_WL_STDOUT_ERR" && grep -q "Topic not found" "$ERR_WL_STDOUT_ERR"; then
    ok "last30days-Watchlist-Fehler als JSON auf stdout (Exit 1, stderr leer) landet trotzdem in der FATAL-Meldung -- kein Diagnose-Verlust"
  else
    bad "FATAL-Meldung verliert die stdout-Fehlermeldung: $(cat "$ERR_WL_STDOUT_ERR")"
  fi
fi

echo "== @trace wiedervorlage-meilensteine#AC2,E2 -- check_watchlist_delta: ungueltige JSON-Antwort wird als FATAL gemeldet =="
ERR_WL3="$TMP/wl_delta_badjson.err"
BAD_JSON_FILE="$TMP/bad.json"
printf 'kein-json' > "$BAD_JSON_FILE"
if FAKE_L30D_WATCHLIST_JSON_FILE="$BAD_JSON_FILE" \
  check_watchlist_delta "$FAKE_L30D_WATCHLIST" "watchlist-item-1" > /dev/null 2> "$ERR_WL3"; then
  bad "check_watchlist_delta haette bei ungueltigem JSON fehlschlagen muessen"
else
  if grep -q "FATAL" "$ERR_WL3" && grep -q "E2" "$ERR_WL3"; then
    ok "ungueltige last30days-Watchlist-JSON-Antwort fuehrt zu FATAL (E2)"
  else
    bad "FATAL-Meldung unklar: $(cat "$ERR_WL3")"
  fi
fi

echo "== @trace wiedervorlage-meilensteine#AC2 -- list_watchlist_candidates: nur offene EXTERNE Meilensteine mit watch_ref eines GEPARKTEN Themas =="
DB_AC2="$(new_migrated_db "$TMP/ac2-candidates.sqlite")"
TOPIC_P="$(create_topic "$DB_AC2" "Geparktes Thema AC2" 2>/dev/null)"
MS_OPEN="$(create_milestone "$DB_AC2" "$TOPIC_P" "Offener externer Meilenstein" "extern" "watchlist-item-open" 2>/dev/null)"
create_milestone "$DB_AC2" "$TOPIC_P" "Eigener Meilenstein" "eigen" > /dev/null 2>&1
MS_DONE="$(create_milestone "$DB_AC2" "$TOPIC_P" "Erfuellter externer Meilenstein" "extern" "watchlist-item-done" 2>/dev/null)"
set_milestone_status "$DB_AC2" "$MS_DONE" "erfuellt" > /dev/null
set_topic_status "$DB_AC2" "$TOPIC_P" "geparkt" > /dev/null

TOPIC_A="$(create_topic "$DB_AC2" "Aktives Thema AC2" 2>/dev/null)"
create_milestone "$DB_AC2" "$TOPIC_A" "Externer Meilenstein auf aktivem Thema" "extern" "watchlist-item-active" > /dev/null 2>&1

CANDIDATES="$(list_watchlist_candidates "$DB_AC2")"
US=$'\x1f'
EXPECTED_CAND="$(printf '%s%s%s%swatchlist-item-open' "$TOPIC_P" "$US" "$MS_OPEN" "$US")"
if [ "$CANDIDATES" = "$EXPECTED_CAND" ]; then
  ok "list_watchlist_candidates liefert GENAU den offenen externen Meilenstein des geparkten Themas -- eigen/erfuellt/aktives-Thema werden ausgeschlossen (AC2)"
else
  bad "erwartet [$EXPECTED_CAND], war [$CANDIDATES]"
fi

echo "== @trace wiedervorlage-meilensteine#AC2,security/R03 -- list_watchlist_candidates: ungueltige Themen-ID wird vor SQL-Interpolation abgelehnt =="
ERR_CAND="$TMP/cand-inject.err"
set +e
INJECT_CAND_OUT="$(list_watchlist_candidates "$DB_AC2" "x'; DROP TABLE ra_milestone; --" 2> "$ERR_CAND")"
INJECT_CAND_RC=$?
set -e
STILL_THERE_CAND="$(sqlite3 "$DB_AC2" "SELECT name FROM sqlite_master WHERE type='table' AND name='ra_milestone';")"
if [ "$INJECT_CAND_RC" -ne 0 ] && [ -z "$INJECT_CAND_OUT" ] && [ "$STILL_THERE_CAND" = "ra_milestone" ] && grep -qi "FATAL" "$ERR_CAND"; then
  ok "manipulierte Themen-ID wird per Format-Check FATAL abgelehnt, ra_milestone bleibt unangetastet (security/R03)"
else
  bad "erwartete Ablehnung, rc=$INJECT_CAND_RC out='$INJECT_CAND_OUT' table='$STILL_THERE_CAND': $(cat "$ERR_CAND")"
fi

echo "== @trace wiedervorlage-meilensteine#AC2,E2 -- report_watchlist_result: last30days-Watchlist nicht verfuegbar (leerer cmd) meldet 'manuell zu pruefen', keine DB-Mutation =="
STATUS_BEFORE="$(sqlite3 "$DB_AC2" "SELECT status FROM ra_milestone WHERE id = $MS_OPEN;")"
REPORT_NOCMD="$(report_watchlist_result "$DB_AC2" "$TOPIC_P" "$MS_OPEN" "watchlist-item-open" "" "127" "/dev/null" "/dev/null")"
STATUS_AFTER="$(sqlite3 "$DB_AC2" "SELECT status FROM ra_milestone WHERE id = $MS_OPEN;")"
if echo "$REPORT_NOCMD" | grep -qi "manuell zu pruefen" && echo "$REPORT_NOCMD" | grep -q "E2" && [ "$STATUS_BEFORE" = "$STATUS_AFTER" ]; then
  ok "ohne aufloesbares last30days-Watchlist-Kommando: Klartext 'manuell zu pruefen' (E2), ra_milestone.status bleibt unveraendert (E2 loest AC3-Reaktivierung nie aus -- kein Delta erkannt)"
else
  bad "unerwartetes Ergebnis: report='$REPORT_NOCMD' status_before=$STATUS_BEFORE status_after=$STATUS_AFTER"
fi

echo "== @trace wiedervorlage-meilensteine#AC2,AC3,BR-020 -- fetch_watchlist_delta+report_watchlist_result: last30days meldet Delta (new>0) -> 'Delta erkannt', Meilenstein 'erfuellt', Thema 'geparkt -> aktiv' wiedervorgelegt =="
FETCH_NEW_LINE="$(FAKE_L30D_WATCHLIST_JSON_FILE="$TEST_DIR/fixtures/watchlist_delta_new.json" \
  fetch_watchlist_delta "$FAKE_L30D_WATCHLIST" "watchlist-item-open")"
IFS=$'\x1f' read -r FETCH_NEW_RC FETCH_NEW_JSON FETCH_NEW_ERR <<< "$FETCH_NEW_LINE"
REPORT_NEW="$(report_watchlist_result "$DB_AC2" "$TOPIC_P" "$MS_OPEN" "watchlist-item-open" "$FAKE_L30D_WATCHLIST" "$FETCH_NEW_RC" "$FETCH_NEW_JSON" "$FETCH_NEW_ERR")"
rm -f "$FETCH_NEW_JSON" "$FETCH_NEW_ERR" 2>/dev/null || true
MS_OPEN_STATUS_AFTER_DELTA="$(sqlite3 "$DB_AC2" "SELECT status FROM ra_milestone WHERE id = $MS_OPEN;")"
TOPIC_P_STATUS_AFTER_DELTA="$(sqlite3 "$DB_AC2" "SELECT status FROM ra_topic WHERE id = '$TOPIC_P';")"
if echo "$REPORT_NEW" | grep -qi "Delta erkannt" && echo "$REPORT_NEW" | grep -q "3 neue" \
  && echo "$REPORT_NEW" | grep -qi "wiedervorgelegt" \
  && [ "$MS_OPEN_STATUS_AFTER_DELTA" = "erfuellt" ] && [ "$TOPIC_P_STATUS_AFTER_DELTA" = "aktiv" ]; then
  ok "last30days-Signal 'status=ok,new=3' wird als 'Delta erkannt (3 ...)' reportiert (AC2, last30days-Signal 1:1 durchgereicht) UND loest die automatische Wiedervorlage aus: Meilenstein 'erfuellt', Thema 'geparkt -> aktiv' (AC3/BR-020)"
else
  bad "unerwarteter Report/Zustand: report='$REPORT_NEW' ms_status=$MS_OPEN_STATUS_AFTER_DELTA topic_status=$TOPIC_P_STATUS_AFTER_DELTA"
fi

echo "== @trace wiedervorlage-meilensteine#AC2 -- fetch_watchlist_delta+report_watchlist_result: last30days meldet kein Delta (new=0) -> 'kein Delta' =="
FETCH_NONE_LINE="$(FAKE_L30D_WATCHLIST_JSON_FILE="$TEST_DIR/fixtures/watchlist_delta_none.json" \
  fetch_watchlist_delta "$FAKE_L30D_WATCHLIST" "watchlist-item-open")"
IFS=$'\x1f' read -r FETCH_NONE_RC FETCH_NONE_JSON FETCH_NONE_ERR <<< "$FETCH_NONE_LINE"
REPORT_NONE="$(report_watchlist_result "$DB_AC2" "$TOPIC_P" "$MS_OPEN" "watchlist-item-open" "$FAKE_L30D_WATCHLIST" "$FETCH_NONE_RC" "$FETCH_NONE_JSON" "$FETCH_NONE_ERR")"
rm -f "$FETCH_NONE_JSON" "$FETCH_NONE_ERR" 2>/dev/null || true
if echo "$REPORT_NONE" | grep -qi "kein Delta"; then
  ok "last30days-Signal 'status=ok,new=0' wird als 'kein Delta' reportiert (AC2)"
else
  bad "unerwarteter Report: $REPORT_NONE"
fi

echo "== @trace wiedervorlage-meilensteine#AC2 -- fetch_watchlist_delta+report_watchlist_result: last30days meldet 'insufficient_history' -> keine Vergleichs-Historie =="
FETCH_HIST_LINE="$(FAKE_L30D_WATCHLIST_JSON_FILE="$TEST_DIR/fixtures/watchlist_delta_insufficient_history.json" \
  fetch_watchlist_delta "$FAKE_L30D_WATCHLIST" "watchlist-item-open")"
IFS=$'\x1f' read -r FETCH_HIST_RC FETCH_HIST_JSON FETCH_HIST_ERR <<< "$FETCH_HIST_LINE"
REPORT_HIST="$(report_watchlist_result "$DB_AC2" "$TOPIC_P" "$MS_OPEN" "watchlist-item-open" "$FAKE_L30D_WATCHLIST" "$FETCH_HIST_RC" "$FETCH_HIST_JSON" "$FETCH_HIST_ERR")"
rm -f "$FETCH_HIST_JSON" "$FETCH_HIST_ERR" 2>/dev/null || true
if echo "$REPORT_HIST" | grep -qi "keine Vergleichs-Historie"; then
  ok "last30days-Signal 'status=insufficient_history' wird als 'keine Vergleichs-Historie' reportiert (AC2, kein eigenes Delta-Scoring)"
else
  bad "unerwarteter Report: $REPORT_HIST"
fi

echo "== @trace wiedervorlage-meilensteine#AC2,E2 -- fetch_watchlist_delta+report_watchlist_result: last30days-Watchlist-Aufruf schlaegt fehl -> 'manuell zu pruefen' (kein Crash) =="
FETCH_FAIL_LINE="$(FAKE_L30D_WATCHLIST_EXIT_CODE=1 FAKE_L30D_WATCHLIST_STDERR="Netzwerkfehler" \
  fetch_watchlist_delta "$FAKE_L30D_WATCHLIST" "watchlist-item-open")"
IFS=$'\x1f' read -r FETCH_FAIL_RC FETCH_FAIL_JSON FETCH_FAIL_ERR <<< "$FETCH_FAIL_LINE"
REPORT_FAIL="$(report_watchlist_result "$DB_AC2" "$TOPIC_P" "$MS_OPEN" "watchlist-item-open" "$FAKE_L30D_WATCHLIST" "$FETCH_FAIL_RC" "$FETCH_FAIL_JSON" "$FETCH_FAIL_ERR")"
rm -f "$FETCH_FAIL_JSON" "$FETCH_FAIL_ERR" 2>/dev/null || true
if echo "$REPORT_FAIL" | grep -qi "manuell zu pruefen" && echo "$REPORT_FAIL" | grep -q "E2"; then
  ok "fehlschlagender last30days-Watchlist-Aufruf wird als 'manuell zu pruefen' reportiert, kein Absturz (E2)"
else
  bad "unerwarteter Report: $REPORT_FAIL"
fi

echo "== @trace wiedervorlage-meilensteine#AC6 -- run_watchlist_pass: ohne Kandidaten meldet Klartext, kein Fehler =="
DB_AC6_EMPTY="$(new_migrated_db "$TMP/ac6-empty.sqlite")"
OUT_AC6_EMPTY="$(RA_LAST30DAYS_WATCHLIST_CMD="$FAKE_L30D_WATCHLIST" run_watchlist_pass "$DB_AC6_EMPTY" 2>/dev/null)"
if echo "$OUT_AC6_EMPTY" | grep -qi "Keine offenen externen Meilensteine"; then
  ok "ohne pruefbare Kandidaten meldet run_watchlist_pass Klartext, kein Fehler"
else
  bad "unerwartete Ausgabe: $OUT_AC6_EMPTY"
fi

echo "== @trace wiedervorlage-meilensteine#AC6,BR-019 -- run_watchlist_pass: bereits durch 'research' gesperrtes Thema wird uebersprungen, anderes Thema wird geprueft, Sperre danach frei =="
DB_AC6="$(new_migrated_db "$TMP/ac6-pass.sqlite")"

TOPIC_X="$(create_topic "$DB_AC6" "Thema X (in Bearbeitung)" 2>/dev/null)"
MS_X="$(create_milestone "$DB_AC6" "$TOPIC_X" "Externer Meilenstein X" "extern" "watchlist-item-x" 2>/dev/null)"
set_topic_status "$DB_AC6" "$TOPIC_X" "geparkt" > /dev/null
acquire_topic_lock "$DB_AC6" "$TOPIC_X" "research" 1800 > /dev/null

TOPIC_Y="$(create_topic "$DB_AC6" "Thema Y (frei)" 2>/dev/null)"
MS_Y="$(create_milestone "$DB_AC6" "$TOPIC_Y" "Externer Meilenstein Y" "extern" "watchlist-item-y" 2>/dev/null)"
set_topic_status "$DB_AC6" "$TOPIC_Y" "geparkt" > /dev/null

OUT_AC6="$TMP/ac6_pass.out"
ERR_AC6="$TMP/ac6_pass.err"
FAKE_L30D_WATCHLIST_JSON_FILE="$TEST_DIR/fixtures/watchlist_delta_new.json" \
  RA_LAST30DAYS_WATCHLIST_CMD="$FAKE_L30D_WATCHLIST" \
  run_watchlist_pass "$DB_AC6" > "$OUT_AC6" 2> "$ERR_AC6"

LOCK_X_HOLDER="$(sqlite3 "$DB_AC6" "SELECT holder FROM ra_topic_lock WHERE topic_id = '$TOPIC_X';")"
LOCK_Y_COUNT="$(sqlite3 "$DB_AC6" "SELECT COUNT(*) FROM ra_topic_lock WHERE topic_id = '$TOPIC_Y';")"
if grep -qi "UEBERSPRUNGEN.*$TOPIC_X" "$ERR_AC6" \
  && ! grep -qF "Meilenstein $MS_X (Thema $TOPIC_X" "$OUT_AC6" \
  && grep -qF "Meilenstein $MS_Y (Thema $TOPIC_Y" "$OUT_AC6" && grep -qi "Delta erkannt" "$OUT_AC6" \
  && [ "$LOCK_X_HOLDER" = "research" ] && [ "$LOCK_Y_COUNT" = "0" ]; then
  ok "gesperrtes Thema X wird uebersprungen (Klartext, kein Doppel-Lauf, Sperre bleibt bei 'research' unangetastet); Thema Y wird geprueft, Watchlist-Sperre danach wieder frei (AC6/BR-019)"
else
  bad "unerwartetes Ergebnis: lock_x=$LOCK_X_HOLDER lock_y_count=$LOCK_Y_COUNT stdout=$(cat "$OUT_AC6") stderr=$(cat "$ERR_AC6")"
fi
release_topic_lock "$DB_AC6" "$TOPIC_X" "research" > /dev/null

echo "== @trace wiedervorlage-meilensteine#AC2,AC6,E2 -- run_watchlist_pass: last30days-Watchlist nicht erreichbar meldet ALLE Kandidaten als 'manuell zu pruefen', Sperre trotzdem korrekt erworben/freigegeben =="
DB_AC6_E2="$(new_migrated_db "$TMP/ac6-e2.sqlite")"
TOPIC_Z="$(create_topic "$DB_AC6_E2" "Thema Z (E2)" 2>/dev/null)"
MS_Z="$(create_milestone "$DB_AC6_E2" "$TOPIC_Z" "Externer Meilenstein Z" "extern" "watchlist-item-z" 2>/dev/null)"
set_topic_status "$DB_AC6_E2" "$TOPIC_Z" "geparkt" > /dev/null

OUT_AC6_E2="$TMP/ac6_e2.out"
ERR_AC6_E2="$TMP/ac6_e2.err"
RA_LAST30DAYS_WATCHLIST_CMD="ra-watchlist-definitiv-nicht-installiert-$$" \
  run_watchlist_pass "$DB_AC6_E2" > "$OUT_AC6_E2" 2> "$ERR_AC6_E2"
LOCK_Z_COUNT="$(sqlite3 "$DB_AC6_E2" "SELECT COUNT(*) FROM ra_topic_lock WHERE topic_id = '$TOPIC_Z';")"
if grep -qi "nicht erreichbar" "$ERR_AC6_E2" \
  && grep -qF "Meilenstein $MS_Z (Thema $TOPIC_Z" "$OUT_AC6_E2" && grep -qi "manuell zu pruefen" "$OUT_AC6_E2" \
  && [ "$LOCK_Z_COUNT" = "0" ]; then
  ok "last30days-Watchlist komplett nicht erreichbar: WARNUNG + jeder Kandidat als 'manuell zu pruefen' (E2), Sperre wird trotzdem erworben+freigegeben (AC6, kein Crash)"
else
  bad "unerwartetes Ergebnis: lock_z_count=$LOCK_Z_COUNT stdout=$(cat "$OUT_AC6_E2") stderr=$(cat "$ERR_AC6_E2")"
fi

echo "== @trace wiedervorlage-meilensteine#AC3,BR-020 -- run_watchlist_pass: Delta (new>0) auf Thema Y wird automatisch wiedervorgelegt (Meilenstein 'erfuellt', Thema 'geparkt -> aktiv') =="
MS_Y_STATUS_AFTER_RUN1="$(sqlite3 "$DB_AC6" "SELECT status FROM ra_milestone WHERE id = $MS_Y;")"
TOPIC_Y_STATUS_AFTER_RUN1="$(sqlite3 "$DB_AC6" "SELECT status FROM ra_topic WHERE id = '$TOPIC_Y';")"
if [ "$MS_Y_STATUS_AFTER_RUN1" = "erfuellt" ] && [ "$TOPIC_Y_STATUS_AFTER_RUN1" = "aktiv" ] \
  && grep -qi "wiedervorgelegt" "$OUT_AC6"; then
  ok "der bereits oben (AC6-Lauf) erkannte Delta fuer Thema Y hat automatisch reaktiviert: Meilenstein 'erfuellt', Thema 'geparkt -> aktiv' (AC3/BR-020), sichtbar im Report ('wiedervorgelegt')"
else
  bad "erwartete Meilenstein='erfuellt'/Thema='aktiv' + 'wiedervorgelegt' im Report, bekam ms=$MS_Y_STATUS_AFTER_RUN1 topic=$TOPIC_Y_STATUS_AFTER_RUN1 report=$(cat "$OUT_AC6")"
fi

echo "== @trace wiedervorlage-meilensteine#NFR -- run_watchlist_pass ist idempotent: ein bereits wiedervorgelegtes (jetzt aktives) Thema erscheint in keinem Folgelauf mehr als Kandidat, keine Doppel-Wiedervorlage =="
OUT_AC6_RUN2="$TMP/ac6_pass_run2.out"
FAKE_L30D_WATCHLIST_JSON_FILE="$TEST_DIR/fixtures/watchlist_delta_new.json" \
  RA_LAST30DAYS_WATCHLIST_CMD="$FAKE_L30D_WATCHLIST" \
  run_watchlist_pass "$DB_AC6" "$TOPIC_Y" > "$OUT_AC6_RUN2" 2>/dev/null
MS_Y_STATUS_AFTER_RUN2="$(sqlite3 "$DB_AC6" "SELECT status FROM ra_milestone WHERE id = $MS_Y;")"
TOPIC_Y_STATUS_AFTER_RUN2="$(sqlite3 "$DB_AC6" "SELECT status FROM ra_topic WHERE id = '$TOPIC_Y';")"
if grep -qi "Keine offenen externen Meilensteine" "$OUT_AC6_RUN2" \
  && [ "$MS_Y_STATUS_AFTER_RUN2" = "$MS_Y_STATUS_AFTER_RUN1" ] && [ "$TOPIC_Y_STATUS_AFTER_RUN2" = "$TOPIC_Y_STATUS_AFTER_RUN1" ]; then
  ok "zweiter Lauf auf dasselbe (jetzt aktive) Thema findet keinen Kandidaten mehr (Filter t.status='geparkt') -- keine Doppel-Wiedervorlage, ra_milestone/ra_topic unveraendert (NFR Idempotenz)"
else
  bad "unerwartetes Ergebnis: ms_after1=$MS_Y_STATUS_AFTER_RUN1 ms_after2=$MS_Y_STATUS_AFTER_RUN2 topic_after1=$TOPIC_Y_STATUS_AFTER_RUN1 topic_after2=$TOPIC_Y_STATUS_AFTER_RUN2 out=$(cat "$OUT_AC6_RUN2")"
fi

echo "== @trace wiedervorlage-meilensteine#AC5,BR-005,BR-020 -- list_watchlist_candidates/run_watchlist_pass schliessen ein 'verworfen'es Thema strukturell aus -- nie Wiedervorlage, selbst wenn ein externer Meilenstein (zurueckgesetzt) 'offen' waere =="
DB_AC5="$(new_migrated_db "$TMP/ac5-discarded.sqlite")"
TOPIC_DISCARDED="$(create_topic "$DB_AC5" "Verworfenes Thema AC5" 2>/dev/null)"
MS_DISCARDED="$(create_milestone "$DB_AC5" "$TOPIC_DISCARDED" "Externer Meilenstein (wird verworfen)" "extern" "watchlist-item-discarded" 2>/dev/null)"
set_topic_status "$DB_AC5" "$TOPIC_DISCARDED" "geparkt" > /dev/null
set_topic_status "$DB_AC5" "$TOPIC_DISCARDED" "verworfen" > /dev/null
# OF-10 hat den Meilenstein beim Verwerfen bereits auf 'hinfaellig' gesetzt
# (getestet in db_scripts/tests/run_tests.sh#"research-datenmodell#AC5,OF-10")
# -- hier zusaetzlich defensiv zurueck auf 'offen' gesetzt, um AC5 UNABHAENGIG
# von der OF-10-Kaskade zu belegen: der Ausschluss greift bereits allein ueber
# t.status='geparkt' in list_watchlist_candidates, nicht erst ueber den
# Meilenstein-Status.
set_milestone_status "$DB_AC5" "$MS_DISCARDED" "offen" > /dev/null
CANDIDATES_DISCARDED="$(list_watchlist_candidates "$DB_AC5")"
OUT_AC5="$(RA_LAST30DAYS_WATCHLIST_CMD="$FAKE_L30D_WATCHLIST" run_watchlist_pass "$DB_AC5" 2>/dev/null)"
TOPIC_DISCARDED_STATUS="$(sqlite3 "$DB_AC5" "SELECT status FROM ra_topic WHERE id = '$TOPIC_DISCARDED';")"
if [ -z "$CANDIDATES_DISCARDED" ] && echo "$OUT_AC5" | grep -qi "Keine offenen externen Meilensteine" \
  && [ "$TOPIC_DISCARDED_STATUS" = "verworfen" ]; then
  ok "ein 'verworfen'es Thema wird NIE als Watchlist-Kandidat gefuehrt/wiedervorgelegt -- ein (zurueckgesetzter) offener externer Meilenstein aendert daran nichts (AC5/BR-005/BR-020)"
else
  bad "erwartete leere Kandidatenliste + unveraendertes 'verworfen', bekam candidates='$CANDIDATES_DISCARDED' status=$TOPIC_DISCARDED_STATUS out=$OUT_AC5"
fi


echo
echo "Ergebnis: $pass OK, $fail FAIL"
[ "$fail" -eq 0 ]
