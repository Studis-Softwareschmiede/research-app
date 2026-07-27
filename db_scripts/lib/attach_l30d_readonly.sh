#!/usr/bin/env bash
# attach_l30d_readonly.sh — read-only last30days-ATTACH-Helfer (BR-018, AC8).
#
# docs/data-model.md §1 (BR-018): die App legt AUSSCHLIESSLICH eigene Tabellen an
# (Praefix ra_...) und veraendert last30days-Plugin-Tabellen NIE. Diese Funktion
# erzwingt das technisch (nicht nur als Konvention): der last30days-Store wird per
# SQLite-URI 'mode=ro' angehaengt, sodass jeder Schreibversuch gegen l30d.* von der
# Engine selbst mit "attempt to write a readonly database" abgelehnt wird.
#
# Nutzung: das erzeugte ATTACH-Statement per Piping/Heredoc in dieselbe sqlite3-
# Session einspeisen, die anschliessend l30d.<tabelle> nur LIEST.
#
#   sqlite3 research-app.sqlite "$(attach_l30d_readonly_sql /pfad/last30days-store.sqlite)
#   SELECT ... FROM l30d.<tabelle> ...;"
#
# attach_l30d_readonly_sql <pfad-zur-last30days-store-datei> [alias, Default: l30d]
# Haertung (security/R03, Review-Fund Iteration 1): der Pfad wird roh in ein
# SQL-String-Literal interpoliert -- Apostrophe darin muessen SQL-escaped werden
# ('->''), sonst bricht ein Pfad mit "'" das Literal auf. Der Alias wird als
# blankes SQL-Bezeichner-Token interpoliert (kein Quoting moeglich) und daher
# strikt gegen ein Identifier-Muster validiert, bevor er ueberhaupt ins SQL geht.
attach_l30d_readonly_sql() {
  local l30d_path="$1"
  local alias="${2:-l30d}"

  if ! [[ "$alias" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "FATAL: ATTACH-Alias '$alias' verletzt das Bezeichner-Muster ^[A-Za-z_][A-Za-z0-9_]*\$ (security/R03)." >&2
    return 1
  fi

  local escaped_path="${l30d_path//\'/\'\'}"
  printf "ATTACH DATABASE 'file:%s?mode=ro' AS %s;\n" "$escaped_path" "$alias"
}
