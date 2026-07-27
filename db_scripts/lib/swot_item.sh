#!/usr/bin/env bash
# swot_item.sh — Data-Access-Schicht fuer ra_swot_item (strukturierte SWOT-Eintraege
# je Lauf: Kategorie-Enum + kontrolliertes claim_key-Vokabular, OF-06).
#
# Quelle: docs/specs/research-skill.md AC2 (BR-012/OF-06), E2 ("claim_key ausserhalb
# des Vokabulars -> gemappt oder als unmapped zurueckgewiesen, nie freier Slug");
# docs/data-model.md §2.3 (Feldliste), §4 BR-012, §3 (Pflicht-Indizes).
#
# architecture.md: "Data-Access" ist die einzige Schreib-/Lesestelle der
# Bewertungs-Tabellen (single-writer) -- diese Datei IST diese Schicht, analog zu
# topic.sh/run.sh/milestone.sh (S-002/S-003/S-011).
#
# claim_key-Vokabular (OF-06, BR-012): kontrolliert + VERSIONIERT -- KEIN SQL-CHECK-
# Enum (im Gegensatz zu category/evidence_source, siehe 007_ra_swot_item.sql-Header),
# weil eine erweiterbare Business-Taxonomie ueber forward-only-Migrationen hinweg sonst
# bei jeder Erweiterung eine neue Migrationsdatei braeuchte (Simplicity-Leiter Stufe 6:
# App-seitige Validierung gegen eine versionierte Bash-Liste ist der einfachere,
# gleichwertig scharfe Backstop). Erweiterungen des Vokabulars erhoehen
# RA_CLAIM_VOCABULARY_VERSION (v2, v3, ...) -- welche claim_keys zu welcher Version
# galten, bleibt damit nachvollziehbar (kein stilles Nachschieben ohne Versionssprung).
#
# "Mapping" (E2) ist bewusst NUR Normalisierung (trim+lowercase, wie
# run.sh#compute_result_hash/data-model.md §5 Normalisierung) -- KEINE Fuzzy-/
# Synonym-Heuristik (kein AC verlangt das, coder/R01: kein Gold-Plating). Findet die
# normalisierte Eingabe keinen Treffer im Vokabular, wird das Item als "unmapped"
# ZURUECKGEWIESEN (rc=1, NICHTS wird persistiert) statt eines freien Slugs (BR-012).
#
# Verbindungs-Idiom (sqlite/R02, Referenz-Pattern run.sh/milestone.sh): JEDE
# Schreib-Verbindung setzt `PRAGMA foreign_keys = ON;` als eigene erste Anweisung;
# `PRAGMA busy_timeout` steht VOR `BEGIN IMMEDIATE` in derselben Verbindung
# (coder.md-Lesson S-004) und wird bei RETURNING-Nutzung per `.output /dev/null`/
# `.output stdout` unterdrueckt (Lesson S-003), damit sein Rueckgabewert nicht in
# das eingesammelte Ergebnis leakt.

# Kontrolliertes claim_key-Vokabular, Version 1 (OF-06). Erweiterungen erfordern eine
# neue Version -- diese Konstante bleibt mit der Liste zusammen dokumentiert.
RA_CLAIM_VOCABULARY_VERSION="v1"
RA_CLAIM_VOCABULARY=(
  marktgroesse
  marktwachstum
  wettbewerbsintensitaet
  wettbewerbsvorteil
  markteintrittsbarriere
  regulierung
  patentschutz
  technologiereife
  technologierisiko
  teamkompetenz
  finanzierungsbedarf
  kostenstruktur
  skalierbarkeit
  kundennachfrage
  partnerschaftspotenzial
  monetarisierung
)

# claim_key_in_vocabulary <claim-key>
# Reine Pruefung (kein DB-Zugriff, keine SQL-Interpolation): rc=0 gdw. der (bereits
# normalisierte, siehe map_claim_key) claim_key Mitglied des aktuellen Vokabulars ist.
claim_key_in_vocabulary() {
  local key="$1"
  local candidate
  for candidate in "${RA_CLAIM_VOCABULARY[@]}"; do
    if [ "$candidate" = "$key" ]; then
      return 0
    fi
  done
  return 1
}

# map_claim_key <raw-claim-key>
# Normalisiert (trim+lowercase, wie data-model.md §5 Punkt 2) und prueft gegen das
# Vokabular (E2). Treffer: gibt den normalisierten, kanonischen Wert auf stdout aus
# (rc=0). Kein Treffer: KEINE Ausgabe, rc=1 ("unmapped" -- der Aufrufer lehnt das Item
# ab, BR-012: nie ein freier Slug persistiert).
map_claim_key() {
  local raw="$1"
  local normalized
  normalized="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  if claim_key_in_vocabulary "$normalized"; then
    printf '%s' "$normalized"
    return 0
  fi
  return 1
}

# create_swot_item <db-path> <run-id> <category> <raw-claim-key> <evidence-source> [rationale]
# Legt einen strukturierten SWOT-Eintrag an (BR-012). claim_key wird VOR jeder
# SQL-Interpolation ueber map_claim_key() gegen das kontrollierte Vokabular validiert
# (E2, security/R03) -- kein freier Slug erreicht je die Datenbank. category/
# evidence_source werden zusaetzlich zur CHECK-Constraint (007_ra_swot_item.sql) hier
# bereits vor der Interpolation geprueft (security/R03, Referenz-Pattern
# run.sh/milestone.sh). Gibt die neue SWOT-Item-ID (INTEGER) auf stdout aus (rc=0)
# oder bricht mit FATAL auf stderr ab (rc=1, z.B. bei Vokabular-Verstoss oder
# UNIQUE(run_id,category,claim_key)-Kollision).
create_swot_item() {
  local db="$1"
  local run_id="$2"
  local category="$3"
  local raw_claim_key="$4"
  local evidence_source="$5"
  local rationale="${6:-}"

  if ! [[ "$run_id" =~ ^[0-9]+$ ]]; then
    echo "FATAL: run_id '$run_id' ist keine gueltige Ganzzahl -- SWOT-Item-Anlage abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  if ! [[ "$category" =~ ^(strength|weakness|opportunity|threat)$ ]]; then
    echo "FATAL: Kategorie '$category' ist kein gueltiger ra_swot_item.category-Wert (BR-012)." >&2
    return 1
  fi

  if ! [[ "$evidence_source" =~ ^(last30days|deep_research)$ ]]; then
    echo "FATAL: evidence_source '$evidence_source' ist kein gueltiger ra_swot_item.evidence_source-Wert (data-model.md §2.3)." >&2
    return 1
  fi

  local claim_key
  if ! claim_key="$(map_claim_key "$raw_claim_key")"; then
    echo "FATAL: claim_key '$raw_claim_key' liegt ausserhalb des kontrollierten Vokabulars ($RA_CLAIM_VOCABULARY_VERSION) -- als 'unmapped' zurueckgewiesen, nichts persistiert (BR-012/OF-06/E2)." >&2
    return 1
  fi

  local esc_claim_key esc_rationale rationale_expr
  esc_claim_key="${claim_key//\'/\'\'}"
  if [ -z "$rationale" ]; then
    rationale_expr="NULL"
  else
    esc_rationale="${rationale//\'/\'\'}"
    rationale_expr="'$esc_rationale'"
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
INSERT INTO ra_swot_item (run_id, category, claim_key, evidence_source, rationale)
VALUES ($run_id, '$category', '$esc_claim_key', '$evidence_source', $rationale_expr)
RETURNING id;
COMMIT;
SQL
)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    echo "FATAL: SWOT-Item-Anlage fuer Lauf '$run_id' (category='$category', claim_key='$claim_key') schlug fehl (BR-012, ggf. UNIQUE(run_id,category,claim_key) oder unbekannte run_id): $out" >&2
    return 1
  fi

  echo "$out"
  return 0
}

# list_swot_items <db-path> <run-id>
# Reine Lesefunktion (kein PRAGMA foreign_keys noetig, SELECT-only): gibt je
# SWOT-Item eine Zeile "category|claim_key" aus, sortiert nach (category, claim_key)
# -- exakt das Eingabeformat, das db_scripts/lib/run.sh#compute_result_hash und
# db_scripts/lib/divergence.sh#compute_swot_delta als <swot-pairs>-Parameter erwarten
# (run.sh-Datei-Header: "der zukuenftige Aufrufer (Recherche-Skill, S-008 ff.) liefert
# sie, sobald diese Datenquelle existiert"). Kein Trennzeichen-Konflikt (Lesson
# milestone.sh): weder category noch claim_key sind Freitext (category CHECK-Enum,
# claim_key kontrolliertes Vokabular ohne '|', RA_CLAIM_VOCABULARY) -- rationale (die
# einzige Freitext-Spalte) wird hier bewusst NICHT ausgegeben (BR-012: rationale ist
# von Hash+Divergenz ausgeschlossen, diese Funktion liefert nur deren Eingabeformat).
# Leere Ausgabe = noch kein SWOT-Item fuer diesen Lauf (rc bleibt 0, kein Fehlerfall).
list_swot_items() {
  local db="$1"
  local run_id="$2"

  if ! [[ "$run_id" =~ ^[0-9]+$ ]]; then
    echo "FATAL: run_id '$run_id' ist keine gueltige Ganzzahl -- Abfrage abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  sqlite3 -separator '|' "$db" "SELECT category, claim_key FROM ra_swot_item WHERE run_id = $run_id ORDER BY category, claim_key;"
  return 0
}
