> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
M1 (Datenmodell) komplett, M2 (F-003) läuft parallel (S-008 In Progress
in anderer Session), M3 (F-004 Wiedervorlage/Meilensteine) hat begonnen:
S-012 (Parken-Gate) ist Done. S-001–S-007, S-011, S-012 auf main. Ready:
S-013 (Watchlist-Kopplung, gleiche Spec wie S-012) und S-021 (Dashboard,
ui-Label → Design-Freigabe-Gate greift). Stack bleibt bewusst offen
(language: md, No-Op build/test) — Implementierung als Bash/SQL unter
db_scripts/ (Migrationen 001–006, lib/, tests/; jetzt 115 Tests) +
skills/research/ (33 Tests), alles grün.

## Letzte Arbeiten
- S-012 / Parken-Gate gelandet (187e58c, Done-Flip mechanisch): BR-004 in
  set_topic_status verschärft — aktiv→geparkt verlangt ≥1 Meilenstein mit
  responsibility='extern' (nicht irgendeinen); Verwerfen ungegated. 5 neue
  AC1-Assertions (@trace), data-model.md an 3 Stellen in §7 präzisiert.
  Gates: reviewer 1 Important (Diagramm-Label, Iteration 2 behoben),
  dba PASS, tester PASS.
- S-007 / /research-Skill-Grundgerüst gelandet (a1897be): skills/research/
  orchestrator.sh + scripts/lib/last30days_client.sh; BR-109 präzisiert.
- S-006 / Advisory-Lock ra_topic_lock (4a79db8): Migration 006 +
  lib/topic_lock.sh, Zwei-Prozess-Parallel-Test.

## Offene Fäden
- Live-Smoke gegen echtes last30days fehlt (S-007 lief nur gegen
  Fixture-Stub RA_LAST30DAYS_CMD). Vor F-003-Abschluss einplanen.
- ra_swot_item-Lücke (an requirement klären): keine M1-Story legt die in
  data-model.md §0/§2.3 geführte Tabelle an; S-008 braucht Klärung.
- DBA-Suggestions offen (S-012-Review): data-model.md:204 Kantentext
  „aktiv→verworfen nur ohne Meilenstein" unpräzise vs. OF-10 („ohne
  offene“); run_tests.sh TID_E prüft Parken-Zwischenschritt-Rückgabewert
  nicht. Dazu älter: fulfilled_at-CHECK (S-005), sqlite/R10 (CLI 3.51.0).
- tok_total-Nachtrag weiterhin verdächtig hoch (153M S-012, 87M S-006) —
  metrics-collect.sh-Zählweise prüfen (retro-Kandidat).
