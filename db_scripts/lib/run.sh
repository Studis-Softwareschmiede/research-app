#!/usr/bin/env bash
# run.sh — Data-Access-Schicht fuer ra_run (versionierte Laeufe + result_hash).
#
# Quelle: docs/specs/research-datenmodell.md AC2; docs/data-model.md §2.2, §4
# (BR-007..BR-009, BR-013/BR-014), §5 (result_hash-Bildungsregel).
# architecture.md: "Data-Access" ist die einzige Schreib-/Lesestelle der
# Bewertungs-Tabellen (single-writer) -- diese Datei IST diese Schicht (M1, kein
# App-Layer, language: md), analog zu topic.sh (S-002).
#
# Verbindungs-Idiom (sqlite/R02, Referenz-Pattern topic.sh): JEDE Schreib-Verbindung
# setzt `PRAGMA foreign_keys = ON;` als eigene erste Anweisung dieser frischen
# CLI-Session (das PRAGMA persistiert NICHT ueber Verbindungen hinweg).
#
# Scope-Grenze (S-003, AC2): ra_swot_item existiert weiterhin NICHT (auch nach
# S-004/S-005 -- ra_milestone kam mit S-005, ra_swot_item bleibt bewusst aussen
# vor, siehe db_scripts/lib/divergence.sh-Datei-Header, S-004). compute_result_hash()
# liest deshalb NICHT selbst aus einer solchen (nicht existenten) Tabelle, sondern
# nimmt die strukturierten Eingaben (SWOT-Paare, Meilenstein-Tripel) als Parameter
# entgegen -- der zukuenftige Aufrufer (Recherche-Skill, S-008 ff.) liefert sie,
# sobald diese Datenquelle existiert. Das entspricht der Bildungsregel selbst
# (data-model.md §5): sie ist eine reine Funktion ueber strukturierte Werte, keine
# SQL-Query gegen ein bestimmtes Schema. divergence.sh (S-004) uebernimmt exakt
# dasselbe Parameter-Format fuer seine compute_swot_delta()/compute_milestone_delta().

# compute_result_hash <recommendation> <swot-pairs> <milestone-triples>
# Bildet den Ergebnisstand-Hash (BR-009, §5): kanonische JSON-Serialisierung ueber
#   - recommendation (Enum-Wert)
#   - die SWOT-Claims als (category, claim_key)-Paare
#   - den Meilenstein-Statusstand als (milestone_stable_key, status, responsibility)-
#     Tripel
# gefolgt von SHA-256 ueber die UTF-8-Bytes. SQLite hat keine eingebaute SHA-256-
# Funktion (Simplicity-Leiter Stufe 4/5 -- kein Extension-Ladepfad noetig): die
# JSON-Kanonisierung (Normalisierung + stabile Tupel-Sortierung + Escaping) macht
# SQLite selbst via json1 (bereits Kern-Abhaengigkeit), den finalen Hash bildet
# `shasum -a 256` (bereits Kern-Abhaengigkeit, wie apply_migrations.sh). Sortierung
# ueber echte SQL-Spalten (ORDER BY) statt Bash-String-Split vermeidet den
# Praefix-Fallstrick eines naiven "feld1|feld2"-String-Sorts (z.B. "cat" vs.
# "category").
#
# <swot-pairs>:       zeilenweise "category|claim_key" (leerer String = keine Paare).
# <milestone-triples>: zeilenweise "milestone_stable_key|status|responsibility"
#                       (leerer String = keine Tripel).
# Normalisierung (§5 Punkt 2): Enum-Werte kleingeschrieben, Strings getrimmt, Listen
# stabil lexikografisch nach Tupel sortiert -- via `lower(trim(...))` + `ORDER BY`.
# Ausgeschlossen (§5 Punkt 3): rationale/Zeitstempel/IDs/l30d_source_ref/
# has_deep_research/momentum_only fliessen bewusst NICHT als Parameter ein.
#
# Gibt den SHA-256-Hex-Digest (64 Zeichen, kleingeschrieben) auf stdout aus.
compute_result_hash() {
  local recommendation="$1"
  local swot_pairs="$2"
  local milestone_triples="$3"

  # Case-insensitive geprueft (nicht wie create_run's strikte Enum-Pruefung): §5
  # Punkt 2 normalisiert Enum-Werte explizit auf kleingeschrieben VOR dem Hashen --
  # ein Aufrufer (z.B. ein Judge-Ergebnis) darf hier bereits in beliebiger
  # Gross-/Kleinschreibung uebergeben, ohne dass sich der resultierende Hash aendert.
  local rec_check
  rec_check="$(printf '%s' "$recommendation" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if ! [[ "$rec_check" =~ ^(weiterverfolgen|parken|verwerfen)$ ]]; then
    echo "FATAL: Empfehlung '$recommendation' ist kein gueltiger ra_run.recommendation-Wert (BR-013) -- Hash-Bildung abgebrochen." >&2
    return 1
  fi
  local esc_rec="${recommendation//\'/\'\'}"

  local swot_inserts=""
  if [ -n "$swot_pairs" ]; then
    local cat key
    while IFS='|' read -r cat key || [ -n "$cat" ] || [ -n "$key" ]; do
      [ -z "$cat" ] && [ -z "$key" ] && continue
      local esc_cat="${cat//\'/\'\'}"
      local esc_key="${key//\'/\'\'}"
      swot_inserts="$swot_inserts
INSERT INTO _ra_run_hash_swot (category, claim_key) VALUES ('$esc_cat', '$esc_key');"
    done <<< "$swot_pairs"
  fi

  local milestone_inserts=""
  if [ -n "$milestone_triples" ]; then
    local mkey status responsibility
    while IFS='|' read -r mkey status responsibility || [ -n "$mkey" ] || [ -n "$status" ] || [ -n "$responsibility" ]; do
      [ -z "$mkey" ] && [ -z "$status" ] && [ -z "$responsibility" ] && continue
      local esc_mkey="${mkey//\'/\'\'}"
      local esc_status="${status//\'/\'\'}"
      local esc_resp="${responsibility//\'/\'\'}"
      milestone_inserts="$milestone_inserts
INSERT INTO _ra_run_hash_milestone (mkey, status, responsibility) VALUES ('$esc_mkey', '$esc_status', '$esc_resp');"
    done <<< "$milestone_triples"
  fi

  local canonical rc
  canonical="$(sqlite3 ':memory:' <<SQL
CREATE TEMP TABLE _ra_run_hash_swot (category TEXT, claim_key TEXT);
CREATE TEMP TABLE _ra_run_hash_milestone (mkey TEXT, status TEXT, responsibility TEXT);
$swot_inserts
$milestone_inserts
SELECT json_object(
  'milestones', json(COALESCE((
    SELECT json_group_array(json_array(mkey, status, responsibility))
    FROM (
      SELECT lower(trim(mkey)) AS mkey, lower(trim(status)) AS status, lower(trim(responsibility)) AS responsibility
      FROM _ra_run_hash_milestone
      ORDER BY 1, 2, 3
    )
  ), '[]')),
  'recommendation', lower(trim('$esc_rec')),
  'swot', json(COALESCE((
    SELECT json_group_array(json_array(category, claim_key))
    FROM (
      SELECT lower(trim(category)) AS category, lower(trim(claim_key)) AS claim_key
      FROM _ra_run_hash_swot
      ORDER BY 1, 2
    )
  ), '[]'))
);
SQL
)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$canonical" ]; then
    echo "FATAL: kanonische JSON-Bildung fuer result_hash schlug fehl: $canonical" >&2
    return 1
  fi

  printf '%s' "$canonical" | shasum -a 256 | awk '{print $1}'
  return 0
}

# create_run <db-path> <topic-id> <kind> <result-hash> <recommendation> <has-deep-research> <momentum-only> [l30d-source-ref]
# Legt einen neuen Lauf an: Version = naechste monotone Version je (topic_id, kind)
# (BR-007, COALESCE(MAX(version),0)+1 innerhalb derselben INSERT...SELECT-Anweisung,
# UNIQUE(topic_id,kind,version) als Backstop gegen Nebenlaeufigkeits-Kollisionen).
# `result_hash` wird vom Aufrufer per compute_result_hash() vorab gebildet und hier
# nur noch validiert + abgelegt (Trennung Versions-Vergabe vs. Hash-Bildung).
# Validiert alle Eingaben gegen ihr erwartetes Format/Enum VOR jeder SQL-Interpolation
# (security/R03, Referenz-Pattern topic.sh set_topic_status).
# Gibt "<run-id>|<version>" auf stdout aus (rc=0) oder bricht mit FATAL auf stderr ab.
create_run() {
  local db="$1"
  local topic_id="$2"
  local kind="$3"
  local result_hash="$4"
  local recommendation="$5"
  local has_deep_research="$6"
  local momentum_only="$7"
  local l30d_source_ref="${8:-}"

  if ! [[ "$topic_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "FATAL: Themen-ID '$topic_id' verletzt das UUID-Format -- Lauf-Anlage abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  if ! [[ "$kind" =~ ^(recherche|pm)$ ]]; then
    echo "FATAL: Lauf-Art '$kind' ist kein gueltiger ra_run.kind-Wert (BR-008)." >&2
    return 1
  fi

  if ! [[ "$result_hash" =~ ^[0-9a-f]{64}$ ]]; then
    echo "FATAL: result_hash '$result_hash' verletzt das erwartete SHA-256-Hex-Format (BR-009) -- Lauf-Anlage abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  if ! [[ "$recommendation" =~ ^(weiterverfolgen|parken|verwerfen)$ ]]; then
    echo "FATAL: Empfehlung '$recommendation' ist kein gueltiger ra_run.recommendation-Wert (BR-013)." >&2
    return 1
  fi

  if ! [[ "$has_deep_research" =~ ^[01]$ ]]; then
    echo "FATAL: has_deep_research '$has_deep_research' muss 0 oder 1 sein." >&2
    return 1
  fi

  if ! [[ "$momentum_only" =~ ^[01]$ ]]; then
    echo "FATAL: momentum_only '$momentum_only' muss 0 oder 1 sein." >&2
    return 1
  fi

  if [ "$has_deep_research" = "0" ] && [ "$momentum_only" != "1" ]; then
    echo "FATAL: has_deep_research=0 erfordert momentum_only=1 (BR-014, 'gdw.')." >&2
    return 1
  fi
  if [ "$has_deep_research" = "1" ] && [ "$momentum_only" != "0" ]; then
    echo "FATAL: has_deep_research=1 erfordert momentum_only=0 (BR-014, 'gdw.')." >&2
    return 1
  fi

  local l30d_expr
  if [ -z "$l30d_source_ref" ]; then
    l30d_expr="NULL"
  else
    local esc_l30d="${l30d_source_ref//\'/\'\'}"
    l30d_expr="'$esc_l30d'"
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
INSERT INTO ra_run (topic_id, kind, version, result_hash, recommendation, has_deep_research, momentum_only, l30d_source_ref)
SELECT '$topic_id', '$kind', COALESCE(MAX(version), 0) + 1, '$result_hash', '$recommendation', $has_deep_research, $momentum_only, $l30d_expr
FROM ra_run WHERE topic_id = '$topic_id' AND kind = '$kind'
RETURNING id, version;
COMMIT;
SQL
)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    echo "FATAL: Lauf-Anlage fuer Thema '$topic_id' (kind='$kind') schlug fehl (BR-007/BR-008/BR-009): $out" >&2
    return 1
  fi

  echo "$out"
  return 0
}
