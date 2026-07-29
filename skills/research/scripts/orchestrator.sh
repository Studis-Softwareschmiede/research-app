#!/usr/bin/env bash
# orchestrator.sh — /research-Skill-Einstieg: Modus-Wahl (discovery|thema),
# Themen-Anlage ueber die Data-Access-Schicht, last30days-Aufruf,
# Quellen-Resilienz-Brief (research-skill#AC1,AC6,AC7, S-007-Grundgeruest),
# Voraussetzungs-Ueberblick: Meilenstein-Liste + Schutzrechte-Klaerungspunkt
# (research-skill#AC5, S-011), Bewertungsschicht-Anzeige: SWOT-Zusammenfassung +
# Empfehlung + Businessplan-Template (research-skill#AC2, S-008),
# Entscheidungs-Gate: explizite PM-Anstoss-Wahl NUR bei 'weiterverfolgen',
# nie automatisch (gate-pm-anstoss#AC1, S-016).
#
# Quelle: docs/specs/research-skill.md AC1/AC2/AC4/AC5/AC6/AC7 + Edge-Cases
# E1/E2/E3. docs/specs/gate-pm-anstoss.md AC1. docs/architecture.md
# "Orchestrator"-Komponente (Einstieg; waehlt Modus, ruft Paesse in
# Reihenfolge) + "Voraussetzungs-Ueberblick"-Komponente ("Klaerungspunkte
# inkl. Schutzrechte, kein Rechtsmodul") + "SWOT-Judge"/"Recommendation"/
# "Businessplan-Emitter"/"Gate"-Komponenten (BR-102: Uebergang nach
# 'uebergeben'/'im_pm' nur ueber das Gate). Deep-Research (AC3)
# ist weiterhin NICHT Teil dieser Datei -- sie folgt mit S-009 (separater
# Scope). Die eigentliche SWOT-Bewertung (Kategorie+claim_key je Claim,
# create_swot_item) UND die Lauf-Anlage (create_run mit recommendation/
# has_deep_research/momentum_only) werden -- analog zur Meilenstein-CRUD
# (S-011) -- vom Skill-Ausfuehrenden (Claude, SKILL.md) waehrend der
# eigentlichen Recherche aufgerufen, NICHT von diesem Skript selbst berechnet.
# recommendation ist aber ab S-010 auch KEIN freier Judge-Entscheid mehr:
# derive_recommendation() bildet den deterministischen Default aus dem
# Meilenstein-Status (AC4/BR-013, data-model.md §8) -- Claude ruft ihn ueber
# den `recommend`-Subbefehl VOR create_run auf und weicht nur mit einer im
# Brief dokumentierten Begruendung ab (Hybrid, OF-09 -- z.B. fuer 'verwerfen',
# das dieser Funktion bewusst nicht automatisch zugaenglich ist).
# print_swot_summary/print_recommendation/print_businessplan_template rendern
# nur den bereits von Claude persistierten Stand eines Laufs (analog
# print_milestone_overview fuer AC5) -- erreichbar ueber den `evaluation`-
# Subbefehl (main()).
#
# Boundary-Konformitaet (architecture.md, Review-Blocker): dieses Skript
# beruehrt SQLite NIE direkt -- jede Themen-/Meilenstein-/Lauf-/SWOT-Anlage/
# -Abfrage laeuft ausschliesslich ueber db_scripts/lib/topic.sh
# (create_topic/find_topic_by_title), db_scripts/lib/milestone.sh
# (create_milestone/list_milestones/set_milestone_status),
# db_scripts/lib/run.sh (get_run) und db_scripts/lib/swot_item.sh
# (list_swot_items) sowie die Sperre ueber db_scripts/lib/topic_lock.sh
# (acquire_topic_lock/release_topic_lock). last30days wird ausschliesslich ueber
# lib/last30days_client.sh aufgerufen (Discovery/Ingest-Pass).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=lib/last30days_client.sh
source "$SCRIPT_DIR/lib/last30days_client.sh"
# shellcheck source=../../../db_scripts/lib/topic.sh
source "$REPO_ROOT/db_scripts/lib/topic.sh"
# shellcheck source=../../../db_scripts/lib/topic_lock.sh
source "$REPO_ROOT/db_scripts/lib/topic_lock.sh"
# shellcheck source=../../../db_scripts/lib/milestone.sh
source "$REPO_ROOT/db_scripts/lib/milestone.sh"
# shellcheck source=../../../db_scripts/lib/run.sh
source "$REPO_ROOT/db_scripts/lib/run.sh"
# shellcheck source=../../../db_scripts/lib/swot_item.sh
source "$REPO_ROOT/db_scripts/lib/swot_item.sh"
# shellcheck source=../../../db_scripts/lib/pm_dispatch.sh
source "$REPO_ROOT/db_scripts/lib/pm_dispatch.sh"

RA_DB_PATH="${RA_DB_PATH:-research-app.sqlite}"
RA_SAVE_DIR="${RA_SAVE_DIR:-last30days-runs}"
RA_LOCK_HOLDER="${RA_LOCK_HOLDER:-research}"
RA_LOCK_TTL_SECONDS="${RA_LOCK_TTL_SECONDS:-1800}"

# check_store_or_die <db-path>
# E1 ("Store fehlt"): prueft VOR jedem last30days-Aufruf, ob die eigene
# research-app.sqlite existiert UND migriert ist (Tabelle ra_topic vorhanden)
# -- "kein Halb-Lauf" (sonst wuerde last30days bereits einen Lauf gefahren
# haben, bevor die anschliessende Persistenz scheitert). Delegiert die
# eigentliche Pruefung an db_scripts/lib/topic.sh#ra_topic_store_ready (keine
# rohe SQLite-Abfrage aus dem Skill-Skript heraus, architecture.md
# Boundary-Regel).
check_store_or_die() {
  local db="$1"

  if [ ! -f "$db" ]; then
    echo "FATAL: research-app.sqlite '$db' existiert nicht -- Store fehlt (E1). Handlungsanweisung: 'db_scripts/migrate.sh $db' ausfuehren, dann erneut versuchen. Lauf abgebrochen VOR jedem last30days-Aufruf (kein Halb-Lauf)." >&2
    return 1
  fi

  if ! ra_topic_store_ready "$db"; then
    echo "FATAL: research-app.sqlite '$db' ist nicht migriert (Tabelle 'ra_topic' fehlt) -- Store fehlt (E1). Handlungsanweisung: 'db_scripts/migrate.sh $db' ausfuehren, dann erneut versuchen." >&2
    return 1
  fi

  return 0
}

# resolve_or_create_topic <db-path> <title>
# AC6/BR-109: exakt EIN bestehendes Thema mit identischem Titel wird
# wiederverwendet (stabile Themen-ID ueber mehrere Laeufe); bei keinem oder
# mehreren Treffern (frueherer OF-02-Duplikat-Fall) legt create_topic ein neues
# Thema an (Titel-Duplikat-Warnung greift dann regulaer, unveraendert aus
# S-002). Gibt die Themen-ID auf stdout aus (rc=0) oder bricht mit FATAL ab
# (rc=1, Fehler kommt bereits von create_topic auf stderr).
resolve_or_create_topic() {
  local db="$1"
  local title="$2"
  local matches match_count topic_id

  matches="$(find_topic_by_title "$db" "$title")"
  if [ -z "$matches" ]; then
    match_count=0
  else
    match_count="$(printf '%s\n' "$matches" | grep -c .)"
  fi

  if [ "$match_count" -eq 1 ]; then
    topic_id="$matches"
    echo "INFO: bestehendes Thema '$title' wiederverwendet (ID $topic_id, BR-109 stabile Identitaet ueber mehrere Laeufe)." >&2
  else
    topic_id="$(create_topic "$db" "$title")" || return 1
  fi

  printf '%s' "$topic_id"
  return 0
}

# print_missing_sources_note <json-file>
# AC7: gibt den "fehlende Quellen"-Teil des Briefs aus (leer = alle Quellen
# vollstaendig).
print_missing_sources_note() {
  local json_file="$1"
  local missing
  missing="$(extract_missing_sources "$json_file")" || return 1

  if [ -z "$missing" ]; then
    echo "Quellen: alle vollstaendig (kein Ausfall, AC7)."
  else
    echo "Fehlende Quellen (ausgefallen, Lauf laeuft mit den verbleibenden Quellen durch, AC7):"
    printf '%s\n' "$missing" | while IFS='|' read -r src status; do
      echo "  - $src: $status"
    done
  fi
  return 0
}

# print_milestone_overview <db-path> <topic-id>
# AC5 ("Voraussetzungs-Ueberblick"): rendert die aktuelle Meilenstein-Liste des
# Themas (Status + Zustaendigkeit extern/eigen, ueber db_scripts/lib/milestone.sh
# #list_milestones -- kein direkter SQLite-Zugriff) und haengt IMMER den fixen
# Schutzrechte-Klaerungspunkt an (C-004, docs/concept.md: "Schutzrechte erscheinen
# nur als Klaerungspunkt im Voraussetzungs-Ueberblick" -- kein Rechtsmodul, keine
# eigene Pruef-/Bewertungslogik dafuer). Die eigentliche Anlage/Aktualisierung der
# Meilensteine (create_milestone/set_milestone_status) erfolgt waehrend der
# Recherche selbst (SKILL.md) -- diese Funktion zeigt nur den zum Aufrufzeitpunkt
# bereits persistierten Stand.
#
# Parsing (DBA-Review Iteration 2, Important-Fund): list_milestones trennt seine
# Felder mit dem ASCII Unit Separator (0x1F, `$'\x1f'`), NICHT mit `|` -- die
# unrestringierte `description`-Spalte (CHECK erlaubt jeden Nicht-Leer-Text, kann
# also `|` enthalten) sitzt mitten in der Zeile; ein `|`-IFS wuerde bei einem `|` in
# der Beschreibung alle Folgefelder verschieben und Status/Zustaendigkeit im Brief
# lautlos falsch anzeigen. `IFS=$'\x1f'` MUSS mit dem Trennzeichen aus
# list_milestones uebereinstimmen (milestone.sh-Datei-Header).
print_milestone_overview() {
  local db="$1"
  local topic_id="$2"
  local rows id description responsibility status watch_ref

  echo "-- Voraussetzungs-Ueberblick --"
  rows="$(list_milestones "$db" "$topic_id")" || return 1

  if [ -z "$rows" ]; then
    echo "Noch keine Meilensteine fuer dieses Thema hinterlegt."
  else
    while IFS=$'\x1f' read -r id description responsibility status watch_ref; do
      [ -z "$id" ] && continue
      if [ -n "$watch_ref" ]; then
        echo "  - [$status] $description (Zustaendigkeit: $responsibility, Watchlist-Ref: $watch_ref)"
      else
        echo "  - [$status] $description (Zustaendigkeit: $responsibility)"
      fi
    done <<< "$rows"
  fi

  echo "Klaerungspunkt Schutzrechte: zu pruefen, kein automatisiertes Rechtsmodul (C-004)."
  return 0
}

# derive_recommendation <db-path> <topic-id>
# AC4/BR-013 (data-model.md §8, Hybrid-Default, S-010-Praezisierung): leitet
# die Empfehlung deterministisch aus dem aktuellen Meilenstein-Status des
# Themas ab -- reiner Logik-Pass ueber den bereits von list_milestones
# gelieferten Stand (keine eigene SQL-Anfrage; architecture.md
# "Recommendation"-Komponente kennt nur "Lauf-Daten", kein SQLite direkt,
# Boundary-Regel). Deckt genau die beiden automatisch ableitbaren Zweige der
# §8-Regel ab:
#   - >=1 offener EXTERNER Meilenstein -> "parken" (Watchlist-Kopplung
#     greift, BR-015 -- automatische Wiedervorlage nach Erfuellung/Delta).
#   - sonst (keine offenen externen Meilensteine -- unabhaengig vom Stand
#     etwaiger 'eigen'-Meilensteine, die laut §2.4/§8-Praezisierung PARALLEL
#     geschaffen werden und daher allein nicht blockieren) -> "weiterverfolgen".
# "verwerfen" (explizite Owner-Wahl / Duplikat / nicht tragfaehig) ist laut
# §8 KEIN aus dem Meilenstein-Status automatisch ableitbarer Zweig -- dieser
# Fall bleibt bewusst ausserhalb dieser Funktion (Hybrid: Default hier,
# begruendete Owner-/Judge-Abweichung bleibt moeglich, AC4 "nicht allein vom
# Judge entschieden" != "nie vom Judge entschieden").
# Gibt "<recommendation>|<begruendung>" auf stdout aus (rc=0) oder bricht mit
# FATAL auf stderr ab (rc=1, delegiert an list_milestones -- z.B. Themen-ID-
# Formatfehler, security/R03).
derive_recommendation() {
  local db="$1"
  local topic_id="$2"
  local rows id description responsibility status watch_ref
  local open_external=0

  rows="$(list_milestones "$db" "$topic_id")" || return 1

  if [ -n "$rows" ]; then
    while IFS=$'\x1f' read -r id description responsibility status watch_ref; do
      [ -z "$id" ] && continue
      if [ "$responsibility" = "extern" ] && [ "$status" = "offen" ]; then
        open_external=$((open_external + 1))
      fi
    done <<< "$rows"
  fi

  if [ "$open_external" -gt 0 ]; then
    printf 'parken|%s offene(r) externe(r) Meilenstein(e) -- Wiedervorlage folgt ueber die Watchlist-Kopplung (data-model.md Sec.8, BR-013/BR-015).\n' "$open_external"
  else
    printf 'weiterverfolgen|Keine offenen externen Meilensteine -- externe Voraussetzungen erfuellt oder nicht vorhanden (data-model.md Sec.8, BR-013).\n'
  fi
  return 0
}

# print_recommendation_derivation <db-path> <topic-id>
# AC4: rendert das Ergebnis von derive_recommendation als CLI-Ausgabe --
# Aufrufpunkt fuer Claude (SKILL.md) VOR compute_result_hash/create_run
# (Reihenfolge: Meilenstein-Stand -> Empfehlung ableiten -> Hash bilden ->
# Lauf anlegen). Reine Text-Ausgabe, keine Persistenz.
print_recommendation_derivation() {
  local db="$1"
  local topic_id="$2"
  local result recommendation begruendung

  result="$(derive_recommendation "$db" "$topic_id")" || return 1
  IFS='|' read -r recommendation begruendung <<< "$result"

  echo "-- Empfehlungs-Ableitung (AC4/BR-013, data-model.md Sec.8) --"
  echo "Empfehlung (Default): $recommendation"
  echo "Begruendung: $begruendung"
  echo "Hinweis: 'verwerfen' ist keine automatisch ableitbare Empfehlung -- nur bei expliziter Owner-Wahl/Duplikat/nicht tragfaehig abweichen, dann im Brief begruenden (Hybrid, OF-09)."
  return 0
}

# print_swot_summary <db-path> <run-id>
# AC2 ("Bewertungsschicht"): rendert die fuer <run-id> bereits persistierten
# strukturierten SWOT-Items (db_scripts/lib/swot_item.sh#list_swot_items --
# kein direkter SQLite-Zugriff), gruppiert nach Kategorie. Die eigentliche
# SWOT-Bewertung (create_swot_item je Claim, Kategorie+claim_key aus dem
# kontrollierten Vokabular) erfolgt waehrend der Recherche selbst (SKILL.md,
# analog zu print_milestone_overview/create_milestone, S-011) -- diese
# Funktion zeigt nur den zum Aufrufzeitpunkt bereits persistierten Stand.
print_swot_summary() {
  local db="$1"
  local run_id="$2"
  local rows category claim_key
  local strength_lines="" weakness_lines="" opportunity_lines="" threat_lines=""

  echo "-- SWOT (strukturiert, BR-012) --"
  rows="$(list_swot_items "$db" "$run_id")" || return 1

  if [ -z "$rows" ]; then
    echo "Noch keine SWOT-Items fuer diesen Lauf hinterlegt."
    return 0
  fi

  while IFS='|' read -r category claim_key; do
    [ -z "$category" ] && continue
    case "$category" in
      strength)    strength_lines="${strength_lines}  - $claim_key"$'\n' ;;
      weakness)    weakness_lines="${weakness_lines}  - $claim_key"$'\n' ;;
      opportunity) opportunity_lines="${opportunity_lines}  - $claim_key"$'\n' ;;
      threat)      threat_lines="${threat_lines}  - $claim_key"$'\n' ;;
    esac
  done <<< "$rows"

  echo "Staerken:"
  if [ -n "$strength_lines" ]; then printf '%s' "$strength_lines"; else echo "  (keine)"; fi
  echo "Schwaechen:"
  if [ -n "$weakness_lines" ]; then printf '%s' "$weakness_lines"; else echo "  (keine)"; fi
  echo "Chancen:"
  if [ -n "$opportunity_lines" ]; then printf '%s' "$opportunity_lines"; else echo "  (keine)"; fi
  echo "Risiken:"
  if [ -n "$threat_lines" ]; then printf '%s' "$threat_lines"; else echo "  (keine)"; fi
  return 0
}

# print_businessplan_template
# BR-107: bei Empfehlung 'weiterverfolgen' wird das Businessplan-Template
# ausgegeben -- ein reines Text-Skelett (analog zum Schutzrechte-
# Klaerungspunkt): keine eigene Persistenz-Entitaet (data-model.md kennt keine
# ra_businessplan-Tabelle; architecture.md "Businessplan-Emitter" liefert ein
# Template, kein strukturiertes Datenmodell) -- Claude fuellt die Platzhalter
# waehrend der Recherche im Brief-Freitext selbst aus (Simplicity-Leiter Stufe
# 6: kein neues Schema fuer reinen Fuelltext; coder/R01: AC2 verlangt kein
# Feld-Modell dafuer, nur die Ausfuellung des Templates).
print_businessplan_template() {
  echo "-- Businessplan-Template (BR-107) --"
  echo "  Problem & Zielgruppe:"
  echo "  Loesungsansatz:"
  echo "  Markt & Wettbewerb (siehe SWOT):"
  echo "  Meilenstein-Plan (siehe Voraussetzungs-Ueberblick):"
  echo "  Ressourcenbedarf:"
  return 0
}

# print_recommendation <db-path> <run-id>
# AC2: liest die fuer <run-id> bereits persistierte Empfehlung + das
# momentum_only-Flag (db_scripts/lib/run.sh#get_run) und rendert sie. Bei
# 'weiterverfolgen' wird zusaetzlich das Businessplan-Template ausgegeben
# (BR-107). Das momentum_only-Flag existiert bereits als Pflichtspalte seit
# ra_run (003_ra_run.sql, S-003) -- diese Funktion zeigt nur den vorhandenen
# Wert an; der Deep-Research-Pass selbst, der ihn befuellt, ist S-009-Scope
# (AC3) und wird hier NICHT implementiert.
print_recommendation() {
  local db="$1"
  local run_id="$2"
  local row recommendation momentum_only

  row="$(get_run "$db" "$run_id")" || return 1
  IFS='|' read -r recommendation momentum_only <<< "$row"

  echo "-- Empfehlung --"
  if [ "$momentum_only" = "1" ]; then
    echo "Empfehlung: $recommendation (Momentum-Signal -- kein Deep-Research-Pass, BR-014)"
  else
    echo "Empfehlung: $recommendation"
  fi

  if [ "$recommendation" = "weiterverfolgen" ]; then
    print_businessplan_template
  fi
  return 0
}

# print_gate_prompt <db-path> <run-id>
# gate-pm-anstoss#AC1: rendert das Entscheidungs-Gate als explizite Wahl
# (CLI/Chat bis M5, ADR-005) -- NUR wenn die fuer <run-id> persistierte
# Empfehlung 'weiterverfolgen' ist. Architecture.md Zustandsautomat/Flow C:
# der Uebergang nach 'uebergeben'/'im_pm' laeuft ausschliesslich ueber dieses
# Gate (BR-102) und ausschliesslich aus 'weiterverfolgen' (kein Gate-Angebot
# fuer 'parken'/'verwerfen' -- dort fuehrt kein Pfad nach 'im_pm'). Reine
# Text-Ausgabe der Wahl; loest selbst KEINE Folgeaktion aus -- der
# tatsaechliche PM-Anstoss (pm-skills-Aufruf ueber PM-Handoff, AC2-AC6) ist
# NICHT Teil dieser Story (S-016 implementiert nur AC1). Ohne explizite
# menschliche Bestaetigung passiert nichts (C-004/BR-102, kein
# Automatik-Anstoss).
print_gate_prompt() {
  local db="$1"
  local run_id="$2"
  local row recommendation momentum_only

  row="$(get_run "$db" "$run_id")" || return 1
  IFS='|' read -r recommendation momentum_only <<< "$row"

  if [ "$recommendation" != "weiterverfolgen" ]; then
    return 0
  fi

  echo "-- Entscheidungs-Gate (gate-pm-anstoss#AC1, ADR-005) --"
  echo "Empfehlung 'weiterverfolgen' erreicht: diesen Lauf jetzt per PM-Anstoss an den PM-Prozess uebergeben?"
  echo "Wahl (CLI/Chat, explizite Bestaetigung noetig -- C-004/BR-102, kein Automatik-Anstoss): PM-Anstoss | Zurueckstellen"
  return 0
}

# render_evaluation <db-path> <run-id>
# Buendelt die Bewertungsschicht-Anzeige (AC2) fuer einen bereits persistierten
# Lauf: SWOT-Zusammenfassung + Empfehlung (inkl. Businessplan-Template bei
# 'weiterverfolgen') + Entscheidungs-Gate (gate-pm-anstoss#AC1). Aufgerufen
# ueber den `evaluation`-Subbefehl (main()), NACHDEM Claude waehrend der
# Recherche create_swot_item/create_run aufgerufen hat (SKILL.md) -- kein
# eigener last30days-/Judge-Aufruf hier.
render_evaluation() {
  local db="$1"
  local run_id="$2"

  if [ -z "$run_id" ] || ! [[ "$run_id" =~ ^[0-9]+$ ]]; then
    echo "FATAL: Lauf-ID '$run_id' ist keine gueltige Ganzzahl -- Aufruf: orchestrator.sh evaluation <run-id>" >&2
    return 1
  fi

  echo "== Bewertungsschicht (research-skill#AC2) =="
  print_swot_summary "$db" "$run_id" || return 1
  print_recommendation "$db" "$run_id" || return 1
  print_gate_prompt "$db" "$run_id" || return 1
  return 0
}

# dispatch_pm_anstoss <db-path> <topic-id> <run-id> <artifact-ref>
# gate-pm-anstoss#AC2 (ADR-009): deterministisches Bookkeeping NACH dem
# agentischen Skill-Dispatch. pm-skills ist kein CLI-Tool und wird von diesem
# Skript NIE aufgerufen -- die aufrufende Claude-Session hat pm-skills bereits
# im selben Turn ueber das Skill-Tool angestossen und liefert die dabei
# erzeugte Vault-Pfad-Referenz als <artifact-ref> mit (gate-pm-anstoss.md
# "AC2 -- Technischer Aufrufmechanismus", Schritt 2). Dieses Skript uebernimmt
# ausschliesslich:
#   - Vorbedingungen pruefen (Lauf existiert, Empfehlung ist 'weiterverfolgen',
#     Thema-Status 'aktiv')
#   - Dispatch in ra_pm_dispatch protokollieren (idempotent via UNIQUE)
#   - Status-Transition 'aktiv' -> 'im_pm' (BR-006, architecture.md §7)
#
# rc=0: neuer Dispatch, Status gesetzt
# rc=2: idempotenter Dispatch (gleicher Hash, bereits erfolgt) -- Status bleibt 'im_pm'
# rc=1: Fehler (Vorbedingung, DB-Fehler) -- kein Statuswechsel
dispatch_pm_anstoss() {
  local db="$1"
  local topic_id="$2"
  local run_id="$3"
  local artifact_ref="$4"
  local row recommendation momentum_only topic_title
  local result_hash rc

  check_store_or_die "$db" || return 1

  if [ -z "$artifact_ref" ]; then
    echo "FATAL: <artifact-ref> fehlt -- orchestrator.sh ruft pm-skills nie selbst auf (ADR-009), die Vault-Pfad-Referenz muss vom Aufrufer geliefert werden. Aufruf: dispatch_pm_anstoss <topic-id> <run-id> <artifact-ref>" >&2
    return 1
  fi

  # Format-Guard fuer topic_id vor SQL-Interpolation (security/R03).
  if ! [[ "$topic_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
    echo "FATAL: Themen-ID '$topic_id' verletzt das UUID-Format -- PM-Anstoss abgelehnt (security/R03)." >&2
    return 1
  fi

  if ! [[ "$run_id" =~ ^[0-9]+$ ]]; then
    echo "FATAL: Lauf-ID '$run_id' ist keine gueltige Ganzzahl -- PM-Anstoss abgelehnt (security/R03)." >&2
    return 1
  fi

  # Lauf auslesen (recommendation, momentum_only).
  row="$(get_run "$db" "$run_id")" || return 1
  IFS='|' read -r recommendation momentum_only <<< "$row"

  # Vorbedingung: Empfehlung muss 'weiterverfolgen' sein (gate-pm-anstoss#AC1, BR-102).
  if [ "$recommendation" != "weiterverfolgen" ]; then
    echo "FATAL: PM-Anstoss erfordert Empfehlung 'weiterverfolgen', Lauf $run_id hat '$recommendation' -- Anstoss abgelehnt." >&2
    return 1
  fi

  # Thema auslesen + pruefen (status='aktiv', title).
  local escaped_id="${topic_id//\'/\'\'}"
  row="$(sqlite3 "$db" "SELECT title, status FROM ra_topic WHERE id = '$escaped_id';" 2>/dev/null)"
  if [ -z "$row" ]; then
    echo "FATAL: Thema '$topic_id' existiert nicht -- PM-Anstoss abgelehnt." >&2
    return 1
  fi
  IFS='|' read -r topic_title current_status <<< "$row"

  # 'aktiv' = Erst-Anstoss; 'im_pm' = das Thema wurde bereits per PM-Anstoss
  # uebergeben -- ein erneuter Aufruf mit identischem Hash muss idempotent
  # durchlaufen koennen (AC3, dispatch_pm_handoff prueft das gleich danach),
  # sonst wuerde jeder Wiederholungs-Anstoss (Skript-Neustart nach Abbruch,
  # AC5) hier schon rejected, BEVOR die Idempotenz-Pruefung ueberhaupt greift.
  if [ "$current_status" != "aktiv" ] && [ "$current_status" != "im_pm" ]; then
    echo "FATAL: PM-Anstoss ist nur aus Status 'aktiv' (Erst-Anstoss) oder 'im_pm' (idempotenter Wiederholungs-Anstoss) moeglich, Thema '$topic_id' ist '$current_status' -- abgelehnt (BR-006)." >&2
    return 1
  fi

  # result_hash auslesen (fuer Idempotenz in ra_pm_dispatch).
  result_hash="$(sqlite3 "$db" "SELECT result_hash FROM ra_run WHERE id = $run_id;" 2>/dev/null)"
  if [ -z "$result_hash" ]; then
    echo "FATAL: result_hash fuer Lauf $run_id nicht gefunden -- PM-Anstoss abgelehnt." >&2
    return 1
  fi

  # Alle Pruefungen OK: Bookkeeping (der Skill-Dispatch selbst ist bereits
  # VOR diesem Aufruf durch die Session ueber das Skill-Tool erfolgt, ADR-009).
  echo "-- PM-Anstoss (gate-pm-anstoss#AC2, ADR-009) --"
  echo "Thema: $topic_title (ID: $topic_id)"
  echo "Lauf: $run_id (Empfehlung: $recommendation)"
  echo "PM-Artefakte im Vault (vom Aufrufer geliefert): $artifact_ref"

  # Dispatch in ra_pm_dispatch protokollieren (idempotent). rc=2 (Idempotenz)
  # ist ein regulaerer, erwarteter Rueckgabewert dieser Funktion -- set -e
  # wuerde die Funktion sonst sofort bei rc=2 abbrechen, BEVOR die
  # Idempotenz-Meldung unten ausgegeben wird (analog set +e/set -e um
  # acquire_topic_lock weiter oben in dieser Datei).
  set +e
  dispatch_pm_handoff "$db" "$topic_id" "$run_id" "$result_hash" "$artifact_ref"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "PM-Dispatch protokolliert (neue Eingabe)."
  elif [ "$rc" -eq 2 ]; then
    echo "PM-Anstoss ist idempotent: gleicher Hash zum Thema bereits vorhanden (BR-017, AC3)."
    # Status bleibt 'im_pm', kein erneuter Wechsel.
    return 2
  else
    echo "FATAL: PM-Dispatch-Protokollierung fehlgeschlagen -- Statusaenderung wird nicht durchgefuehrt." >&2
    return 1
  fi

  # Status-Wechsel: aktiv -> im_pm (BR-006, architecture.md §7). Ausnahme: war
  # das Thema schon 'im_pm' (zweiter Dispatch mit abweichendem result_hash,
  # z.B. ein weiterer Recherche-Lauf waehrend das Thema noch im PM-Prozess
  # ist), ist der Status bereits korrekt -- 'im_pm' -> 'im_pm' ist KEINE
  # gueltige Kante in ra_topic_valid_transition, ein unconditional-Aufruf
  # wuerde hier faelschlich fehlschlagen, obwohl der Dispatch oben bereits
  # erfolgreich committet wurde (Lesson S-017, 2026-07-30).
  if [ "$current_status" = "im_pm" ]; then
    echo "Thema-Status: bleibt 'im_pm' (bereits im PM-Prozess; aktualisierter Dispatch protokolliert)."
  elif ! set_topic_status "$db" "$topic_id" "im_pm"; then
    # Fehlerfall: pm-skills hat bereits Artefakte geschrieben (vor diesem Aufruf,
    # ADR-009), aber der DB-Statuswechsel ist gescheitert. Das ist ein
    # Konsistenz-Problem (BR-005: "kein halb aktualisierter Stand"). AC2 hat das
    # nicht direkt im Scope (AC5 "Abbruch-Sicherheit" mit Idempotenz + AC6
    # "manuelle Vault-Aenderung" mit Hash-Mismatch sind separate Stories), aber
    # wir geben einen klaren Fehler aus.
    echo "FATAL: Statuswechsel 'aktiv' -> 'im_pm' ist fehlgeschlagen -- PM-Artefakte wurden bereits geschrieben, aber Thema bleibt in 'aktiv' (Konsistenz-Problem, AC5-Scope)." >&2
    return 1
  else
    echo "Thema-Status: 'aktiv' -> 'im_pm' (architecture.md §7, BR-006)"
  fi

  echo "PM-Anstoss erfolgreich abgeschlossen -- Uebergabe an agent-flow per pm-import (pm-import liest Vault-Artefakte, ADR-003)."
  return 0
}

# research_thema <db-path> <topic-title> <save-dir-base>
# Thema-Modus (AC1): last30days ueber lib/last30days_client.sh aufrufen,
# Thema ueber die Data-Access-Schicht anlegen/wiederverwenden (AC6),
# Advisory-Lock je Thema (E3/BR-019), Quellen-Resilienz-Brief (AC7).
research_thema() {
  local db="$1"
  local title="$2"
  local save_dir_base="$3"
  local cmd topic_id rc json_file mode_save_dir

  cmd="$(resolve_last30days_cmd)" || return 1
  check_store_or_die "$db" || return 1

  topic_id="$(resolve_or_create_topic "$db" "$title")" || return 1

  set +e
  acquire_topic_lock "$db" "$topic_id" "$RA_LOCK_HOLDER" "$RA_LOCK_TTL_SECONDS"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    return 1
  fi

  mode_save_dir="$save_dir_base/thema_$(date +%Y%m%dT%H%M%S%N 2>/dev/null || date +%Y%m%dT%H%M%S)"
  json_file="$(mktemp)"
  set +e
  invoke_last30days_thema "$cmd" "$title" "$mode_save_dir" > "$json_file"
  rc=$?
  set -e

  release_topic_lock "$db" "$topic_id" "$RA_LOCK_HOLDER" || true

  if [ "$rc" -ne 0 ]; then
    rm -f "$json_file"
    return 1
  fi

  echo "== Recherche-Brief (Grundgeruest, S-007) =="
  echo "Modus: thema"
  echo "Thema: $title"
  echo "Themen-ID: $topic_id"
  print_milestone_overview "$db" "$topic_id"
  print_missing_sources_note "$json_file"
  rm -f "$json_file"
  return 0
}

# research_discovery <db-path> <save-dir-base>
# Discovery-Modus (AC1): autonome Topthemen-Suche via last30days --discover;
# jedes gefundene Thema wird ueber die Data-Access-Schicht angelegt/
# wiederverwendet (AC6), je Thema Advisory-Lock (E3/BR-019 -- ein bereits
# gesperrtes Thema wird uebersprungen, kein Doppel-Lauf, kein Abbruch des
# gesamten Discovery-Laufs), gemeinsamer Quellen-Resilienz-Brief (AC7).
research_discovery() {
  local db="$1"
  local save_dir_base="$2"
  local cmd rc json_file mode_save_dir topics title topic_id

  cmd="$(resolve_last30days_cmd)" || return 1
  check_store_or_die "$db" || return 1

  mode_save_dir="$save_dir_base/discovery_$(date +%Y%m%dT%H%M%S%N 2>/dev/null || date +%Y%m%dT%H%M%S)"
  json_file="$(mktemp)"
  set +e
  invoke_last30days_discovery "$cmd" "$mode_save_dir" > "$json_file"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    rm -f "$json_file"
    return 1
  fi

  echo "== Recherche-Brief (Discovery, S-007) =="

  topics="$(extract_discovery_topics "$json_file")" || { rm -f "$json_file"; return 1; }
  if [ -z "$topics" ]; then
    echo "Keine belastbaren Topthemen in diesem Fenster (last30days-Konfidenzschwelle nicht erreicht)."
  else
    while IFS= read -r title; do
      [ -z "$title" ] && continue

      topic_id="$(resolve_or_create_topic "$db" "$title")" || { rm -f "$json_file"; return 1; }

      set +e
      acquire_topic_lock "$db" "$topic_id" "$RA_LOCK_HOLDER" "$RA_LOCK_TTL_SECONDS"
      rc=$?
      set -e
      if [ "$rc" -ne 0 ]; then
        echo "  UEBERSPRUNGEN: Thema '$title' (ID $topic_id) ist gerade in Bearbeitung (BR-019, E3) -- kein Doppel-Lauf." >&2
        continue
      fi
      release_topic_lock "$db" "$topic_id" "$RA_LOCK_HOLDER" || true

      echo "Thema: $title (ID $topic_id)"
    done <<< "$topics"
  fi

  print_missing_sources_note "$json_file"
  rm -f "$json_file"
  return 0
}

usage() {
  cat >&2 <<'USAGE'
Usage:
  orchestrator.sh discovery [save-dir]
  orchestrator.sh thema "<Thema-String>" [save-dir]
  orchestrator.sh recommend <topic-id>
  orchestrator.sh evaluation <run-id>
  orchestrator.sh dispatch_pm_anstoss <topic-id> <run-id> <artifact-ref>

Env:
  RA_DB_PATH                    Pfad zur research-app.sqlite (Default: research-app.sqlite)
  RA_LAST30DAYS_CMD             last30days-Kommando (Default: last30days, auf PATH aufgeloest)
  RA_LOCK_HOLDER                ra_topic_lock.holder-Wert (Default: research)
  RA_LOCK_TTL_SECONDS           Lock-TTL in Sekunden (Default: 1800)

Hinweis (ADR-009): <artifact-ref> ist die Vault-Pfad-Referenz der PM-Artefakte,
die die aufrufende Claude-Session bereits VOR diesem Aufruf ueber das
Skill-Tool per pm-skills erzeugt hat -- orchestrator.sh ruft pm-skills nie
selbst auf und ermittelt <artifact-ref> nie selbst.
USAGE
}

main() {
  local mode="${1:-}"
  case "$mode" in
    discovery)
      research_discovery "$RA_DB_PATH" "${2:-$RA_SAVE_DIR}"
      ;;
    thema)
      local title="${2:-}"
      research_thema "$RA_DB_PATH" "$title" "${3:-$RA_SAVE_DIR}"
      ;;
    recommend)
      local topic_id="${2:-}"
      print_recommendation_derivation "$RA_DB_PATH" "$topic_id"
      ;;
    evaluation)
      local run_id="${2:-}"
      render_evaluation "$RA_DB_PATH" "$run_id"
      ;;
    dispatch_pm_anstoss)
      local topic_id="${2:-}"
      local run_id="${3:-}"
      local artifact_ref="${4:-}"
      dispatch_pm_anstoss "$RA_DB_PATH" "$topic_id" "$run_id" "$artifact_ref"
      ;;
    *)
      usage
      return 1
      ;;
  esac
}

# Nur ausfuehren, wenn direkt aufgerufen -- nicht beim Sourcen fuer Tests (die
# Testsuite sourced dieses Skript, um die einzelnen Funktionen isoliert
# aufzurufen, ohne main() auszuloesen).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit $?
fi
