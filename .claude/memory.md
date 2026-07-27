> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
M1 (Datenmodell) läuft. S-001 (DB-Grundgerüst), S-002 (ra_topic), S-003
(ra_run, versionierte Läufe) und S-005 (ra_milestone) sind Done und auf main.
Mit S-005 werden S-004 und S-012 frei (depends erfüllt); daneben weiter ready:
S-006, S-007, S-021. Board: 20 offene Stories in 5 Features. Stack bleibt
bewusst offen (language: md, No-Op build/test) — Implementierung als Bash/SQL
unter db_scripts/ (Migrationen 001–004, lib/, tests/; 75 Tests grün).

## Letzte Arbeiten
- S-005 / Meilenstein-Entität ra_milestone gelandet (54fbcdb): Status-Enum
  {offen,erfuellt,hinfaellig}, Zuständigkeit {extern,eigen}, Watchlist-Ref-
  Pflicht bei extern als CHECK-Constraints (BR-015/BR-016). Ein Gate-Lauf,
  reviewer+dba+tester PASS ohne Befunde. Die in S-002 vorbereitete
  BR-004-Gate/OF-10-Kaskade in lib/topic.sh ist damit scharf.
- S-001 / DB-Grundgerüst gelandet (zwei Gate-Läufe 26./27.07., tester-PASS);
  Metrik-Ledger nachgetragen, .gitignore um .claude/metrics/ + board/runs/.

## Offene Fäden
- board-ship.sh hängt in diesem Repo an der CI-Watch (keine push-getriggerten
  Workflows, nur Dependabot/Schedule) — nach Ship-Timeout Remote-State prüfen,
  Done-Flip mechanisch nachziehen (S-005, 2026-07-27; siehe lessons/flow.md).
- Parallel-Sessions: `board next` liest den Working-Tree — vor Board-Read in
  frischen Worktree wechseln (S-001-Vorfall 2026-07-27, lessons/flow.md).
- Hauptordner hängt auf 0c4f0d2 mit unversionierter Lesson-Änderung
  (.claude/lessons/coder.md) einer früheren Session — nicht anfassen.
- DBA-Suggestion S-005: fulfilled_at hat noch keinen Konsistenz-CHECK zu
  status='erfuellt' — ergänzen, sobald eine Data-Access-Funktion ihn setzt.
