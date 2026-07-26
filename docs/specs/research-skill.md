---
id: research-skill
title: /research-Skill — Orchestrierung, SWOT-Judge, Empfehlung, Voraussetzungs-Überblick (M2)
status: active
version: 1
spec_format: use-case-2.0
---

# Spec: `/research`-Skill  (`research-skill`)  *(← C-005, C-006)*

> **Schicht 3 von 3.** Source of Truth für `coder`/`tester`/`reviewer`. Detailkonzepte: [`docs/architecture.md`](../architecture.md) (Pass-Struktur, Boundaries), [`docs/data-model.md`](../data-model.md) (Persistenz).

## Zweck

Der projekt-lokale `/research`-Skill (skills/research/, ADR-006) orchestriert eine vollständige Themen-Recherche samt Bewertung: last30days-Lauf, SWOT mit zweiter Evidenzquelle, begründete Empfehlung, Voraussetzungs-Überblick — und persistiert alles über das Datenmodell. (PRD FR-5–FR-8, ← IDEA-003/IDEA-004.)

## Acceptance-Kriterien

- **AC1 — Zwei Modi:** Ein Lauf startet im Modus `discovery` (autonome Topthemen-Suche) oder `thema <string>` (vorgegebenes Thema); beide nutzen last30days über `--emit=json` + `--save-dir` + `--store` (kein Scraping-Eigenbau). Nur Discovery/Watchlist-Pässe rufen last30days auf (architecture.md Boundary 2).
- **AC2 — Brief + Bewertung:** Jeder Lauf erzeugt einen Recherche-Brief plus Bewertungsschicht: SWOT-Einträge als strukturierte Items (Kategorie-Enum + `claim_key` aus dem kontrollierten Vokabular, BR-012/OF-06) und Empfehlung `{weiterverfolgen, parken, verwerfen}`. Bei `weiterverfolgen` wird zusätzlich das Businessplan-Template ausgefüllt.
- **AC3 — Zweite Evidenzquelle:** Die SWOT zieht einen Deep-Research-Pass (Claude, Owner-Entscheid a-3) für Fundamentals heran. Fehlt er in einem Lauf, wird die Empfehlung sichtbar als Momentum-Signal markiert (`momentum_only=1`, BR-014) — kein hartes Blocking.
- **AC4 — Empfehlungs-Kopplung:** Die Empfehlung wird gemäss der in data-model §8 festgelegten Regel aus dem Meilenstein-Status abgeleitet und begründet (BR-013) — nicht allein vom Judge entschieden.
- **AC5 — Voraussetzungs-Überblick:** Je Thema entsteht/aktualisiert sich die Meilenstein-Liste (Status + Zuständigkeit extern/eigen); Schutzrechte erscheinen höchstens als Klärungspunkt (kein Rechtsmodul, C-004).
- **AC6 — Persistenz:** Themen-Anlage und Lauf-Ablage laufen ausschliesslich über die Data-Access-Schicht (Themen-Regeln AC1 der Datenmodell-Spec; Titel-Duplikat ⇒ Warnung + Merge-Vorschlag).
- **AC7 — Quellen-Resilienz:** Fällt eine Quelle aus (Credential abgelaufen, Kontingent erschöpft), läuft der Lauf mit den verbleibenden Quellen durch und weist die fehlenden im Brief aus (PRD Edge).

## Verträge
- Skill lebt projekt-lokal unter `skills/research/` (ADR-006); Gate/PM-Anstoss sind NICHT Teil dieses Skills (eigene Spec `gate-pm-anstoss`).
- Tests taggen `@trace research-skill#AC<n>`.

## Edge-Cases & Fehlerverhalten
- **E1** last30days nicht installiert/Store fehlt → klarer Abbruch mit Handlungsanweisung, kein Halb-Lauf.
- **E2** Judge liefert `claim_key` ausserhalb des Vokabulars → Item wird auf das Vokabular gemappt oder als `unmapped` zurückgewiesen; nie ein freier Slug persistiert (OF-06).
- **E3** Gleichzeitiger Lauf auf dasselbe Thema → Advisory-Lock verweigert den zweiten Lauf mit Klartext (BR-019).

## NFRs
- Grösster Kostenposten sind Claude-Tokens pro Lauf — der Brief weist den Token-Verbrauch aus (Kostenerfahrung vor Automatisierung, C-007).

## Nicht-Ziele
- Keine neuen Recherche-Quellen (C-004). Kein PM-Anstoss aus diesem Skill (M4). Keine Anzeige (M5).

## Abhängigkeiten
- Spec `research-datenmodell` (M1 muss gelandet sein — depends). last30days installiert + parametrisiert. Deep-Research-Fähigkeit im Claude-Setup.
