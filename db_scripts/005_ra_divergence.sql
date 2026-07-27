-- 005_ra_divergence.sql
-- ra_divergence: Divergenz zwischen zwei Laeufen desselben Themas/derselben Art,
-- materialisiert je Folgelauf, Story S-004.
-- Quelle: docs/specs/research-datenmodell.md AC3; docs/data-model.md §2.5 (Feldliste),
-- §4 BR-010/BR-011 (Leer-/Gleichheits-Invarianten), §6 (Divergenz-Bildungsregel),
-- §3 (Pflicht-Indizes).
--
-- Forward-only (sqlite/R06): diese Datei nach dem ersten Apply NIE mehr editieren. Neue
-- Schema-Aenderungen kommen als neue db_scripts/<NNN>_name.sql (naechste Nummer).
--
-- BR-011 ("beide Laeufe gleicher Art UND gleiches Thema") ist NICHT als zeilen-lokales
-- CHECK ausdrueckbar (haengt vom Inhalt der referenzierten ra_run-Zeilen ab, die ein
-- CHECK auf dieser Zeile nicht kennt) -- analog zur Kanten-Topologie in
-- 002_ra_topic.sql (BR-006, dort per Data-Access-Funktion statt Trigger geloest).
-- Das erledigt die Data-Access-Schicht (db_scripts/lib/divergence.sh, Funktion
-- create_divergence): sie liest from_run/to_run vorab und lehnt bei
-- topic_id-/kind-Mismatch ab, BEVOR sie diese Zeile schreibt.
--
-- is_empty (BR-010, "gdw. hash(from)=hash(to)") wird ebenfalls in create_divergence
-- berechnet (Vergleich der bereits gespeicherten ra_run.result_hash-Werte) statt als
-- CHECK -- der Hash-Vergleich selbst ist trivial, aber die Werte muessen ohnehin aus
-- ra_run gelesen werden, um topic_id/kind zu pruefen (kein zusaetzlicher Query-Pfad).
--
-- swot_delta/milestone_status_delta sind JSON-Freitext (kein eigenes strukturiertes
-- Schema hier) -- die zugrundeliegenden SWOT-/Meilenstein-Tupel werden analog zu
-- run.sh#compute_result_hash als PARAMETER an die reinen Berechnungsfunktionen in
-- divergence.sh uebergeben, nicht aus einer Tabelle gelesen: ra_swot_item existiert
-- noch nicht (S-003-Scope-Grenze, siehe run.sh-Datei-Header) und der Meilenstein-Stand
-- "zum Laufzeitpunkt" wird ohnehin nirgends historisiert (ra_milestone haelt nur den
-- aktuellen Stand). Der kuenftige Aufrufer (Recherche-Skill, S-008 ff.) liefert die
-- Tupel-Schnappschuesse beider Laeufe, sobald diese Datenquelle existiert.

CREATE TABLE IF NOT EXISTS ra_divergence (
  id                       INTEGER NOT NULL PRIMARY KEY,
  topic_id                 TEXT    NOT NULL REFERENCES ra_topic(id),
  kind                     TEXT    NOT NULL CHECK (kind IN ('recherche','pm')),
  from_run_id              INTEGER NOT NULL REFERENCES ra_run(id),
  to_run_id                INTEGER NOT NULL REFERENCES ra_run(id),
  is_empty                 INTEGER NOT NULL CHECK (is_empty IN (0,1)),
  recommendation_changed   INTEGER NOT NULL CHECK (recommendation_changed IN (0,1)),
  swot_delta               TEXT,
  milestone_status_delta   TEXT,
  computed_at              TEXT    NOT NULL DEFAULT (datetime('now')),
  UNIQUE (from_run_id, to_run_id),
  CHECK (is_empty = 0 OR (swot_delta IS NULL AND milestone_status_delta IS NULL))
) STRICT;

CREATE INDEX IF NOT EXISTS idx_ra_divergence_topic_id ON ra_divergence(topic_id);
CREATE INDEX IF NOT EXISTS idx_ra_divergence_to_run_id ON ra_divergence(to_run_id);
