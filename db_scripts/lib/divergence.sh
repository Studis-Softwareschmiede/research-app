#!/usr/bin/env bash
# divergence.sh — Data-Access-Schicht fuer ra_divergence (Divergenz zwischen zwei
# Laeufen desselben Themas/derselben Art, materialisiert je Folgelauf).
#
# Quelle: docs/specs/research-datenmodell.md AC3; docs/data-model.md §2.5, §4
# (BR-010/BR-011), §6 (Divergenz-Bildungsregel).
# architecture.md: "Data-Access" ist die einzige Schreib-/Lesestelle der
# Bewertungs-Tabellen (single-writer) -- diese Datei IST diese Schicht (M1, kein
# App-Layer, language: md), analog zu topic.sh/run.sh (S-002/S-003).
#
# Verbindungs-Idiom (sqlite/R02, Referenz-Pattern topic.sh/run.sh): JEDE Schreib-
# Verbindung setzt `PRAGMA foreign_keys = ON;` als eigene erste Anweisung dieser
# frischen CLI-Session.
#
# Scope-Grenze (S-004, AC3, Simplicity-Leiter Stufe 2 -- Wiederverwendung des
# run.sh#compute_result_hash-Musters statt einer neuen Abstraktion): ra_swot_item
# existiert noch nicht (S-003-Datei-Header) und der Meilenstein-Statusstand "zum
# Laufzeitpunkt" wird nirgends historisiert (ra_milestone haelt nur den aktuellen
# Stand). compute_swot_delta()/compute_milestone_delta() nehmen deshalb die
# strukturierten SWOT-/Meilenstein-Tupel BEIDER Laeufe als Parameter entgegen
# (exakt dasselbe Zeilenformat wie compute_result_hash's swot-pairs/
# milestone-triples) statt sie aus einer Tabelle zu lesen -- der kuenftige Aufrufer
# (Recherche-Skill, S-008 ff.) liefert die Schnappschuesse, sobald diese
# Datenquellen existieren. is_empty/recommendation_changed brauchen das NICHT: sie
# werden direkt aus den bereits gespeicherten ra_run-Spalten (result_hash,
# recommendation) gelesen -- einzige Quelle der Wahrheit, keine Duplikation der vom
# Aufrufer gelieferten Tupel noetig (BR-010/BR-011).

# compute_swot_delta <from-swot-pairs> <to-swot-pairs>
# Bildet den SWOT-Delta-Teil (§6, AC3 "Einzel-Item-Differenz (category, claim_key)
# PLUS Kategorie-Rollup"): symmetrische Differenz der (category, claim_key)-Mengen
# zwischen Vorlauf (from) und Folgelauf (to), plus je Kategorie mit Aenderung eine
# Rollup-Zaehlung (added/removed-Anzahl).
#
# <swot-pairs>: zeilenweise "category|claim_key" (leerer String = keine Paare),
# identisches Format zu run.sh#compute_result_hash. Normalisierung wie dort
# (lower(trim(...))) -- BR-012: nur category+claim_key fliessen ein, rationale/
# evidence_source/IDs bleiben aussen vor.
#
# Gibt kanonisches JSON auf stdout aus:
#   {"added": [[category,claim_key], ...], "removed": [[...], ...],
#    "by_category": {category: {"added": n, "removed": n}, ...}}
# (added/removed jeweils lexikografisch sortiert; by_category nur fuer Kategorien
# mit tatsaechlicher Aenderung).
compute_swot_delta() {
  local from_pairs="$1"
  local to_pairs="$2"

  local from_inserts="" to_inserts=""
  local cat key esc_cat esc_key
  if [ -n "$from_pairs" ]; then
    while IFS='|' read -r cat key || [ -n "$cat" ] || [ -n "$key" ]; do
      [ -z "$cat" ] && [ -z "$key" ] && continue
      esc_cat="${cat//\'/\'\'}"
      esc_key="${key//\'/\'\'}"
      from_inserts="$from_inserts
INSERT INTO from_swot_raw (category, claim_key) VALUES ('$esc_cat', '$esc_key');"
    done <<< "$from_pairs"
  fi
  if [ -n "$to_pairs" ]; then
    while IFS='|' read -r cat key || [ -n "$cat" ] || [ -n "$key" ]; do
      [ -z "$cat" ] && [ -z "$key" ] && continue
      esc_cat="${cat//\'/\'\'}"
      esc_key="${key//\'/\'\'}"
      to_inserts="$to_inserts
INSERT INTO to_swot_raw (category, claim_key) VALUES ('$esc_cat', '$esc_key');"
    done <<< "$to_pairs"
  fi

  local out rc
  out="$(sqlite3 ':memory:' <<SQL
CREATE TEMP TABLE from_swot_raw (category TEXT, claim_key TEXT);
CREATE TEMP TABLE to_swot_raw (category TEXT, claim_key TEXT);
$from_inserts
$to_inserts
CREATE TEMP TABLE from_swot AS SELECT lower(trim(category)) AS category, lower(trim(claim_key)) AS claim_key FROM from_swot_raw;
CREATE TEMP TABLE to_swot AS SELECT lower(trim(category)) AS category, lower(trim(claim_key)) AS claim_key FROM to_swot_raw;
WITH added AS (
  SELECT category, claim_key FROM to_swot
  EXCEPT
  SELECT category, claim_key FROM from_swot
),
removed AS (
  SELECT category, claim_key FROM from_swot
  EXCEPT
  SELECT category, claim_key FROM to_swot
),
cats AS (
  SELECT category FROM added
  UNION
  SELECT category FROM removed
)
SELECT json_object(
  'added', (SELECT COALESCE(json_group_array(json_array(category, claim_key)), '[]') FROM (SELECT category, claim_key FROM added ORDER BY 1, 2)),
  'removed', (SELECT COALESCE(json_group_array(json_array(category, claim_key)), '[]') FROM (SELECT category, claim_key FROM removed ORDER BY 1, 2)),
  'by_category', (SELECT COALESCE(json_group_object(category, json_object(
       'added', (SELECT COUNT(*) FROM added a WHERE a.category = c.category),
       'removed', (SELECT COUNT(*) FROM removed r WHERE r.category = c.category)
     )), '{}')
     FROM (SELECT DISTINCT category FROM cats ORDER BY category) c)
);
SQL
)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    echo "FATAL: SWOT-Delta-Bildung schlug fehl: $out" >&2
    return 1
  fi
  printf '%s' "$out"
  return 0
}

# compute_milestone_delta <from-milestone-triples> <to-milestone-triples>
# Bildet den Meilenstein-Delta-Teil (§6, AC3 "Meilenstein-Status-Delta"): geaenderte
# (milestone_stable_key, status)-Tripel zwischen Vorlauf (from) und Folgelauf (to)
# -- inkl. neu hinzugekommener (from_status=null) bzw. entfallener
# (to_status=null) Meilensteine. Kein Kategorie-Rollup (AC3 sieht das Rollup nur
# fuer den SWOT-Delta vor, nicht fuer Meilensteine).
#
# <milestone-triples>: zeilenweise "milestone_stable_key|status|responsibility",
# identisches Format zu run.sh#compute_result_hash (responsibility fliesst hier
# nicht in den Vergleich ein -- §6 nennt nur (milestone_stable_key, status)).
#
# Gibt kanonisches JSON auf stdout aus:
#   {"changed": [{"milestone_stable_key":..., "from_status":..., "to_status":...}, ...]}
# (sortiert nach milestone_stable_key, nur Eintraege mit tatsaechlicher Aenderung).
compute_milestone_delta() {
  local from_triples="$1"
  local to_triples="$2"

  local from_inserts="" to_inserts=""
  local mkey status responsibility esc_mkey esc_status
  if [ -n "$from_triples" ]; then
    while IFS='|' read -r mkey status responsibility || [ -n "$mkey" ] || [ -n "$status" ] || [ -n "$responsibility" ]; do
      [ -z "$mkey" ] && [ -z "$status" ] && [ -z "$responsibility" ] && continue
      esc_mkey="${mkey//\'/\'\'}"
      esc_status="${status//\'/\'\'}"
      from_inserts="$from_inserts
INSERT INTO from_ms_raw (mkey, status) VALUES ('$esc_mkey', '$esc_status');"
    done <<< "$from_triples"
  fi
  if [ -n "$to_triples" ]; then
    while IFS='|' read -r mkey status responsibility || [ -n "$mkey" ] || [ -n "$status" ] || [ -n "$responsibility" ]; do
      [ -z "$mkey" ] && [ -z "$status" ] && [ -z "$responsibility" ] && continue
      esc_mkey="${mkey//\'/\'\'}"
      esc_status="${status//\'/\'\'}"
      to_inserts="$to_inserts
INSERT INTO to_ms_raw (mkey, status) VALUES ('$esc_mkey', '$esc_status');"
    done <<< "$to_triples"
  fi

  local out rc
  out="$(sqlite3 ':memory:' <<SQL
CREATE TEMP TABLE from_ms_raw (mkey TEXT, status TEXT);
CREATE TEMP TABLE to_ms_raw (mkey TEXT, status TEXT);
$from_inserts
$to_inserts
CREATE TEMP TABLE from_ms AS SELECT lower(trim(mkey)) AS mkey, lower(trim(status)) AS status FROM from_ms_raw;
CREATE TEMP TABLE to_ms AS SELECT lower(trim(mkey)) AS mkey, lower(trim(status)) AS status FROM to_ms_raw;
WITH all_keys AS (
  SELECT mkey FROM from_ms
  UNION
  SELECT mkey FROM to_ms
),
paired AS (
  SELECT ak.mkey AS mkey,
         (SELECT status FROM from_ms f WHERE f.mkey = ak.mkey) AS from_status,
         (SELECT status FROM to_ms t WHERE t.mkey = ak.mkey) AS to_status
  FROM all_keys ak
),
changed AS (
  SELECT mkey, from_status, to_status FROM paired WHERE from_status IS NOT to_status
)
SELECT json_object('changed', COALESCE((
  SELECT json_group_array(json_object('milestone_stable_key', mkey, 'from_status', from_status, 'to_status', to_status))
  FROM (SELECT mkey, from_status, to_status FROM changed ORDER BY mkey)
), '[]'));
SQL
)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    echo "FATAL: Meilenstein-Delta-Bildung schlug fehl: $out" >&2
    return 1
  fi
  printf '%s' "$out"
  return 0
}

# create_divergence <db-path> <from-run-id> <to-run-id> <swot-delta-json> <milestone-delta-json>
# Materialisiert eine Divergenz zwischen zwei Laeufen (BR-010/BR-011, "je
# Folgelauf"). topic_id/kind werden NICHT vom Aufrufer uebergeben, sondern aus den
# beiden referenzierten ra_run-Zeilen gelesen und dabei auf Gleichheit geprueft
# (BR-011: "beide Laeufe gleicher Art UND gleiches Thema") -- vermeidet einen
# widerspruechlichen Aufrufer-Parameter, der ra_run widersprechen koennte.
# is_empty (BR-010, "gdw. hash(from)=hash(to)") und recommendation_changed werden
# aus den bereits gespeicherten ra_run.result_hash/recommendation-Werten berechnet,
# nicht aus swot-delta/milestone-delta hergeleitet (einzige Quelle der Wahrheit).
# Validiert alle Eingaben gegen ihr erwartetes Format VOR jeder SQL-Interpolation
# (security/R03, Referenz-Pattern topic.sh/run.sh).
# Gibt die neue ra_divergence.id auf stdout aus (rc=0) oder bricht mit FATAL auf
# stderr ab.
create_divergence() {
  local db="$1"
  local from_run_id="$2"
  local to_run_id="$3"
  local swot_delta="$4"
  local milestone_delta="$5"

  if ! [[ "$from_run_id" =~ ^[0-9]+$ ]]; then
    echo "FATAL: from-run-id '$from_run_id' ist keine gueltige ra_run.id -- Divergenz-Anlage abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi
  if ! [[ "$to_run_id" =~ ^[0-9]+$ ]]; then
    echo "FATAL: to-run-id '$to_run_id' ist keine gueltige ra_run.id -- Divergenz-Anlage abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  local from_row to_row
  from_row="$(sqlite3 -separator '|' "$db" "SELECT topic_id, kind, result_hash, recommendation FROM ra_run WHERE id = $from_run_id;")"
  if [ -z "$from_row" ]; then
    echo "FATAL: Vorlauf (from_run_id=$from_run_id) existiert nicht -- Divergenz-Anlage abgelehnt." >&2
    return 1
  fi
  to_row="$(sqlite3 -separator '|' "$db" "SELECT topic_id, kind, result_hash, recommendation FROM ra_run WHERE id = $to_run_id;")"
  if [ -z "$to_row" ]; then
    echo "FATAL: Folgelauf (to_run_id=$to_run_id) existiert nicht -- Divergenz-Anlage abgelehnt." >&2
    return 1
  fi

  local from_topic from_kind from_hash from_rec
  local to_topic to_kind to_hash to_rec
  IFS='|' read -r from_topic from_kind from_hash from_rec <<< "$from_row"
  IFS='|' read -r to_topic to_kind to_hash to_rec <<< "$to_row"

  if [ "$from_topic" != "$to_topic" ]; then
    echo "FATAL: Vorlauf (Thema '$from_topic') und Folgelauf (Thema '$to_topic') gehoeren zu verschiedenen Themen -- Divergenz nur innerhalb desselben Themas zulaessig (BR-011)." >&2
    return 1
  fi
  if [ "$from_kind" != "$to_kind" ]; then
    echo "FATAL: Vorlauf (Art '$from_kind') und Folgelauf (Art '$to_kind') haben unterschiedliche Lauf-Art -- Divergenz nur zwischen Laeufen derselben Art zulaessig (BR-011)." >&2
    return 1
  fi

  local is_empty=0
  [ "$from_hash" = "$to_hash" ] && is_empty=1
  local recommendation_changed=0
  [ "$from_rec" != "$to_rec" ] && recommendation_changed=1

  # is_empty ist die einzige Quelle der Wahrheit (Hash-Vergleich oben) -- der
  # CHECK-Constraint in 005_ra_divergence.sql verlangt is_empty=0 ODER beide
  # Deltas NULL. Verwirft hier aktiv die vom Aufrufer gelieferten Delta-Strings,
  # statt dem Aufrufer die is_empty-Kenntnis vorab abzuverlangen (S-019-Lesson):
  # zwei verschiedene Laeufe mit zufaellig identischem result_hash lieferten
  # sonst nicht-leere Deltas bei is_empty=1 -> CHECK-Constraint-Verletzung.
  if [ "$is_empty" -eq 1 ]; then
    swot_delta=""
    milestone_delta=""
  fi

  local esc_swot_delta esc_milestone_delta
  esc_swot_delta="${swot_delta//\'/\'\'}"
  esc_milestone_delta="${milestone_delta//\'/\'\'}"

  local swot_expr milestone_expr
  if [ -z "$swot_delta" ]; then
    swot_expr="NULL"
  else
    swot_expr="'$esc_swot_delta'"
  fi
  if [ -z "$milestone_delta" ]; then
    milestone_expr="NULL"
  else
    milestone_expr="'$esc_milestone_delta'"
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
INSERT INTO ra_divergence (topic_id, kind, from_run_id, to_run_id, is_empty, recommendation_changed, swot_delta, milestone_status_delta)
VALUES ('$from_topic', '$from_kind', $from_run_id, $to_run_id, $is_empty, $recommendation_changed, $swot_expr, $milestone_expr)
RETURNING id;
COMMIT;
SQL
)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    echo "FATAL: Divergenz-Anlage fuer Laeufe from=$from_run_id/to=$to_run_id schlug fehl (BR-010/BR-011, UNIQUE(from_run_id,to_run_id)): $out" >&2
    return 1
  fi

  echo "$out"
  return 0
}

# get_divergence <db-path> <from-run-id> <to-run-id>
# Reine Lesefunktion (gate-pm-anstoss#AC4/AC5): gibt eine bereits materialisierte
# Divergenz-Zeile fuer dieses Laufpaar als "is_empty|recommendation_changed|
# swot_delta|milestone_status_delta" aus, oder leere Ausgabe, wenn noch keine
# existiert (rc=0, kein Fehlerfall). Ermoeglicht dem Aufrufer
# (orchestrator.sh#materialize_and_render_divergence), einen bereits angelegten
# Datensatz wiederzuverwenden statt erneut gegen UNIQUE(from_run_id,to_run_id) zu
# laufen (gefahrloser Neustart, analog pm_dispatch.sh#dispatch_pm_handoff-Idempotenz).
get_divergence() {
  local db="$1"
  local from_run_id="$2"
  local to_run_id="$3"

  if ! [[ "$from_run_id" =~ ^[0-9]+$ ]]; then
    echo "FATAL: from-run-id '$from_run_id' ist keine gueltige Ganzzahl -- Abfrage abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi
  if ! [[ "$to_run_id" =~ ^[0-9]+$ ]]; then
    echo "FATAL: to-run-id '$to_run_id' ist keine gueltige Ganzzahl -- Abfrage abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  sqlite3 -separator '|' "$db" "SELECT is_empty, recommendation_changed, swot_delta, milestone_status_delta FROM ra_divergence WHERE from_run_id = $from_run_id AND to_run_id = $to_run_id;" 2>/dev/null
  return 0
}
