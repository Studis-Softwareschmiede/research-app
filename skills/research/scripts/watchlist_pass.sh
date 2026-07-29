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
# SCOPE (S-013, AC2+AC6; erweitert um S-014, AC3+AC5): der last30days-
# Watchlist-Aufruf selbst bleibt reiner Lese-/Report-Pfad -- der last30days-
# eigene Delta-Wert (status/new aus watchlist_client.sh#check_watchlist_delta)
# wird 1:1 reportiert, nicht neu bewertet (kein eigenes Delta-Scoring,
# Nicht-Ziel). Wird dabei ein Delta erkannt (status=ok, new>0), gilt der
# geprüfte externe Meilenstein als erfüllt (OF-12: "Delta" ist bewusst KEIN
# eigener Schwellwert-Mechanismus neben der Meilenstein-Erfüllung, sondern
# DAS last30days-Signal, das sie auslöst) -- die Data-Access-Schicht setzt
# dann `ra_milestone.status='erfuellt'` (`db_scripts/lib/milestone.sh#
# set_milestone_status`) UND das Thema `geparkt -> aktiv` (BR-020,
# `db_scripts/lib/topic.sh#set_topic_status`, siehe
# `_reactivate_topic_on_delta` unten).
#
# AC4-Markierung (S-015, "nicht automatisch pruefbarer Meilenstein bleibt
# sichtbar als 'manuell zu pruefen' markiert -- keine stille
# Nicht-Pruefung"): `report_watchlist_result` deckt ALLE Faelle ab, in denen
# der Watchlist-Pass keinen verwertbaren last30days-Delta-Wert bekommt --
# last30days-Watchlist fuer den Pass nicht aufloesbar (leerer `cmd`, E2),
# last30days-Aufruf selbst schlaegt fehl (`fetch_rc<>0`, E2), die Antwort ist
# trotz `fetch_rc=0` kein gueltiges JSON, oder last30days meldet einen
# status-Wert ausserhalb von `{ok, insufficient_history}`: jeder dieser Faelle
# gibt eine Klartext-Zeile mit "manuell zu pruefen" aus und mutiert weder
# `ra_milestone` noch `ra_topic` (kein Scope-Uebergriff auf AC3). E2 ist damit
# eine TEILMENGE von AC4 (die reine Nichterreichbarkeits-Variante); AC4 selbst
# ist umfassender (jede Form von "extern nicht automatisch pruefbar").
#
# Idempotenz (NFR): die Reaktivierung selbst mutiert NUR, wenn das Thema noch
# `geparkt` ist (siehe `_reactivate_topic_on_delta`) -- list_watchlist_candidates
# liefert ein bereits reaktiviertes (jetzt `aktiv`es) Thema in keinem
# folgenden Lauf mehr als Kandidat (Filter `t.status='geparkt'`,
# `db_scripts/lib/milestone.sh#list_watchlist_candidates`), daher erzeugt
# mehrfaches Ausfuehren gegen denselben Stand strukturell keine
# Doppel-Wiedervorlage.
#
# Kein eigener Scheduler (Nicht-Ziel, C-002): dieses Skript ist ein
# eigenstaendiger Einstiegspunkt (analog orchestrator.sh/db_scripts/migrate.sh)
# -- ein EXTERNER Scheduler (cron o.ae.) stoesst es an; keine eigene
# Tageslauf-/Cadence-Logik hier (last30days selbst loest das identisch:
# watchlist.py run-all wird ebenfalls extern angestossen).
#
# Boundary-Konformitaet (architecture.md, Review-Blocker): dieses Skript
# beruehrt SQLite NIE direkt -- jede Meilenstein-/Themen-/Sperren-Mutation
# laeuft ausschliesslich ueber db_scripts/lib/milestone.sh
# (list_watchlist_candidates, set_milestone_status), db_scripts/lib/topic.sh
# (set_topic_status, S-014) und db_scripts/lib/topic_lock.sh
# (acquire_topic_lock/release_topic_lock). last30days wird ausschliesslich
# ueber lib/watchlist_client.sh aufgerufen (Watchlist-Pass ist neben
# Discovery/Ingest die einzige last30days-Aufruferin, Boundary 2).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=lib/watchlist_client.sh
source "$SCRIPT_DIR/lib/watchlist_client.sh"
# shellcheck source=../../../db_scripts/lib/topic_lock.sh
source "$REPO_ROOT/db_scripts/lib/topic_lock.sh"
# shellcheck source=../../../db_scripts/lib/milestone.sh
source "$REPO_ROOT/db_scripts/lib/milestone.sh"
# shellcheck source=../../../db_scripts/lib/topic.sh
source "$REPO_ROOT/db_scripts/lib/topic.sh"

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

# _reactivate_topic_on_delta <db> <topic-id> <milestone-id>
# AC3 (wiedervorlage-meilensteine): setzt den erkannten externen Meilenstein
# auf 'erfuellt' und das Thema von 'geparkt' auf 'aktiv' (Wiedervorlage,
# BR-020) -- geschuetzt durch die Themen-Sperre (BR-019), analog zum
# externen last30days-Aufruf oben (Minimal-Halte-Prinzip: die Sperre wird
# NUR waehrend der eigentlichen Schreiboperation gehalten, nicht waehrend der
# vorausgehenden JSON-Auswertung).
#
# Idempotent (NFR): mutiert NUR, wenn das Thema zu diesem Zeitpunkt noch
# 'geparkt' ist -- ein bereits wiedervorgelegtes (aktives) Thema erscheint
# ohnehin in keinem folgenden list_watchlist_candidates-Ergebnis mehr
# (Filter t.status='geparkt'), dieser Check ist die zusaetzliche Absicherung
# fuer direkte/wiederholte Aufrufe innerhalb desselben Durchlaufs.
#
# Ist das Thema gerade durch einen anderen Lauf gesperrt (z.B. ein manueller
# /research-Lauf), wird die Reaktivierung fuer DIESEN Durchlauf ausgelassen
# (kein Doppel-Lauf, BR-019) -- der naechste Watchlist-Pass holt nach (E1).
#
# rc=0 gdw. die Reaktivierung tatsaechlich durchgefuehrt wurde, sonst rc=1
# (kein eigener Fehlerfall -- entscheidet nur den Report-Text des Aufrufers).
_reactivate_topic_on_delta() {
  local db="$1"
  local topic_id="$2"
  local milestone_id="$3"
  local current_status lock_rc ms_rc topic_rc

  # UUID-Format-Guard VOR jeder SQL-Interpolation (security/R03, unconditional
  # -- auch wenn topic_id aus der vertrauenswuerdigen list_watchlist_candidates
  # stammt, siehe .claude/lessons/coder.md, Reviewer-Fund Iteration 2 S-014),
  # analog topic.sh#set_topic_status/milestone.sh#create_milestone|list_milestones|
  # list_watchlist_candidates.
  if ! [[ "$topic_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "FATAL: Themen-ID '$topic_id' verletzt das UUID-Format -- Reaktivierung abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  current_status="$(sqlite3 "$db" "SELECT status FROM ra_topic WHERE id = '$topic_id';" 2>/dev/null)"
  if [ "$current_status" != "geparkt" ]; then
    return 1
  fi

  set +e
  acquire_topic_lock "$db" "$topic_id" "$WATCHLIST_LOCK_HOLDER" "$RA_LOCK_TTL_SECONDS"
  lock_rc=$?
  set -e
  if [ "$lock_rc" -ne 0 ]; then
    echo "UEBERSPRUNGEN: Thema $topic_id ist gerade in Bearbeitung (BR-019) -- Wiedervorlage (AC3) fuer diesen Durchlauf ausgelassen, naechster Watchlist-Pass holt nach." >&2
    return 1
  fi

  # Zweiter, GESPERRTER Status-Check unmittelbar vor der ersten Schreiboperation
  # (Reviewer-Fund Iteration 2, S-014): der Vorab-Check oben lief VOR dem Lock
  # und ist deshalb selbst kein Schutz gegen einen nebenlaeufigen Statuswechsel
  # (TOCTOU) -- ohne diesen Re-Check koennte set_milestone_status das
  # 'erfuellt' bereits schreiben, bevor der (an sich geschuetzte) Statuswechsel
  # des Themas ueberhaupt versucht wird; schlaegt dieser dann fehl (Thema
  # zwischenzeitlich z.B. 'verworfen'), bliebe der Meilenstein dauerhaft
  # 'erfuellt', ohne dass das Thema je reaktiviert wurde -- Widerspruch zu
  # E1 ("kein Meilenstein geht verloren").
  current_status="$(sqlite3 "$db" "SELECT status FROM ra_topic WHERE id = '$topic_id';" 2>/dev/null)"
  if [ "$current_status" != "geparkt" ]; then
    release_topic_lock "$db" "$topic_id" "$WATCHLIST_LOCK_HOLDER" || true
    return 1
  fi

  set +e
  set_milestone_status "$db" "$milestone_id" "erfuellt" 2>/dev/null
  ms_rc=$?
  set_topic_status "$db" "$topic_id" "aktiv" 2>/dev/null
  topic_rc=$?
  set -e
  release_topic_lock "$db" "$topic_id" "$WATCHLIST_LOCK_HOLDER" || true

  [ "$ms_rc" -eq 0 ] && [ "$topic_rc" -eq 0 ]
}

# report_watchlist_result <db> <topic-id> <milestone-id> <watch-ref>
#                          <cmd-or-empty> <fetch-rc> <json-file> <err-file>
# Interpretiert ein BEREITS eingesammeltes last30days-Watchlist-Ergebnis (die
# Themen-Sperre ist zu diesem Zeitpunkt laengst wieder frei, siehe
# run_watchlist_pass) und gibt eine Klartext-Report-Zeile auf stdout aus.
# Reine lokale Verarbeitung (JSON-Parsing ueber sqlite3 ':memory:', beide
# Extraktionen zusaetzlich defensiv per set+e/-e gekapselt, Reviewer-Fund
# Iteration 1 S-013) -- kann NIE mehr zu einer haengenden Sperre fuehren,
# selbst wenn ein Schritt hier fehlschlaegt. Wird ein Delta erkannt (status=ok,
# new>0), loest diese Funktion zusaetzlich die AC3-Reaktivierung aus
# (_reactivate_topic_on_delta, holt sich die Themen-Sperre dafuer selbst
# erneut). rc ist immer 0.
report_watchlist_result() {
  local db="$1"
  local topic_id="$2"
  local milestone_id="$3"
  local watch_ref="$4"
  local cmd="$5"
  local fetch_rc="$6"
  local json_file="$7"
  local err_file="$8"
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
        if _reactivate_topic_on_delta "$db" "$topic_id" "$milestone_id"; then
          echo "Meilenstein $milestone_id (Thema $topic_id, Watchlist-Ref '$watch_ref'): Delta erkannt ($new_count neue(r) Fund(e), last30days-Signal) -- Meilenstein auf 'erfuellt' gesetzt, Thema wiedervorgelegt (geparkt -> aktiv, AC3/BR-020)."
        else
          echo "Meilenstein $milestone_id (Thema $topic_id, Watchlist-Ref '$watch_ref'): Delta erkannt ($new_count neue(r) Fund(e), last30days-Signal)."
        fi
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
# research_discovery#E3 in orchestrator.sh). AC3: erkennt report_watchlist_result
# ein Delta, wird das Thema automatisch wiedervorgelegt (geparkt -> aktiv,
# siehe _reactivate_topic_on_delta) -- da list_watchlist_candidates nur
# 'geparkt'e Themen liefert (AC5), scheidet ein bereits 'verworfen'es Thema
# fuer diese Reaktivierung strukturell aus (nie Wiedervorlage, BR-005/BR-020).
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

    report_watchlist_result "$db" "$topic_id" "$milestone_id" "$watch_ref" "$cmd" "$fetch_rc" "$fetch_json" "$fetch_err"
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
