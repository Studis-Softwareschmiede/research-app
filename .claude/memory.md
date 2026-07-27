> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
M1 (Datenmodell) ist komplett, M2 (F-003 /research-Skill) läuft. S-001
bis S-007 sind Done und auf main (zuletzt S-007: Skill-Grundgerüst unter
skills/research/). Ready: S-008, S-011, S-012, S-013, S-021 — nächster
Lauf nimmt voraussichtlich S-008 (Recherche-Brief + SWOT-Judge). Board:
17 offene Stories. Stack bleibt bewusst offen (language: md, No-Op
build/test) — Implementierung als Bash/SQL unter db_scripts/ (Migrationen
001–006, lib/, tests/; 110 Tests) + skills/research/ (19 Tests), alles grün.

## Letzte Arbeiten
- S-007 / /research-Skill-Grundgerüst gelandet (a1897be, Done 0884067):
  skills/research/ mit orchestrator.sh (discovery/thema-Modi, E1-Preflight,
  E3-Lock via lib/topic_lock.sh, Quellen-Resilienz-Brief AC7) +
  scripts/lib/last30days_client.sh (--emit=json/--save-dir/--store);
  topic.sh um Lesefunktionen find_topic_by_title/ra_topic_store_ready
  erweitert; Spec-Präzisierung BR-109 (titelgleiches Thema wird
  wiederverwendet). Ein Gate-Lauf: reviewer+dba+tester PASS ohne Befunde.
- S-006 / Advisory-Lock ra_topic_lock (4a79db8): Migration 006 +
  lib/topic_lock.sh, Zwei-Prozess-Parallel-Test.
- S-004/S-005 / Divergenz ra_divergence (869f62b) + Meilenstein
  ra_milestone (54fbcdb).

## Offene Fäden
- Live-Smoke gegen echtes last30days fehlt (S-007 lief nur gegen
  Fixture-Stub RA_LAST30DAYS_CMD — last30days im Env nicht installiert).
  Vor F-003-Abschluss einplanen (Reviewer/Tester-Vermerk, reviewer/R06d).
- ra_swot_item-Lücke (an requirement klären): keine M1-Story legt die in
  data-model.md §0/§2.3 geführte Tabelle an; S-008 (SWOT-Items!) braucht
  Klärung — run.sh/divergence.sh umgehen sie per Parameter-Übergabe.
- S-008-Implementierer-Hinweis: create_divergence verlangt bei is_empty=1
  leere Delta-Strings, sonst FATAL durch CHECK. create_run wird in S-008
  erstmals aus dem Skill heraus aufgerufen.
- sqlite/R10: gebundene sqlite3-CLI 3.51.0 unter WAL-Reset-Guard-Schwelle;
  version_guard.sh nur in migrate.sh gesourct. M2-Folgeaufgabe.
- DBA-Suggestions offen: fulfilled_at-CHECK zu status='erfuellt' (S-005);
  Apostroph-Injection-Test für find_topic_by_title (S-007, Test-Hygiene).
- board-ship.sh CI-Watch-Hang zum 3. Mal (S-005/S-006/S-007) — Recovery-
  Muster in lessons/flow.md greift; tok_total-Nachtrag evtl. zu hoch
  (87M S-006, 51M S-007).
