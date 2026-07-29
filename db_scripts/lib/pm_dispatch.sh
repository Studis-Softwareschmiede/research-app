#!/usr/bin/env bash
# pm_dispatch.sh — Data-Access-Schicht fuer ra_pm_dispatch (PM-Anstoss-Protokoll,
# idempotent).
#
# Quelle: docs/specs/gate-pm-anstoss.md AC2 ("PM-Anstoss idempotent mit
# Divergenz-Ausweis"), AC3 ("Idempotenz via UNIQUE(topic_id, result_hash)"),
# AC4 ("Divergenz-Ausweis bei veraendertem Ergebnisstand" -- get_latest_pm_dispatch
# liefert den Vorlauf fuer orchestrator.sh#materialize_and_render_divergence);
# docs/data-model.md §2.6, §4 BR-017 (Idempotenz-Invariante).
# architecture.md: "Data-Access" ist die einzige Schreib-/Lesestelle der
# Bewertungs-Tabellen (single-writer) -- diese Datei IST diese Schicht. Analog
# zu topic.sh/milestone.sh/run.sh: reine Bash-Funktionen, die SQL gegen die
# Ziel-DB fahren, ausschliesslich.
#
# Verbindungs-Idiom (sqlite/R02, Referenz-Pattern): JEDE Schreib-Verbindung
# (`sqlite3 "$db" "..."`) setzt `PRAGMA foreign_keys = ON;` als erste Anweisung.
# Der eigentliche INSERT laeuft zusaetzlich in `BEGIN IMMEDIATE` + gesetztem
# `PRAGMA busy_timeout` (data-model.md §9, BR-019: Single-Writer-Lock, da
# Watchlist-Job + /research gleichzeitig schreiben koennen; Referenz-Idiom
# run.sh#create_run).

# dispatch_pm_handoff <db-path> <topic-id> <run-id> <result-hash> <artifact-ref>
# Laegt einen PM-Dispatch-Datensatz an, idempotent ueber (topic_id, result_hash).
# Bei Idempotenz-Konflikt (gleiche topic_id + result_hash):
#   - rc=2: wiederholter Dispatch identischen Inhalts (is_empty Divergenz, AC3)
#   - rc=0: neuer Dispatch angelegt
#   - rc=1: Fehler (DB-Fehler, Constraint-Verletzung, Formatfehler)
#
# Gibt die neue/bestehende dispatch-ID auf stdout aus, nur wenn rc=0.
#
# Sicherheit (security/R03): topic_id und run_id werden VOR der SQL-Interpolation
# formatiert/validiert (UUID-Format bzw. Ganzzahl-Format).
dispatch_pm_handoff() {
  local db="$1"
  local topic_id="$2"
  local run_id="$3"
  local result_hash="$4"
  local artifact_ref="$5"
  local insert_err rc dispatch_id

  # Format-Guard fuer topic_id (UUID, security/R03, Lesson S-001 2026-07-27).
  if ! [[ "$topic_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
    echo "FATAL: Themen-ID '$topic_id' verletzt das UUID-Format -- PM-Dispatch abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  # Format-Guard fuer run_id (Ganzzahl, kein UUID).
  if ! [[ "$run_id" =~ ^[0-9]+$ ]]; then
    echo "FATAL: Lauf-ID '$run_id' ist keine gueltige Ganzzahl -- PM-Dispatch abgelehnt (security/R03)." >&2
    return 1
  fi

  # Apostroph-Escape fuer result_hash und artifact_ref (Freitext, security/R03).
  local escaped_hash="${result_hash//\'/\'\'}"
  local escaped_ref="${artifact_ref//\'/\'\'}"

  # Ueberpruefung auf Idempotenz-Konflikt: gibt es bereits einen Dispatch
  # mit (topic_id, result_hash)?
  local existing_id
  existing_id="$(sqlite3 "$db" "SELECT id FROM ra_pm_dispatch WHERE topic_id = '$topic_id' AND result_hash = '$escaped_hash';" 2>/dev/null)"
  if [ -n "$existing_id" ]; then
    # Idempotenter Wiederholungslauf: gleiche topic_id + result_hash.
    # Divergenz-Ausweis (AC3/AC4, separate Stories) wird woanders gehandhabt.
    return 2
  fi

  # Neuer Dispatch: INSERT. BEGIN IMMEDIATE + busy_timeout (data-model.md §9,
  # BR-019): Watchlist-Job und /research koennen gleichzeitig schreibend
  # zugreifen (Referenz-Idiom run.sh#create_run).
  insert_err="$(sqlite3 "$db" <<SQL 2>&1
PRAGMA foreign_keys = ON;
.output /dev/null
PRAGMA busy_timeout = 5000;
.output stdout
BEGIN IMMEDIATE;
INSERT INTO ra_pm_dispatch (topic_id, run_id, result_hash, artifact_ref)
VALUES ('$topic_id', $run_id, '$escaped_hash', '$escaped_ref');
COMMIT;
SQL
)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FATAL: PM-Dispatch fuer Thema '$topic_id'/Lauf $run_id schlug fehl (BR-017): $insert_err" >&2
    return 1
  fi

  # Neue ID auslesen (wird gerade eben angelegt, fuer den Log/weitere Verarbeitung).
  dispatch_id="$(sqlite3 "$db" "SELECT id FROM ra_pm_dispatch WHERE topic_id = '$topic_id' AND result_hash = '$escaped_hash';" 2>/dev/null)"
  echo "$dispatch_id"
  return 0
}

# get_pm_dispatch <db-path> <topic-id> <result-hash>
# Reine Lesefunktion: gibt die PM-Dispatch-Zeile aus, falls sie existiert
# (Felder: id|run_id|artifact_ref|dispatched_at), sonst leere Ausgabe.
# Genutzt von AC3/AC4-Passagen zum Divergenz-Ausweis.
get_pm_dispatch() {
  local db="$1"
  local topic_id="$2"
  local result_hash="$3"
  local escaped_hash="${result_hash//\'/\'\'}"

  if ! [[ "$topic_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
    echo "FATAL: Themen-ID '$topic_id' verletzt das UUID-Format -- Abfrage abgelehnt (security/R03)." >&2
    return 1
  fi

  sqlite3 "$db" "SELECT id, run_id, artifact_ref, dispatched_at FROM ra_pm_dispatch WHERE topic_id = '$topic_id' AND result_hash = '$escaped_hash';" 2>/dev/null
  return 0
}

# get_latest_pm_dispatch <db-path> <topic-id> [exclude-run-id]
# Reine Lesefunktion (gate-pm-anstoss#AC4): liefert den zuletzt fuer dieses Thema
# dispatchten Lauf als "run_id|result_hash" (neuester Eintrag nach dispatched_at,
# id als Tie-Breaker), oder leere Ausgabe, wenn kein passender PM-Dispatch
# existiert (rc=0, kein Fehlerfall -- Erst-Anstoss hat keinen Vorlauf).
#
# [exclude-run-id] (optional): schliesst Zeilen mit genau diesem run_id aus der
# Suche aus. Aufrufer (orchestrator.sh#dispatch_pm_anstoss) uebergibt hier den
# gerade dispatchten Lauf, um den "Vorlauf" (den tatsaechlich VORHERGEHENDEN,
# ANDEREN Lauf) robust gegen einen Abbruch-Neustart (AC5) zu ermitteln: OHNE
# Ausschluss wuerde ein bereits VOR dem Abbruch committeter eigener
# ra_pm_dispatch-Eintrag (derselbe run_id, gleicher Hash -- der Neustart faellt
# auf den idempotenten rc=2-Pfad) sich selbst als "Vorlauf" zurueckliefern,
# sobald dieser Aufruf NACH dispatch_pm_handoff erfolgt (notwendig, um auch den
# Abbruch-zwischen-Dispatch-und-Divergenz-Fall abzudecken).
get_latest_pm_dispatch() {
  local db="$1"
  local topic_id="$2"
  local exclude_run_id="${3:-}"

  if ! [[ "$topic_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
    echo "FATAL: Themen-ID '$topic_id' verletzt das UUID-Format -- Abfrage abgelehnt (security/R03)." >&2
    return 1
  fi

  local exclude_clause=""
  if [ -n "$exclude_run_id" ]; then
    if ! [[ "$exclude_run_id" =~ ^[0-9]+$ ]]; then
      echo "FATAL: exclude-run-id '$exclude_run_id' ist keine gueltige Ganzzahl -- Abfrage abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
      return 1
    fi
    exclude_clause="AND run_id != $exclude_run_id"
  fi

  sqlite3 -separator '|' "$db" "SELECT run_id, result_hash FROM ra_pm_dispatch WHERE topic_id = '$topic_id' $exclude_clause ORDER BY dispatched_at DESC, id DESC LIMIT 1;" 2>/dev/null
  return 0
}

# Nur ausfuehren, wenn direkt aufgerufen -- nicht beim Sourcen fuer Tests/andere Skripte.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  usage() {
    cat >&2 <<'USAGE'
Usage:
  pm_dispatch.sh dispatch <db-path> <topic-id> <run-id> <result-hash> <artifact-ref>
  pm_dispatch.sh get <db-path> <topic-id> <result-hash>
  pm_dispatch.sh latest <db-path> <topic-id> [exclude-run-id]
USAGE
    return 1
  }

  case "${1:-}" in
    dispatch)
      dispatch_pm_handoff "$2" "$3" "$4" "$5" "$6"
      ;;
    get)
      get_pm_dispatch "$2" "$3" "$4"
      ;;
    latest)
      get_latest_pm_dispatch "$2" "$3" "${4:-}"
      ;;
    *)
      usage
      ;;
  esac
fi
