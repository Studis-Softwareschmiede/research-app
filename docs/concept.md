# Konzept — research-app

> **Schicht 1 von 3** (Konzept → Detailkonzept → Spezifikation). Das **WARUM & WAS**, sprach-/paradigma-unabhängig. Ändert selten. Source of Truth — der Code ist nachgelagert.

## Problem <a id="C-001"></a> *(C-001 ← IDEA-003, IDEA-004)*

Recherche mit last30days liefert heute Momentaufnahmen ohne Gedächtnis: Ergebnisse landen im Chat, Bewertungen sind nicht reproduzierbar, geparkte Themen geraten in Vergessenheit, und der Übergang von „interessantes Thema" zu strukturiertem PM-Prozess (pm-skills → pm-import → agent-flow) passiert manuell und ad hoc. Es fehlt eine Ebene, die Themen als Portfolio mit Verlauf führt, Bewertungen nachvollziehbar macht und den PM-Anstoss kontrolliert — per Entscheidungs-Gate, nie automatisch — auslöst. Der Praxis-Befund vom 18.07.2026 (manueller Workflow Terminal ↔ Claude Code ↔ Chat als „Hin und Her" erlebt) bestätigt den Schmerzpunkt.

## Nutzer & Kontext <a id="C-002"></a> *(C-002 ← IDEA-004)*

Alex als einziger Nutzer (Owner/PM/Entwickler in Personalunion) — keine Mehrbenutzer-Fähigkeit, keine Auth, kein öffentliches Deployment. Die App ist eine **eigenständige App** (Owner-Entscheid 26.07.2026, Katalog a-1) — kein dev-gui-Modul —, wird über die Fabrik (agent-flow) entwickelt und erscheint in der dev-gui wie jedes andere Projekt. Betrieb der Recherche-Jobs auf dem **Mac** (Owner-Entscheid a-4): der Obsidian-Vault ist nur dort direkt erreichbar; ein VPS-Betrieb (Git-Zwischenspeicher + Vault-Sync) bleibt bewusst zurückgestellt, bis autonome Tagesläufe anstehen. Die App ist zugleich erster Dogfooding-Kandidat der eigenen Kette: last30days → pm-skills → pm-import → agent-flow → Anzeige.

## Ziele <a id="C-003"></a> *(C-003 ← IDEA-004)*

1. Themen von der Entdeckung bis zum PM-Anstoss als **Portfolio mit Verlauf, Bewertung und Wiedervorlage** führen — statt verstreuter Einzelrecherchen im Chat.
2. Bewertung **reproduzierbar und ehrlich** machen: SWOT mit zweiter Evidenzquelle für Fundamentals (**Deep-Research-Pass**, Owner-Entscheid a-3), Empfehlung aus Meilenstein-Status ableitbar statt reiner Judge-Entscheid.
3. PM-Läufe **idempotent wiederholbar** machen, mit ausgewiesener Divergenz zwischen den Läufen.

**Erfolgsmessung** (Funktionsfähigkeit, nicht Wachstum — Single-User, keine Baselines): ≥ 5 aktive Themen mit vollständigem Datensatz (3 Monate nach Datenmodell) · ≥ 80 % der bewerteten Läufe mit zweiter Evidenzquelle · 100 % der geparkten Themen mit Meilenstein werden automatisch wiedervorgelegt · jeder Wiederholungslauf zeigt die Divergenz zum Vorlauf · 1 Thema durchläuft die volle Kette end-to-end.

## Nicht-Ziele <a id="C-004"></a> *(C-004 ← IDEA-004)*

- **Kein Rechtsmodul** — Schutzrechte erscheinen nur als Klärungspunkt im Voraussetzungs-Überblick.
- **Kein automatischer PM-Anstoss** — das Entscheidungs-Gate ist bewusst manuell.
- **Kein Neubau der Wiedervorlage** — last30days `--store`/Watchlist/Briefing-Digests werden genutzt; die Bewertungsschicht setzt obendrauf.
- **Keine Änderungen an pm-skills selbst** — Idempotenz leistet die Orchestrierung, nicht das fremde Plugin.
- **Keine neuen Recherche-Quellen** jenseits der bereits parametrisierten last30days-Quellen.
- **Keine Mehrbenutzer-Fähigkeit**, keine Auth, kein öffentliches Deployment.
- **Kein dev-gui-Modul** als Anzeige-Träger (Owner-Entscheid a-1 — eigenständige App).

## Scope <a id="C-005"></a> *(C-005 ← IDEA-003, IDEA-004)*

Fünf Kernbausteine, Reihenfolge verbindlich (Meilensteine M1–M6, Daten bewusst offen — Nebenprojekt):

1. **Datenmodell (M1, zuerst):** stabile Themen-ID, versionierte Läufe mit Hash, Divergenz-Berechnung über strukturierte Felder (Empfehlung, SWOT-Kategorien, Meilenstein-Status — nicht Freitext), Meilenstein-Format (Status + Zuständigkeit extern/eigen). Persistenz-Kandidat: bestehende last30days-SQLite (`--store`) als Basis.
2. **`/research`-Skill (M2):** Orchestrierung von last30days in beiden Modi (Discovery / vorgegebenes Thema), SWOT-Judge mit Deep-Research-Pass als zweiter Evidenzquelle, Empfehlung „weiterverfolgen / parken / verwerfen", Voraussetzungs-Überblick, Businessplan-Template bei „weiterverfolgen".
3. **Meilenstein-gekoppelte Wiedervorlage (M3):** Parken nur mit hinterlegtem Meilenstein; die last30days-Watchlist prüft und legt Themen bei erfülltem Meilenstein/Delta automatisch wieder vor.
4. **Entscheidungs-Gate + idempotenter PM-Anstoss (M4):** Gate als explizite Wahl (bis M5 als CLI-/Chat-Abfrage); PM-Anstoss erzeugt via pm-skills (ganzes Plugin installiert, Owner-Entscheid a-2) Konzepte/Spezifikationen im Obsidian und übergibt an agent-flow (pm-import); Wiederholung idempotent (ID + Hash) mit Divergenz-Ausweis.
5. **Anzeige (M5):** Portfolio-, Verlaufs-, Divergenz- und Gate-Ansicht als eigenständige App-Oberfläche; **M6 Dogfooding:** ein Thema durchläuft die volle Kette.

Die Details je Capability stehen in `docs/specs/<feature>.md`.

## Werkzeugkette & Integrationen <a id="C-006"></a> *(C-006 ← IDEA-001, IDEA-002, IDEA-003)*

- **last30days** (installiert): Recherche-Engine — Discovery-Modus, `--emit=json`, `--save-dir`, `--store`/Watchlist (SQLite, Delta-Erkennung), Briefing-Digests.
- **pm-skills** (ganzes Plugin, Entscheid a-2): erzeugt beim PM-Anstoss die PM-Artefakte (PRD, Hypothesen, Acceptance-Kriterien) im Obsidian.
- **agent-flow / pm-import** (bereits umgesetzt, agent-flow S-095–S-097): Intake der PM-Artefakte aus dem Vault — frontmatter-first-Erkennung, Sektions-Mapping nach dem Mapping-Schema (IDEA-002), Idempotenz über `version`/Revision-History als Anker. Liefert zugleich das Muster (stabile IDs + Hash-Vergleich) für die PM-Idempotenz der App — eine Ebene früher angewendet.
- **Obsidian-Vault:** Ablageort der PM-Artefakte; nur vom Mac erreichbar → bestimmt den Betriebsort (C-002).
- **Deep-Research-Pass** (Entscheid a-3): zweite Evidenzquelle für Fundamentals; fehlt sie in einem Lauf, wird die Empfehlung explizit als „Momentum-Signal" markiert.
- **Credentials:** GPG-verschlüsselt, nie im Vault (Detail-Liste in IDEA-003 §Bedarf; grösster Kostenposten sind Claude-Tokens pro Lauf).

## Risiken & offene Punkte <a id="C-007"></a> *(C-007 ← IDEA-004)*

| Risiko | Gegenmassnahme |
|---|---|
| SWOT-Bias: last30days misst Aufmerksamkeit, nicht Geschäftspotenzial (H/H) | Deep-Research-Pass als Regelfall; ohne ihn Empfehlung explizit als Momentum-Signal markiert — kein hartes Blocking |
| Token-Kosten autonomer Tagesläufe (M/M) | Kostenlimit im Headless-Setup; Automatisierung erst nach manueller Kostenerfahrung |
| App vor stabilem Datenmodell gebaut (M/H) | Harte Reihenfolge: Datenmodell zuerst (M1), Anzeige zuletzt (M5) |
| Idempotenz-Erwartung an pm-skills (M/M) | Idempotenz vollständig in der Orchestrierung (ID + Hash), pm-skills unverändert |
| last30days-SQLite-Schema nicht garantiert stabil | Schema-Änderung des Plugins bricht die Persistenz-Basis — bei M1 als Abhängigkeit ausweisen |

Offen (bewusst vertagt): Ablageort der last30days-Briefs im Vault (400 Ressourcen vs. Projektordner) — Detail-Entscheid bei M2. Die vier Owner-Entscheide vom 26.07.2026 (a-1 eigenständige App · a-2 pm-skills ganz · a-3 Deep-Research-Pass · a-4 Mac) sind oben eingearbeitet.
