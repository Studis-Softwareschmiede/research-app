#!/usr/bin/env bash
# milestone.sh — Data-Access-Schicht fuer ra_milestone (Meilenstein-Liste je Thema:
# Anlage/Aktualisierung/Abfrage).
#
# Quelle: docs/specs/research-skill.md AC5 ("Je Thema entsteht/aktualisiert sich die
# Meilenstein-Liste (Status + Zustaendigkeit extern/eigen); Schutzrechte erscheinen
# hoechstens als Klaerungspunkt, kein Rechtsmodul, C-004"); docs/data-model.md §2.4
# (ra_milestone-Feldliste), §4 BR-015/BR-016 (bereits als CHECK-Constraints in
# 004_ra_milestone.sql durchgesetzt, S-005).
#
# architecture.md: "Data-Access" ist die einzige Schreib-/Lesestelle der
# Bewertungs-Tabellen (single-writer) -- diese Datei IST diese Schicht, analog zu
# topic.sh/run.sh/divergence.sh/topic_lock.sh (S-002..S-006). Bis S-005 existierten
# nur die rohen CHECK-Constraints der Tabelle selbst (getestet in
# db_scripts/tests/run_tests.sh) -- kein Aufrufer brauchte bis dahin einen
# CRUD-Wrapper. Das aendert sich mit S-011 (research-skill#AC5,
# "Voraussetzungs-Ueberblick"-Pass, architecture.md-Komponente "Voraussetzungs-
# Ueberblick"): der /research-Skill legt Meilensteine je Thema an
# (create_milestone) und aktualisiert ihren Status (set_milestone_status), ohne
# SQLite direkt zu beruehren (Boundary-Regel architecture.md).
#
# Schutzrechte (C-004, Nicht-Ziel): dieses Modul bietet KEIN Rechtsmodul -- keine
# eigene Entitaet/kein eigenes Feld fuer "Schutzrechte". Der Klaerungspunkt ist reiner
# Text im Recherche-Brief (skills/research/scripts/orchestrator.sh), nicht Teil des
# Datenmodells (Simplicity-Leiter: AC5 verlangt keine Persistenz dafuer).
#
# Verbindungs-Idiom (sqlite/R02, Referenz-Pattern topic_lock.sh/run.sh): JEDE
# Schreib-Verbindung setzt `PRAGMA foreign_keys = ON;` als eigene erste Anweisung
# dieser frischen CLI-Session; `PRAGMA busy_timeout` steht VOR `BEGIN IMMEDIATE` in
# derselben Verbindung (coder.md-Lesson S-004) und wird bei RETURNING-Nutzung per
# `.output /dev/null`/`.output stdout` unterdrueckt, damit sein Rueckgabewert nicht in
# das eingesammelte Ergebnis leakt (run.sh/topic_lock.sh-Referenz-Idiom, S-003).

# create_milestone <db-path> <topic-id> <description> <responsibility> [watch-ref]
# Legt einen neuen Meilenstein fuer <topic-id> an; Status startet immer 'offen'
# (Neuanlage, kein anderer Startwert vorgesehen). BR-015 (watch_ref-Pflicht bei
# 'extern', verboten bei 'eigen') wird bereits durch die CHECK-Constraint der Tabelle
# (004_ra_milestone.sql) erzwungen -- diese Funktion validiert Format/Enum-Werte nur
# VOR der SQL-Interpolation (security/R03) und dupliziert damit nicht die
# CHECK-Logik selbst (Simplicity-Leiter Stufe 2: bestehender Backstop wiederverwendet
# statt ein zweites Mal implementiert).
# Gibt die neue Meilenstein-ID (INTEGER) auf stdout aus (rc=0) oder bricht mit FATAL
# auf stderr ab (rc=1).
create_milestone() {
  local db="$1"
  local topic_id="$2"
  local description="$3"
  local responsibility="$4"
  local watch_ref="${5:-}"

  if ! [[ "$topic_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "FATAL: Themen-ID '$topic_id' verletzt das UUID-Format -- Meilenstein-Anlage abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  if ! [[ "$responsibility" =~ ^(extern|eigen)$ ]]; then
    echo "FATAL: Zustaendigkeit '$responsibility' ist kein gueltiger ra_milestone.responsibility-Wert (BR-015)." >&2
    return 1
  fi

  if [ "$responsibility" = "extern" ] && [ -z "$watch_ref" ]; then
    echo "FATAL: responsibility='extern' erfordert eine Watchlist-Referenz (watch_ref, BR-015)." >&2
    return 1
  fi
  if [ "$responsibility" = "eigen" ] && [ -n "$watch_ref" ]; then
    echo "FATAL: responsibility='eigen' verbietet eine Watchlist-Referenz (watch_ref muss leer bleiben, BR-015)." >&2
    return 1
  fi

  if [ -z "$(printf '%s' "$description" | tr -d '[:space:]')" ]; then
    echo "FATAL: Meilenstein-Beschreibung ist leer/nur Whitespace -- Anlage abgelehnt." >&2
    return 1
  fi

  # Apostroph-Escape vor der SQL-Interpolation (security/R03, Lesson S-001).
  local esc_desc esc_ref ref_expr
  esc_desc="${description//\'/\'\'}"
  if [ -z "$watch_ref" ]; then
    ref_expr="NULL"
  else
    esc_ref="${watch_ref//\'/\'\'}"
    ref_expr="'$esc_ref'"
  fi

  local out rc
  out="$(sqlite3 "$db" <<SQL 2>&1
.mode list
.separator '|'
PRAGMA foreign_keys = ON;
.output /dev/null
PRAGMA busy_timeout = 5000;
.output stdout
BEGIN IMMEDIATE;
INSERT INTO ra_milestone (topic_id, description, responsibility, status, watch_ref)
VALUES ('$topic_id', '$esc_desc', '$responsibility', 'offen', $ref_expr)
RETURNING id;
COMMIT;
SQL
)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    echo "FATAL: Meilenstein-Anlage fuer Thema '$topic_id' schlug fehl (BR-015/BR-016): $out" >&2
    return 1
  fi

  echo "$out"
  return 0
}

# list_milestones <db-path> <topic-id>
# Reine Lesefunktion (kein PRAGMA foreign_keys noetig, SELECT-only): gibt je
# Meilenstein eine Zeile "id<0x1f>description<0x1f>responsibility<0x1f>status<0x1f>
# watch_ref" aus (watch_ref leer bei 'eigen'), sortiert nach id (Anlage-Reihenfolge)
# -- die "Meilenstein-Liste" aus AC5. Leere Ausgabe = noch kein Meilenstein fuer
# dieses Thema (rc bleibt 0, kein Fehlerfall).
#
# Trennzeichen (DBA-Review Iteration 2, Important-Fund): `description` ist die
# einzige unrestringierte Freitext-Spalte (CHECK erlaubt jeden Nicht-Leer-Text,
# `004_ra_milestone.sql`) und sitzt MITTEN in der Zeile -- ein `|` im Bash-`|`-
# Trennzeichen wuerde alle Folgefelder (responsibility/status/watch_ref) beim
# Parsen verschieben, OHNE sichtbaren Fehler (AC5-Kernzweck verletzt: Status/
# Zustaendigkeit wuerden falsch angezeigt). Fix: ASCII Unit Separator (0x1F,
# `$'\x1f'`) statt `|` -- ein Steuerzeichen, das in normalem Freitext praktisch nie
# vorkommt und deshalb kein Escaping im Aufrufer braucht (Simplicity-Leiter Stufe 4:
# natives sqlite3-`-separator`-Feature statt Escaping-Logik). Jeder Aufrufer (aktuell
# nur orchestrator.sh#print_milestone_overview) MUSS denselben Separator beim Parsen
# verwenden (`IFS=$'\x1f'`).
list_milestones() {
  local db="$1"
  local topic_id="$2"

  if ! [[ "$topic_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "FATAL: Themen-ID '$topic_id' verletzt das UUID-Format -- Abfrage abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  sqlite3 -separator $'\x1f' "$db" "SELECT id, description, responsibility, status, COALESCE(watch_ref, '') FROM ra_milestone WHERE topic_id = '$topic_id' ORDER BY id;"
  return 0
}

# set_milestone_status <db-path> <milestone-id> <new-status>
# Aktualisiert den Status eines bestehenden Meilensteins (BR-016 Enum). Setzt
# `fulfilled_at` gdw. der Zielstatus 'erfuellt' ist (data-model.md §2.4), analog zum
# discarded_at-Muster in topic.sh#set_topic_status. Kein eigener Statuswechsel-Automat
# vorgesehen (anders als ra_topic/BR-006): data-model.md §4 definiert fuer
# ra_milestone.status nur das Enum (BR-016), keine gesicherten Kanten -- jeder
# gueltige Enum-Wert ist direkt erreichbar (Simplicity-Leiter: keine ungeforderte
# Automaten-Logik erfinden, coder/R01).
# Gibt rc=0 bei Erfolg aus (kein stdout-Payload) oder bricht mit FATAL auf stderr ab.
set_milestone_status() {
  local db="$1"
  local milestone_id="$2"
  local new_status="$3"

  if ! [[ "$milestone_id" =~ ^[0-9]+$ ]]; then
    echo "FATAL: Meilenstein-ID '$milestone_id' ist keine gueltige Ganzzahl -- Statuswechsel abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  if ! [[ "$new_status" =~ ^(offen|erfuellt|hinfaellig)$ ]]; then
    echo "FATAL: Zielstatus '$new_status' ist kein gueltiger ra_milestone.status-Wert (BR-016)." >&2
    return 1
  fi

  local exists
  exists="$(sqlite3 "$db" "SELECT COUNT(*) FROM ra_milestone WHERE id = $milestone_id;")"
  if [ "$exists" != "1" ]; then
    echo "FATAL: Meilenstein '$milestone_id' existiert nicht -- Statuswechsel abgelehnt." >&2
    return 1
  fi

  local fulfilled_expr="NULL"
  if [ "$new_status" = "erfuellt" ]; then
    fulfilled_expr="datetime('now')"
  fi

  # ">/dev/null": kein RETURNING hier (analog set_topic_status) -- der geleakte
  # 'PRAGMA busy_timeout'-Rueckgabewert (Lesson S-002) braucht deshalb keine
  # separate .output-Kapselung, da der gesamte Aufruf ohnehin verworfen wird.
  if ! sqlite3 "$db" <<SQL > /dev/null
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
BEGIN IMMEDIATE;
UPDATE ra_milestone
SET status = '$new_status',
    fulfilled_at = $fulfilled_expr
WHERE id = $milestone_id;
COMMIT;
SQL
  then
    echo "FATAL: Statuswechsel fuer Meilenstein '$milestone_id' auf '$new_status' schlug beim Schreiben fehl." >&2
    return 1
  fi

  return 0
}
