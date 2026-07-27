#!/usr/bin/env bash
# topic.sh — Data-Access-Schicht fuer ra_topic (Themen-Anlage + Zustandsautomat).
#
# Quelle: docs/specs/research-datenmodell.md AC1, AC5; docs/specs/wiedervorlage-
# meilensteine.md AC1 (BR-004, S-012); docs/data-model.md §2.1, §4, §7.
# architecture.md: "Data-Access" ist die einzige Schreib-/Lesestelle der
# Bewertungs-Tabellen (single-writer) -- diese Datei IST diese Schicht (M1, kein
# App-Layer, language: md). Wie apply_migrations.sh/attach_l30d_readonly.sh (S-001)
# sind das reine Bash-Funktionen, die SQL gegen die Ziel-DB fahren.
#
# Dokumentierte Design-Entscheidung (S-002, urspruenglich): ra_milestone existierte erst
# ab S-005 (jetzt angelegt, 004_ra_milestone.sql). Zwei Stellen im Zustandsautomaten
# haengen an Meilensteinen:
#   - BR-004 (aktiv -> geparkt nur mit >=1 EXTERNEM Meilenstein, seit S-012 scharf
#     auf responsibility='extern' eingeengt -- siehe set_topic_status-Kommentar)
#   - OF-10  (geparkt -> verworfen setzt offene Meilensteine auf 'hinfaellig',
#     unabhaengig von responsibility)
# Beide greifen seit S-005 scharf (der Existenz-Check via sqlite_master bleibt als
# Defensiv-Absicherung bestehen, ist aber gegen jede Migration ab 004_ra_milestone.sql
# immer wahr). Die Kanten-Topologie selbst (BR-006, AC5-Fokus dieser Story) ist davon
# unabhaengig und war immer vollstaendig scharf.
#
# Verbindungs-Idiom (DBA-Review Iteration 2, sqlite/R02 -- Referenz-Pattern fuer alle
# kommenden FK-tragenden Data-Access-Dateien, ra_run/ra_swot_item/ra_milestone/...):
# JEDE Schreib-Verbindung (`sqlite3 "$db" "..."`) ist eine frische, kurzlebige
# CLI-Session -- `PRAGMA foreign_keys = ON;` gilt NUR fuer diese eine Verbindung,
# anders als `journal_mode=WAL`, das im DB-Datei-Header persistiert. Deshalb setzt
# JEDE Schreib-Verbindung dieser Datei `PRAGMA foreign_keys = ON;` als eigene erste
# Anweisung -- unabhaengig davon, ob `ra_topic` selbst FK-Spalten hat (aktuell nicht).
# Reine Lesezugriffe (SELECT) brauchen das PRAGMA nicht (wirkt nur auf INSERT/UPDATE/
# DELETE-FK-Validierung) und setzen es hier bewusst nicht.

# generate_uuidv7
# Erzeugt eine RFC-9562-UUIDv7 (zeitsortierbar, OF-01). Nutzt sqlite3 (ohnehin
# Kern-Abhaengigkeit dieses Projekts) als einzige externe Quelle fuer Millisekunden-
# Zeitstempel (`unixepoch('now','subsec')`) und Zufallsbytes (`randomblob`) --
# Simplicity-Leiter Stufe 4/5: kein zusaetzlicher Interpreter (python/perl) fuer eine
# UUID-Formatierung, die in wenigen Zeilen Bash-Stringverarbeitung erledigt ist.
generate_uuidv7() {
  local raw ts_ms rand_hex ts_hex variant_src variant_val variant_hex
  raw="$(sqlite3 ':memory:' "SELECT CAST(unixepoch('now','subsec')*1000 AS INTEGER) || '|' || lower(hex(randomblob(10)));")"
  ts_ms="${raw%%|*}"
  rand_hex="${raw##*|}"
  ts_hex="$(printf '%012x' "$ts_ms")"

  # rand_hex hat 20 Hex-Zeichen (10 Zufalls-Bytes). Layout (RFC 9562 §5.2):
  #   ts_hex[0:8]-ts_hex[8:12]-7<rand_a 3 hex>-<variant 1 hex><rand_b 3 hex>-<rand_b 12 hex>
  # Variant-Nibble: oberste 2 Bit muessen auf '10' fixiert sein (Wertebereich 8..b) --
  # ein Zufalls-Hex-Zeichen wird dafuer per Bitmaske (& 3 | 8) reduziert, alle anderen
  # Zufalls-Zeichen bleiben unveraendert.
  variant_src="${rand_hex:3:1}"
  variant_val=$(( (16#$variant_src & 3) | 8 ))
  variant_hex="$(printf '%x' "$variant_val")"

  printf '%s-%s-7%s-%s%s-%s\n' \
    "${ts_hex:0:8}" "${ts_hex:8:4}" "${rand_hex:0:3}" \
    "$variant_hex" "${rand_hex:4:3}" "${rand_hex:7:12}"
}

# ra_topic_store_ready <db-path>
# Reine Lesefunktion (rc-basiert, kein stdout-Payload): rc=0 gdw. die DB-Datei
# existiert UND bereits bis mindestens Migration 002 (ra_topic) angewandt ist.
# Genutzt vom /research-Skill (S-007, research-skill#AC1 Edge-Case E1 -- "Store
# fehlt") als alleinige Store-Bereitschaftspruefung VOR jedem last30days-Aufruf
# ("kein Halb-Lauf"); haelt die einzige SQLite-Abfrage dieser Art in der
# Data-Access-Schicht statt eines rohen sqlite3-Aufrufs aus dem Skill-Skript
# heraus (architecture.md: Data-Access ist die einzige Schreib-/Lesestelle der
# Bewertungs-Tabellen).
ra_topic_store_ready() {
  local db="$1"

  [ -f "$db" ] || return 1

  sqlite3 "$db" "SELECT name FROM sqlite_master WHERE type='table' AND name='ra_topic';" \
    | grep -qx "ra_topic"
}

# find_topic_by_title <db-path> <title>
# Reine Lesefunktion (kein PRAGMA foreign_keys noetig, SELECT-only) fuer den
# EXAKTEN Titel-Abgleich (gleicher Vergleich wie der Duplikat-Check in
# create_topic, kein Trim/Case-Fuzzing). Gibt eine Zeile je Treffer (Themen-ID)
# auf stdout aus (leer = kein Treffer). Genutzt vom /research-Skill (S-007,
# research-skill#AC1/AC6/BR-109): "dasselbe Thema" (exakt gleicher Titel) wird
# ueber mehrere Laeufe hinweg wiederverwendet (stabile Themen-ID, BR-109) statt
# bei jedem Aufruf ein neues Thema anzulegen; existieren mehrere Treffer (ein
# frueherer OF-02-Duplikat-Fall) oder keiner, entscheidet der Aufrufer (S-007:
# dann Neuanlage per create_topic, OF-02-Warnung greift reguaer). Kein
# Fehlerfall vorgesehen (rc immer 0, auch bei 0 Treffern).
find_topic_by_title() {
  local db="$1"
  local title="$2"
  local escaped_title="${title//\'/\'\'}"

  sqlite3 "$db" "SELECT id FROM ra_topic WHERE title = '$escaped_title';"
  return 0
}

# create_topic <db-path> <title>
# Legt ein neues Thema an: generiert die stabile UUIDv7-ID (BR-001), setzt
# status='aktiv' (Anlage-Kante §7). Leerer Titel wird von der CHECK-Constraint
# (BR-002, 002_ra_topic.sql) abgelehnt -- kein doppelter App-seitiger Leer-Check
# (Simplicity-Leiter Stufe 4). Gleicher Titel blockiert NICHT (OF-02): nach
# erfolgreicher Anlage wird bei vorhandenem Titel-Duplikat eine Warnung + die
# ID(e) des/der bestehenden Themas/Themen auf stderr ausgegeben (Merge-Vorschlag).
# Gibt die neue Themen-ID auf stdout aus (rc=0) oder bricht mit FATAL auf stderr ab.
create_topic() {
  local db="$1"
  local title="$2"
  local id escaped_title insert_err rc existing

  id="$(generate_uuidv7)"
  if ! [[ "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
    echo "FATAL: generierte UUIDv7 '$id' verletzt das erwartete Format -- Anlage abgebrochen (BR-001)." >&2
    return 1
  fi

  # Apostroph-Escape vor der SQL-Interpolation (security/R03, Lesson S-001
  # 2026-07-27) -- Titel ist Freitext und darf legitime Apostrophe enthalten.
  escaped_title="${title//\'/\'\'}"

  insert_err="$(sqlite3 "$db" "PRAGMA foreign_keys = ON; INSERT INTO ra_topic (id, title, status) VALUES ('$id', '$escaped_title', 'aktiv');" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FATAL: Themen-Anlage fuer Titel '$title' schlug fehl (BR-001/BR-002): $insert_err" >&2
    return 1
  fi

  existing="$(sqlite3 "$db" "SELECT id FROM ra_topic WHERE title = '$escaped_title' AND id != '$id';")"
  if [ -n "$existing" ]; then
    echo "WARNUNG: weitere(s) Thema/Themen mit identischem Titel '$title' vorhanden -- Merge-Vorschlag pruefen (OF-02, blockiert die Anlage nicht): $existing" >&2
  fi

  echo "$id"
  return 0
}

# ra_topic_valid_transition <from-status> <to-status>
# Reine Kanten-Pruefung (kein DB-Zugriff) gegen den Zustandsautomaten aus
# data-model.md §7 inkl. OF-10-Restkanten. rc=0 = Kante erlaubt, rc=1 = abgelehnt
# (BR-006 -- "alle anderen Uebergaenge werden abgelehnt").
ra_topic_valid_transition() {
  local from="$1"
  local to="$2"
  case "$from:$to" in
    aktiv:geparkt|aktiv:im_pm|aktiv:verworfen|geparkt:aktiv|geparkt:verworfen|im_pm:aktiv)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# set_topic_status <db-path> <topic-id> <new-status>
# Fuehrt einen Statuswechsel nur aus, wenn er im Zustandsautomaten vorgesehen ist
# (BR-006, ra_topic_valid_transition). Setzt `discarded_at` gdw. der Zielstatus
# 'verworfen' ist (BR-005) und `updated_at` immer neu. Kaskaden (nur wenn
# `ra_milestone` bereits existiert, siehe Datei-Header-Entscheidung):
#   - aktiv -> geparkt: lehnt ab, wenn 0 EXTERNE Meilensteine existieren (BR-004,
#     wiedervorlage-meilensteine#AC1, S-012). "Extern" ist bewusst enger als der
#     data-model.md-Kurztext "≥1 Meilenstein": nur responsibility='extern'-
#     Meilensteine tragen eine Watchlist-Referenz (BR-015) und koennen die
#     automatische Wiedervorlage (AC3) ueberhaupt ausloesen -- ein rein 'eigen'er
#     Meilenstein wuerde ein geparktes Thema fuer immer unbeobachtet lassen. Reine
#     'eigen'-Meilensteine zaehlen daher NICHT fuer dieses Gate.
#   - geparkt -> verworfen: setzt offene Meilensteine auf 'hinfaellig' (OF-10).
#     Verwerfen (egal ob direkt aus 'aktiv' oder aus 'geparkt') verlangt selbst
#     KEINEN Meilenstein (AC1: "nicht beim Verwerfen", BR-005).
set_topic_status() {
  local db="$1"
  local topic_id="$2"
  local new_status="$3"
  local current discarded_expr

  if ! [[ "$topic_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "FATAL: Themen-ID '$topic_id' verletzt das UUID-Format -- Statuswechsel abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  if ! [[ "$new_status" =~ ^(aktiv|geparkt|im_pm|verworfen)$ ]]; then
    echo "FATAL: Zielstatus '$new_status' ist kein gueltiger ra_topic.status-Wert (BR-003)." >&2
    return 1
  fi

  current="$(sqlite3 "$db" "SELECT status FROM ra_topic WHERE id = '$topic_id';")"
  if [ -z "$current" ]; then
    echo "FATAL: Thema '$topic_id' existiert nicht -- Statuswechsel abgelehnt." >&2
    return 1
  fi

  if ! ra_topic_valid_transition "$current" "$new_status"; then
    echo "FATAL: Statuswechsel '$current' -> '$new_status' ist im Zustandsautomaten (data-model.md §7) nicht vorgesehen -- abgelehnt (BR-006)." >&2
    return 1
  fi

  if [ "$current" = "aktiv" ] && [ "$new_status" = "geparkt" ]; then
    if sqlite3 "$db" "SELECT name FROM sqlite_master WHERE type='table' AND name='ra_milestone';" | grep -qx "ra_milestone"; then
      local ms_extern_count
      ms_extern_count="$(sqlite3 "$db" "SELECT COUNT(*) FROM ra_milestone WHERE topic_id = '$topic_id' AND responsibility = 'extern';")"
      if [ "$ms_extern_count" -lt 1 ]; then
        echo "FATAL: Statuswechsel 'aktiv' -> 'geparkt' fuer Thema '$topic_id' abgelehnt -- Parken erfordert mindestens 1 EXTERNEN Meilenstein (BR-004, wiedervorlage-meilensteine#AC1); rein 'eigen'e Meilensteine reichen nicht." >&2
        return 1
      fi
    fi
    # Ohne ra_milestone (vor S-005): Gate degradiert zum No-op, siehe Datei-Header.
  fi

  discarded_expr="NULL"
  if [ "$new_status" = "verworfen" ]; then
    discarded_expr="datetime('now')"
  fi

  # ">/dev/null": 'PRAGMA busy_timeout = <n>;' gibt (anders als 'PRAGMA foreign_keys
  # = ON;') seinen neu gesetzten Wert als Ergebniszeile aus -- ohne Unterdrueckung
  # wuerde "5000" auf stdout jedes erfolgreichen Aufrufs leaken (DBA-Review-Fund,
  # beim Ergaenzen von busy_timeout entdeckt; gleiches Idiom wie apply_migrations.sh
  # bei 'PRAGMA journal_mode = WAL;').
  if ! sqlite3 "$db" <<SQL > /dev/null
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
BEGIN IMMEDIATE;
UPDATE ra_topic
SET status = '$new_status',
    updated_at = datetime('now'),
    discarded_at = $discarded_expr
WHERE id = '$topic_id';
COMMIT;
SQL
  then
    echo "FATAL: Statuswechsel '$current' -> '$new_status' fuer Thema '$topic_id' schlug beim Schreiben fehl." >&2
    return 1
  fi

  if [ "$current" = "geparkt" ] && [ "$new_status" = "verworfen" ]; then
    if sqlite3 "$db" "SELECT name FROM sqlite_master WHERE type='table' AND name='ra_milestone';" | grep -qx "ra_milestone"; then
      sqlite3 "$db" "PRAGMA foreign_keys = ON; UPDATE ra_milestone SET status = 'hinfaellig' WHERE topic_id = '$topic_id' AND status = 'offen';"
    fi
    # Ohne ra_milestone (vor S-005): Kaskade degradiert zum No-op, siehe Datei-Header.
  fi

  return 0
}
