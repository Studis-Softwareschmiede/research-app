#!/usr/bin/env bash
# watchlist_pass.sh — Watchlist-Pass (M3, architecture.md-Komponente
# "Watchlist/Wiedervorlage").
#
# Quelle: docs/specs/wiedervorlage-meilensteine.md AC2 ("Externe Meilensteine
# (responsibility=extern) tragen eine Watchlist-Referenz (BR-015) und werden
# vom Watchlist-Job geprueft; 'Delta' = das last30days-Delta-Signal,
# OF-12-Entscheid"), AC6 ("Nebenlaeufigkeit: der Watchlist-Job respektiert die
# Themen-Sperre (BR-019) und serialisiert sich gegen manuelle Laeufe"),
# E2 ("last30days-Watchlist nicht verfuegbar -> externe Meilensteine werden
# als 'manuell zu pruefen' gemeldet, kein Crash").
#
# SCOPE (S-013, NUR AC2+AC6): dieser Pass ENDET beim GEPRUEFTEN Delta-/
# Erfuellungs-Signal je externem Meilenstein -- er AENDERT WEDER
# ra_milestone.status NOCH ra_topic.status. Die automatische Wiedervorlage
# (geparkt -> aktiv bei erfuelltem Meilenstein/Delta, AC3) und die volle
# AC4-Markierung "nicht automatisch pruefbarer Meilenstein bleibt sichtbar
# markiert" sind Folge-Stories (S-014/S-015) -- hier gilt nur die
# E2-Teilmenge "last30days-Watchlist nicht erreichbar -> Klartext-Meldung,
# kein Absturz". Kein eigenes Delta-Scoring (Nicht-Ziel): das last30days-
# eigene Delta-Ergebnis (status/new aus watchlist_client.sh#check_watchlist_delta)
# wird nur reportiert, nicht neu bewertet.
#
# Idempotenz (NFR): dieser Pass mutiert NICHTS (reiner Lese-/Report-Pfad) --
# mehrfaches Ausfuehren gegen denselben Stand erzeugt daher strukturell keine
# Doppel-Wirkung (kein Schreibzugriff, den ein zweiter Lauf verdoppeln
# koennte).
#
# Kein eigener Scheduler (Nicht-Ziel, C-002): dieses Skript ist ein
# eigenstaendiger Einstiegspunkt (analog orchestrator.sh/db_scripts/migrate.sh)
# -- ein EXTERNER Scheduler (cron o.ae.) stoesst es an; keine eigene
# Tageslauf-/Cadence-Logik hier (last30days selbst loest das identisch:
# watchlist.py run-all wird ebenfalls extern angestossen).
#
# Boundary-Konformitaet (architecture.md, Review-Blocker): dieses Skript
# beruehrt SQLite NIE direkt -- jede Meilenstein-/Sperren-Abfrage laeuft
# ausschliesslich ueber db_scripts/lib/milestone.sh (list_watchlist_candidates)
# und db_scripts/lib/topic_lock.sh (acquire_topic_lock/release_topic_lock).
# last30days wird ausschliesslich ueber lib/watchlist_client.sh aufgerufen
# (Watchlist-Pass ist neben Discovery/Ingest die einzige last30days-Aufruferin,
# Boundary 2).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=lib/watchlist_client.sh
source "$SCRIPT_DIR/lib/watchlist_client.sh"
# shellcheck source=../../../db_scripts/lib/topic_lock.sh
source "$REPO_ROOT/db_scripts/lib/topic_lock.sh"
# shellcheck source=../../../db_scripts/lib/milestone.sh
source "$REPO_ROOT/db_scripts/lib/milestone.sh"

RA_DB_PATH="${RA_DB_PATH:-research-app.sqlite}"
RA_LOCK_TTL_SECONDS="${RA_LOCK_TTL_SECONDS:-1800}"
WATCHLIST_LOCK_HOLDER="watchlist"

# fetch_watchlist_delta <cmd-or-empty> <watch-ref>
# Fuehrt GENAU den externen last30days-Aufruf aus -- der Aufrufer (siehe
# run_watchlist_pass) haelt zu diesem Zeitpunkt die Themen-Sperre und gibt sie
# UNMITTELBAR NACH dieser Funktion wieder frei, VOR jeder lokalen JSON-
# Auswertung (Reviewer-Fund Iteration 1, S-013: "Lock nur minimal halten und
# releasen, bevor die JSON-Auswertung laeuft", analog orchestrator.sh#
# research_thema, S-007: die Sperre schuetzt nur den externen Aufruf selbst,
# nicht die anschliessende lokale Nachverarbeitung).
#
# Gibt IMMER (rc=0) eine Zeile "fetch_rc<0x1f>json_file<0x1f>err_file" auf
# stdout aus -- Fehler werden ausschliesslich ueber den eingebetteten
# fetch_rc-Wert transportiert, NIE ueber den Funktions-Returncode, damit der
# Aufrufer unter `set -e` niemals abbricht, waehrend er die Sperre haelt.
# "<cmd-or-empty>" leer (last30days-Watchlist fuer den gesamten Pass nicht
# aufloesbar, E2) liefert fetch_rc=127 (Sentinel "nicht versucht"), ohne
# ueberhaupt aufzurufen.
fetch_watchlist_delta() {
  local cmd="$1"
  local watch_ref="$2"
  local json_file err_file rc

  json_file="$(mktemp)"
  err_file="$(mktemp)"

  if [ -z "$cmd" ]; then
    printf '127\x1f%s\x1f%s' "$json_file" "$err_file"
    return 0
  fi

  set +e
  check_watchlist_delta "$cmd" "$watch_ref" > "$json_file" 2> "$err_file"
  rc=$?
  set -e

  printf '%s\x1f%s\x1f%s' "$rc" "$json_file" "$err_file"
  return 0
}

# report_watchlist_result <topic-id> <milestone-id> <watch-ref> <cmd-or-empty>
#                          <fetch-rc> <json-file> <err-file>
# Interpretiert ein BEREITS eingesammeltes last30days-Watchlist-Ergebnis (die
# Themen-Sperre ist zu diesem Zeitpunkt laengst wieder frei, siehe
# run_watchlist_pass) und gibt eine Klartext-Report-Zeile auf stdout aus --
# KEINE Statusaenderung (Scope-Grenze S-013, siehe Datei-Header). Reine lokale
# Verarbeitung (JSON-Parsing ueber sqlite3 ':memory:', beide Extraktionen
# zusaetzlich defensiv per set+e/-e gekapselt, Reviewer-Fund Iteration 1) --
# kann NIE mehr zu einer haengenden Sperre fuehren, selbst wenn ein Schritt
# hier fehlschlaegt. rc ist immer 0.
report_watchlist_result() {
  local topic_id="$1"
  local milestone_id="$2"
  local watch_ref="$3"
  local cmd="$4"
  local fetch_rc="$5"
  local json_file="$6"
  local err_file="$7"
  local status new_count escaped_path status_rc new_count_rc

  if [ -z "$cmd" ]; then
    echo "Meilenstein $milestone_id (Thema $topic_id, Watchlist-Ref '$watch_ref'): last30days-Watchlist nicht verfuegbar -- manuell zu pruefen (E2)."
    return 0
  fi

  if [ "$fetch_rc" -ne 0 ]; then
    echo "Meilenstein $milestone_id (Thema $topic_id, Watchlist-Ref '$watch_ref'): last30days-Watchlist nicht verfuegbar -- manuell zu pruefen (E2): $(cat "$err_file" 2>/dev/null)"
    return 0
  fi

  escaped_path="${json_file//\'/\'\'}"
  set +e
  status="$(sqlite3 ':memory:' "SELECT COALESCE(json_extract(readfile('$escaped_path'), '\$.status'), '');" 2>/dev/null)"
  status_rc=$?
  new_count="$(sqlite3 ':memory:' "SELECT COALESCE(json_extract(readfile('$escaped_path'), '\$.new'), 0);" 2>/dev/null)"
  new_count_rc=$?
  set -e

  if [ "$status_rc" -ne 0 ] || [ "$new_count_rc" -ne 0 ]; then
    echo "Meilenstein $milestone_id (Thema $topic_id, Watchlist-Ref '$watch_ref'): last30days-Watchlist-Antwort konnte nicht ausgewertet werden -- manuell zu pruefen (E2)."
    return 0
  fi

  case "$status" in
    ok)
      if [ "${new_count:-0}" -gt 0 ] 2>/dev/null; then
        echo "Meilenstein $milestone_id (Thema $topic_id, Watchlist-Ref '$watch_ref'): Delta erkannt ($new_count neue(r) Fund(e), last30days-Signal)."
      else
        echo "Meilenstein $milestone_id (Thema $topic_id, Watchlist-Ref '$watch_ref'): kein Delta (last30days meldet 0 neue Funde)."
      fi
      ;;
    insufficient_history)
      echo "Meilenstein $milestone_id (Thema $topic_id, Watchlist-Ref '$watch_ref'): noch keine Vergleichs-Historie bei last30days -- kein Delta pruefbar."
      ;;
    *)
      echo "Meilenstein $milestone_id (Thema $topic_id, Watchlist-Ref '$watch_ref'): unbekannter last30days-Watchlist-Status '$status' -- manuell zu pruefen."
      ;;
  esac
  return 0
}

# run_watchlist_pass <db-path> [topic-id]
# AC2: prueft jeden offenen externen Meilenstein (watch_ref gesetzt) eines
# geparkten Themas ueber last30days-Watchlist (oder meldet E2, wenn die CLI
# nicht erreichbar ist). AC6: erwirbt je Meilenstein die Themen-Sperre
# (BR-019, holder='watchlist') VOR dem externen last30days-Aufruf und gibt sie
# UNMITTELBAR DANACH wieder frei -- vor jeder lokalen JSON-Auswertung (siehe
# fetch_watchlist_delta/report_watchlist_result-Kommentare, Reviewer-Fund
# Iteration 1: die Sperre darf nie durch einen fehlschlagenden lokalen
# Verarbeitungsschritt haengen bleiben). Ist das Thema bereits gesperrt (ein
# manueller /research-Lauf ist in Bearbeitung), wird DIESER Meilenstein fuer
# diesen Durchlauf uebersprungen (Klartext-Hinweis auf stderr), kein
# Doppel-Lauf, kein Abbruch des gesamten Passes (analog
# research_discovery#E3 in orchestrator.sh).
run_watchlist_pass() {
  local db="$1"
  local topic_filter="${2:-}"
  local cmd="" rc rows topic_id milestone_id watch_ref

  set +e
  cmd="$(resolve_last30days_watchlist_cmd)"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "WARNUNG: last30days-Watchlist ist fuer diesen Lauf nicht erreichbar -- alle offenen externen Meilensteine werden als 'manuell zu pruefen' gemeldet (E2)." >&2
    cmd=""
  fi

  rows="$(list_watchlist_candidates "$db" "$topic_filter")" || return 1
  if [ -z "$rows" ]; then
    echo "Keine offenen externen Meilensteine mit Watchlist-Referenz fuer geparkte Themen -- nichts zu pruefen."
    return 0
  fi

  while IFS=$'\x1f' read -r topic_id milestone_id watch_ref; do
    [ -z "$topic_id" ] && continue

    set +e
    acquire_topic_lock "$db" "$topic_id" "$WATCHLIST_LOCK_HOLDER" "$RA_LOCK_TTL_SECONDS"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      echo "UEBERSPRUNGEN: Thema $topic_id ist gerade in Bearbeitung (BR-019/AC6) -- kein Doppel-Lauf, Watchlist-Pruefung fuer diesen Meilenstein in diesem Durchlauf ausgelassen." >&2
      continue
    fi

    local fetch_line fetch_rc fetch_json fetch_err
    fetch_line="$(fetch_watchlist_delta "$cmd" "$watch_ref")"

    # Sperre SOFORT freigeben -- fetch_watchlist_delta liefert IMMER rc=0
    # (Fehler stecken im eingebetteten fetch_rc), daher ist an dieser Stelle
    # garantiert noch nichts abgebrochen; alles Folgende (Parsen der Zeile,
    # Report-Erzeugung) laeuft bereits lock-frei.
    release_topic_lock "$db" "$topic_id" "$WATCHLIST_LOCK_HOLDER" || true

    IFS=$'\x1f' read -r fetch_rc fetch_json fetch_err <<< "$fetch_line"

    report_watchlist_result "$topic_id" "$milestone_id" "$watch_ref" "$cmd" "$fetch_rc" "$fetch_json" "$fetch_err"
    rm -f "$fetch_json" "$fetch_err" 2>/dev/null || true
  done <<< "$rows"

  return 0
}

# Aufruf: watchlist_pass.sh [topic-id]
#
# Env:
#   RA_DB_PATH                  Pfad zur research-app.sqlite (Default: research-app.sqlite)
#   RA_LAST30DAYS_WATCHLIST_CMD Override fuer das last30days-Watchlist-Kommando
#                               (Default: Auto-Discovery von watchlist.py unter
#                               ~/.claude/skills/last30days, ~/.codex/skills/last30days
#                               bzw. dem Claude-Plugin-Cache, ausgefuehrt via
#                               LAST30DAYS_PYTHON/python3 -- siehe
#                               lib/watchlist_client.sh)
#   LAST30DAYS_PYTHON           Python-Interpreter fuer die Auto-Discovery (Default: python3)
#   RA_LOCK_TTL_SECONDS         Lock-TTL in Sekunden (Default: 1800)
# watchlist_pass_main -- eigener Name (NICHT "main"), weil
# skills/research/tests/run_tests.sh sowohl orchestrator.sh als auch dieses
# Skript sourced (Namenskollision-Fund S-013 Iteration 1: ein generisches
# "main" wuerde die zuletzt gesourcte Definition gewinnen lassen und
# orchestrator.sh#main -- inkl. dessen "evaluation"-Subcommand -- unsichtbar
# ueberschreiben).
watchlist_pass_main() {
  run_watchlist_pass "$RA_DB_PATH" "${1:-}"
}

# Nur ausfuehren, wenn direkt aufgerufen -- nicht beim Sourcen fuer Tests (die
# Testsuite sourced dieses Skript, um die einzelnen Funktionen isoliert
# aufzurufen, ohne watchlist_pass_main() auszuloesen).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  watchlist_pass_main "$@"
  exit $?
fi
