-- 006_ra_topic_lock.sql
-- ra_topic_lock: Advisory-Serialisierungssperre je Thema (Nebenlaeufigkeit), Story S-006.
-- Quelle: docs/specs/research-datenmodell.md AC7; docs/data-model.md §2.7 (Feldliste),
-- §4 BR-019 (Serialisierungspflicht), §9 (BEGIN IMMEDIATE + busy_timeout + Advisory-Lock).
--
-- Forward-only (sqlite/R06): diese Datei nach dem ersten Apply NIE mehr editieren. Neue
-- Schema-Aenderungen kommen als neue db_scripts/<NNN>_name.sql (naechste Nummer).
--
-- Ein Lock-Row je Thema (topic_id ist PK, kein zusaetzlicher technischer Schluessel
-- noetig -- data-model.md §2.7 "Ein Lock-Row je Thema"). holder-Enum + Stale-Ablauf
-- (expires_at, E2 "kein Dauer-Deadlock") lebt in der Data-Access-Schicht
-- (db_scripts/lib/topic_lock.sh, Funktionen acquire_topic_lock/release_topic_lock):
-- die "Uebernahme nach expires_at"-Bedingung haengt vom AKTUELLEN Zeitpunkt ab, kein
-- zeilen-lokales CHECK-ausdrueckbares Constraint (analog zur monotonen Versionierung
-- in 003_ra_run.sql -- Simplicity-Leiter Stufe 4 dort, hier Stufe 6: die Serialisierung
-- selbst ist der Zweck der Tabelle, kein triviales Constraint).
--
-- holder/Enum als natives CHECK (Simplicity-Leiter Stufe 4, gleiches Muster wie
-- ra_run.kind/ra_topic.status).

CREATE TABLE IF NOT EXISTS ra_topic_lock (
  topic_id     TEXT NOT NULL PRIMARY KEY REFERENCES ra_topic(id),
  holder       TEXT NOT NULL CHECK (holder IN ('watchlist','research')),
  acquired_at  TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at   TEXT NOT NULL
) STRICT;
