#!/usr/bin/env bash
# fake-last30days.sh — Test-Stub fuer last30days (skills/research/tests). Kein
# echtes last30days im Test-Environment installiert (last30days ist eine
# externe, API-/Netzwerk-abhaengige Installation) -- dieser Stub simuliert den
# last30days-Agent-JSON-Vertrag (docs/reference/json-export.md des
# last30days-Projekts) rein lokal, damit orchestrator.sh/last30days_client.sh
# ohne echten Netzwerk-/API-Aufruf getestet werden koennen.
#
# Steuerung ueber Env-Variablen (vom Aufrufer/Test gesetzt):
#   FAKE_L30D_SENTINEL   Datei, die bei JEDEM Aufruf beruehrt wird (Beleg: "wurde
#                        ueberhaupt aufgerufen" -- fuer E1/E3-Abbruch-Tests, die
#                        pruefen, dass last30days NICHT aufgerufen wurde).
#   FAKE_L30D_JSON_FILE  Pfad zu einer JSON-Datei, deren Inhalt auf stdout
#                        ausgegeben wird (simulierter --emit=json-Export).
#   FAKE_L30D_EXIT_CODE  Exitcode, mit dem der Stub endet (Default 0).
#   FAKE_L30D_STDERR     Optionale stderr-Zeile (z.B. fuer den last30days-
#                        Fehlerpfad-Test).
#   FAKE_L30D_ARGS_FILE  Optionaler Pfad, in den "$@" (eine Zeile je Argument)
#                        geschrieben wird -- Beleg fuer die korrekten CLI-Flags
#                        (--emit=json/--save-dir/--store, AC1).
set -euo pipefail

if [ -n "${FAKE_L30D_SENTINEL:-}" ]; then
  : > "$FAKE_L30D_SENTINEL"
fi

if [ -n "${FAKE_L30D_ARGS_FILE:-}" ]; then
  printf '%s\n' "$@" > "$FAKE_L30D_ARGS_FILE"
fi

if [ -n "${FAKE_L30D_STDERR:-}" ]; then
  echo "$FAKE_L30D_STDERR" >&2
fi

exit_code="${FAKE_L30D_EXIT_CODE:-0}"
if [ "$exit_code" -ne 0 ]; then
  exit "$exit_code"
fi

if [ -n "${FAKE_L30D_JSON_FILE:-}" ]; then
  cat "$FAKE_L30D_JSON_FILE"
fi

exit 0
