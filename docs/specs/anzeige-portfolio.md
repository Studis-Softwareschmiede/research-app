---
id: anzeige-portfolio
title: Anzeige-Ebene — Portfolio, Verläufe, Divergenz-Ansicht, klickbare Gates (M5)
status: active
version: 1
spec_format: use-case-2.0
---

# Spec: Anzeige-Ebene  (`anzeige-portfolio`)  *(← C-005)*

> **Schicht 3 von 3.** Source of Truth für `coder`/`tester`/`reviewer`. Detailkonzepte: [`docs/architecture.md`](../architecture.md) (Schicht 3, ADR-007/F-4), [`docs/data-model.md`](../data-model.md).

## Zweck

Die eigenständige App-Oberfläche (Owner-Entscheid a-1 — kein dev-gui-Modul) macht sichtbar, wofür Chat/CLI das falsche Medium ist: Themen-Portfolio mit Verlauf, Divergenz-Ansicht zwischen Läufen und Entscheidungs-Gates als klickbare Wahl. Reines Lesemodell plus Gate-Bedienung — Recherche/Bewertung/PM bleiben Schicht-1-Logik. (PRD FR-14–FR-16, ← IDEA-003/IDEA-004; Praxis-Befund 18.07. als Auslöser.)

## Acceptance-Kriterien

- **AC1 — Portfolio:** Alle Themen mit Status (aktiv/geparkt/im PM/verworfen), letzter Bewertung (Empfehlung + Momentum-Kennzeichen) und offenen Meilensteinen sind einsehbar.
- **AC2 — Verlauf & Divergenz:** Pro Thema sind der Lauf-Verlauf und die Divergenz-Ansicht zwischen zwei frei wählbaren Läufen darstellbar (Empfehlungs-Wechsel, SWOT-Item-Delta + Kategorie-Rollup, Meilenstein-Delta — aus `ra_divergence`, nie aus Freitext).
- **AC3 — Klickbare Gates:** Anstehende Entscheidungs-Gates sind in der Anzeige bedienbar (PM anstossen / warten); die Aktion läuft über die Schicht-1-Schnittstelle, nie an ihr vorbei.
- **AC4 — Lesemodell-Boundary:** Die Anzeige liest direkt aus `research-app.sqlite` (F-4-Entscheid, lokaler Betrieb) und schreibt selbst nie — einzige Ausnahme ist die Gate-Aktion über Schicht 1 (AC3).
- **AC5 — Stack:** Umsetzung in HTML/JS (ADR-007, Owner-Entscheid b-1 vom 26.07.2026) als leichtgewichtiges lokales Dashboard; gebaut wird erst, wenn M1–M4 gelandet sind (M5 ist letzter Meilenstein — harte Reihenfolge C-005).

## Verträge
- Kein Schreibpfad ausser Gate-Aktion; keine eigene Geschäftslogik in der Anzeige (Divergenz wird gelesen, nicht neu berechnet).
- Tests taggen `@trace anzeige-portfolio#AC<n>`.

## Edge-Cases & Fehlerverhalten
- **E1** DB nicht vorhanden/leer → Leere-Zustands-Ansicht mit Handlungsanweisung (ersten Lauf starten), kein Fehler-Stack.
- **E2** Gate-Aktion kollidiert mit laufendem Lauf (Themen-Lock) → sichtbare Meldung, keine Doppel-Auslösung.

## NFRs
- Single-User, lokal; keine Auth, kein öffentliches Deployment (C-004).

## Nicht-Ziele
- Kein dev-gui-Modul (Entscheid a-1). Keine Ausführungs-Logik in der Anzeige. Kein Mehrbenutzer-Betrieb.

## Abhängigkeiten
- Specs `research-datenmodell`, `research-skill`, `wiedervorlage-meilensteine`, `gate-pm-anstoss` (depends — M5 zuletzt). ADR-007-Stack-Entscheid (Katalog b-1).
