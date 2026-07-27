> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
M1 (Datenmodell) läuft. S-001 (DB-Grundgerüst SQLite: forward-only-Migrationen
STRICT/WAL/foreign_keys, Version-Guard ≥ 3.51.3, read-only ATTACH der
last30days-DB) ist Done und als f168fb1 auf main gelandet. Damit werden
S-002/S-003/S-005/S-006/S-021 frei (depends auf S-001). Board: 23 offene
Stories in 5 Features. Stack bleibt bewusst offen (language: md, No-Op
build/test) — Implementierung bisher als Bash/SQL unter db_scripts/.

## Letzte Arbeiten
- S-001 / DB-Grundgerüst gelandet (zwei Gate-Läufe 26./27.07., tester-PASS).
  Diese Session: versehentlichen Re-Claim der bereits Done-Story zurückgenommen
  (stale Hauptordner-Read), Metrik-Ledger nachgetragen, .gitignore um
  .claude/metrics/ + board/runs/ ergänzt.

## Offene Fäden
- Parallel-Sessions: `board next` liest den Working-Tree — vor Board-Read in
  frischen Worktree wechseln, sonst stale Reads (S-001-Vorfall 2026-07-27,
  siehe .claude/lessons/flow.md).
- Hauptordner hängt auf 0c4f0d2 mit unversionierter Lesson-Änderung
  (.claude/lessons/coder.md) einer früheren Session — nicht anfassen, gehört
  ggf. einer noch aktiven Session.
