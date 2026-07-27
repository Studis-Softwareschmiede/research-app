> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
M1 (Datenmodell) komplett inkl. ra_swot_item (Migration 007). M2 (F-003)
läuft: S-007 + S-008 Done, offen AC3/Deep-Research (S-009 ready, next).
M3 (F-004): S-012 + S-013 Done — Watchlist-Pass steht, S-014/S-015
(automatische Wiedervorlage/Markierung) jetzt ready. S-021 (Dashboard,
ui-Label → Design-Freigabe-Gate) ready. Stack bleibt bewusst offen
(language: md, No-Op build/test) — Implementierung als Bash/SQL unter
db_scripts/ (Migrationen 001–007, lib/, 132 Tests) + skills/research/
(59 Tests), alles grün.

## Letzte Arbeiten
- S-013 / Watchlist-Pass gelandet (063d29d): Wiederaufnahme des vom
  Loop-Releaser gesicherten WIP-Worktrees (abgebrochene Session), auf
  main rebased (Union mit S-008-Testblöcken), main()-Kollision
  watchlist_pass↔orchestrator gelöst (watchlist_pass_main). AC2:
  list_watchlist_candidates + watchlist_client (Auto-Discovery
  watchlist.py, real gegen last30days 3.16.0 verifiziert); AC6:
  ra_topic_lock holder='watchlist', Minimal-Halte-Prinzip. Alle Gates
  PASS in 1 Iteration.
- S-008 / Recherche-Brief + SWOT-Judge gelandet (3dd9b1e): Migration 007
  ra_swot_item, claim_key-Vokabular v1, evaluation-Subcommand.
- S-012 / Parken-Gate gelandet (187e58c): BR-004 verschärft.

## Offene Fäden
- Live-Smoke: Watchlist-Pfad ist real verifiziert (Reviewer, last30days
  3.16.0); der Recherche-Pfad (RA_LAST30DAYS_CMD, S-007/S-008) lief
  weiterhin nur gegen Fixture-Stub. Vor F-003-Abschluss einplanen.
- Stale Kommentar db_scripts/lib/run.sh:14-16 („ra_swot_item existiert
  weiterhin NICHT") — seit S-008 falsch; mit nächster db-Story fixen.
- mktemp-Shim in watchlist_client.sh wird nie aufgeräumt (Reviewer-
  Suggestion S-013) — bei S-014/S-015 (häufigere Läufe) gegenprüfen.
- DBA-Suggestions offen (S-012): data-model.md:204 Kantentext vs. OF-10;
  run_tests.sh TID_E-Rückgabewert. Älter: fulfilled_at-CHECK (S-005),
  sqlite/R10 (CLI 3.51.0).
- tok_total weiterhin verdächtig hoch (57,8M S-008, 197M S-013) —
  metrics-collect.sh-Zählweise prüfen (retro-Kandidat).
