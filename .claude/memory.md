> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
M1 (Datenmodell) komplett inkl. ra_swot_item (Migration 007, S-008). M2
(F-003) läuft: S-007 + S-008 Done, offen sind AC3 (Deep-Research) und
weitere F-003-Storys. M3 (F-004): S-012 Done, S-013 (Watchlist-Kopplung)
ready. S-021 (Dashboard, ui-Label → Design-Freigabe-Gate greift) ready.
Stack bleibt bewusst offen (language: md, No-Op build/test) —
Implementierung als Bash/SQL unter db_scripts/ (Migrationen 001–007,
lib/, tests/; jetzt 132 Tests) + skills/research/ (39 Tests), alles grün.

## Letzte Arbeiten
- S-008 / Recherche-Brief + SWOT-Judge gelandet (3dd9b1e): Migration 007
  ra_swot_item (data-model §2.3), lib/swot_item.sh mit kontrolliertem
  claim_key-Vokabular v1 (OF-06/E2, nie freier Slug), get_run in run.sh,
  evaluation-Subcommand + Businessplan-Template (nur weiterverfolgen) im
  /research-Skill. Gates: reviewer PASS, dba PASS, tester PASS. Die im
  Memory notierte „ra_swot_item-Lücke" war KEINE Spec-Lücke — data-model
  §2.3 war vollständig, S-008 hat die Tabelle angelegt.
- S-012 / Parken-Gate gelandet (187e58c): BR-004 verschärft
  (aktiv→geparkt verlangt ≥1 extern-Meilenstein); 5 AC1-Assertions.
- S-007 / /research-Skill-Grundgerüst gelandet (a1897be): orchestrator.sh
  + last30days_client.sh; BR-109 präzisiert.

## Offene Fäden
- Live-Smoke gegen echtes last30days fehlt (S-007/S-008 liefen nur gegen
  Fixture-Stub RA_LAST30DAYS_CMD). Vor F-003-Abschluss einplanen.
- Stale Kommentar db_scripts/lib/run.sh:14-16 („ra_swot_item existiert
  weiterhin NICHT") — seit S-008 falsch; mit nächster db-Story fixen
  (Lesson in coder.md vermerkt).
- DBA-Suggestions offen (S-012): data-model.md:204 Kantentext unpräzise
  vs. OF-10; run_tests.sh TID_E-Rückgabewert. Älter: fulfilled_at-CHECK
  (S-005), sqlite/R10 (CLI 3.51.0).
- tok_total weiterhin verdächtig hoch (57,8M S-008, 153M S-012) —
  metrics-collect.sh-Zählweise prüfen (retro-Kandidat).
