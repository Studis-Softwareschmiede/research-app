#!/usr/bin/env bash
# orchestrator.sh — /research-Skill-Einstieg: Modus-Wahl (discovery|thema),
# Themen-Anlage ueber die Data-Access-Schicht, last30days-Aufruf,
# Quellen-Resilienz-Brief (research-skill#AC1,AC6,AC7, S-007-Grundgeruest).
#
# Quelle: docs/specs/research-skill.md AC1/AC6/AC7 + Edge-Cases E1/E3.
# docs/architecture.md "Orchestrator"-Komponente (Einstieg; waehlt Modus, ruft
# Paesse in Reihenfolge). SWOT-Judge/Deep-Research/Empfehlung/Voraussetzungs-
# Ueberblick (AC2-AC5) sind NICHT Teil dieser Story (S-008 ff. bauen auf diesem
# Grundgeruest auf).
#
# Boundary-Konformitaet (architecture.md, Review-Blocker): dieses Skript
# beruehrt SQLite NIE direkt -- jede Themen-Anlage/-Abfrage laeuft ausschliesslich
# ueber db_scripts/lib/topic.sh (create_topic/find_topic_by_title) und die
# Sperre ueber db_scripts/lib/topic_lock.sh (acquire_topic_lock/
# release_topic_lock). last30days wird ausschliesslich ueber
# lib/last30days_client.sh aufgerufen (Discovery/Ingest-Pass).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=lib/last30days_client.sh
source "$SCRIPT_DIR/lib/last30days_client.sh"
# shellcheck source=../../../db_scripts/lib/topic.sh
source "$REPO_ROOT/db_scripts/lib/topic.sh"
# shellcheck source=../../../db_scripts/lib/topic_lock.sh
source "$REPO_ROOT/db_scripts/lib/topic_lock.sh"

RA_DB_PATH="${RA_DB_PATH:-research-app.sqlite}"
RA_SAVE_DIR="${RA_SAVE_DIR:-last30days-runs}"
RA_LOCK_HOLDER="${RA_LOCK_HOLDER:-research}"
RA_LOCK_TTL_SECONDS="${RA_LOCK_TTL_SECONDS:-1800}"

# check_store_or_die <db-path>
# E1 ("Store fehlt"): prueft VOR jedem last30days-Aufruf, ob die eigene
# research-app.sqlite existiert UND migriert ist (Tabelle ra_topic vorhanden)
# -- "kein Halb-Lauf" (sonst wuerde last30days bereits einen Lauf gefahren
# haben, bevor die anschliessende Persistenz scheitert). Delegiert die
# eigentliche Pruefung an db_scripts/lib/topic.sh#ra_topic_store_ready (keine
# rohe SQLite-Abfrage aus dem Skill-Skript heraus, architecture.md
# Boundary-Regel).
check_store_or_die() {
  local db="$1"

  if [ ! -f "$db" ]; then
    echo "FATAL: research-app.sqlite '$db' existiert nicht -- Store fehlt (E1). Handlungsanweisung: 'db_scripts/migrate.sh $db' ausfuehren, dann erneut versuchen. Lauf abgebrochen VOR jedem last30days-Aufruf (kein Halb-Lauf)." >&2
    return 1
  fi

  if ! ra_topic_store_ready "$db"; then
    echo "FATAL: research-app.sqlite '$db' ist nicht migriert (Tabelle 'ra_topic' fehlt) -- Store fehlt (E1). Handlungsanweisung: 'db_scripts/migrate.sh $db' ausfuehren, dann erneut versuchen." >&2
    return 1
  fi

  return 0
}

# resolve_or_create_topic <db-path> <title>
# AC6/BR-109: exakt EIN bestehendes Thema mit identischem Titel wird
# wiederverwendet (stabile Themen-ID ueber mehrere Laeufe); bei keinem oder
# mehreren Treffern (frueherer OF-02-Duplikat-Fall) legt create_topic ein neues
# Thema an (Titel-Duplikat-Warnung greift dann regulaer, unveraendert aus
# S-002). Gibt die Themen-ID auf stdout aus (rc=0) oder bricht mit FATAL ab
# (rc=1, Fehler kommt bereits von create_topic auf stderr).
resolve_or_create_topic() {
  local db="$1"
  local title="$2"
  local matches match_count topic_id

  matches="$(find_topic_by_title "$db" "$title")"
  if [ -z "$matches" ]; then
    match_count=0
  else
    match_count="$(printf '%s\n' "$matches" | grep -c .)"
  fi

  if [ "$match_count" -eq 1 ]; then
    topic_id="$matches"
    echo "INFO: bestehendes Thema '$title' wiederverwendet (ID $topic_id, BR-109 stabile Identitaet ueber mehrere Laeufe)." >&2
  else
    topic_id="$(create_topic "$db" "$title")" || return 1
  fi

  printf '%s' "$topic_id"
  return 0
}

# print_missing_sources_note <json-file>
# AC7: gibt den "fehlende Quellen"-Teil des Briefs aus (leer = alle Quellen
# vollstaendig).
print_missing_sources_note() {
  local json_file="$1"
  local missing
  missing="$(extract_missing_sources "$json_file")" || return 1

  if [ -z "$missing" ]; then
    echo "Quellen: alle vollstaendig (kein Ausfall, AC7)."
  else
    echo "Fehlende Quellen (ausgefallen, Lauf laeuft mit den verbleibenden Quellen durch, AC7):"
    printf '%s\n' "$missing" | while IFS='|' read -r src status; do
      echo "  - $src: $status"
    done
  fi
  return 0
}

# research_thema <db-path> <topic-title> <save-dir-base>
# Thema-Modus (AC1): last30days ueber lib/last30days_client.sh aufrufen,
# Thema ueber die Data-Access-Schicht anlegen/wiederverwenden (AC6),
# Advisory-Lock je Thema (E3/BR-019), Quellen-Resilienz-Brief (AC7).
research_thema() {
  local db="$1"
  local title="$2"
  local save_dir_base="$3"
  local cmd topic_id rc json_file mode_save_dir

  cmd="$(resolve_last30days_cmd)" || return 1
  check_store_or_die "$db" || return 1

  topic_id="$(resolve_or_create_topic "$db" "$title")" || return 1

  set +e
  acquire_topic_lock "$db" "$topic_id" "$RA_LOCK_HOLDER" "$RA_LOCK_TTL_SECONDS"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    return 1
  fi

  mode_save_dir="$save_dir_base/thema_$(date +%Y%m%dT%H%M%S%N 2>/dev/null || date +%Y%m%dT%H%M%S)"
  json_file="$(mktemp)"
  set +e
  invoke_last30days_thema "$cmd" "$title" "$mode_save_dir" > "$json_file"
  rc=$?
  set -e

  release_topic_lock "$db" "$topic_id" "$RA_LOCK_HOLDER" || true

  if [ "$rc" -ne 0 ]; then
    rm -f "$json_file"
    return 1
  fi

  echo "== Recherche-Brief (Grundgeruest, S-007) =="
  echo "Modus: thema"
  echo "Thema: $title"
  echo "Themen-ID: $topic_id"
  print_missing_sources_note "$json_file"
  rm -f "$json_file"
  return 0
}

# research_discovery <db-path> <save-dir-base>
# Discovery-Modus (AC1): autonome Topthemen-Suche via last30days --discover;
# jedes gefundene Thema wird ueber die Data-Access-Schicht angelegt/
# wiederverwendet (AC6), je Thema Advisory-Lock (E3/BR-019 -- ein bereits
# gesperrtes Thema wird uebersprungen, kein Doppel-Lauf, kein Abbruch des
# gesamten Discovery-Laufs), gemeinsamer Quellen-Resilienz-Brief (AC7).
research_discovery() {
  local db="$1"
  local save_dir_base="$2"
  local cmd rc json_file mode_save_dir topics title topic_id

  cmd="$(resolve_last30days_cmd)" || return 1
  check_store_or_die "$db" || return 1

  mode_save_dir="$save_dir_base/discovery_$(date +%Y%m%dT%H%M%S%N 2>/dev/null || date +%Y%m%dT%H%M%S)"
  json_file="$(mktemp)"
  set +e
  invoke_last30days_discovery "$cmd" "$mode_save_dir" > "$json_file"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    rm -f "$json_file"
    return 1
  fi

  echo "== Recherche-Brief (Discovery, S-007) =="

  topics="$(extract_discovery_topics "$json_file")" || { rm -f "$json_file"; return 1; }
  if [ -z "$topics" ]; then
    echo "Keine belastbaren Topthemen in diesem Fenster (last30days-Konfidenzschwelle nicht erreicht)."
  else
    while IFS= read -r title; do
      [ -z "$title" ] && continue

      topic_id="$(resolve_or_create_topic "$db" "$title")" || { rm -f "$json_file"; return 1; }

      set +e
      acquire_topic_lock "$db" "$topic_id" "$RA_LOCK_HOLDER" "$RA_LOCK_TTL_SECONDS"
      rc=$?
      set -e
      if [ "$rc" -ne 0 ]; then
        echo "  UEBERSPRUNGEN: Thema '$title' (ID $topic_id) ist gerade in Bearbeitung (BR-019, E3) -- kein Doppel-Lauf." >&2
        continue
      fi
      release_topic_lock "$db" "$topic_id" "$RA_LOCK_HOLDER" || true

      echo "Thema: $title (ID $topic_id)"
    done <<< "$topics"
  fi

  print_missing_sources_note "$json_file"
  rm -f "$json_file"
  return 0
}

usage() {
  cat >&2 <<'USAGE'
Usage:
  orchestrator.sh discovery [save-dir]
  orchestrator.sh thema "<Thema-String>" [save-dir]

Env:
  RA_DB_PATH            Pfad zur research-app.sqlite (Default: research-app.sqlite)
  RA_LAST30DAYS_CMD     last30days-Kommando (Default: last30days, auf PATH aufgeloest)
  RA_LOCK_HOLDER        ra_topic_lock.holder-Wert (Default: research)
  RA_LOCK_TTL_SECONDS   Lock-TTL in Sekunden (Default: 1800)
USAGE
}

main() {
  local mode="${1:-}"
  case "$mode" in
    discovery)
      research_discovery "$RA_DB_PATH" "${2:-$RA_SAVE_DIR}"
      ;;
    thema)
      local title="${2:-}"
      research_thema "$RA_DB_PATH" "$title" "${3:-$RA_SAVE_DIR}"
      ;;
    *)
      usage
      return 1
      ;;
  esac
}

# Nur ausfuehren, wenn direkt aufgerufen -- nicht beim Sourcen fuer Tests (die
# Testsuite sourced dieses Skript, um die einzelnen Funktionen isoliert
# aufzurufen, ohne main() auszuloesen).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit $?
fi
