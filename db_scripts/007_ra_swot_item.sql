-- 007_ra_swot_item.sql
-- ra_swot_item: strukturierte SWOT-Eintraege je Lauf (Kategorie-Enum + kontrolliertes
-- claim_key-Vokabular), Story S-008.
-- Quelle: docs/specs/research-skill.md AC2 (BR-012/OF-06), E2 ("claim_key ausserhalb
-- des Vokabulars -> gemappt oder als unmapped zurueckgewiesen, nie freier Slug");
-- docs/data-model.md §2.3 (Feldliste), §4 BR-012, §3 (Pflicht-Indizes
-- ra_swot_item(run_id)/ra_swot_item(category)).
--
-- Forward-only (sqlite/R06): diese Datei nach dem ersten Apply NIE mehr editieren. Neue
-- Schema-Aenderungen kommen als neue db_scripts/<NNN>_name.sql (naechste Nummer).
--
-- ra_swot_item existierte bewusst noch NICHT (siehe db_scripts/lib/run.sh-Datei-Header,
-- S-003/S-004: "bleibt bewusst aussen vor") -- diese Migration legt sie erstmals an.
-- compute_result_hash()/compute_swot_delta() (run.sh/divergence.sh) bleiben davon
-- UNVERAENDERT: sie nehmen weiterhin (category,claim_key)-Paare als Parameter entgegen
-- (reine Funktion ueber strukturierte Werte, kein Tabellenzugriff) -- der neue Aufrufer
-- (db_scripts/lib/swot_item.sh#list_swot_items, S-008) liefert diese Paare jetzt aus
-- der echten Tabelle statt aus Test-Fixtures.
--
-- category/evidence_source als native CHECK-Enums (Simplicity-Leiter Stufe 4, gleiches
-- Muster wie ra_run.kind/ra_topic.status). claim_key ABSICHTLICH KEIN CHECK-Enum: das
-- kontrollierte Vokabular (OF-06) ist eine versionierte, erweiterbare Business-Taxonomie
-- -- ein SQL-CHECK-Enum wuerde bei jeder Vokabular-Erweiterung eine neue forward-only-
-- Migration erzwingen. Die Vokabular-Pruefung (BR-012/E2: nie ein freier Slug
-- persistiert) lebt app-seitig in db_scripts/lib/swot_item.sh (map_claim_key/
-- claim_key_in_vocabulary) -- die CHECK hier erzwingt nur "nicht leer" als
-- schwaecheren, schreibpfad-unabhaengigen Backstop (analog description bei
-- ra_milestone).

CREATE TABLE IF NOT EXISTS ra_swot_item (
  id              INTEGER NOT NULL PRIMARY KEY,
  run_id          INTEGER NOT NULL REFERENCES ra_run(id) ON DELETE CASCADE,
  category        TEXT    NOT NULL CHECK (category IN ('strength','weakness','opportunity','threat')),
  claim_key       TEXT    NOT NULL CHECK (length(trim(claim_key)) >= 1),
  evidence_source TEXT    NOT NULL CHECK (evidence_source IN ('last30days','deep_research')),
  rationale       TEXT,
  UNIQUE (run_id, category, claim_key)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_ra_swot_item_run_id ON ra_swot_item(run_id);
CREATE INDEX IF NOT EXISTS idx_ra_swot_item_category ON ra_swot_item(category);
