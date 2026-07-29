-- 008_ra_pm_dispatch.sql
-- ra_pm_dispatch: PM-Anstoss-Protokoll (idempotent ueber topic_id + result_hash),
-- Story S-017.
-- Quelle: docs/specs/gate-pm-anstoss.md AC2; docs/data-model.md §2.6 (Feldliste),
-- §4 BR-017 (Idempotenz-Invariante), §3 (Pflicht-Indizes).
--
-- Forward-only (sqlite/R06): diese Datei nach dem ersten Apply NIE mehr editieren. Neue
-- Schema-Aenderungen kommen als neue db_scripts/<NNN>_name.sql (naechste Nummer).
--
-- Idempotenz (BR-017): UNIQUE(topic_id, result_hash) -- gleicher Hash zum selben Thema
-- bedeutet kein neues PM-Artefakt, sondern nur Divergenz-Ausweis (AC3/AC4). Der PM-
-- Handoff-Pass (AC2) uebernimmt die Idempotenz-Logik selbst (preuft, bevor insert/update
-- versucht wird) oder delegiert auf Datenbankkonstraint (beide Varianten korrekt). Hier
-- nur das Constraint-Modell.

CREATE TABLE IF NOT EXISTS ra_pm_dispatch (
  id               INTEGER NOT NULL PRIMARY KEY,
  topic_id         TEXT    NOT NULL REFERENCES ra_topic(id),
  run_id           INTEGER NOT NULL REFERENCES ra_run(id),
  result_hash      TEXT    NOT NULL,
  artifact_ref     TEXT    NOT NULL,
  dispatched_at    TEXT    NOT NULL DEFAULT (datetime('now')),
  UNIQUE (topic_id, result_hash)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_ra_pm_dispatch_topic_id ON ra_pm_dispatch(topic_id);
