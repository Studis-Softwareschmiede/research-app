---
id: wiedervorlage-meilensteine
title: Meilenstein-gekoppelte Wiedervorlage über die last30days-Watchlist (M3)
status: active
version: 1
spec_format: use-case-2.0
---

# Spec: Wiedervorlage & Meilensteine  (`wiedervorlage-meilensteine`)  *(← C-005)*

> **Schicht 3 von 3.** Source of Truth für `coder`/`tester`/`reviewer`. Detailkonzepte: [`docs/data-model.md`](../data-model.md) (BR-004/BR-015/BR-016/BR-020), [`docs/architecture.md`](../architecture.md).

## Zweck

Geparkte Themen geraten nie mehr in Vergessenheit: Parken ist an Meilensteine geknüpft, die bestehende last30days-Watchlist (`--store`, Delta-Erkennung) prüft externe Meilensteine und legt Themen automatisch wieder vor. Kein Neubau der Wiedervorlage (C-004). (PRD FR-9–FR-10, ← IDEA-003/IDEA-004.)

## Acceptance-Kriterien

- **AC1 — Parken nur mit Meilenstein:** Beim Parken (nicht beim Verwerfen) müssen ≥ 1 externe Meilensteine hinterlegt werden; ohne Meilenstein ist Parken nicht abschliessbar (BR-004).
- **AC2 — Watchlist-Kopplung:** Externe Meilensteine (`responsibility=extern`) tragen eine Watchlist-Referenz (BR-015) und werden vom Watchlist-Job geprüft; „Delta" = das last30days-Delta-Signal (OF-12-Entscheid).
- **AC3 — Automatische Wiedervorlage:** Bei erfülltem Meilenstein oder erkanntem Delta wechselt das Thema `geparkt → aktiv` (BR-020) und erscheint als wiedervorgelegt (sichtbar im Portfolio/CLI-Ausgabe).
- **AC4 — Nicht prüfbare Meilensteine:** Ein extern nicht automatisch prüfbarer Meilenstein bleibt sichtbar als „manuell zu prüfen" markiert — keine stille Nicht-Prüfung (PRD Edge).
- **AC5 — Verworfen bleibt verworfen:** `verworfen`-Themen werden nie wiedervorgelegt (BR-005/BR-020); `geparkt → verworfen` setzt offene Meilensteine auf `hinfaellig` (OF-10-Entscheid).
- **AC6 — Nebenläufigkeit:** Der Watchlist-Job respektiert die Themen-Sperre (BR-019) und serialisiert sich gegen manuelle Läufe.

## Verträge
- Watchlist-Zugriff nur über den Watchlist-Pass (architecture.md Boundary 2); Statuswechsel nur über Data-Access + Zustandsautomat.
- Tests taggen `@trace wiedervorlage-meilensteine#AC<n>`.

## Edge-Cases & Fehlerverhalten
- **E1** Watchlist-Job läuft, während der Mac schlief → Nachholprüfung beim nächsten Lauf; kein Meilenstein geht verloren.
- **E2** last30days-Watchlist nicht verfügbar → externe Meilensteine werden als „manuell zu prüfen" gemeldet (AC4-Verhalten), kein Crash.

## NFRs
- Wiedervorlage-Lauf ist idempotent: mehrfaches Prüfen desselben Stands erzeugt keine Doppel-Wiedervorlage.

## Nicht-Ziele
- Kein eigener Scheduler in dieser Stufe (Automatisierung/Tagesläufe = Future, C-002). Kein eigenes Delta-Scoring jenseits des last30days-Signals.

## Abhängigkeiten
- Spec `research-datenmodell` (depends). last30days-Watchlist funktionsfähig.
