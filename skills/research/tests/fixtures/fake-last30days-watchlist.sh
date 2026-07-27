#!/usr/bin/env bash
# fake-last30days-watchlist.sh — Test-Stub fuer die last30days-Watchlist-CLI
# (skills/research/tests, wiedervorlage-meilensteine#AC2/AC6). Kein echtes
# last30days-Watchlist im Test-Environment installiert (externe, API-
# abhaengige Installation) -- dieser Stub simuliert "<cmd> delta <watch-ref>"
# rein lokal, damit watchlist_client.sh/watchlist_pass.sh ohne echten
# Netzwerk-/API-Aufruf getestet werden koennen (gleiches Muster wie
# fake-last30days.sh fuer den Discovery/Ingest-Pass, S-007).
#
# Steuerung ueber Env-Variablen (vom Aufrufer/Test gesetzt):
#   FAKE_L30D_WATCHLIST_SENTINEL   Datei, die bei JEDEM Aufruf beruehrt wird
#                                  (Beleg: "wurde ueberhaupt aufgerufen").
#   FAKE_L30D_WATCHLIST_JSON_FILE  Pfad zu einer JSON-Datei, deren Inhalt auf
#                                  stdout ausgegeben wird (simulierte
#                                  "delta"-Antwort).
#   FAKE_L30D_WATCHLIST_EXIT_CODE  Exitcode, mit dem der Stub endet (Default 0).
#   FAKE_L30D_WATCHLIST_STDERR     Optionale stderr-Zeile.
#   FAKE_L30D_WATCHLIST_ARGS_FILE  Optionaler Pfad, in den "$@" (eine Zeile je
#                                  Argument) geschrieben wird -- Beleg fuer
#                                  "delta <watch-ref>" (AC2).
set -euo pipefail

if [ -n "${FAKE_L30D_WATCHLIST_SENTINEL:-}" ]; then
  : > "$FAKE_L30D_WATCHLIST_SENTINEL"
fi

if [ -n "${FAKE_L30D_WATCHLIST_ARGS_FILE:-}" ]; then
  printf '%s\n' "$@" > "$FAKE_L30D_WATCHLIST_ARGS_FILE"
fi

if [ -n "${FAKE_L30D_WATCHLIST_STDERR:-}" ]; then
  echo "$FAKE_L30D_WATCHLIST_STDERR" >&2
fi

# JSON-Ausgabe IMMER vor dem Exit schreiben, auch bei exit_code != 0 -- die
# reale last30days-Watchlist-CLI meldet Fehler als JSON AUF STDOUT bei
# Exitcode 1 (siehe watchlist_client.sh-Header, Reviewer-Fund Iteration 1:
# "Topic not found: ..."), ein fruehes exit VOR der JSON-Ausgabe wuerde dieses
# Szenario in der Fixture strukturell unsimulierbar machen.
if [ -n "${FAKE_L30D_WATCHLIST_JSON_FILE:-}" ]; then
  cat "$FAKE_L30D_WATCHLIST_JSON_FILE"
fi

exit_code="${FAKE_L30D_WATCHLIST_EXIT_CODE:-0}"
exit "$exit_code"
