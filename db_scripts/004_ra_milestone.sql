-- 004_ra_milestone.sql
-- ra_milestone: Meilenstein-Entitaet (je Thema), Story S-005.
-- Quelle: docs/specs/research-datenmodell.md AC4; docs/data-model.md §2.4 (Feldliste),
-- §4 BR-015/BR-016 (Zustaendigkeits-/Status-Invarianten), §3 (Pflicht-Indizes).
--
-- Forward-only (sqlite/R06): diese Datei nach dem ersten Apply NIE mehr editieren. Neue
-- Schema-Aenderungen kommen als neue db_scripts/<NNN>_name.sql (naechste Nummer).
--
-- BR-015 (watch_ref-Pflicht bei responsibility='extern', NULL bei 'eigen') ist als
-- zeilen-lokales CHECK-Constraint ausdrueckbar (Simplicity-Leiter Stufe 4, gleiches
-- Muster wie ra_topic.discarded_at (002_ra_topic.sql) und
-- ra_run.has_deep_research/momentum_only (003_ra_run.sql)) -- kein zusaetzlicher
-- Data-Access-Wrapper noetig (anders als create_topic/create_run, die eine
-- nicht-deklarative Berechnung wie UUID-Generierung bzw. monotone Versionsvergabe
-- brauchen): das native CHECK ist hier der vollstaendige, schreibpfad-unabhaengige
-- Backstop fuer AC4.
--
-- BR-016 (status-Enum) analog zu ra_topic.status/ra_run.kind als CHECK.
--
-- Das Statuswechsel-/Kaskaden-Verhalten rund um Meilensteine (BR-004-Gate "aktiv ->
-- geparkt erfordert >=1 Meilenstein", OF-10-Kaskade "geparkt -> verworfen setzt offene
-- Meilensteine auf hinfaellig", beides AC5) lebt bereits in db_scripts/lib/topic.sh
-- (S-002, dort bewusst vorbereitet fuer den Moment, in dem diese Tabelle existiert) --
-- ab dieser Migration greifen beide Regeln automatisch, ohne dass topic.sh angefasst
-- werden muss (siehe Datei-Header dort).

CREATE TABLE IF NOT EXISTS ra_milestone (
  id              INTEGER NOT NULL PRIMARY KEY,
  topic_id        TEXT    NOT NULL REFERENCES ra_topic(id) ON DELETE CASCADE,
  description     TEXT    NOT NULL CHECK (length(trim(description)) >= 1),
  responsibility  TEXT    NOT NULL CHECK (responsibility IN ('extern','eigen')),
  status          TEXT    NOT NULL CHECK (status IN ('offen','erfuellt','hinfaellig')),
  watch_ref       TEXT,
  created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
  fulfilled_at    TEXT,
  CHECK (
    (responsibility = 'extern' AND watch_ref IS NOT NULL)
    OR (responsibility = 'eigen' AND watch_ref IS NULL)
  )
) STRICT;

CREATE INDEX IF NOT EXISTS idx_ra_milestone_topic_id ON ra_milestone(topic_id);
CREATE INDEX IF NOT EXISTS idx_ra_milestone_status ON ra_milestone(status);
CREATE INDEX IF NOT EXISTS idx_ra_milestone_responsibility ON ra_milestone(responsibility);
