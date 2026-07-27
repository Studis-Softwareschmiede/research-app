-- 002_ra_topic.sql
-- ra_topic: Themen-Entitaet (Portfolio-Kern), Story S-002.
-- Quelle: docs/specs/research-datenmodell.md AC1, AC5; docs/data-model.md §2.1 (Feldliste),
-- §4 BR-001..BR-006 (Anlage-/Status-Invarianten), §7 (Zustandsautomat) + OF-10.
--
-- Forward-only (sqlite/R06): diese Datei nach dem ersten Apply NIE mehr editieren. Neue
-- Schema-Aenderungen kommen als neue db_scripts/<NNN>_name.sql (naechste Nummer).
--
-- Statuswechsel-Kantenpruefung (BR-006) lebt bewusst NICHT als Trigger hier, sondern in
-- der Data-Access-Schicht (db_scripts/lib/topic.sh, Funktion set_topic_status) -- die
-- Migrationsdatei erzwingt nur, was sich als native CHECK-Constraint sauber ausdruecken
-- laesst (Simplicity-Leiter Stufe 4):
--   - BR-002: leerer Titel technisch unmoeglich (`length(trim(title)) >= 1`).
--   - BR-003: `status` nur einer der vier erlaubten Enum-Werte.
--   - BR-005: `discarded_at` genau dann gesetzt, wenn `status = 'verworfen'`
--     (Konsistenz-Invariante, verhindert einen inkonsistenten Datensatz unabhaengig
--     davon, welcher Schreibpfad die Zeile aendert).
-- Die Kanten-Topologie selbst (welche status-Wechsel ueberhaupt erlaubt sind, inkl.
-- OF-10-Restkanten `im_pm -> aktiv` / `geparkt -> verworfen`) ist kein CHECK-ausdruckbares
-- Constraint (haengt vom VORHERIGEN Wert ab, den ein CHECK auf derselben Zeile nicht
-- kennt) -- das bleibt Aufgabe von `set_topic_status` (BR-006).

CREATE TABLE IF NOT EXISTS ra_topic (
  id            TEXT NOT NULL PRIMARY KEY,
  title         TEXT NOT NULL CHECK (length(trim(title)) >= 1),
  status        TEXT NOT NULL CHECK (status IN ('aktiv','geparkt','im_pm','verworfen')),
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
  discarded_at  TEXT,
  CHECK (
    (status = 'verworfen' AND discarded_at IS NOT NULL)
    OR (status <> 'verworfen' AND discarded_at IS NULL)
  )
) STRICT;

CREATE INDEX IF NOT EXISTS idx_ra_topic_status ON ra_topic(status);
