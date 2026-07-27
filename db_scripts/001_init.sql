-- 001_init.sql
-- Migrations-Grundgeruest: WAL-Modus + foreign_keys-Konvention (sqlite/R02, sqlite/R03)
-- + Marker-Tabelle fuer forward-only-Migrationen (sqlite/R06).
--
-- Quelle: docs/specs/research-datenmodell.md AC6, docs/data-model.md §9.
-- Forward-only (sqlite/R06): diese Datei nach dem ersten Apply NIE mehr editieren.
-- Neue Schema-Aenderungen kommen als neue db_scripts/<NNN>_name.sql (naechste Nummer,
-- lueckenlos). Die eigentlichen Entitaets-Tabellen (ra_topic, ra_run, ...) sind NICHT
-- Teil dieser Story (S-001 = nur das Grundgeruest) -- sie kommen in den Folge-Migrationen
-- der Stories S-002..S-006, jeweils als STRICT-Tabellen (sqlite/R04).

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS _schema_migrations (
  version     TEXT NOT NULL PRIMARY KEY,
  applied_at  TEXT NOT NULL DEFAULT (datetime('now')),
  checksum    TEXT
) STRICT;
