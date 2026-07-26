---
id: research-datenmodell
title: Datenmodell & Persistenz — Themen, Läufe, Hashes, Divergenz, Meilensteine (M1)
status: active
version: 1
spec_format: use-case-2.0
---

# Spec: Datenmodell & Persistenz  (`research-datenmodell`)  *(← C-005)*

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**. Source of Truth für `coder`/`tester`/`reviewer`.
> Bindendes Detailkonzept: [`docs/data-model.md`](../data-model.md) (Entitäten, BR-001–BR-020, Hash-/Divergenz-Regeln, Zustandsautomat) + [`docs/architecture.md`](../architecture.md) (Data-Access als einziger Schreiber).

## Zweck

Fundament der Research App (Meilenstein M1, verbindlich zuerst): Themen-Portfolio mit stabilen IDs, versionierten Läufen, deterministischen Ergebnis-Hashes, berechneter Divergenz und meilenstein-gekoppelten Zuständen — als SQLite-Schema samt Migrationen und Zugriffsschicht. (PRD FR-1–FR-4, ← IDEA-004.)

## Acceptance-Kriterien

- **AC1 — Themen-Anlage:** Ein Thema erhält eine stabile, app-generierte ID (UUIDv7), die über alle Läufe/Artefakte/PM-Anstösse unverändert bleibt (BR-001). Leerer Titel wird abgelehnt (BR-002); Duplikat-ID ist unmöglich; gleicher Titel löst Warnung + Merge-Vorschlag aus, blockiert aber nicht (OF-02-Entscheid).
- **AC2 — Versionierte Läufe:** Jeder Recherche-/PM-Lauf wird als `ra_run` mit monotoner Version je (Thema, Art) (BR-007) und deterministischem `result_hash` (BR-009, Bildungsregel data-model §5) gespeichert. Zwei Läufe mit identischem strukturiertem Ergebnis ⇒ identischer Hash, unabhängig von Judge-Formulierungen.
- **AC3 — Divergenz:** Die Divergenz zwischen zwei wählbaren Läufen desselben Themas/derselben Art ist berechenbar und wird je Folgelauf materialisiert (`ra_divergence`, BR-010/BR-011): Empfehlungs-Wechsel, SWOT-Delta als Einzel-Item-Differenz `(category, claim_key)` **plus** Kategorie-Rollup, Meilenstein-Status-Delta. Gleicher Hash ⇒ `is_empty=1`.
- **AC4 — Meilensteine:** Meilensteine tragen Status `{offen, erfuellt, hinfaellig}` und Zuständigkeit `{extern, eigen}` (BR-015/BR-016); bei `extern` ist die Watchlist-Referenz Pflicht.
- **AC5 — Zustandsautomat:** Themen-Status `{aktiv, geparkt, im_pm, verworfen}` mit genau den Kanten aus data-model §7 inkl. OF-10-Entscheid (`im_pm → aktiv` nach PM-Lauf; `geparkt → verworfen` setzt offene Meilensteine auf `hinfaellig`); alle anderen Übergänge werden abgelehnt (BR-006).
- **AC6 — Migrationen:** Schema als forward-only-Migrationen `db_scripts/NNN_name.sql` (STRICT-Tabellen, WAL, `foreign_keys=ON`, Marker-Tabelle — sqlite/R02/R03/R04/R06). Die gebundene SQLite-Version wird beim Start gegen den WAL-Korruptionsbug geprüft (≥ 3.51.3, sqlite/R10) — bei Verstoss klare Fehlermeldung statt stillem Betrieb.
- **AC7 — Nebenläufigkeit:** Gleichzeitige Schreiber (Watchlist-Job + `/research`-Lauf) korrumpieren nichts: `BEGIN IMMEDIATE` + `busy_timeout` + Advisory-Lock je Thema (`ra_topic_lock`, Stale-Ablauf via `expires_at`, BR-019). Ein Test simuliert zwei parallele Schreiber.
- **AC8 — Fremd-Store-Schutz:** Eigene Daten leben im separaten `research-app.sqlite`; die last30days-DB wird ausschliesslich read-only ge-ATTACHt, nie verändert (BR-018, OF-03-Entscheid).

## Verträge
- Nur die Data-Access-Schicht schreibt SQLite (architecture.md Boundary 1); Enums/Invarianten als CHECK-Constraints gemäss data-model.
- Tests taggen `@trace research-datenmodell#AC<n>[,BR-NNN]`.

## Edge-Cases & Fehlerverhalten
- **E1** Themen-String leer / ID-Kollision → Anlage abgelehnt bzw. bestehendes Thema referenziert (PRD Edge).
- **E2** Lock veraltet (Prozess abgestürzt) → Übernahme nach `expires_at`, kein Dauer-Deadlock.
- **E3** last30days-Store fehlt/umbenannt → App-Funktionen ohne Fremd-Store bleiben nutzbar; Watchlist-Bezüge melden den Ausfall klartextlich.

## NFRs
- Single-User, lokal (Mac); keine horizontale Skalierung (sqlite/R01).

## Nicht-Ziele
- Kein Umbau/DDL an last30days-Tabellen (BR-018). Keine Retention/Archivierung (OF-13: Verlauf unbegrenzt).

## Abhängigkeiten
- `docs/data-model.md` (bindend), `docs/architecture.md` §Schicht 2, last30days `--store`-SQLite (extern, Schema nicht garantiert — E3).
