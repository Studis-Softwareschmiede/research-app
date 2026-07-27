> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
M1 (Datenmodell) läuft. S-001 (DB-Grundgerüst), S-002 (ra_topic), S-003
(ra_run), S-005 (ra_milestone) und S-004 (ra_divergence) sind Done und auf
main. Ready als Nächstes: S-006, S-007, S-012, S-021. Board: 19 offene
Stories in 5 Features. Stack bleibt bewusst offen (language: md, No-Op
build/test) — Implementierung als Bash/SQL unter db_scripts/ (Migrationen
001–005, lib/, tests/; 93 Tests grün).

## Letzte Arbeiten
- S-004 / Divergenz-Berechnung ra_divergence gelandet (869f62b, main 4fe08bd):
  Migration 005 + lib/divergence.sh (compute_swot_delta, compute_milestone_
  delta, create_divergence), 13+5 neue Tests. Zwei Gate-Läufe: Reviewer fand
  fehlendes busy_timeout vor BEGIN IMMEDIATE (Regressions-Fund) + fehlenden
  is_empty-CHECK-Backstop — behoben, dann reviewer+dba+tester PASS.
- S-005 / Meilenstein-Entität ra_milestone gelandet (54fbcdb): CHECK-
  Constraints BR-015/BR-016; BR-004-Gate/OF-10-Kaskade in lib/topic.sh scharf.
- S-001 / DB-Grundgerüst gelandet (26./27.07.); Metrik-Ledger nachgetragen.

## Offene Fäden
- ra_swot_item-Lücke (Reviewer-Befund S-004, an requirement klären): keine
  F-002/M1-Story legt die in data-model.md §0/§2.3 als M1 geführte Tabelle
  an — run.sh (S-003) und divergence.sh (S-004) umgehen sie per Parameter-
  Übergabe. Entweder eigene M1-Story nachziehen oder data-model auf M2 anpassen.
- S-008-Implementierer-Hinweis: create_divergence verlangt bei erwarteter
  Hash-Gleichheit (is_empty=1) leere Delta-Strings, sonst FATAL durch CHECK.
- DBA-Suggestion S-005: fulfilled_at hat noch keinen Konsistenz-CHECK zu
  status='erfuellt' — ergänzen, sobald eine Data-Access-Funktion ihn setzt.
- board-ship.sh: CI-Watch-Hang trat bei S-004 nicht auf (bei S-005 schon) —
  regulär versuchen, Recovery nur nach Timeout (lessons/flow.md).
