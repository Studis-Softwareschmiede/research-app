#!/usr/bin/env bash
# watchlist_client.sh — Watchlist-Pass: last30days-Watchlist-Delta-Abfrage
# (wiedervorlage-meilensteine#AC2, E2).
#
# Quelle: docs/specs/wiedervorlage-meilensteine.md AC2 ("Externe Meilensteine
# ... werden vom Watchlist-Job geprueft; 'Delta' = das last30days-Delta-Signal,
# OF-12-Entscheid"); E2 ("last30days-Watchlist nicht verfuegbar -> externe
# Meilensteine werden als 'manuell zu pruefen' gemeldet, kein Crash").
# docs/architecture.md: "Watchlist/Wiedervorlage"-Komponente -- ausser
# Discovery/Ingest ist NUR Watchlist erlaubt, last30days aufzurufen
# (Boundary 2, "Zentrale Boundary-Regel"/architecture/R01).
#
# Kein eigenes Delta-Scoring (Nicht-Ziel der Spec): das last30days-eigene
# Delta-Ergebnis wird 1:1 durchgereicht (JSON unveraendert auf stdout), nicht
# neu bewertet/interpretiert -- die Interpretation (Report-Text) lebt in
# watchlist_pass.sh, nicht hier.
#
# Eigenes Kommando-Override (RA_LAST30DAYS_WATCHLIST_CMD), bewusst GETRENNT
# von RA_LAST30DAYS_CMD (last30days_client.sh, Discovery/Ingest-Pass): das
# last30days-Projekt liefert die Watchlist-Verwaltung ueber ein eigenes,
# separates CLI-Skript (skills/last30days/scripts/watchlist.py, nicht
# last30days.py) -- ein gemeinsamer Kommando-Name waere technisch falsch.
#
# Realistische Default-Aufloesung (Reviewer-Fund Iteration 1, S-013): last30days
# installiert KEIN "last30days-watchlist"-Kommando auf PATH -- die reale
# Distribution ruft das Skript direkt ueber einen Python-Interpreter auf
# ("${LAST30DAYS_PYTHON:-python3}" "<skill-dir>/scripts/watchlist.py" ...,
# last30days-Projekt: SKILL.md/README.md "Trend monitoring"). Deshalb sucht
# resolve_last30days_watchlist_cmd OHNE Override an den vom last30days-Projekt
# selbst dokumentierten Installationsorten (SKILL.md-Kommentar "Read
# ~/.claude/skills/last30days/SKILL.md" / "~/.codex/skills/last30days" /
# Claude-Plugin-Cache "~/.claude/plugins/cache/last30days-skill/last30days/
# <version>") nach watchlist.py und baut daraus einen einzelnen aufrufbaren
# Shim (Simplicity-Leiter Stufe 6 hier gerechtfertigt: check_watchlist_delta
# ruft "<cmd> delta <watch-ref>" als EIN Token auf, analog last30days_client.sh
# -- ein Shim vermeidet eine Aufruf-Signatur-Aenderung ueber die ganze Kette).
# $HOME wird bewusst als Variable (nicht hartkodiert) verwendet, damit Tests
# per HOME=<fake-home> eine isolierte, portable Fake-Installation simulieren
# koennen (Simplicity-Leiter Stufe 3: kein zusaetzlicher Test-Hook noetig).
#
# $RA_LAST30DAYS_WATCHLIST_CMD bleibt der Override (> Auto-Discovery) --
# gedacht fuer Tests (Fake-Stub) und fuer Installationen an einem nicht
# vorhergesehenen Pfad. Ob eine nicht aufloesbare Watchlist-CLI den GESAMTEN
# Watchlist-Pass abbricht oder je Meilenstein als "manuell zu pruefen" (E2)
# reportiert wird, entscheidet der Aufrufer (watchlist_pass.sh) -- diese
# Funktion meldet nur den rohen Aufloesungs-Fehlschlag.
#
# JSON-Validierung nutzt die bereits vorhandene _json_valid_or_die-Haltestelle
# aus last30days_client.sh (Simplicity-Leiter Stufe 2: wiederverwendet statt
# ein zweites Mal implementiert) -- deshalb wird diese Datei IMMER zusammen
# mit last30days_client.sh gesourced (siehe Source-Zeile unten).

WATCHLIST_CLIENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./last30days_client.sh
source "$WATCHLIST_CLIENT_DIR/last30days_client.sh"

# _find_last30days_watchlist_script
# Sucht watchlist.py an den vom last30days-Projekt selbst dokumentierten
# Installationsorten (siehe Kommentar oben) und gibt den ERSTEN Treffer auf
# stdout aus (rc=0). Im Claude-Plugin-Cache koennen mehrere Versionen
# parallel liegen -- `sort -V` waehlt die hoechste. Kein Treffer: leere
# Ausgabe, rc=1 (kein Fehlerfall dieser Hilfsfunktion selbst, der Aufrufer
# entscheidet ueber FATAL/E2).
_find_last30days_watchlist_script() {
  local candidate
  for candidate in \
    "$HOME/.claude/skills/last30days/scripts/watchlist.py" \
    "$HOME/.codex/skills/last30days/scripts/watchlist.py"; do
    if [ -f "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  local plugin_cache_base="$HOME/.claude/plugins/cache/last30days-skill/last30days"
  if [ -d "$plugin_cache_base" ]; then
    local newest_version_dir
    newest_version_dir="$(find "$plugin_cache_base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n1)"
    if [ -n "$newest_version_dir" ] && [ -f "$newest_version_dir/skills/last30days/scripts/watchlist.py" ]; then
      printf '%s' "$newest_version_dir/skills/last30days/scripts/watchlist.py"
      return 0
    fi
  fi

  return 1
}

# _write_last30days_watchlist_shim <python-bin> <script-path>
# Erzeugt einen kleinen, EINMAL aufrufbaren Wrapper ("exec <python-bin>
# <script-path> "$@""), damit resolve_last30days_watchlist_cmd weiterhin
# einen einzelnen Kommando-Token liefert (check_watchlist_delta bleibt
# unveraendert: "<cmd> delta <watch-ref>"). Ueber mktemp erzeugt -- bewusst
# KEIN automatisches Aufraeumen (Simplicity-Leiter: der Shim lebt fuer die
# Dauer des gesamten Watchlist-Passes, ein Trap wuerde den bestehenden
# EXIT-Trap des Aufrufers/Testharnesses ueberschreiben; das verbleibende
# Temp-File ist ein bekannter, tolerierter Nebeneffekt, kein Datenmodell-
# Artefakt). Gibt den Shim-Pfad auf stdout aus (rc=0) oder bricht mit FATAL
# ab (rc=1), wenn chmod fehlschlaegt.
_write_last30days_watchlist_shim() {
  local python_bin="$1"
  local script="$2"
  local shim
  shim="$(mktemp)"

  cat > "$shim" <<SHIM
#!/usr/bin/env bash
exec "$python_bin" "$script" "\$@"
SHIM

  if ! chmod +x "$shim"; then
    echo "FATAL: Shim-Erzeugung fuer last30days-Watchlist ('$shim') schlug beim chmod fehl." >&2
    rm -f "$shim"
    return 1
  fi

  printf '%s' "$shim"
  return 0
}

# resolve_last30days_watchlist_cmd
# Gibt den aufzurufenden Watchlist-CLI-Befehl auf stdout aus (rc=0) oder
# bricht mit FATAL auf stderr ab (rc=1, E2-Ausloeser fuer den Aufrufer).
resolve_last30days_watchlist_cmd() {
  if [ -n "${RA_LAST30DAYS_WATCHLIST_CMD:-}" ]; then
    if ! command -v "$RA_LAST30DAYS_WATCHLIST_CMD" > /dev/null 2>&1; then
      echo "FATAL: last30days-Watchlist-Override '$RA_LAST30DAYS_WATCHLIST_CMD' (RA_LAST30DAYS_WATCHLIST_CMD) ist nicht installiert bzw. nicht ausfuehrbar (E2). Handlungsanweisung: \$RA_LAST30DAYS_WATCHLIST_CMD auf den korrekten Aufrufpfad setzen." >&2
      return 1
    fi
    printf '%s' "$RA_LAST30DAYS_WATCHLIST_CMD"
    return 0
  fi

  local script
  script="$(_find_last30days_watchlist_script)"
  if [ -z "$script" ]; then
    echo "FATAL: last30days-Watchlist ist nicht installiert -- watchlist.py wurde an keinem bekannten Installationsort gefunden (~/.claude/skills/last30days, ~/.codex/skills/last30days, ~/.claude/plugins/cache/last30days-skill/last30days/<version>) und \$RA_LAST30DAYS_WATCHLIST_CMD ist nicht gesetzt (E2). Handlungsanweisung: last30days-Skill installieren oder \$RA_LAST30DAYS_WATCHLIST_CMD auf den korrekten Aufrufpfad setzen." >&2
    return 1
  fi

  local python_bin="${LAST30DAYS_PYTHON:-python3}"
  if ! command -v "$python_bin" > /dev/null 2>&1; then
    echo "FATAL: Python-Interpreter '$python_bin' (LAST30DAYS_PYTHON-Default python3) ist nicht auf PATH -- last30days-Watchlist-Skript '$script' kann nicht ausgefuehrt werden (E2)." >&2
    return 1
  fi

  _write_last30days_watchlist_shim "$python_bin" "$script"
}

# check_watchlist_delta <cmd> <watch-ref>
# Ruft "<cmd>" delta "<watch-ref>" auf (last30days-Watchlist-Delta-Kommando,
# last30days-Projekt: watchlist.py delta <topic>) -- Array-Aufruf, kein
# String-Interpolieren in eine Shell-Kommandozeile (security/R03; watch_ref
# ist last30days' eigener Watchlist-Bezeichner, kein SQL-/Shell-Sink hier).
# Gibt das last30days-JSON-Ergebnis UNVERAENDERT auf stdout aus (rc=0) --
# 1:1-Durchreichung, kein eigenes Delta-Scoring (Nicht-Ziel). Bricht mit
# FATAL auf stderr ab (rc=1), wenn der Aufruf selbst fehlschlaegt ODER die
# Ausgabe kein gueltiges JSON ist -- beides zaehlt fuer den Aufrufer als E2
# "last30days-Watchlist nicht verfuegbar".
#
# Diagnose-Vollstaendigkeit (Reviewer-Fund Iteration 1, S-013): die reale
# last30days-Watchlist-CLI (watchlist.py#cmd_delta) meldet einen Fehler
# ("Topic not found: ...") als JSON auf STDOUT bei Exitcode 1, OHNE
# stderr-Zeile. Die FATAL-Meldung nimmt deshalb IMMER sowohl $out_file
# (last30days' eigene Fehler-JSON) als auch $err_file (generische
# Interpreter-/Systemfehler) auf -- keine der beiden Quellen wird verworfen.
check_watchlist_delta() {
  local cmd="$1"
  local watch_ref="$2"
  local out_file err_file rc

  out_file="$(mktemp)"
  err_file="$(mktemp)"

  if "$cmd" delta "$watch_ref" > "$out_file" 2> "$err_file"; then
    if _json_valid_or_die "$out_file" 2>> "$err_file"; then
      cat "$out_file"
      rm -f "$out_file" "$err_file"
      return 0
    fi
    echo "FATAL: last30days-Watchlist-Antwort fuer '$watch_ref' ist kein gueltiges JSON (E2): $(cat "$err_file")" >&2
    rm -f "$out_file" "$err_file"
    return 1
  fi
  rc=$?
  echo "FATAL: last30days-Watchlist-Delta-Abfrage fuer '$watch_ref' schlug mit Exitcode $rc fehl (E2): stdout=$(cat "$out_file") stderr=$(cat "$err_file")" >&2
  rm -f "$out_file" "$err_file"
  return 1
}
