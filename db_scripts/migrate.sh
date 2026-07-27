#!/usr/bin/env bash
# migrate.sh — Migrations-Runner fuer das eigene research-app.sqlite (AC6, AC8).
#
# Reihenfolge ist bindend (coder.md-Lesson 2026-07-27): der Version-Guard MUSS als
# allererstes laufen, VOR jedem Schreibzugriff gegen die Ziel-DB -- nicht erst
# innerhalb der Migrations-Schleife. Der Guard selbst beruehrt die Ziel-DB nicht
# (Query laeuft gegen ':memory:'), erst nach bestandenem Guard wird "$DB_PATH"
# ueberhaupt geoeffnet.
#
# Usage: db_scripts/migrate.sh [db-path]   (Default: ./research-app.sqlite)
#
# AC8 / BR-018: dieser Runner wendet Migrationen NUR gegen die eigene
# research-app.sqlite an. Die last30days-Store-Datei wird von diesem Skript nie
# beruehrt -- sie wird ausschliesslich per lib/attach_l30d_readonly.sh read-only
# ge-ATTACHt (separate Naht, kein Migrations-Ziel).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/version_guard.sh
source "$SCRIPT_DIR/lib/version_guard.sh"
# shellcheck source=lib/apply_migrations.sh
source "$SCRIPT_DIR/lib/apply_migrations.sh"

DB_PATH="${1:-research-app.sqlite}"

require_sqlite_version_or_die "$DB_PATH"

apply_migrations "$DB_PATH" "$SCRIPT_DIR"
