> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
M1 (Datenmodell) läuft. S-001 bis S-006 sind Done und auf main (zuletzt
S-006 Advisory-Lock). Ready als Nächstes: S-007, S-012, S-013, S-021 —
nächster Lauf nimmt voraussichtlich S-007 (/research-Skill-Grundgerüst,
F-003). Board: 18 offene Stories. Stack bleibt bewusst offen (language:
md, No-Op build/test) — Implementierung als Bash/SQL unter db_scripts/
(Migrationen 001–006, lib/, tests/; 110 Tests grün).

## Letzte Arbeiten
- S-006 / Advisory-Lock ra_topic_lock gelandet (4a79db8, Done 3d82789):
  Migration 006 + lib/topic_lock.sh (acquire/release, atomare Stale-
  Übernahme via ON CONFLICT…WHERE expires_at<now, changes()-Auswertung),
  17 neue Tests inkl. echtem Zwei-Prozess-Parallel-Test. Ein Gate-Lauf:
  reviewer+dba+tester PASS ohne Befunde (nur sqlite/R10-Suggestion).
- S-004 / Divergenz-Berechnung ra_divergence gelandet (869f62b):
  Migration 005 + lib/divergence.sh; Reviewer-Fund busy_timeout vor
  BEGIN IMMEDIATE behoben.
- S-005 / Meilenstein-Entität ra_milestone gelandet (54fbcdb): CHECK-
  Constraints BR-015/BR-016; BR-004-Gate/OF-10-Kaskade in lib/topic.sh.

## Offene Fäden
- ra_swot_item-Lücke (Reviewer-Befund S-004, an requirement klären): keine
  F-002/M1-Story legt die in data-model.md §0/§2.3 als M1 geführte Tabelle
  an — run.sh (S-003) und divergence.sh (S-004) umgehen sie per Parameter-
  Übergabe. Eigene M1-Story nachziehen oder data-model auf M2 anpassen.
- sqlite/R10 (DBA-Suggestion S-006): gebundene sqlite3-CLI ist 3.51.0 —
  unter dem WAL-Reset-Guard-Schwellwert; version_guard.sh prüft nur in
  migrate.sh, nicht in den Data-Access-Skripten. Vor Produktiv-Einsatz
  klären (Version anheben oder Guard auch dort sourcen), M2-Folgeaufgabe.
- S-008-Implementierer-Hinweis: create_divergence verlangt bei erwarteter
  Hash-Gleichheit (is_empty=1) leere Delta-Strings, sonst FATAL durch CHECK.
- DBA-Suggestion S-005: fulfilled_at hat noch keinen Konsistenz-CHECK zu
  status='erfuellt' — ergänzen, sobald eine Data-Access-Funktion ihn setzt.
- board-ship.sh: CI-Watch-Hang auch bei S-006 (wie S-005) — Recovery-Muster
  in lessons/flow.md; tok_total-Nachtrag zählt evtl. zu viel (87M bei S-006).
