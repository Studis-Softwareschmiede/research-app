---
id: gate-pm-anstoss
title: Entscheidungs-Gate + idempotenter PM-Anstoss mit Divergenz-Ausweis (M4)
status: active
version: 1
spec_format: use-case-2.0
---

# Spec: Entscheidungs-Gate & PM-Anstoss  (`gate-pm-anstoss`)  *(← C-005, C-006)*

> **Schicht 3 von 3.** Source of Truth für `coder`/`tester`/`reviewer`. Detailkonzepte: [`docs/architecture.md`](../architecture.md) (ADR-003/ADR-004, PM-Handoff-Boundary), [`docs/data-model.md`](../data-model.md) (BR-017).

## Zweck

Der Übergang vom bewerteten Thema in den PM-Prozess bleibt eine bewusste menschliche Entscheidung: Nach jedem bewerteten Lauf bietet das System den PM-Anstoss als explizite Wahl an; der Anstoss selbst erzeugt via pm-skills die PM-Artefakte im Obsidian und übergibt an agent-flow (pm-import) — idempotent, mit ausgewiesener Divergenz. (PRD FR-11–FR-13, ← IDEA-003/IDEA-004.)

## Acceptance-Kriterien

- **AC1 — Gate ist manuell:** Nach jedem bewerteten Lauf wird der PM-Anstoss als explizite Wahl angeboten (bis M5 als CLI-/Chat-Abfrage, ADR-005); ohne menschliche Entscheidung passiert nichts (C-004 — kein Automatik-Anstoss).
- **AC2 — PM-Anstoss über die Kette:** Der Anstoss erzeugt via pm-skills (ganzes Plugin, Entscheid a-2) Konzept-/Spec-Artefakte, legt sie im Obsidian-Vault ab und übergibt an agent-flow über pm-import — nie direkt ins agent-flow-Board (ADR-003). Das Thema wechselt `aktiv → im_pm`; nach abgeschlossenem PM-Lauf zurück `im_pm → aktiv` (OF-10).
- **AC3 — Idempotenz:** Ein wiederholter Anstoss zum selben Thema mit gleichem `result_hash` erzeugt kein neues PM-Artefakt (`UNIQUE(topic_id, result_hash)`, BR-017) und wird als „keine Divergenz" protokolliert (PRD Edge).
- **AC4 — Divergenz-Ausweis:** Bei verändertem Ergebnisstand aktualisiert der Anstoss die PM-Ergebnisse und weist die Divergenz zum Vorlauf strukturiert aus (Datenmodell-Spec AC3).
- **AC5 — Abbruch-Sicherheit:** Bricht ein Anstoss mittendrin ab, erlaubt die Idempotenz den gefahrlosen Neustart; kein halb aktualisierter Stand wird als „aktuell" markiert (PRD Edge).
- **AC6 — Manuelle Vault-Änderung:** Wurde ein PM-Artefakt zwischen zwei Läufen manuell im Obsidian bearbeitet (Hash-Mismatch gegen erwarteten Vorlauf-Stand), löst der Anstoss eine Rückfrage aus statt still zu überschreiben (PRD Edge).

## Verträge
- Nur der PM-Handoff-Pass berührt Vault + pm-skills (architecture.md Boundary 3). Die Empfehlungs-/Override-Semantik am Gate ist entschieden (Owner b-2): Hybrid — deterministische Ableitung als Default, begründeter Owner-Override am Gate, protokolliert (data-model §8).
- Tests taggen `@trace gate-pm-anstoss#AC<n>`.

## Edge-Cases & Fehlerverhalten
- **E1** Vault nicht erreichbar (Mac-Pfad, iCloud-Sync) → klarer Abbruch vor jedem Schreiben, kein Teil-Artefakt.
- **E2** pm-skills nicht installiert → Gate meldet die fehlende Voraussetzung; das Thema bleibt unverändert `aktiv`.

## NFRs
- Jeder Anstoss protokolliert Thema, Lauf-Version, Hash und Entscheid — nachvollziehbar ohne Log-Archäologie.

## Nicht-Ziele
- Kein automatischer Anstoss (C-004). Keine Änderungen an pm-skills selbst (Idempotenz lebt in der Orchestrierung). Kein direktes agent-flow-Board-Schreiben.

## Abhängigkeiten
- Specs `research-datenmodell`, `research-skill` (depends). pm-skills installiert; agent-flow pm-import (existiert, agent-flow S-095–S-097); Obsidian-Vault erreichbar (Mac, Entscheid a-4).
