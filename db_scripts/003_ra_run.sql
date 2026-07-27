-- 003_ra_run.sql
-- ra_run: Lauf-Entitaet (Recherche/PM), versioniert je (Thema, Art), Story S-003.
-- Quelle: docs/specs/research-datenmodell.md AC2; docs/data-model.md §2.2 (Feldliste),
-- §4 BR-007..BR-009/BR-013/BR-014 (Versions-/Hash-/Empfehlungs-Invarianten), §5
-- (result_hash-Bildungsregel), §3 (Pflicht-Indizes).
--
-- Forward-only (sqlite/R06): diese Datei nach dem ersten Apply NIE mehr editieren. Neue
-- Schema-Aenderungen kommen als neue db_scripts/<NNN>_name.sql (naechste Nummer).
--
-- Monotone Versionierung (BR-007) ist NICHT als CHECK ausdrueckbar (haengt vom bereits
-- vorhandenen MAX(version) je (topic_id,kind) ab -- kein zeilen-lokales Constraint,
-- braucht den Datenbestand). Das erledigt die Data-Access-Schicht
-- (db_scripts/lib/run.sh, Funktion create_run) per
-- `COALESCE(MAX(version),0)+1` innerhalb derselben INSERT...SELECT-Anweisung. Die
-- native UNIQUE(topic_id,kind,version) ist der harte Backstop gegen Doppel-Versionen
-- unter Nebenlaeufigkeit (Simplicity-Leiter Stufe 4) -- data-model.md §3 vermerkt sie
-- explizit als den Pflicht-Index fuer diese Spaltenkombination ("UNIQUE deckt ab"),
-- ein zusaetzlicher expliziter Index waere redundant.
--
-- result_hash wird AUSSERHALB von SQLite in run.sh (compute_result_hash) als SHA-256
-- ueber eine kanonische JSON-Serialisierung gebildet (BR-009, §5) -- SQLite hat keine
-- eingebaute SHA-256-Funktion. Die Spalte hier ist nur die Ablage des vorab berechneten
-- Hex-Digests; die CHECK-Constraint erzwingt das erwartete Format (64 Hex-Zeichen,
-- kleingeschrieben) als Konsistenz-Backstop, kein Ersatz fuer die Bildungsregel selbst.
--
-- BR-014-Konsistenz (has_deep_research=0 gdw. momentum_only=1) als CHECK-Constraint,
-- gleiches Muster wie ra_topic.discarded_at (002_ra_topic.sql).

CREATE TABLE IF NOT EXISTS ra_run (
  id                 INTEGER NOT NULL PRIMARY KEY,
  topic_id           TEXT    NOT NULL REFERENCES ra_topic(id),
  kind               TEXT    NOT NULL CHECK (kind IN ('recherche','pm')),
  version            INTEGER NOT NULL,
  result_hash        TEXT    NOT NULL CHECK (
    length(result_hash) = 64 AND result_hash NOT GLOB '*[^0-9a-f]*'
  ),
  recommendation     TEXT    NOT NULL CHECK (recommendation IN ('weiterverfolgen','parken','verwerfen')),
  has_deep_research  INTEGER NOT NULL CHECK (has_deep_research IN (0,1)),
  momentum_only      INTEGER NOT NULL CHECK (momentum_only IN (0,1)),
  l30d_source_ref    TEXT,
  created_at         TEXT    NOT NULL DEFAULT (datetime('now')),
  UNIQUE (topic_id, kind, version),
  CHECK (
    (has_deep_research = 0 AND momentum_only = 1)
    OR (has_deep_research = 1 AND momentum_only = 0)
  )
) STRICT;
