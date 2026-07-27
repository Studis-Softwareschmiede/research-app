#!/usr/bin/env bash
# last30days_client.sh — Discovery/Ingest-Pass: last30days-CLI-Aufruf + JSON-
# Auswertung (research-skill#AC1,AC7).
#
# Quelle: docs/specs/research-skill.md AC1 ("last30days ueber --emit=json +
# --save-dir + --store, kein Scraping-Eigenbau"), AC7 (Quellen-Resilienz).
# docs/architecture.md: "Discovery/Ingest" ist -- ausser Watchlist (M3, noch
# nicht gebaut) -- die EINZIGE Komponente, die last30days aufruft (Boundary 2);
# last30days selbst bleibt read-only konsumiert (nur der dokumentierte
# Agent-JSON-Export, last30days README docs/reference/json-export.md,
# schema_version 1.x + separater Discovery-Contract) -- Kopplungsminimierung
# (architecture.md NFR, C-007: last30days-Schema ist extern & nicht garantiert
# stabil).
#
# Kommando-Aufloesung (E1, "last30days nicht installiert"): $RA_LAST30DAYS_CMD
# (expliziter Override, z.B. Tests/abweichende Installation) > `last30days` auf
# PATH. Bewusst KEIN Rueckgriff auf einen bestimmten Plugin-Cache-Pfad (fragil,
# versionsabhaengig, host-spezifisch) -- "last30days installiert" ist die in
# architecture.md dokumentierte externe Abhaengigkeit (CLI), keine
# Implementierungsannahme ueber einen bestimmten Claude-Plugin-Cache.
#
# JSON-Auswertung nutzt sqlite3 (ohnehin Kern-Abhaengigkeit dieses Projekts,
# json1 bereits durchgaengig genutzt in db_scripts/lib/run.sh/divergence.sh) +
# dessen CLI-eigene readfile()-Funktion (Teil des shell.c-Fileio-Bausteins,
# Test bestaetigt: verfuegbar auf der hier gebundenen sqlite3-CLI) statt die
# potenziell sehr grosse last30days-JSON-Ausgabe manuell als SQL-String-Literal
# zu escapen (Simplicity-Leiter Stufe 4/5 -- kein zusaetzlicher
# JSON-Parser/-Interpreter noetig).

# resolve_last30days_cmd
# Gibt den aufzurufenden Befehl auf stdout aus (rc=0) oder bricht mit FATAL auf
# stderr ab (rc=1, E1) -- MUSS vor jedem last30days-Aufruf laufen, damit ein
# nicht installiertes last30days nie fuer einen dann doch abgebrochenen Lauf
# befragt wird ("kein Halb-Lauf").
resolve_last30days_cmd() {
  local cmd="${RA_LAST30DAYS_CMD:-last30days}"

  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "FATAL: last30days ist nicht installiert bzw. '$cmd' ist nicht auf PATH (E1). Handlungsanweisung: last30days-Skill installieren (siehe last30days-Plugin/README 'Install') oder \$RA_LAST30DAYS_CMD auf den korrekten Aufrufpfad setzen -- Lauf abgebrochen VOR jedem last30days-Aufruf (kein Halb-Lauf)." >&2
    return 1
  fi

  printf '%s' "$cmd"
  return 0
}

# invoke_last30days_thema <cmd> <topic-title> <save-dir>
# Ruft last30days im Thema-Modus auf: "<cmd>" "<topic-title>" --emit=json
# --save-dir <save-dir> --store (AC1, vorgegebenes Thema). Array-Aufruf --
# kein String-Interpolieren in eine Shell-Kommandozeile (security/R03); der
# Thema-String ist last30days' eigener Suchbegriff, kein SQL-/Shell-Sink in
# dieser Funktion. Schreibt den JSON-Export auf stdout (Aufrufer leitet das in
# eine Datei um), rc=0 bei Erfolg. Bricht mit FATAL auf stderr ab (rc=1), wenn
# last30days selbst mit einem Fehler-Exitcode endet.
invoke_last30days_thema() {
  local cmd="$1"
  local topic="$2"
  local save_dir="$3"

  mkdir -p "$save_dir"

  local err_file rc
  err_file="$(mktemp)"
  if "$cmd" "$topic" --emit=json --save-dir "$save_dir" --store 2> "$err_file"; then
    rm -f "$err_file"
    return 0
  fi
  rc=$?
  echo "FATAL: last30days-Aufruf fuer Thema '$topic' schlug mit Exitcode $rc fehl: $(cat "$err_file")" >&2
  rm -f "$err_file"
  return 1
}

# invoke_last30days_discovery <cmd> <save-dir>
# Ruft last30days im Discovery-Modus auf: "<cmd>" --discover --emit=json
# --save-dir <save-dir> --store (AC1, autonome Topthemen-Suche, kein
# positionelles Thema -- last30days-Doku: "--discover [domain]", bare
# --discover ohne Domain = globales Trending). Ansonsten identisch zu
# invoke_last30days_thema (Array-Aufruf, stdout=JSON, stderr nur bei Fehler).
invoke_last30days_discovery() {
  local cmd="$1"
  local save_dir="$2"

  mkdir -p "$save_dir"

  local err_file rc
  err_file="$(mktemp)"
  if "$cmd" --discover --emit=json --save-dir "$save_dir" --store 2> "$err_file"; then
    rm -f "$err_file"
    return 0
  fi
  rc=$?
  echo "FATAL: last30days-Discovery-Aufruf schlug mit Exitcode $rc fehl: $(cat "$err_file")" >&2
  rm -f "$err_file"
  return 1
}

# _json_valid_or_die <json-file>
# Interner Guard: prueft ueber sqlite3/json1, ob die last30days-Ausgabe
# gueltiges JSON ist, BEVOR json_extract/json_each darauf laufen (klare
# FATAL-Meldung statt kryptischem sqlite3-Parse-Fehler).
_json_valid_or_die() {
  local json_file="$1"

  if [ ! -f "$json_file" ]; then
    echo "FATAL: JSON-Datei '$json_file' fuer die last30days-Auswertung existiert nicht." >&2
    return 1
  fi

  local escaped_path valid
  escaped_path="${json_file//\'/\'\'}"
  valid="$(sqlite3 ':memory:' "SELECT json_valid(readfile('$escaped_path'));")"
  if [ "$valid" != "1" ]; then
    echo "FATAL: last30days-Ausgabe in '$json_file' ist kein gueltiges JSON -- Agent-JSON-Vertrag verletzt." >&2
    return 1
  fi
  return 0
}

# extract_missing_sources <json-file>
# Liest das Top-Level-Feld 'source_status' (in beiden last30days-Export-
# Varianten vorhanden -- normaler Research- UND Discovery-Export, last30days
# docs/reference/json-export.md) und gibt jede Quelle mit einem NICHT
# erfolgreichen Status zeilenweise als "<quelle>|<status>" aus (AC7).
# 'ok'/'no-results'/'partial' gelten NICHT als ausgefallen (haben Ergebnisse
# geliefert bzw. sauber leer abgeschlossen); 'skipped-unconfigured' ebenfalls
# nicht (bewusste Konfigurationsentscheidung, keine Quelle, die IM LAUFENDEN
# LAUF ausgefallen ist). Alle anderen Werte (u.a. 'auth-failed' = Credential
# abgelaufen, 'rate-limited' = Kontingent erschoepft, 'unreachable',
# 'timeout', 'schema-drift', 'error') gelten als ausgefallen. Leere Ausgabe =
# keine ausgefallene Quelle in diesem Lauf.
extract_missing_sources() {
  local json_file="$1"
  _json_valid_or_die "$json_file" || return 1

  local escaped_path="${json_file//\'/\'\'}"
  sqlite3 -separator '|' ':memory:' "
SELECT key, value
FROM json_each(json_extract(readfile('$escaped_path'), '\$.source_status'))
WHERE value NOT IN ('ok', 'no-results', 'partial', 'skipped-unconfigured')
ORDER BY key;
"
}

# extract_discovery_topics <json-file>
# Liest die Discovery-Kandidaten (Top-Level-Feld 'results', last30days
# Discovery-Export-Contract) und gibt je Kandidat den Themen-Titel
# (Feld 'topic') zeilenweise auf stdout aus, in der von last30days gelieferten
# Ranking-Reihenfolge (kein eigenes Re-Ranking/Capping -- last30days wendet
# bereits seine eigene Konfidenz-/Rankingschwelle an). Leere Ausgabe = last30days
# hat kein Topthema ueber der Konfidenzschwelle gefunden ('outcome'=
# 'nothing-solid').
extract_discovery_topics() {
  local json_file="$1"
  _json_valid_or_die "$json_file" || return 1

  local escaped_path="${json_file//\'/\'\'}"
  sqlite3 ':memory:' "
SELECT json_extract(value, '\$.topic')
FROM json_each(json_extract(readfile('$escaped_path'), '\$.results'))
WHERE json_extract(value, '\$.topic') IS NOT NULL;
"
}
