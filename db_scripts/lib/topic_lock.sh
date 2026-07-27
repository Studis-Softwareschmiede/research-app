#!/usr/bin/env bash
# topic_lock.sh — Data-Access-Schicht fuer ra_topic_lock (Advisory-Serialisierungssperre
# je Thema, Nebenlaeufigkeit).
#
# Quelle: docs/specs/research-datenmodell.md AC7; docs/data-model.md §2.7, §4 (BR-019),
# §9 ("BEGIN IMMEDIATE + gesetztes busy_timeout fuer den physischen Single-Writer-Lock;
# zusaetzlich der logische ra_topic_lock-Advisory-Lock gegen versehentliche Doppel-
# Laeufe je Thema (Stale-Lock via expires_at)").
# architecture.md: "Data-Access" ist die einzige Schreib-/Lesestelle der
# Bewertungs-Tabellen (single-writer) -- diese Datei IST diese Schicht (M1, kein
# App-Layer, language: md), analog zu topic.sh/run.sh/divergence.sh (S-002..S-004).
#
# Verbindungs-Idiom (sqlite/R02, Referenz-Pattern topic.sh/run.sh/divergence.sh): JEDE
# Schreib-Verbindung setzt `PRAGMA foreign_keys = ON;` als eigene erste Anweisung dieser
# frischen CLI-Session; `PRAGMA busy_timeout` steht VOR `BEGIN IMMEDIATE` in derselben
# Verbindung (coder.md-Lesson S-004: sonst wirkt das PRAGMA nicht mehr innerhalb der
# Transaktion) und wird per `.output /dev/null`/`.output stdout` unterdrueckt, damit sein
# Rueckgabewert nicht in das eingesammelte Ergebnis leakt (run.sh-Referenz-Idiom, S-003).
#
# Atomare Uebernahme (E2 "kein Dauer-Deadlock", BR-019): acquire_topic_lock nutzt EIN
# einzelnes INSERT .. ON CONFLICT(topic_id) DO UPDATE .. WHERE ra_topic_lock.expires_at <
# datetime('now') -- SQLite fuehrt die UPDATE-Klausel nur aus, wenn diese WHERE-Bedingung
# fuer die bereits vorhandene Zeile wahr ist (der Lock ist abgelaufen); ist der Lock noch
# gueltig, bleibt die Zeile unveraendert UND `changes()` liefert 0 -- kein Fehler, kein
# Ausnahmefall, sondern der reguläre "Lock ist noch belegt"-Pfad. Kombiniert mit
# `BEGIN IMMEDIATE` (serialisiert konkurrierende Schreiber physisch, sqlite/R01/R03) ist
# das die vollstaendige Atomaritaet fuer "gleichzeitige Schreiber (Watchlist-Job +
# /research-Lauf) korrumpieren nichts" (AC7): ein zweiter, echt gleichzeitiger Aufrufer
# wartet (busy_timeout) auf die Transaktion des ersten und sieht danach entweder eine
# frische, noch gueltige Sperre (changes()=0, Ablehnung) oder eine bereits abgelaufene
# (changes()=1, Uebernahme) -- nie einen inkonsistenten Zwischenzustand.

# acquire_topic_lock <db-path> <topic-id> <holder> <ttl-seconds>
# Versucht, die Sperre fuer <topic-id> zugunsten von <holder> zu erwerben: legt die
# Lock-Zeile neu an (kein bestehender Lock) ODER uebernimmt eine bereits abgelaufene
# Zeile (E2, `expires_at < datetime('now')`). `expires_at` wird serverseitig als
# `datetime('now', '+<ttl-seconds> seconds')` gebildet (keine Client-Uhr-Abhaengigkeit).
# Gibt bei Erfolg rc=0 aus (kein stdout-Payload noetig, analog set_topic_status). Ist der
# Lock bereits von einem anderen Halter gehalten und noch nicht abgelaufen, bricht die
# Funktion mit FATAL auf stderr ab (rc=1) -- der Aufrufer (Watchlist-Job bzw.
# /research-Lauf) muss diesen Fall als "Thema gerade in Bearbeitung" behandeln, nicht als
# Systemfehler.
acquire_topic_lock() {
  local db="$1"
  local topic_id="$2"
  local holder="$3"
  local ttl_seconds="$4"

  if ! [[ "$topic_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "FATAL: Themen-ID '$topic_id' verletzt das UUID-Format -- Lock-Erwerb abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  if ! [[ "$holder" =~ ^(watchlist|research)$ ]]; then
    echo "FATAL: Halter '$holder' ist kein gueltiger ra_topic_lock.holder-Wert (BR-019)." >&2
    return 1
  fi

  if ! [[ "$ttl_seconds" =~ ^[0-9]+$ ]] || [ "$ttl_seconds" -lt 1 ]; then
    echo "FATAL: TTL '$ttl_seconds' ist keine positive Ganzzahl (Sekunden) -- Lock-Erwerb abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
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
INSERT INTO ra_topic_lock (topic_id, holder, acquired_at, expires_at)
VALUES ('$topic_id', '$holder', datetime('now'), datetime('now', '+$ttl_seconds seconds'))
ON CONFLICT(topic_id) DO UPDATE SET
  holder = excluded.holder,
  acquired_at = excluded.acquired_at,
  expires_at = excluded.expires_at
WHERE ra_topic_lock.expires_at < datetime('now');
SELECT changes();
COMMIT;
SQL
)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FATAL: Lock-Erwerb fuer Thema '$topic_id' (Halter '$holder') schlug beim Schreiben fehl: $out" >&2
    return 1
  fi

  if [ "$out" = "1" ]; then
    return 0
  fi

  local current
  current="$(sqlite3 -separator '|' "$db" "SELECT holder, expires_at FROM ra_topic_lock WHERE topic_id = '$topic_id';")"
  echo "FATAL: Thema '$topic_id' ist bereits gesperrt und die Sperre ist noch nicht abgelaufen (BR-019, Advisory-Lock) -- aktuell: '$current'." >&2
  return 1
}

# release_topic_lock <db-path> <topic-id> <holder>
# Gibt die Sperre fuer <topic-id> frei -- NUR wenn <holder> tatsaechlich der aktuelle
# Halter ist (verhindert, dass ein Aufrufer versehentlich eine zwischenzeitlich von
# jemand anderem uebernommene Sperre loescht, z.B. nach eigenem Stale-Ablauf). Gibt bei
# Erfolg rc=0 aus; war <holder> nicht der aktuelle Halter (falscher Halter oder kein
# Lock vorhanden), bricht die Funktion mit FATAL auf stderr ab (rc=1).
release_topic_lock() {
  local db="$1"
  local topic_id="$2"
  local holder="$3"

  if ! [[ "$topic_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "FATAL: Themen-ID '$topic_id' verletzt das UUID-Format -- Lock-Freigabe abgelehnt vor jeder SQL-Interpolation (security/R03)." >&2
    return 1
  fi

  if ! [[ "$holder" =~ ^(watchlist|research)$ ]]; then
    echo "FATAL: Halter '$holder' ist kein gueltiger ra_topic_lock.holder-Wert (BR-019)." >&2
    return 1
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
DELETE FROM ra_topic_lock WHERE topic_id = '$topic_id' AND holder = '$holder';
SELECT changes();
COMMIT;
SQL
)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FATAL: Lock-Freigabe fuer Thema '$topic_id' (Halter '$holder') schlug beim Schreiben fehl: $out" >&2
    return 1
  fi

  if [ "$out" = "1" ]; then
    return 0
  fi

  echo "FATAL: Thema '$topic_id' war nicht durch Halter '$holder' gesperrt -- Freigabe abgelehnt (keine fremde Sperre loeschen)." >&2
  return 1
}
