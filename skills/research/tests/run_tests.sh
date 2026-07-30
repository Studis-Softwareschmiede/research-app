#!/usr/bin/env bash
# run_tests.sh — Self-Test fuer skills/research/ (/research-Skill-Grundgeruest,
# S-007: Discovery-/Thema-Modus, last30days-Aufruf, Persistenz ueber die
# Data-Access-Schicht, Quellen-Resilienz; S-011: Voraussetzungs-Ueberblick --
# Meilenstein-Liste je Thema + Schutzrechte-Klaerungspunkt; S-008:
# Bewertungsschicht-Anzeige -- SWOT-Zusammenfassung + Empfehlung +
# Businessplan-Template; S-013: Watchlist-Pass -- Watchlist-Kopplung +
# Nebenlaeufigkeits-Serialisierung; S-016: Entscheidungs-Gate -- explizite
# PM-Anstoss-Wahl NUR bei 'weiterverfolgen', nie automatisch).
#
# Rein mechanisches Shell-Test-Artefakt (M2/M3-Grundgeruest, kein App-Layer im
# profile.md-Sinn -- language: md). Erfuellt die Spec-Vertragszeile "Tests
# taggen @trace research-skill#AC<n>" (docs/specs/research-skill.md
# "Verträge") bzw. "@trace wiedervorlage-meilensteine#AC<n>"
# (docs/specs/wiedervorlage-meilensteine.md "Verträge") bzw. "@trace
# gate-pm-anstoss#AC<n>" (docs/specs/gate-pm-anstoss.md "Verträge").
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
# AC3 (Deep-Research-Pass als zweite Evidenzquelle, S-009: der Pass selbst ist
# rein agentisch (Claude, SKILL.md, Owner-Entscheid a-3, kein last30days-/
# CLI-Aufruf, analog ADR-009 nicht als Bash-Funktion abbildbar) --
# unit-testbar ist hier nur die bereits bestehende Persistenz-/Anzeige-Seite:
# create_run legt einen Lauf mit has_deep_research=0/momentum_only=1 normal an
# (rc=0, kein hartes Blocking, BR-014), print_recommendation markiert ihn
# sichtbar als Momentum-Signal; die BR-014-"gdw."-Konsistenzpruefung selbst ist
# in db_scripts/tests/run_tests.sh#"research-datenmodell#AC2,BR-014" getestet),
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
# kein Doppel-Lauf, kein Abbruch des Gesamt-Passes), AC4 (Nicht pruefbare
# Meilensteine, S-015: watchlist_pass.sh#report_watchlist_result meldet JEDEN
# extern nicht automatisch pruefbaren Fall als "manuell zu pruefen" statt ihn
# still zu uebergehen -- last30days-Watchlist nicht aufloesbar/nicht
# erreichbar (E2, deckungsgleich mit AC4), last30days-Antwort trotz fetch_rc=0
# kein gueltiges JSON, last30days meldet einen der Implementierung
# unbekannten status-Wert; in allen drei Faellen bleibt ra_milestone.status
# unveraendert -- keine stille Nicht-Pruefung), E2 (last30days-Watchlist
# nicht erreichbar -> jeder betroffene Meilenstein wird als "manuell zu
# pruefen" gemeldet, kein Absturz des Passes). AC1 dieser Spec ist NICHT
# Gegenstand dieser Story (S-012/Done).
#
# Covers (gate-pm-anstoss): AC1 (Entscheidungs-Gate ist manuell, S-016:
# orchestrator.sh#print_gate_prompt -- rendert die explizite PM-Anstoss-Wahl
# NUR wenn die fuer den Lauf persistierte Empfehlung 'weiterverfolgen' ist
# (architecture.md BR-102: Uebergang nach 'im_pm' nur ueber das Gate, nie aus
# 'parken'/'verwerfen'); render_evaluation/main('evaluation') bindet das Gate
# automatisch in den Bewertungsschicht-Brief ein; ohne die vorgelagerte
# Empfehlung 'weiterverfolgen' erscheint KEIN Gate-Text -- reine Anzeige,
# loest selbst keinen PM-Anstoss aus (C-004/BR-102)). AC2 (PM-Anstoss-Bookkeeping,
# S-017, ADR-009: orchestrator.sh#dispatch_pm_anstoss -- ruft pm-skills NIE
# selbst auf (kein CLI/Subprocess); nimmt die vom Aufrufer (Skill-Tool-Dispatch
# derselben Session) bereits erzeugte Vault-Pfad-Referenz als drittes Argument
# <artifact-ref> entgegen und uebernimmt ausschliesslich das deterministische
# Bookkeeping: pm_dispatch.sh#dispatch_pm_handoff (idempotent via
# UNIQUE(topic_id,result_hash), BR-017, AC3-Vorbereitung); Statuswechsel
# 'aktiv' -> 'im_pm' (BR-006, architecture.md Zustandsautomat); ein zweiter
# Dispatch mit abweichendem result_hash auf ein bereits 'im_pm'-Thema bleibt
# rc=0 mit Status unveraendert 'im_pm' -- KEIN unconditional
# set_topic_status-Aufruf, da 'im_pm' -> 'im_pm' keine gueltige Transition-
# Kante ist (Reviewer-Fund, Lesson S-017 2026-07-30). main('dispatch_
# pm_anstoss') ist der Reachability-Pfad fuer AC2, coder/R07). AC3 (Idempotenz,
# S-018: pm_dispatch.sh#dispatch_pm_handoff prueft VOR jedem INSERT per SELECT
# auf (topic_id,result_hash) und liefert rc=2 ohne neue Zeile; die
# UNIQUE(topic_id,result_hash)-Spalte (008_ra_pm_dispatch.sql) ist der
# native DB-Backstop dahinter (BR-017); dispatch_pm_anstoss protokolliert den
# idempotenten Treffer als "gleicher Hash ... bereits vorhanden" statt still
# durchzulaufen). AC5 (Abbruch-Sicherheit, S-018: dispatch_pm_anstoss haelt
# den Statuswechsel 'aktiv' -> 'im_pm' NICHT mehr nur im rc=0-Zweig (neuer
# Dispatch) fest, sondern holt ihn AUCH im idempotenten rc=2-Zweig nach --
# bricht ein Anstoss genau zwischen dem dispatch_pm_handoff-COMMIT und dem
# Statuswechsel ab (Prozessabbruch), bleibt ra_topic.status sonst dauerhaft
# 'aktiv', obwohl der PM-Dispatch bereits geschrieben ist; ein Neustart mit
# identischem result_hash trifft den idempotenten Pfad und schliesst den
# Statuswechsel jetzt ab, statt ihn zu uebergehen -- kein halb aktualisierter
# Stand wird als "aktuell" markiert). AC4 (Divergenz-Ausweis, S-019:
# pm_dispatch.sh#get_latest_pm_dispatch ermittelt den Vorlauf -- den zuletzt
# fuer dieses Thema dispatchten ANDEREN Lauf, mit dem soeben dispatchten
# run_id explizit ausgeschlossen (robust gegen einen Abbruch-Neustart, s.u.);
# orchestrator.sh#materialize_and_render_divergence materialisiert (idempotent
# via db_scripts/lib/divergence.sh#get_divergence VOR jedem create_divergence)
# die Divergenz zwischen Vorlauf und Folgelauf ueber
# compute_swot_delta(list_swot_items(from), list_swot_items(to)) und rendert
# sie strukturiert (Empfehlung geaendert/SWOT-Delta/Meilenstein-Status-Delta);
# Meilenstein-Delta bleibt dabei stets leer (kein Lauf-Zeitpunkt-Snapshot,
# divergence.sh-Datei-Header-Scope-Grenze S-004). Kein Vorlauf (Erst-Anstoss)
# -> kein Divergenz-Ausweis. Der Divergenz-Materialisierungs-Schritt laeuft
# unconditional bzgl. rc (auch im idempotenten rc=2-Zweig), um einen Abbruch
# GENAU zwischen dispatch_pm_handoff-COMMIT und Divergenz-Materialisierung bei
# Neustart nachzuholen (AC5-Konsistenz fuer diese neue Schreiboperation).
# divergence.sh#create_divergence verwirft die vom Aufrufer gelieferten
# swot-/milestone-Delta-Strings selbst, sobald es is_empty=1 (Hash-Vergleich)
# feststellt -- einzige Quelle der Wahrheit bleibt der Hash, nicht der Aufrufer
# (Reviewer-Fund Iteration 2: zwei VERSCHIEDENE Laeufe mit IDENTISCHEM
# result_hash auf demselben Thema loesten sonst eine CHECK-Constraint-
# Verletzung in ra_divergence aus, obwohl Dispatch+Statuswechsel bereits
# erfolgreich durchliefen). Scheitert die Divergenz-Materialisierung aus einem
# ANDEREN Grund (z.B. ein raum-/zeitgleicher zweiter Anstoss auf dasselbe
# Vorlauf/Folgelauf-Paar, der create_divergence's UNIQUE(from_run_id,
# to_run_id) verletzt), gibt dispatch_pm_anstoss das NICHT mehr als
# irrefuehrendes rc=1 ("kein Statuswechsel") zurueck, obwohl Dispatch+
# Statuswechsel an dieser Stelle bereits real committet sind -- stattdessen
# eine Warnung auf stderr, die Funktion faehrt mit ihrem eigentlichen rc (0
# oder 2) fort (Reviewer-Fund S-019 Iteration 3, Header-Vertrag oben in
# orchestrator.sh#dispatch_pm_anstoss praezisiert).
# AC6 (Manuelle Vault-Aenderung, S-020): orchestrator.sh#check_artifact_hash --
# read-only Vorab-Pruefung, die die aufrufende Session VOR jedem Skill-Dispatch
# (kein eigener Vault-Zugriff, ADR-009) durchfuehrt: vergleicht einen vom
# Aufrufer gelieferten Inhalts-Hash gegen den in pm_dispatch.sh#
# get_latest_pm_dispatch gespeicherten artifact_hash des Vorlaufs. Kein Vorlauf
# ODER Vorlauf ohne bekannten artifact_hash (Alt-Dispatch vor S-020) ODER
# uebereinstimmender Hash -> rc=0 (Skill-Dispatch darf starten); Mismatch ->
# rc=3 (Rueckfrage statt stillem Ueberschreiben). dispatch_pm_anstoss nimmt ein
# optionales fuenftes Argument [artifact-hash] entgegen und speichert es ueber
# pm_dispatch.sh#dispatch_pm_handoff als neuen erwarteten Vorlauf-Stand fuer
# den naechsten Anstoss. main('check_artifact_hash', ...) ist der
# Reachability-Pfad (coder/R07).
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
# shellcheck source=../../../db_scripts/lib/pm_dispatch.sh
source "$REPO_ROOT/db_scripts/lib/pm_dispatch.sh"

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

echo "== @trace research-skill#AC3,BR-014 -- fehlender Deep-Research-Pass (has_deep_research=0/momentum_only=1): Lauf-Anlage gelingt normal, Empfehlung sichtbar als Momentum-Signal markiert, KEIN hartes Blocking =="
HASH9_PARK="$(compute_result_hash "parken" "" "" 2>/dev/null)"
RUN9_PARK_RC=0
RUN9_PARK="$(create_run "$DB9" "$TOPIC9" "recherche" "$HASH9_PARK" "parken" 0 1)" || RUN9_PARK_RC=$?
RUN9_PARK_ID="${RUN9_PARK%%|*}"
REC_PARK_OUT="$(print_recommendation "$DB9" "$RUN9_PARK_ID")"
if [ "$RUN9_PARK_RC" -eq 0 ] && [ -n "$RUN9_PARK_ID" ] \
  && echo "$REC_PARK_OUT" | grep -q "Empfehlung: parken (Momentum-Signal -- kein Deep-Research-Pass, BR-014)" \
  && ! echo "$REC_PARK_OUT" | grep -q "Businessplan-Template"; then
  ok "has_deep_research=0/momentum_only=1: create_run legt den Lauf trotz fehlendem Deep-Research-Pass normal an (rc=0, kein hartes Blocking, AC3), print_recommendation markiert die Empfehlung sichtbar als Momentum-Signal, KEIN Businessplan-Template (coder/R01, BR-107 nur bei weiterverfolgen)"
else
  bad "erwartete rc=0 + Momentum-Hinweis ohne Businessplan-Template, bekam: rc=$RUN9_PARK_RC out='$REC_PARK_OUT'"
fi

echo "== @trace research-skill#AC2,gate-pm-anstoss#AC1 -- render_evaluation/main('evaluation'): SWOT + Empfehlung + Gate als ein Block =="
create_swot_item "$DB9" "$RUN9_WV_ID" "opportunity" "kundennachfrage" "last30days" > /dev/null
EVAL_OUT="$(RA_DB_PATH="$DB9" main evaluation "$RUN9_WV_ID")"
if echo "$EVAL_OUT" | grep -q "Bewertungsschicht (research-skill#AC2)" \
  && echo "$EVAL_OUT" | grep -q "SWOT (strukturiert, BR-012)" \
  && echo "$EVAL_OUT" | grep -q "kundennachfrage" \
  && echo "$EVAL_OUT" | grep -q "Empfehlung: weiterverfolgen" \
  && echo "$EVAL_OUT" | grep -q "Businessplan-Template" \
  && echo "$EVAL_OUT" | grep -q "Entscheidungs-Gate (gate-pm-anstoss#AC1, ADR-005)" \
  && echo "$EVAL_OUT" | grep -q "PM-Anstoss | Zurueckstellen"; then
  ok "main('evaluation', <run-id>) rendert SWOT-Zusammenfassung + Empfehlung + Businessplan-Template + Entscheidungs-Gate ueber render_evaluation"
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

echo "== @trace gate-pm-anstoss#AC1 -- print_gate_prompt: 'weiterverfolgen' rendert die explizite PM-Anstoss-Wahl =="
GATE_WV_OUT="$(print_gate_prompt "$DB9" "$RUN9_WV_ID")"
if echo "$GATE_WV_OUT" | grep -q "Entscheidungs-Gate (gate-pm-anstoss#AC1, ADR-005)" \
  && echo "$GATE_WV_OUT" | grep -q "weiterverfolgen" \
  && echo "$GATE_WV_OUT" | grep -q "PM-Anstoss | Zurueckstellen" \
  && echo "$GATE_WV_OUT" | grep -q "kein Automatik-Anstoss"; then
  ok "print_gate_prompt zeigt bei 'weiterverfolgen' die explizite Gate-Wahl inkl. C-004/BR-102-Hinweis (kein Automatik-Anstoss)"
else
  bad "erwartete Gate-Wahl, bekam: $GATE_WV_OUT"
fi

echo "== @trace gate-pm-anstoss#AC1,BR-102 -- print_gate_prompt: 'parken' zeigt KEIN Gate (kein Pfad nach 'im_pm') =="
GATE_PARK_OUT="$(print_gate_prompt "$DB9" "$RUN9_PARK_ID")"
if [ -z "$GATE_PARK_OUT" ]; then
  ok "print_gate_prompt bleibt bei 'parken' leer -- kein Gate-Angebot ausserhalb 'weiterverfolgen' (architecture.md Zustandsautomat)"
else
  bad "erwartete leere Ausgabe fuer 'parken', bekam: $GATE_PARK_OUT"
fi

echo "== @trace gate-pm-anstoss#AC1 -- render_evaluation/main('evaluation'): 'parken'-Lauf zeigt KEIN Gate im Brief =="
EVAL_PARK_OUT="$(RA_DB_PATH="$DB9" main evaluation "$RUN9_PARK_ID")"
if echo "$EVAL_PARK_OUT" | grep -q "Empfehlung: parken" \
  && ! echo "$EVAL_PARK_OUT" | grep -q "Entscheidungs-Gate"; then
  ok "main('evaluation', <run-id>) zeigt fuer 'parken' keine Gate-Wahl -- kein Automatik-Anstoss ausserhalb 'weiterverfolgen'"
else
  bad "erwartete Brief ohne Gate-Abschnitt fuer 'parken', bekam: $EVAL_PARK_OUT"
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

echo "== @trace wiedervorlage-meilensteine#AC2,AC4,E2 -- report_watchlist_result: last30days-Watchlist nicht verfuegbar (leerer cmd) meldet 'manuell zu pruefen', keine DB-Mutation =="
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

echo "== @trace wiedervorlage-meilensteine#AC2,AC4,E2 -- fetch_watchlist_delta+report_watchlist_result: last30days-Watchlist-Aufruf schlaegt fehl -> 'manuell zu pruefen' (kein Crash) =="
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

echo "== @trace wiedervorlage-meilensteine#AC4 -- report_watchlist_result: last30days-Watchlist-Antwort ist trotz fetch_rc=0 kein gueltiges JSON -> 'manuell zu pruefen', keine DB-Mutation =="
BAD_RESPONSE_FILE="$TMP/ac4-bad-response.json"
printf 'kein-json' > "$BAD_RESPONSE_FILE"
STATUS_BEFORE_BADJSON="$(sqlite3 "$DB_AC2" "SELECT status FROM ra_milestone WHERE id = $MS_OPEN;")"
REPORT_BADJSON="$(report_watchlist_result "$DB_AC2" "$TOPIC_P" "$MS_OPEN" "watchlist-item-open" "$FAKE_L30D_WATCHLIST" "0" "$BAD_RESPONSE_FILE" "/dev/null")"
STATUS_AFTER_BADJSON="$(sqlite3 "$DB_AC2" "SELECT status FROM ra_milestone WHERE id = $MS_OPEN;")"
if echo "$REPORT_BADJSON" | grep -qi "konnte nicht ausgewertet werden" && echo "$REPORT_BADJSON" | grep -qi "manuell zu pruefen" \
  && [ "$STATUS_BEFORE_BADJSON" = "$STATUS_AFTER_BADJSON" ]; then
  ok "nicht auswertbare last30days-Watchlist-Antwort wird als 'manuell zu pruefen' gemeldet, keine stille Nicht-Pruefung, ra_milestone.status unveraendert (AC4)"
else
  bad "unerwartetes Ergebnis: report='$REPORT_BADJSON' status_before=$STATUS_BEFORE_BADJSON status_after=$STATUS_AFTER_BADJSON"
fi

echo "== @trace wiedervorlage-meilensteine#AC4 -- report_watchlist_result: last30days meldet einen unbekannten status-Wert -> 'manuell zu pruefen', keine DB-Mutation =="
FETCH_UNKNOWN_LINE="$(FAKE_L30D_WATCHLIST_JSON_FILE="$TEST_DIR/fixtures/watchlist_delta_unknown_status.json" \
  fetch_watchlist_delta "$FAKE_L30D_WATCHLIST" "watchlist-item-open")"
IFS=$'\x1f' read -r FETCH_UNKNOWN_RC FETCH_UNKNOWN_JSON FETCH_UNKNOWN_ERR <<< "$FETCH_UNKNOWN_LINE"
STATUS_BEFORE_UNKNOWN="$(sqlite3 "$DB_AC2" "SELECT status FROM ra_milestone WHERE id = $MS_OPEN;")"
REPORT_UNKNOWN="$(report_watchlist_result "$DB_AC2" "$TOPIC_P" "$MS_OPEN" "watchlist-item-open" "$FAKE_L30D_WATCHLIST" "$FETCH_UNKNOWN_RC" "$FETCH_UNKNOWN_JSON" "$FETCH_UNKNOWN_ERR")"
rm -f "$FETCH_UNKNOWN_JSON" "$FETCH_UNKNOWN_ERR" 2>/dev/null || true
STATUS_AFTER_UNKNOWN="$(sqlite3 "$DB_AC2" "SELECT status FROM ra_milestone WHERE id = $MS_OPEN;")"
if echo "$REPORT_UNKNOWN" | grep -qi "unbekannter last30days-Watchlist-Status" && echo "$REPORT_UNKNOWN" | grep -qi "manuell zu pruefen" \
  && [ "$STATUS_BEFORE_UNKNOWN" = "$STATUS_AFTER_UNKNOWN" ]; then
  ok "ein last30days-Watchlist-Status ausserhalb von {ok,insufficient_history} wird als 'manuell zu pruefen' gemeldet statt stillschweigend ignoriert, ra_milestone.status unveraendert (AC4, extern nicht automatisch pruefbar)"
else
  bad "unerwartetes Ergebnis: report='$REPORT_UNKNOWN' status_before=$STATUS_BEFORE_UNKNOWN status_after=$STATUS_AFTER_UNKNOWN"
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

echo "== @trace wiedervorlage-meilensteine#AC2,AC4,AC6,E2 -- run_watchlist_pass: last30days-Watchlist nicht erreichbar meldet ALLE Kandidaten als 'manuell zu pruefen', Sperre trotzdem korrekt erworben/freigegeben =="
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


echo "== @trace gate-pm-anstoss#AC2 -- orchestrator.sh dispatch_pm_anstoss: PM-Anstoss-Bookkeeping mit Status-Wechsel (aktiv -> im_pm), artifact-ref kommt vom Aufrufer (ADR-009) =="
# Test Setup: Thema + Lauf + Empfehlung 'weiterverfolgen' vorbereiten
DB_AC2="$(new_migrated_db "$TMP/ac2-pm-dispatch.sqlite")"
TOPIC_AC2="$(create_topic "$DB_AC2" "Thema fuer AC2 PM-Anstoss" 2>/dev/null)"
RUN_AC2_FULL="$(create_run "$DB_AC2" "$TOPIC_AC2" "recherche" "ca761c12aa31c1e37cd9a5f6e7f8a9b9c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC2="${RUN_AC2_FULL%%|*}"  # Extract id from id|version

# artifact-ref simuliert die Vault-Pfad-Referenz, die die aufrufende Session
# bereits VOR diesem Aufruf ueber das Skill-Tool per pm-skills erzeugt hat
# (ADR-009, Schritt 1 -- kein Subprocess-Aufruf, kein Fake-CLI-Stub noetig).
ARTIFACT_REF_AC2="Research/PM_Artifacts_${TOPIC_AC2}_${RUN_AC2}"

# Test dispatch_pm_anstoss (echter Orchestrator-Aufruf)
ORCHESTRATOR_SCRIPT="$RESEARCH_DIR/scripts/orchestrator.sh"
OUT_AC2="$TMP/ac2_out.txt"
ERR_AC2="$TMP/ac2_err.txt"
rc_ac2=0
RA_DB_PATH="$DB_AC2" \
  bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC2" "$RUN_AC2" "$ARTIFACT_REF_AC2" > "$OUT_AC2" 2> "$ERR_AC2" || rc_ac2=$?

# Prüfungen: ra_pm_dispatch existiert, Status ist 'im_pm', Erfolgs-Meldung
DISPATCH_COUNT="$(sqlite3 "$DB_AC2" "SELECT COUNT(*) FROM ra_pm_dispatch WHERE topic_id = '$TOPIC_AC2';")"
TOPIC_STATUS="$(sqlite3 "$DB_AC2" "SELECT status FROM ra_topic WHERE id = '$TOPIC_AC2';")"
DISPATCHED_REF="$(sqlite3 "$DB_AC2" "SELECT artifact_ref FROM ra_pm_dispatch WHERE topic_id = '$TOPIC_AC2';")"
if [ "$rc_ac2" = "0" ] && [ "$DISPATCH_COUNT" = "1" ] && [ "$TOPIC_STATUS" = "im_pm" ] \
  && [ "$DISPATCHED_REF" = "$ARTIFACT_REF_AC2" ] \
  && grep -qi "erfolgreich abgeschlossen" "$OUT_AC2"; then
  ok "PM-Dispatch protokolliert mit dem vom Aufrufer gelieferten artifact-ref, Status 'aktiv' -> 'im_pm', Erfolgs-Meldung sichtbar (AC2 Happy Path, ADR-009)"
else
  bad "erwartete rc=0/dispatch_count=1/status=im_pm/ref=$ARTIFACT_REF_AC2/Erfolgsmeldung, bekam rc=$rc_ac2 count=$DISPATCH_COUNT status=$TOPIC_STATUS ref=$DISPATCHED_REF out=$(cat "$OUT_AC2") err=$(cat "$ERR_AC2")"
fi

echo "== @trace gate-pm-anstoss#AC2 -- orchestrator.sh dispatch_pm_anstoss: fehlendes artifact-ref bricht ab (kein DB-Schreibversuch ohne Aufrufer-Referenz, ADR-009/E2) =="
DB_AC2_NOREF="$(new_migrated_db "$TMP/ac2-noref.sqlite")"
TOPIC_AC2_NOREF="$(create_topic "$DB_AC2_NOREF" "Thema ohne artifact-ref" 2>/dev/null)"
RUN_AC2_NOREF_FULL="$(create_run "$DB_AC2_NOREF" "$TOPIC_AC2_NOREF" "recherche" "ea761c12aa31c1e37cd9a5f6e7f8a9b9c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC2_NOREF="${RUN_AC2_NOREF_FULL%%|*}"
ERR_AC2_NOREF="$TMP/ac2_noref.err"
rc_noref=0
RA_DB_PATH="$DB_AC2_NOREF" \
  bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC2_NOREF" "$RUN_AC2_NOREF" "" > /dev/null 2> "$ERR_AC2_NOREF" || rc_noref=$?
DISPATCH_COUNT_NOREF="$(sqlite3 "$DB_AC2_NOREF" "SELECT COUNT(*) FROM ra_pm_dispatch;")"
if [ "$rc_noref" != "0" ] && [ "$DISPATCH_COUNT_NOREF" = "0" ] && grep -qi "artifact-ref" "$ERR_AC2_NOREF"; then
  ok "fehlendes artifact-ref bricht mit FATAL ab, kein ra_pm_dispatch-Eintrag (ADR-009, orchestrator.sh ermittelt es nie selbst)"
else
  bad "erwartete rc!=0/dispatch_count=0/FATAL zu artifact-ref, bekam rc=$rc_noref count=$DISPATCH_COUNT_NOREF err=$(cat "$ERR_AC2_NOREF")"
fi

echo "== @trace gate-pm-anstoss#AC2,AC3 -- orchestrator.sh dispatch_pm_anstoss: Idempotenz (gleicher Hash = rc=2, kein neuer Dispatch) =="
# Zweiter Aufruf mit identischem Hash
OUT_AC2_IDEM="$TMP/ac2_idem.txt"
ERR_AC2_IDEM="$TMP/ac2_idem.err"
rc_idem=0
RA_DB_PATH="$DB_AC2" \
  bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC2" "$RUN_AC2" "$ARTIFACT_REF_AC2" > "$OUT_AC2_IDEM" 2> "$ERR_AC2_IDEM" || rc_idem=$?
DISPATCH_COUNT_IDEM="$(sqlite3 "$DB_AC2" "SELECT COUNT(*) FROM ra_pm_dispatch WHERE topic_id = '$TOPIC_AC2';")"
if [ "$rc_idem" = "2" ] && [ "$DISPATCH_COUNT_IDEM" = "1" ] \
  && grep -qi "idempotent" "$OUT_AC2_IDEM"; then
  ok "idempotenter Dispatch: rc=2, UNIQUE-Constraint verhindert Duplikat, Ausgabe zeigt Idempotenz (AC2/AC3)"
else
  bad "erwartete rc=2/count=1/Idempotenz-Ausgabe, bekam rc=$rc_idem count=$DISPATCH_COUNT_IDEM out=$(cat "$OUT_AC2_IDEM")"
fi

echo "== @trace gate-pm-anstoss#AC5 -- orchestrator.sh dispatch_pm_anstoss: Neustart nach Abbruch ZWISCHEN dispatch_pm_handoff-COMMIT und Statuswechsel holt den ausstehenden Statuswechsel nach (kein halb aktualisierter Stand) =="
# Abbruch-Simulation: dispatch_pm_handoff() wird HIER direkt (nicht ueber
# dispatch_pm_anstoss) aufgerufen -- das bildet exakt den Zustand nach, den
# ein zwischen COMMIT und dem nachfolgenden set_topic_status abgebrochener
# Anstoss hinterlaesst: ra_pm_dispatch traegt bereits den Eintrag, aber
# ra_topic.status ist noch 'aktiv' (der Statuswechsel wurde nie erreicht).
DB_AC5S="$(new_migrated_db "$TMP/ac5-abort-restart.sqlite")"
TOPIC_AC5S="$(create_topic "$DB_AC5S" "Thema fuer AC5 Abbruch-Neustart" 2>/dev/null)"
RUN_AC5S_FULL="$(create_run "$DB_AC5S" "$TOPIC_AC5S" "recherche" "ac5abc12aa31c1e37cd9a5f6e7f8a9b9c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC5S="${RUN_AC5S_FULL%%|*}"
ARTIFACT_REF_AC5S="Research/PM_Artifacts_${TOPIC_AC5S}_${RUN_AC5S}"
RESULT_HASH_AC5S="ac5abc12aa31c1e37cd9a5f6e7f8a9b9c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8"

dispatch_pm_handoff "$DB_AC5S" "$TOPIC_AC5S" "$RUN_AC5S" "$RESULT_HASH_AC5S" "$ARTIFACT_REF_AC5S" > /dev/null 2>&1
TOPIC_STATUS_PRE_AC5S="$(sqlite3 "$DB_AC5S" "SELECT status FROM ra_topic WHERE id = '$TOPIC_AC5S';")"
DISPATCH_COUNT_PRE_AC5S="$(sqlite3 "$DB_AC5S" "SELECT COUNT(*) FROM ra_pm_dispatch WHERE topic_id = '$TOPIC_AC5S';")"
if [ "$TOPIC_STATUS_PRE_AC5S" != "aktiv" ] || [ "$DISPATCH_COUNT_PRE_AC5S" != "1" ]; then
  bad "Abbruch-Simulation fehlgeschlagen: erwartete status=aktiv/dispatch_count=1 VOR dem Neustart, bekam status=$TOPIC_STATUS_PRE_AC5S count=$DISPATCH_COUNT_PRE_AC5S"
fi

# Neustart: identischer Aufruf (gleicher Hash) ueber den echten
# dispatch_pm_anstoss-Pfad -- muss den ausstehenden Statuswechsel nachholen,
# OHNE ein zweites ra_pm_dispatch-Artefakt anzulegen.
OUT_AC5S="$TMP/ac5s_restart.txt"
ERR_AC5S="$TMP/ac5s_restart.err"
rc_ac5s=0
RA_DB_PATH="$DB_AC5S" \
  bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC5S" "$RUN_AC5S" "$ARTIFACT_REF_AC5S" > "$OUT_AC5S" 2> "$ERR_AC5S" || rc_ac5s=$?
TOPIC_STATUS_POST_AC5S="$(sqlite3 "$DB_AC5S" "SELECT status FROM ra_topic WHERE id = '$TOPIC_AC5S';")"
DISPATCH_COUNT_POST_AC5S="$(sqlite3 "$DB_AC5S" "SELECT COUNT(*) FROM ra_pm_dispatch WHERE topic_id = '$TOPIC_AC5S';")"
if [ "$rc_ac5s" = "2" ] && [ "$TOPIC_STATUS_POST_AC5S" = "im_pm" ] && [ "$DISPATCH_COUNT_POST_AC5S" = "1" ] \
  && grep -qi "idempotent" "$OUT_AC5S"; then
  ok "Neustart nach simuliertem Abbruch: rc=2 (idempotent, kein neues Artefakt), Statuswechsel 'aktiv' -> 'im_pm' NACHGEHOLT statt dauerhaft haengen zu bleiben (AC5, gefahrloser Neustart)"
else
  bad "erwartete rc=2/status=im_pm/count=1 nach Neustart, bekam rc=$rc_ac5s status=$TOPIC_STATUS_POST_AC5S count=$DISPATCH_COUNT_POST_AC5S out=$(cat "$OUT_AC5S") err=$(cat "$ERR_AC5S")"
fi

echo "== @trace gate-pm-anstoss#AC2 -- orchestrator.sh dispatch_pm_anstoss: zweiter Dispatch mit ABWEICHENDEM result_hash auf ein bereits 'im_pm'-Thema bleibt rc=0, Status bleibt 'im_pm' (Lesson S-017, im_pm:im_pm ist keine Transition-Kante) =="
# Zweiter, unabhaengiger Lauf auf demselben (bereits im_pm) Thema mit einem
# ANDEREN result_hash -- reproduziert den Reviewer-Fund: set_topic_status
# durfte hier NICHT unconditional aufgerufen werden (Kante im_pm:im_pm fehlt
# in ra_topic_valid_transition), sonst rc=1 trotz erfolgreich geschriebenem
# ra_pm_dispatch-Eintrag.
RUN_AC2_DIVERGENT_FULL="$(create_run "$DB_AC2" "$TOPIC_AC2" "recherche" "fb761c12aa31c1e37cd9a5f6e7f8a9b9c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC2_DIVERGENT="${RUN_AC2_DIVERGENT_FULL%%|*}"
ARTIFACT_REF_AC2_DIVERGENT="Research/PM_Artifacts_${TOPIC_AC2}_${RUN_AC2_DIVERGENT}"
OUT_AC2_DIVERGENT="$TMP/ac2_divergent.txt"
ERR_AC2_DIVERGENT="$TMP/ac2_divergent.err"
rc_divergent=0
RA_DB_PATH="$DB_AC2" \
  bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC2" "$RUN_AC2_DIVERGENT" "$ARTIFACT_REF_AC2_DIVERGENT" > "$OUT_AC2_DIVERGENT" 2> "$ERR_AC2_DIVERGENT" || rc_divergent=$?
DISPATCH_COUNT_DIVERGENT="$(sqlite3 "$DB_AC2" "SELECT COUNT(*) FROM ra_pm_dispatch WHERE topic_id = '$TOPIC_AC2';")"
TOPIC_STATUS_DIVERGENT="$(sqlite3 "$DB_AC2" "SELECT status FROM ra_topic WHERE id = '$TOPIC_AC2';")"
if [ "$rc_divergent" = "0" ] && [ "$DISPATCH_COUNT_DIVERGENT" = "2" ] && [ "$TOPIC_STATUS_DIVERGENT" = "im_pm" ] \
  && grep -qi "bleibt 'im_pm'" "$OUT_AC2_DIVERGENT"; then
  ok "zweiter Dispatch mit abweichendem Hash auf bereits-im_pm-Thema: rc=0, neuer ra_pm_dispatch-Eintrag, Status bleibt 'im_pm' (kein irrefuehrender rc=1 trotz committetem Write)"
else
  bad "erwartete rc=0/count=2/status=im_pm, bekam rc=$rc_divergent count=$DISPATCH_COUNT_DIVERGENT status=$TOPIC_STATUS_DIVERGENT out=$(cat "$OUT_AC2_DIVERGENT") err=$(cat "$ERR_AC2_DIVERGENT")"
fi

echo "== @trace gate-pm-anstoss#AC4 -- orchestrator.sh dispatch_pm_anstoss: veraenderter Ergebnisstand materialisiert die Divergenz zum Vorlauf (ra_divergence) und weist sie strukturiert aus =="
# Fortsetzung des obigen Tests (derselbe divergente Dispatch RUN_AC2 -> RUN_AC2_DIVERGENT):
# der PM-Anstoss auf einen veraenderten Ergebnisstand muss ZUSAETZLICH zum
# Bookkeeping (AC2, oben) die Divergenz zum Vorlauf materialisieren + strukturiert
# ausweisen (AC4). Keiner der beiden Laeufe traegt SWOT-Items -> leeres Delta
# erwartet (reale Delta-Inhalte werden im eigenen AC4-Testblock unten geprueft).
DIVERGENCE_COUNT_AC4="$(sqlite3 "$DB_AC2" "SELECT COUNT(*) FROM ra_divergence WHERE from_run_id = $RUN_AC2 AND to_run_id = $RUN_AC2_DIVERGENT;")"
DIVERGENCE_ROW_AC4="$(sqlite3 -separator '|' "$DB_AC2" "SELECT is_empty, recommendation_changed, swot_delta, milestone_status_delta FROM ra_divergence WHERE from_run_id = $RUN_AC2 AND to_run_id = $RUN_AC2_DIVERGENT;")"
if [ "$DIVERGENCE_COUNT_AC4" = "1" ] \
  && [ "$DIVERGENCE_ROW_AC4" = '0|0|{"added":[],"removed":[],"by_category":{}}|{"changed":[]}' ] \
  && grep -q "Divergenz-Ausweis (gate-pm-anstoss#AC4, Vorlauf $RUN_AC2 -> Folgelauf $RUN_AC2_DIVERGENT)" "$OUT_AC2_DIVERGENT" \
  && grep -q "Empfehlung geaendert: nein" "$OUT_AC2_DIVERGENT" \
  && grep -q "SWOT-Delta:" "$OUT_AC2_DIVERGENT" \
  && grep -q "Meilenstein-Status-Delta:" "$OUT_AC2_DIVERGENT"; then
  ok "veraenderter Ergebnisstand (abweichender Hash) materialisiert genau EINE ra_divergence-Zeile (Vorlauf=$RUN_AC2 -> Folgelauf=$RUN_AC2_DIVERGENT) und rendert sie strukturiert im Dispatch-Output (AC4)"
else
  bad "erwartete genau 1 Divergenz-Zeile mit is_empty=0/recommendation_changed=0/leerem Delta + strukturierter Ausgabe, bekam count=$DIVERGENCE_COUNT_AC4 row='$DIVERGENCE_ROW_AC4' out=$(cat "$OUT_AC2_DIVERGENT")"
fi

echo "== @trace gate-pm-anstoss#AC4 -- orchestrator.sh dispatch_pm_anstoss: Erst-Anstoss (kein Vorlauf) materialisiert KEINE Divergenz =="
# Ganz frisches Thema/Lauf, noch nie per PM-Anstoss dispatcht (kein Vorlauf) --
# der Erst-Anstoss selbst (gate-pm-anstoss#AC2) darf keine ra_divergence-Zeile
# erzeugen, da es nichts gibt, wozu er divergieren koennte.
DB_AC4_FIRST="$(new_migrated_db "$TMP/ac4-first.sqlite")"
TOPIC_AC4_FIRST="$(create_topic "$DB_AC4_FIRST" "Thema fuer AC4 Erst-Anstoss" 2>/dev/null)"
RUN_AC4_FIRST_FULL="$(create_run "$DB_AC4_FIRST" "$TOPIC_AC4_FIRST" "recherche" "aa11111111111111111111111111111111111111111111111111111111111111" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC4_FIRST="${RUN_AC4_FIRST_FULL%%|*}"
OUT_AC4_FIRST="$TMP/ac4_first.out"
RA_DB_PATH="$DB_AC4_FIRST" \
  bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC4_FIRST" "$RUN_AC4_FIRST" "Research/PM_Artifacts_first" > "$OUT_AC4_FIRST" 2>/dev/null
DIVERGENCE_COUNT_FIRST="$(sqlite3 "$DB_AC4_FIRST" "SELECT COUNT(*) FROM ra_divergence;")"
if [ "$DIVERGENCE_COUNT_FIRST" = "0" ] && ! grep -q "Divergenz-Ausweis" "$OUT_AC4_FIRST"; then
  ok "Erst-Anstoss ohne Vorlauf erzeugt keine ra_divergence-Zeile und keinen Divergenz-Ausweis-Block (AC4)"
else
  bad "erwartete 0 Divergenz-Zeilen ohne Vorlauf, bekam count=$DIVERGENCE_COUNT_FIRST out=$(cat "$OUT_AC4_FIRST")"
fi

echo "== @trace gate-pm-anstoss#AC4 -- orchestrator.sh dispatch_pm_anstoss: Divergenz-Ausweis spiegelt echte SWOT-Aenderung zwischen Vorlauf und Folgelauf strukturiert wider =="
# Vorlauf: 'teamkompetenz' (strength) + 'wettbewerbsintensitaet' (threat).
# Folgelauf: 'teamkompetenz' bleibt, 'wettbewerbsintensitaet' entfaellt, neu:
# 'regulierung' (threat) -- added=[threat,regulierung], removed=[threat,
# wettbewerbsintensitaet], by_category.threat={added:1,removed:1}.
DB_AC4_SWOT="$(new_migrated_db "$TMP/ac4-swot.sqlite")"
TOPIC_AC4_SWOT="$(create_topic "$DB_AC4_SWOT" "Thema fuer AC4 SWOT-Divergenz" 2>/dev/null)"

RUN_AC4_SWOT_1_FULL="$(create_run "$DB_AC4_SWOT" "$TOPIC_AC4_SWOT" "recherche" "cc33333333333333333333333333333333333333333333333333333333333333" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC4_SWOT_1="${RUN_AC4_SWOT_1_FULL%%|*}"
create_swot_item "$DB_AC4_SWOT" "$RUN_AC4_SWOT_1" "strength" "teamkompetenz" "last30days" > /dev/null
create_swot_item "$DB_AC4_SWOT" "$RUN_AC4_SWOT_1" "threat" "wettbewerbsintensitaet" "last30days" > /dev/null
RA_DB_PATH="$DB_AC4_SWOT" bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC4_SWOT" "$RUN_AC4_SWOT_1" "Research/PM_Artifacts_swot_1" > /dev/null 2>&1

RUN_AC4_SWOT_2_FULL="$(create_run "$DB_AC4_SWOT" "$TOPIC_AC4_SWOT" "recherche" "dd44444444444444444444444444444444444444444444444444444444444444" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC4_SWOT_2="${RUN_AC4_SWOT_2_FULL%%|*}"
create_swot_item "$DB_AC4_SWOT" "$RUN_AC4_SWOT_2" "strength" "teamkompetenz" "last30days" > /dev/null
create_swot_item "$DB_AC4_SWOT" "$RUN_AC4_SWOT_2" "threat" "regulierung" "last30days" > /dev/null
OUT_AC4_SWOT_2="$TMP/ac4_swot_2.out"
RA_DB_PATH="$DB_AC4_SWOT" \
  bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC4_SWOT" "$RUN_AC4_SWOT_2" "Research/PM_Artifacts_swot_2" > "$OUT_AC4_SWOT_2" 2>/dev/null

EXPECTED_SWOT_DELTA_AC4='{"added":[["threat","regulierung"]],"removed":[["threat","wettbewerbsintensitaet"]],"by_category":{"threat":{"added":1,"removed":1}}}'
ACTUAL_SWOT_DELTA_AC4="$(sqlite3 "$DB_AC4_SWOT" "SELECT swot_delta FROM ra_divergence WHERE from_run_id = $RUN_AC4_SWOT_1 AND to_run_id = $RUN_AC4_SWOT_2;")"
if [ "$ACTUAL_SWOT_DELTA_AC4" = "$EXPECTED_SWOT_DELTA_AC4" ] \
  && grep -qF "$EXPECTED_SWOT_DELTA_AC4" "$OUT_AC4_SWOT_2"; then
  ok "Divergenz-Ausweis materialisiert + rendert das echte SWOT-Delta (added 'threat/regulierung', removed 'threat/wettbewerbsintensitaet', unveraendertes 'strength/teamkompetenz' bleibt aussen vor) strukturiert (AC4)"
else
  bad "erwartetes swot_delta '$EXPECTED_SWOT_DELTA_AC4', bekam '$ACTUAL_SWOT_DELTA_AC4' (Output: $(cat "$OUT_AC4_SWOT_2"))"
fi

echo "== @trace gate-pm-anstoss#AC3,AC4 -- orchestrator.sh dispatch_pm_anstoss: zwei VERSCHIEDENE Laeufe mit IDENTISCHEM result_hash duerfen keine CHECK-Constraint-Verletzung in ra_divergence ausloesen (Reviewer-Fund S-019 Iteration 2) =="
# Normaler AC3-Wiederholungsfall UEBER EINEN NEUEN LAUF (nicht dieselbe run_id
# erneut uebergeben, sondern ein Recherche-Rerun ohne inhaltliche Aenderung):
# create_run erzwingt KEINE Hash-Eindeutigkeit pro Thema
# (UNIQUE(topic_id,kind,version) erlaubt beliebig viele Laeufe mit gleichem
# Hash). dispatch_pm_handoff liefert fuer den zweiten Lauf rc=2 (Idempotenz
# ueber (topic_id,result_hash)), OHNE einen neuen ra_pm_dispatch-Eintrag
# anzulegen -- get_latest_pm_dispatch findet daher trotzdem den AELTEREN Lauf
# (RUN_1) als "Vorlauf", und materialize_and_render_divergence versucht, eine
# Divergenz mit is_empty=1 (gleicher Hash) UND von compute_swot_delta/
# compute_milestone_delta gelieferten NICHT-NULL-Delta-Strings anzulegen (beide
# Funktionen liefern IMMER ein JSON-Objekt, auch ohne SWOT-Items). Der
# CHECK-Constraint in 005_ra_divergence.sql (is_empty=0 ODER beide Deltas NULL)
# verlangt, dass create_divergence die vom Aufrufer gelieferten Deltas selbst
# verwirft, sobald es is_empty=1 feststellt.
DB_AC4_SAMEHASH="$(new_migrated_db "$TMP/ac4-samehash.sqlite")"
TOPIC_AC4_SAMEHASH="$(create_topic "$DB_AC4_SAMEHASH" "Thema fuer AC4 gleicher Hash ueber zwei Laeufe" 2>/dev/null)"
SAMEHASH_AC4="9988888888888888888888888888888888888888888888888888888888888888"

RUN_AC4_SAMEHASH_1_FULL="$(create_run "$DB_AC4_SAMEHASH" "$TOPIC_AC4_SAMEHASH" "recherche" "$SAMEHASH_AC4" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC4_SAMEHASH_1="${RUN_AC4_SAMEHASH_1_FULL%%|*}"
RA_DB_PATH="$DB_AC4_SAMEHASH" bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC4_SAMEHASH" "$RUN_AC4_SAMEHASH_1" "Research/PM_Artifacts_samehash_1" > /dev/null 2>&1

RUN_AC4_SAMEHASH_2_FULL="$(create_run "$DB_AC4_SAMEHASH" "$TOPIC_AC4_SAMEHASH" "recherche" "$SAMEHASH_AC4" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC4_SAMEHASH_2="${RUN_AC4_SAMEHASH_2_FULL%%|*}"
OUT_AC4_SAMEHASH_2="$TMP/ac4_samehash_2.out"
rc_ac4_samehash=0
RA_DB_PATH="$DB_AC4_SAMEHASH" \
  bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC4_SAMEHASH" "$RUN_AC4_SAMEHASH_2" "Research/PM_Artifacts_samehash_2" > "$OUT_AC4_SAMEHASH_2" 2>&1 || rc_ac4_samehash=$?

DIVERGENCE_ROW_SAMEHASH="$(sqlite3 -separator '|' "$DB_AC4_SAMEHASH" "SELECT is_empty, swot_delta, milestone_status_delta FROM ra_divergence WHERE from_run_id = $RUN_AC4_SAMEHASH_1 AND to_run_id = $RUN_AC4_SAMEHASH_2;")"
if [ "$rc_ac4_samehash" = "2" ] && [ "$DIVERGENCE_ROW_SAMEHASH" = "1||" ] \
  && grep -q "Divergenz-Ausweis" "$OUT_AC4_SAMEHASH_2"; then
  ok "zwei verschiedene Laeufe mit identischem result_hash: idempotenter Dispatch (rc=2) materialisiert die Divergenz mit is_empty=1 und NULL-Deltas OHNE CHECK-Constraint-Verletzung (AC3/AC4, Reviewer-Fund S-019 Iteration 2)"
else
  bad "erwartete rc=2 mit is_empty=1 und NULL-Deltas ('1||'), bekam rc=$rc_ac4_samehash row='$DIVERGENCE_ROW_SAMEHASH' out=$(cat "$OUT_AC4_SAMEHASH_2")"
fi

echo "== @trace gate-pm-anstoss#AC4 -- orchestrator.sh dispatch_pm_anstoss: scheitert die Divergenz-Materialisierung NACHDEM Dispatch+Statuswechsel bereits committet sind, wird das als Warnung gemeldet statt als rc=1 (Reviewer-Fund S-019 Iteration 3) =="
# In der Praxis nur ueber zwei ECHT gleichzeitige dispatch_pm_anstoss-Aufrufe
# auf dasselbe Vorlauf/Folgelauf-Paar erreichbar (TOCTOU zwischen
# get_divergence und create_divergence, UNIQUE(from_run_id,to_run_id)) --
# hier deterministisch simuliert, indem materialize_and_render_divergence
# in-process (orchestrator.sh ist oben bereits gesourced) durch einen
# fehlschlagenden Stub ersetzt wird, statt eine echte, timing-abhaengige
# Race-Condition zu erzwingen.
DB_AC4_DIVFAIL="$(new_migrated_db "$TMP/ac4-divfail.sqlite")"
TOPIC_AC4_DIVFAIL="$(create_topic "$DB_AC4_DIVFAIL" "Thema fuer AC4 Divergenz-Materialisierungs-Fehlschlag" 2>/dev/null)"

RUN_AC4_DIVFAIL_1_FULL="$(create_run "$DB_AC4_DIVFAIL" "$TOPIC_AC4_DIVFAIL" "recherche" "aa11111111111111111111111111111111111111111111111111111111111111" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC4_DIVFAIL_1="${RUN_AC4_DIVFAIL_1_FULL%%|*}"
RA_DB_PATH="$DB_AC4_DIVFAIL" bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC4_DIVFAIL" "$RUN_AC4_DIVFAIL_1" "Research/PM_Artifacts_divfail_1" > /dev/null 2>&1

RUN_AC4_DIVFAIL_2_FULL="$(create_run "$DB_AC4_DIVFAIL" "$TOPIC_AC4_DIVFAIL" "recherche" "bb22222222222222222222222222222222222222222222222222222222222222" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC4_DIVFAIL_2="${RUN_AC4_DIVFAIL_2_FULL%%|*}"

materialize_and_render_divergence() {
  echo "FATAL: simulierter Divergenz-Materialisierungs-Fehlschlag fuer Testzwecke (S-019 Iteration 3)." >&2
  return 1
}

OUT_AC4_DIVFAIL_2="$TMP/ac4_divfail_2.out"
ERR_AC4_DIVFAIL_2="$TMP/ac4_divfail_2.err"
rc_ac4_divfail=0
dispatch_pm_anstoss "$DB_AC4_DIVFAIL" "$TOPIC_AC4_DIVFAIL" "$RUN_AC4_DIVFAIL_2" "Research/PM_Artifacts_divfail_2" > "$OUT_AC4_DIVFAIL_2" 2> "$ERR_AC4_DIVFAIL_2" || rc_ac4_divfail=$?

# Echte materialize_and_render_divergence-Definition fuer alle nachfolgenden
# Tests wiederherstellen (Re-Sourcing loest KEIN main() aus -- BASH_SOURCE-Guard
# am Skriptende).
source "$RESEARCH_DIR/scripts/orchestrator.sh"

DISPATCH_COUNT_DIVFAIL="$(sqlite3 "$DB_AC4_DIVFAIL" "SELECT COUNT(*) FROM ra_pm_dispatch WHERE topic_id = '$TOPIC_AC4_DIVFAIL';")"
STATUS_DIVFAIL="$(sqlite3 "$DB_AC4_DIVFAIL" "SELECT status FROM ra_topic WHERE id = '$TOPIC_AC4_DIVFAIL';")"

if [ "$rc_ac4_divfail" = "0" ] && [ "$DISPATCH_COUNT_DIVFAIL" = "2" ] && [ "$STATUS_DIVFAIL" = "im_pm" ] \
  && grep -q "WARNUNG" "$ERR_AC4_DIVFAIL_2" \
  && ! grep -q "kein Statuswechsel\|Statuswechsel wird nicht durchgefuehrt" "$OUT_AC4_DIVFAIL_2" "$ERR_AC4_DIVFAIL_2"; then
  ok "Divergenz-Materialisierungs-Fehlschlag NACH bereits committetem Dispatch+Statuswechsel wird als Warnung gemeldet, nicht als rc=1 re-exportiert (Reviewer-Fund S-019 Iteration 3)"
else
  bad "erwartete rc=0/dispatch_count=2/status=im_pm + WARNUNG in stderr ohne 'kein Statuswechsel'-Text, bekam rc=$rc_ac4_divfail dispatch_count=$DISPATCH_COUNT_DIVFAIL status=$STATUS_DIVFAIL out=$(cat "$OUT_AC4_DIVFAIL_2") err=$(cat "$ERR_AC4_DIVFAIL_2")"
fi

echo "== @trace gate-pm-anstoss#AC4,AC5 -- orchestrator.sh dispatch_pm_anstoss: Abbruch ZWISCHEN dispatch_pm_handoff-COMMIT und Divergenz-Materialisierung wird bei Neustart nachgeholt =="
# Abbruch-Simulation: dispatch_pm_handoff() wird HIER direkt (nicht ueber
# dispatch_pm_anstoss) fuer den ZWEITEN (divergenten) Lauf aufgerufen -- das
# bildet den Zustand nach, den ein Prozessabbruch GENAU zwischen dem
# dispatch_pm_handoff-COMMIT und der nachfolgenden Divergenz-Materialisierung
# hinterlaesst: ra_pm_dispatch traegt den neuen Eintrag bereits, ra_divergence
# zum Vorlauf existiert aber noch NICHT.
DB_AC4_ABORT="$(new_migrated_db "$TMP/ac4-abort.sqlite")"
TOPIC_AC4_ABORT="$(create_topic "$DB_AC4_ABORT" "Thema fuer AC4 Abbruch-Neustart" 2>/dev/null)"
RUN_AC4_ABORT_1_FULL="$(create_run "$DB_AC4_ABORT" "$TOPIC_AC4_ABORT" "recherche" "ee55555555555555555555555555555555555555555555555555555555555555" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC4_ABORT_1="${RUN_AC4_ABORT_1_FULL%%|*}"
RA_DB_PATH="$DB_AC4_ABORT" bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC4_ABORT" "$RUN_AC4_ABORT_1" "Research/PM_Artifacts_abort_1" > /dev/null 2>&1

RUN_AC4_ABORT_2_FULL="$(create_run "$DB_AC4_ABORT" "$TOPIC_AC4_ABORT" "recherche" "ff66666666666666666666666666666666666666666666666666666666666666" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC4_ABORT_2="${RUN_AC4_ABORT_2_FULL%%|*}"
ARTIFACT_REF_AC4_ABORT_2="Research/PM_Artifacts_abort_2"
RESULT_HASH_AC4_ABORT_2="ff66666666666666666666666666666666666666666666666666666666666666"

# "Abbruch": nur das Bookkeeping (dispatch_pm_handoff), OHNE die Divergenz-
# Materialisierung, die im echten dispatch_pm_anstoss-Pfad erst danach liefe.
dispatch_pm_handoff "$DB_AC4_ABORT" "$TOPIC_AC4_ABORT" "$RUN_AC4_ABORT_2" "$RESULT_HASH_AC4_ABORT_2" "$ARTIFACT_REF_AC4_ABORT_2" > /dev/null 2>&1
DIVERGENCE_COUNT_PRE_ABORT="$(sqlite3 "$DB_AC4_ABORT" "SELECT COUNT(*) FROM ra_divergence WHERE from_run_id = $RUN_AC4_ABORT_1 AND to_run_id = $RUN_AC4_ABORT_2;")"
if [ "$DIVERGENCE_COUNT_PRE_ABORT" != "0" ]; then
  bad "Abbruch-Simulation fehlgeschlagen: erwartete 0 Divergenz-Zeilen VOR dem Neustart, bekam $DIVERGENCE_COUNT_PRE_ABORT"
fi

# Neustart: identischer Aufruf (gleicher Hash, also rc=2 -- der Dispatch selbst
# ist ja bereits committet) ueber den echten dispatch_pm_anstoss-Pfad -- muss die
# ausstehende Divergenz-Materialisierung nachholen, OHNE ein zweites
# ra_pm_dispatch-Artefakt anzulegen.
OUT_AC4_ABORT_RESTART="$TMP/ac4_abort_restart.out"
rc_ac4_abort=0
RA_DB_PATH="$DB_AC4_ABORT" \
  bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC4_ABORT" "$RUN_AC4_ABORT_2" "$ARTIFACT_REF_AC4_ABORT_2" > "$OUT_AC4_ABORT_RESTART" 2>&1 || rc_ac4_abort=$?
DIVERGENCE_COUNT_POST_ABORT="$(sqlite3 "$DB_AC4_ABORT" "SELECT COUNT(*) FROM ra_divergence WHERE from_run_id = $RUN_AC4_ABORT_1 AND to_run_id = $RUN_AC4_ABORT_2;")"
DISPATCH_COUNT_POST_ABORT="$(sqlite3 "$DB_AC4_ABORT" "SELECT COUNT(*) FROM ra_pm_dispatch WHERE topic_id = '$TOPIC_AC4_ABORT';")"
if [ "$rc_ac4_abort" = "2" ] && [ "$DIVERGENCE_COUNT_POST_ABORT" = "1" ] && [ "$DISPATCH_COUNT_POST_ABORT" = "2" ] \
  && grep -q "Divergenz-Ausweis" "$OUT_AC4_ABORT_RESTART"; then
  ok "Neustart nach simuliertem Abbruch zwischen Dispatch-COMMIT und Divergenz-Materialisierung: ausstehende ra_divergence-Zeile wird NACHGEHOLT (genau 1, kein Duplikat), kein zweites ra_pm_dispatch-Artefakt (AC4/AC5, gefahrloser Neustart)"
else
  bad "erwartete rc=2/divergence_count=1/dispatch_count=2, bekam rc=$rc_ac4_abort divergence_count=$DIVERGENCE_COUNT_POST_ABORT dispatch_count=$DISPATCH_COUNT_POST_ABORT out=$(cat "$OUT_AC4_ABORT_RESTART")"
fi

echo "== @trace gate-pm-anstoss#AC2,BR-102 -- orchestrator.sh dispatch_pm_anstoss: Vorbedingung 'recommendation=weiterverfolgen' wird geprueft =="
# Neues Thema mit Empfehlung 'parken'
DB_AC2_COND="$(new_migrated_db "$TMP/ac2-cond.sqlite")"
TOPIC_AC2_COND="$(create_topic "$DB_AC2_COND" "Thema mit Empfehlung parken" 2>/dev/null)"
RUN_AC2_COND_FULL="$(create_run "$DB_AC2_COND" "$TOPIC_AC2_COND" "recherche" "db761c12aa31c1e37cd9a5f6e7f8a9b9c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8" "parken" "0" "1" 2>/dev/null)"
RUN_AC2_COND="${RUN_AC2_COND_FULL%%|*}"  # Extract id from id|version

OUT_AC2_COND="$TMP/ac2_cond.txt"
ERR_AC2_COND="$TMP/ac2_cond.err"
rc_cond=0
RA_DB_PATH="$DB_AC2_COND" \
  bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC2_COND" "$RUN_AC2_COND" "Research/PM_Artifacts_cond" > "$OUT_AC2_COND" 2> "$ERR_AC2_COND" || rc_cond=$?
if [ "$rc_cond" != "0" ] && grep -qi "weiterverfolgen" "$ERR_AC2_COND"; then
  ok "Vorbedingung 'recommendation=weiterverfolgen' wird geprueft und durchgesetzt (AC2, BR-102)"
else
  bad "erwartete rc!=0 + Fehler-Meldung mit 'weiterverfolgen', bekam rc=$rc_cond err=$(cat "$ERR_AC2_COND")"
fi

echo "== @trace gate-pm-anstoss#AC6 -- orchestrator.sh check_artifact_hash: kein Vorlauf-PM-Anstoss -- kein Hash-Vergleich noetig, Skill-Dispatch darf starten =="
DB_AC6_NOPREV="$(new_migrated_db "$TMP/ac6-noprev.sqlite")"
TOPIC_AC6_NOPREV="$(create_topic "$DB_AC6_NOPREV" "Thema ohne PM-Vorlauf" 2>/dev/null)"
OUT_AC6_NOPREV="$TMP/ac6_noprev.txt"
rc_ac6_noprev=0
RA_DB_PATH="$DB_AC6_NOPREV" \
  bash "$ORCHESTRATOR_SCRIPT" check_artifact_hash "$TOPIC_AC6_NOPREV" "irgendein-aktueller-hash" > "$OUT_AC6_NOPREV" 2>&1 || rc_ac6_noprev=$?
if [ "$rc_ac6_noprev" = "0" ] && grep -qi "Kein Vorlauf" "$OUT_AC6_NOPREV"; then
  ok "check_artifact_hash: kein Vorlauf -> rc=0, kein Vergleich noetig (AC6, Erst-Anstoss)"
else
  bad "erwartete rc=0 + 'Kein Vorlauf'-Meldung, bekam rc=$rc_ac6_noprev out=$(cat "$OUT_AC6_NOPREV")"
fi

echo "== @trace gate-pm-anstoss#AC6,security/R03 -- orchestrator.sh check_artifact_hash: ungueltige Themen-ID wird vor SQL-Interpolation abgelehnt =="
ERR_AC6_BADID="$TMP/ac6_badid.err"
rc_ac6_badid=0
RA_DB_PATH="$DB_AC6_NOPREV" \
  bash "$ORCHESTRATOR_SCRIPT" check_artifact_hash "not-a-uuid" "irgendein-hash" > /dev/null 2> "$ERR_AC6_BADID" || rc_ac6_badid=$?
if [ "$rc_ac6_badid" = "1" ] && grep -qi "UUID-Format" "$ERR_AC6_BADID"; then
  ok "check_artifact_hash: ungueltige Themen-ID wird vor SQL-Interpolation abgelehnt (security/R03)"
else
  bad "erwartete rc=1 + UUID-Format-Fehler, bekam rc=$rc_ac6_badid err=$(cat "$ERR_AC6_BADID")"
fi

echo "== @trace gate-pm-anstoss#AC6 -- orchestrator.sh dispatch_pm_anstoss speichert [artifact-hash]; check_artifact_hash: uebereinstimmender Hash -> rc=0, keine manuelle Vault-Aenderung erkannt =="
DB_AC6="$(new_migrated_db "$TMP/ac6-match.sqlite")"
TOPIC_AC6="$(create_topic "$DB_AC6" "Thema fuer AC6 Hash-Match" 2>/dev/null)"
RUN_AC6_FULL="$(create_run "$DB_AC6" "$TOPIC_AC6" "recherche" "fa761c12aa31c1e37cd9a5f6e7f8a9b9c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC6="${RUN_AC6_FULL%%|*}"
ARTIFACT_REF_AC6="Research/PM_Artifacts_${TOPIC_AC6}_${RUN_AC6}"
ARTIFACT_HASH_AC6="deadbeef00112233445566778899aabbccddeeff0011223344556677889900"

RA_DB_PATH="$DB_AC6" \
  bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC6" "$RUN_AC6" "$ARTIFACT_REF_AC6" "$ARTIFACT_HASH_AC6" > /dev/null 2>&1

STORED_HASH_AC6="$(sqlite3 "$DB_AC6" "SELECT artifact_hash FROM ra_pm_dispatch WHERE topic_id = '$TOPIC_AC6';")"
if [ "$STORED_HASH_AC6" = "$ARTIFACT_HASH_AC6" ]; then
  ok "dispatch_pm_anstoss speichert das gelieferte [artifact-hash] in ra_pm_dispatch.artifact_hash (AC6)"
else
  bad "erwartetes artifact_hash=$ARTIFACT_HASH_AC6, bekam '$STORED_HASH_AC6'"
fi

OUT_AC6_MATCH="$TMP/ac6_match.txt"
rc_ac6_match=0
RA_DB_PATH="$DB_AC6" \
  bash "$ORCHESTRATOR_SCRIPT" check_artifact_hash "$TOPIC_AC6" "$ARTIFACT_HASH_AC6" > "$OUT_AC6_MATCH" 2>&1 || rc_ac6_match=$?
if [ "$rc_ac6_match" = "0" ] && grep -qi "stimmt.*ueberein" "$OUT_AC6_MATCH"; then
  ok "check_artifact_hash: uebereinstimmender Hash -> rc=0, keine manuelle Vault-Aenderung erkannt (AC6)"
else
  bad "erwartete rc=0 + Uebereinstimmungs-Meldung, bekam rc=$rc_ac6_match out=$(cat "$OUT_AC6_MATCH")"
fi

echo "== @trace gate-pm-anstoss#AC6 -- orchestrator.sh check_artifact_hash: Hash-Mismatch -> rc=3, Rueckfrage statt stillem Ueberschreiben =="
ERR_AC6_MISMATCH="$TMP/ac6_mismatch.err"
rc_ac6_mismatch=0
RA_DB_PATH="$DB_AC6" \
  bash "$ORCHESTRATOR_SCRIPT" check_artifact_hash "$TOPIC_AC6" "0000000000000000000000000000000000000000000000000000000000" > /dev/null 2> "$ERR_AC6_MISMATCH" || rc_ac6_mismatch=$?
if [ "$rc_ac6_mismatch" = "3" ] && grep -qi "RUECKFRAGE" "$ERR_AC6_MISMATCH" && grep -qi "manuell" "$ERR_AC6_MISMATCH"; then
  ok "check_artifact_hash: Hash-Mismatch -> rc=3, Rueckfrage-Meldung statt stillem Ueberschreiben (AC6, PRD Edge)"
else
  bad "erwartete rc=3 + RUECKFRAGE-Meldung, bekam rc=$rc_ac6_mismatch err=$(cat "$ERR_AC6_MISMATCH")"
fi

echo "== @trace gate-pm-anstoss#AC6 -- orchestrator.sh check_artifact_hash: Vorlauf ohne bekannten artifact_hash (Alt-Dispatch vor S-020) -> rc=0, kein falscher Mismatch-Alarm =="
DB_AC6_LEGACY="$(new_migrated_db "$TMP/ac6-legacy.sqlite")"
TOPIC_AC6_LEGACY="$(create_topic "$DB_AC6_LEGACY" "Thema mit Alt-Dispatch ohne Hash" 2>/dev/null)"
RUN_AC6_LEGACY_FULL="$(create_run "$DB_AC6_LEGACY" "$TOPIC_AC6_LEGACY" "recherche" "ab761c12aa31c1e37cd9a5f6e7f8a9b9c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8" "weiterverfolgen" "0" "1" 2>/dev/null)"
RUN_AC6_LEGACY="${RUN_AC6_LEGACY_FULL%%|*}"

RA_DB_PATH="$DB_AC6_LEGACY" \
  bash "$ORCHESTRATOR_SCRIPT" dispatch_pm_anstoss "$TOPIC_AC6_LEGACY" "$RUN_AC6_LEGACY" "Research/PM_Artifacts_legacy" > /dev/null 2>&1
# Bewusst KEIN 5. Argument (artifact-hash) -- simuliert einen Alt-Dispatch vor S-020

OUT_AC6_LEGACY="$TMP/ac6_legacy.txt"
rc_ac6_legacy=0
RA_DB_PATH="$DB_AC6_LEGACY" \
  bash "$ORCHESTRATOR_SCRIPT" check_artifact_hash "$TOPIC_AC6_LEGACY" "irgendein-aktueller-hash" > "$OUT_AC6_LEGACY" 2>&1 || rc_ac6_legacy=$?
if [ "$rc_ac6_legacy" = "0" ] && grep -qi "keinen bekannten artifact_hash" "$OUT_AC6_LEGACY"; then
  ok "check_artifact_hash: Alt-Dispatch ohne artifact_hash -> rc=0, kein falscher Mismatch-Alarm (AC6)"
else
  bad "erwartete rc=0 + 'keinen bekannten artifact_hash'-Meldung, bekam rc=$rc_ac6_legacy out=$(cat "$OUT_AC6_LEGACY")"
fi

echo
echo "Ergebnis: $pass OK, $fail FAIL"
[ "$fail" -eq 0 ]
