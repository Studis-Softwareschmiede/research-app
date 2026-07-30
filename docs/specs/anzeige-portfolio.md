---
id: anzeige-portfolio
title: Anzeige-Ebene — Portfolio, Verläufe, Divergenz-Ansicht, klickbare Gates (M5)
status: active
version: 1
spec_format: use-case-2.0
---

# Spec: Anzeige-Ebene  (`anzeige-portfolio`)  *(← C-005)*

> **Schicht 3 von 3.** Source of Truth für `coder`/`tester`/`reviewer`. Detailkonzepte: [`docs/architecture.md`](../architecture.md) (Schicht 3 inkl. Constraints **UI-C1..UI-C8**, ADR-007/ADR-010), [`docs/design.md`](../design.md) (owner-freigegeben, bindend), [`docs/data-model.md`](../data-model.md).

## Zweck

Die eigenständige App-Oberfläche (Owner-Entscheid a-1 — kein dev-gui-Modul) macht sichtbar, wofür Chat/CLI das falsche Medium ist: Themen-Portfolio mit Verlauf, Divergenz-Ansicht zwischen Läufen und Entscheidungs-Gates als klickbare Wahl. Reines Lesemodell plus Gate-Bedienung — Recherche/Bewertung/PM bleiben Schicht-1-Logik. (PRD FR-14–FR-16, ← IDEA-003/IDEA-004; Praxis-Befund 18.07. als Auslöser.)

## Acceptance-Kriterien

- **AC1 — Portfolio:** Alle Themen mit Status (aktiv/geparkt/im PM/verworfen), letzter Bewertung (Empfehlung + Momentum-Kennzeichen) und offenen Meilensteinen sind einsehbar. Zeilen sind bereits ab AC1 fokussierbar (`tabindex`-fähiges Element, `design.md` #Grundkomponenten 4 Accessibility-Vorgabe) — die eigentliche Klick-/Enter-Navigation zum Thema-Detail wird erst mit AC2 (S-023) verdrahtet, da die Zielsicht (Verlauf/Divergenz/Gate) vorher nicht existiert.
- **AC2 — Verlauf & Divergenz:** Pro Thema sind der Lauf-Verlauf und die Divergenz-Ansicht zwischen zwei frei wählbaren Läufen darstellbar (Empfehlungs-Wechsel, SWOT-Item-Delta + Kategorie-Rollup, Meilenstein-Delta — aus `ra_divergence`, nie aus Freitext). Default-Auswahl: neuester Lauf vs. Vorgänger. **Präzisierung (S-023):** „frei wählbar" bezieht sich auf die Auswahl-UI (zwei `<select>` mit allen Läufen des Themas) — `ra_divergence` wird laut `data-model.md` OF-07 nur **je Folgelauf** (unmittelbar aufeinanderfolgendes Laufpaar) materialisiert. Wählt der Nutzer ein Laufpaar ohne materialisierte Zeile, zeigt die Ansicht einen Hinweis („keine Divergenz-Daten für diese Kombination") statt selbst zu rechnen (Verträge: „Divergenz wird gelesen, nicht neu berechnet").
- **AC3 — Klickbare Gates:** Anstehende Entscheidungs-Gates sind in der Anzeige bedienbar (PM anstossen / warten). Mechanismus (ADR-011, Owner-Entscheid 2026-07-30, bindend, präzisiert gegen ADR-009): „bedienbar" heisst konkret **kopierbar** — die Anzeige zeigt zum anstehenden Gate einen fertig formulierten **Chat-Auftragstext** (inkl. Themen-Titel, Themen-/Lauf-Kontext) als Text mit Kopieren-Button. Da pm-skills kein CLI-Tool ist (ADR-009), ist das **kein Terminal-Befehl**: der Nutzer fügt den Text in eine Claude-Code-Chat-Session ein, die daraufhin den Skill-Tool-Dispatch + das Bookkeeping (`gate-pm-anstoss.md`, `orchestrator.sh dispatch_pm_anstoss`) durchführt — nie an dieser Schnittstelle vorbei. Kein Auto-Submit, keine Aktion, die selbst schreibt — die Anzeige bleibt dadurch strukturell lesend (deckungsgleich mit AC4). „Warten" ist der Nicht-Klick (kein Gegenstück-Button nötig, das Gate bleibt einfach unbeantwortet sichtbar).
- **AC4 — Lesemodell-Boundary:** Die Anzeige liest `research-app.sqlite` **direkt** — kein Export-Artefakt, kein Zwischenformat, kein Server-Prozess. Mechanismus (ADR-010, bindend): eine unter `app/vendor/` mitgelieferte SQLite-Engine (WASM/asm.js) läuft im Browser; die DB-Datei wird vom Nutzer per Datei-Auswahl übergeben (`<input type="file">`, optional Drag&Drop) und als **In-Memory-Lesekopie** geöffnet. Es werden ausschliesslich `SELECT`-Abfragen ausgeführt, die Datei wird nie zurückgeschrieben (read-only by construction) — einzige Schreib-Ausnahme im Gesamtsystem ist die Gate-Aktion über Schicht 1 (AC3). Da die Ansicht ein Schnappschuss ist, zeigt sie den Ladezeitpunkt und bietet erneutes Laden an. Es gilt die Constraint-Liste **UI-C1..UI-C8** in `docs/architecture.md`.
- **AC5 — Stack:** Umsetzung als statisches HTML5 + CSS + Vanilla-JS (ADR-007, Owner-Entscheid b-1 vom 26.07.2026) — **kein** Framework, **kein** Build-Step, **kein** Server-Prozess, offline lauffähig (keine CDN-/Netzwerk-Abhängigkeit, `html/R03`). `app/index.html` muss per Doppelklick (`file://`) funktionieren; daraus folgen die harten Einschränkungen aus **UI-C2** (keine ES-Module, kein `fetch()` auf lokale Dateien). Gebaut wird erst, wenn M1–M4 gelandet sind (M5 ist letzter Meilenstein — harte Reihenfolge C-005).

## Verträge
- Kein Schreibpfad ausser Gate-Aktion; keine eigene Geschäftslogik in der Anzeige (Divergenz wird gelesen, nicht neu berechnet).
- Tests taggen `@trace anzeige-portfolio#AC<n>`.

## Edge-Cases & Fehlerverhalten
- **E1** Noch keine DB ausgewählt bzw. DB leer → Leere-Zustands-Ansicht mit Handlungsanweisung (DB wählen / ersten Lauf starten), kein Fehler-Stack.
- **E2** Gate-Aktion kollidiert mit laufendem Lauf (Themen-Lock) → sichtbare Meldung, keine Doppel-Auslösung.
- **E3** Ausgewählte Datei ist kein gültiges SQLite oder enthält keine `ra_*`-Tabellen (falsche Datei erwischt) → verständliche Meldung mit Hinweis auf die erwartete Datei, kein Fehler-Stack, vorheriger Anzeigezustand bleibt unverändert.

## NFRs
- Single-User, lokal; keine Auth, kein öffentliches Deployment (C-004).

## Nicht-Ziele
- Kein dev-gui-Modul (Entscheid a-1). Keine Ausführungs-Logik in der Anzeige. Kein Mehrbenutzer-Betrieb.

## Abhängigkeiten
- Specs `research-datenmodell`, `research-skill`, `wiedervorlage-meilensteine`, `gate-pm-anstoss` (depends — M5 zuletzt). ADR-007-Stack-Entscheid (Katalog b-1) und ADR-010-Zugriffsentscheid sind gesetzt.
- ADR-011 (Gate-Schreibweg) ist entschieden — AC3 ist unblockiert.
