# Detailkonzept / Architektur — research-app

> **Schicht 2 von 3.** Das **WIE konzeptionell** — logisch, sprach-/paradigma-unabhängig (Komponenten/Flows/Zustände, keine Idiome/Klassen). Geschrieben vom `architekt`. Bindend für den `coder`; Architektur-Konformität ist Review-Kriterium.
> **Herkunft:** leitet `docs/concept.md` (C-001..C-007) ab. Datenschema-Details entwirft der `dba` parallel in `docs/data-model.md` — hier steht nur die **Schnittstelle**, kein Detailmodell.

## Systemüberblick — Schichtenmodell

Drei Schichten, entlang der bindenden Meilenstein-Reihenfolge M1–M6 (C-005). Abhängigkeiten zeigen nach innen (stabiler Kern = Daten): Anzeige kennt die Skill-Logik nicht, die Skill-Logik kennt die Anzeige nicht; beide gehen über die Datenschicht bzw. definierte Verträge.

```
Schicht 3  Anzeige-App (M5)                  eigenständige App, statisches HTML/JS (ADR-007)
             │  liest (read-model)            Portfolio · Verläufe · Divergenz · Gate-Ansicht
             │  In-Memory-Lesekopie           SQLite-Engine im Browser (ADR-010)
             ▼
Schicht 2  Datenschicht (M1, ZUERST)         SQLite: last30days --store (read-only Basis)
             ▲  liest/schreibt                 + eigene Bewertungs-Tabellen (single-writer)
             │
Schicht 1  /research-Skill (M2–M4)           Orchestrierung · SWOT-Judge · Deep-Research ·
             │                                Empfehlung · Wiedervorlage · Gate · PM-Anstoss
             ├──▶ last30days (CLI)            Recherche-Engine (extern, installiert)
             ├──▶ pm-skills (Plugin)          erzeugt PM-Artefakte im Obsidian-Vault
             └──▶ agent-flow /from-notes      liest Vault → Board (pm-import, indirekt)
```

**Kernprinzip (KISS, Single-User, Nebenprojekt):** ein modularer Monolith (`architecture/R05`), **ein Prozess**, keine Service-Splits, keine Auth, kein Deployment. Komplexität nur wo die Anforderung sie erzwingt (`architecture/R04`).

## Domänenmodell

Sprach-neutrale Kern-Entitäten (Begriffe → `glossary.md`, dort zu pflegen; Datenfelder → `data-model.md`):

- **Thema** — die stabile Identität, die über alle Recherchen hinweg verfolgt wird. Trägt eine **stabile Themen-ID** (unabhängig vom einzelnen Lauf) und einen Lebenszyklus-Zustand.
- **Lauf (Run)** — eine einzelne Recherche-/Bewertungs-Durchführung zu einem Thema. Versioniert, mit **Inhalts-Hash** über die strukturierten Bewertungsfelder. Ein Thema hat 1..n Läufe (Historie).
- **Bewertung** — die strukturierten Felder eines Laufs: **Empfehlung** (`weiterverfolgen | parken | verwerfen`), **SWOT-Kategorien**, **Meilenstein-Status**. Grundlage von Divergenz und Anzeige — kein Freitext.
- **Meilenstein** — extern messbare Bedingung eines geparkten Themas: **Status** + **Zuständigkeit** (extern/eigen). Voraussetzung fürs Parken und Auslöser der Wiedervorlage.
- **Deep-Research-Evidenz** — zweite Evidenzquelle für Fundamentals eines Laufs (Regelfall). Fehlt sie, ist der Lauf als **Momentum-Signal** markiert.
- **Voraussetzungs-Überblick** — Klärungspunkte je Thema (u.a. Schutzrechte — nur als Klärungspunkt, kein Rechtsmodul, C-004).
- **PM-Anstoss** — kontrollierte Übergabe eines `weiterverfolgen`-Themas an die PM-Kette. Trägt Idempotenz-Schlüssel (Themen-ID + Hash).

## Geschäftsregeln (BR-NNN)

> Verhaltensbezogene Invarianten (feature-übergreifend, hier je **einmal**; Specs referenzieren `(→ BR-NNN)`, Tests taggen `#BR-NNN`). **Datenvalidierende** BRs schreibt der `dba` in `data-model.md` — gleicher Namensraum, fortlaufend. **Reservierung zur Kollisionsvermeidung (Parallelarbeit):** Architektur belegt **BR-101..BR-109**; der `dba` beginnt datenvalidierende BRs bei **BR-001+**.

### BR-101: Kein Parken ohne Meilenstein
Ein Thema darf nur in den Zustand `geparkt` übergehen, wenn ein Meilenstein (Status + Zuständigkeit) hinterlegt ist. (→ C-005 M3)

### BR-102: PM-Anstoss nie automatisch
Ein PM-Anstoss erfolgt ausschliesslich nach einer expliziten Gate-Wahl des Nutzers, nie als Automatismus. (→ C-004)

### BR-103: PM-Anstoss idempotent mit Divergenz-Ausweis
Ein wiederholter PM-Anstoss zu identischer Themen-ID **und** identischem Inhalts-Hash aktualisiert die bestehenden PM-Artefakte statt Duplikate zu erzeugen; bei geändertem Hash wird die Divergenz zum Vorlauf ausgewiesen. (→ C-003 Ziel 3, C-006)

### BR-104: Fehlende Deep-Research → Momentum-Signal, kein Blocking
Fehlt der Deep-Research-Pass in einem Lauf, wird die Empfehlung explizit als „Momentum-Signal" markiert; der Lauf wird **nicht** blockiert. (→ C-007 SWOT-Bias)

### BR-105: Empfehlung aus Meilenstein-Status abgeleitet
Die Empfehlung (`weiterverfolgen | parken | verwerfen`) wird aus dem Meilenstein-Status (plus SWOT) **abgeleitet**, nicht als reiner Judge-Entscheid gesetzt. (→ C-003 Ziel 2)

### BR-106: Divergenz nur über strukturierte Felder
Die Divergenz zwischen zwei Läufen wird ausschliesslich über strukturierte Felder berechnet (Empfehlung, SWOT-Kategorien, Meilenstein-Status), nie über Freitext. (→ C-005 M1)

### BR-107: Businessplan-Template nur bei „weiterverfolgen"
Ein Businessplan-Template wird genau dann erzeugt, wenn die Empfehlung eines Laufs `weiterverfolgen` lautet. (→ C-005 M2)

### BR-108: Credentials nie im Vault
Credentials (u.a. Claude-Token) liegen GPG-verschlüsselt ausserhalb des Obsidian-Vaults; sie werden nie im Vault, in Commits oder Notizen abgelegt. (→ C-006)

### BR-109: Stabile Themen-Identität
Die Themen-ID ist über alle Läufe hinweg stabil und unabhängig vom einzelnen Lauf; Identität (Thema) und Ereignis (Lauf) sind getrennt. (→ C-005 M1)

## Komponenten

Schicht 1 ist ein Satz **logischer Orchestrierungs-Pässe** innerhalb des `/research`-Skills — keine verteilten Dienste, sondern klar abgegrenzte Verantwortlichkeiten mit expliziten Verträgen (`architecture/R01`, `R02`). Boundaries: Pässe kommunizieren nur über den **Lauf**-Datensatz (Datenschicht) bzw. explizite Rückgaben, nicht über geteilten Ad-hoc-Zustand.

| Komponente (Pass) | Verantwortung | Kennt / darf zugreifen auf | M |
|---|---|---|---|
| **Orchestrator** (`/research`) | Einstieg; wählt Modus (Discovery / Thema); ruft Pässe in Reihenfolge; hält Lauf-Kontext | alle Pässe, Datenschicht | M2 |
| **Discovery/Ingest** | ruft last30days in beiden Modi (`--emit=json`, `--save-dir`, `--store`); normalisiert Ergebnis in einen Lauf | last30days-CLI (nur lesend, s. ADR-002) | M2 |
| **SWOT-Judge** | bildet SWOT-Kategorien aus Brief + Deep-Research-Evidenz | Lauf-Daten | M2 |
| **Deep-Research** | zweite Evidenzquelle für Fundamentals; setzt bei Fehlen das Momentum-Flag (BR-104) | externe Recherche (kostentreibend) | M2 |
| **Recommendation** | leitet Empfehlung aus Meilenstein-Status + SWOT ab (BR-105) | Lauf-Daten | M2 |
| **Voraussetzungs-Überblick** | Klärungspunkte inkl. Schutzrechte (kein Rechtsmodul) | Lauf-Daten | M2 |
| **Businessplan-Emitter** | erzeugt Businessplan-Template bei `weiterverfolgen` (BR-107) | Lauf-Daten | M2 |
| **Divergence** | berechnet Delta zum Vorlauf über strukturierte Felder (BR-106); bildet den Inhalts-Hash | Datenschicht (Lauf-Historie) | M2/M4 |
| **Watchlist/Wiedervorlage** | koppelt geparkte Themen an last30days-Watchlist; legt bei Meilenstein-/Delta-Treffer wieder vor | last30days-Watchlist, Datenschicht | M3 |
| **Gate** | explizite Entscheidungs-Wahl (CLI/Chat bis M5); nie automatisch (BR-102) | Nutzer-Interaktion | M4 |
| **PM-Handoff** | stösst pm-skills an → Artefakte im Vault; idempotent per ID+Hash (BR-103); übergibt an pm-import. **Zweigeteilt** (ADR-009): Skill-Dispatch agentisch (Claude-Session, Skill-Tool) + Bookkeeping deterministisch (`orchestrator.sh`, kein pm-skills-Zugriff) | pm-skills, Obsidian-Vault; **nie** direkt ans agent-flow-Board (ADR-003) | M4 |
| **Data-Access** | einzige Schreib-/Lesestelle der Bewertungs-Tabellen (single-writer, ADR-002) | SQLite | M1 |

**Zentrale Boundary-Regel (prüfbar):** Ausser **Data-Access** greift **kein** Pass direkt schreibend auf SQLite zu; ausser **Discovery/Ingest** und **Watchlist** ruft **kein** Pass last30days; ausser **PM-Handoff** berührt **kein** Pass Vault oder pm-skills. Verstösse gegen diese drei Grenzen sind Review-Blocker (`architecture/R01`).

## Kern-Flows

**Flow A — Recherche-/Bewertungs-Lauf (M2), Modus `discovery` | `thema=<id>`:**
1. Orchestrator startet, wählt Modus.
2. Discovery/Ingest ruft last30days → normalisiert in neuen Lauf.
3. SWOT-Judge bildet SWOT.
4. Deep-Research holt Fundamentals; fehlt er → Momentum-Flag (BR-104).
5. Recommendation leitet Empfehlung aus Meilenstein-Status + SWOT ab (BR-105).
6. Voraussetzungs-Überblick wird erstellt (inkl. Schutzrechte-Klärungspunkt).
7. Bei `weiterverfolgen`: Businessplan-Template (BR-107).
8. Data-Access persistiert Lauf versioniert (Themen-ID + Inhalts-Hash, BR-109); Divergence berechnet Delta zum Vorlauf (BR-106).

**Flow B — Wiedervorlage (M3):**
1. Parken nur mit Meilenstein (BR-101) → Data-Access setzt Zustand `geparkt`.
2. Watchlist prüft (last30days) Delta/Meilenstein-Erfüllung.
3. Treffer → Thema automatisch wiedervorgelegt = neuer Flow A.

**Flow C — Gate + idempotenter PM-Anstoss (M4):**
1. Gate als explizite Wahl (CLI/Chat bis M5), nie automatisch (BR-102).
2. Wahl `PM-Anstoss` → **dieselbe** Claude-Session ruft pm-skills direkt über das Skill-Tool auf (kein Subprocess, ADR-009) → PM-Artefakte im Obsidian-Vault (von pm-skills selbst geschrieben).
3. Dieselbe Session übergibt die Artefakt-Vault-Referenz an `orchestrator.sh dispatch_pm_anstoss` → Idempotenz-Schlüssel = Themen-ID + Inhalts-Hash: gleicher Schlüssel ⇒ Update, geänderter Hash ⇒ Divergenz-Ausweis (BR-103).
4. agent-flow `/from-notes` (pm-import) liest die Vault-Artefakte → Board-Items. research-app schreibt **nie** direkt ins Board (ADR-003).

**Flow D — Dogfooding (M6):** ein Thema durchläuft A → C → agent-flow end-to-end; kein neuer Code, Verifikation der Kette.

## Zustände

Themen-Lebenszyklus (Zustandsmaschine je **Thema**; Läufe sind Ereignisse darauf):

```
              ┌─────────── entdeckt ──────────┐
              ▼                                 
           bewertet ──▶ verworfen (Endzustand)
           │    │
           │    └──▶ geparkt(+Meilenstein) ──(Watchlist-Treffer)──▶ bewertet   [Flow B]
           │
           └──▶ weiterverfolgen ──(Gate: PM-Anstoss)──▶ übergeben
                                                          │
                                                          └──(Re-Anstoss, geänderter Hash)──▶ übergeben′ (divergenz-aktualisiert)
```

Invarianten: `geparkt` nur mit Meilenstein (BR-101); Übergang nach `übergeben` nur über das Gate (BR-102).

## Externe Schnittstellen

| Dienst | Rolle | Vertragspunkt |
|---|---|---|
| **last30days** (CLI, installiert) | Recherche-Engine + Persistenz-Basis | Discovery/Thema-Modus; `--emit=json`, `--save-dir`, `--store`/Watchlist. **Konsumiert wird der JSON-Emit + dokumentierte Store-Sicht — read-only** (ADR-002). Schema-Instabilität ist Risiko (C-007) → Kopplung minimal halten. |
| **pm-skills** (Plugin, ganz installiert) | erzeugt PM-Artefakte (PRD/Hypothesen/AC…) im Vault | wird nur angestossen; **unverändert** (kein Fork, C-004). Idempotenz leistet PM-Handoff, nicht pm-skills. **Kein CLI** — reine Claude-Code-Skills/Sub-Agenten (`SKILL.md`, kein `bin`/Kommandozeilen-Interface); Aufruf ausschliesslich über das Skill-Tool der aktiven Session, nie per Bash-Subprocess (ADR-009). |
| **Obsidian-Vault** | Ablageort der PM-Artefakte | nur vom Mac erreichbar → bestimmt Betriebsort (C-002). Artefakt-Frontmatter (`artifact:`, `version`) ist Ankerfläche für pm-import. |
| **agent-flow `/from-notes` (pm-import)** | liest Vault-Artefakte → Board | research-app schreibt Artefakte in den Vault, **nie** direkt ins Board. Idempotenz-Muster gespiegelt aus pm-import (`sync_hash`/`version`, AC6) — eine Ebene früher. |
| **Deep-Research** | zweite Evidenzquelle | Regelfall; kostentreibend (Claude-Token). Ausfall → Momentum-Flag (BR-104). |

## Schicht 2 — Datenschnittstelle (Detail: `data-model.md`, dba)

Nur die **Schnittstelle** (Schema-Details entwirft der `dba`):
- **Persistenz:** SQLite. Basis ist die last30days-`--store`-DB (read-only, ADR-002); die **eigenen Bewertungs-Tabellen** setzen obendrauf und referenzieren last30days-Entitäten über einen **stabilen externen Schlüssel**, nicht über dessen interne Struktur.
- **Zugriffsvertrag:** ausschliesslich über die **Data-Access**-Komponente (single-writer der Bewertungs-Tabellen, `architecture/R09`).
- **Muss-Felder für die Skill-Logik** (Ausprägung → dba): stabile Themen-ID (BR-109), versionierter Lauf + Inhalts-Hash (BR-103/006), strukturierte Bewertung (Empfehlung/SWOT/Meilenstein-Status), Meilenstein (Status + Zuständigkeit extern/eigen), Momentum-Flag.
- **Physische Topologie (entschieden, ADR-008):** eigenes File `research-app.sqlite` für die Bewertungs-Tabellen; die last30days-`--store`-Datei wird bei Bedarf **read-only ge-ATTACHt**, nie verändert (`data-model.md` OF-03, `research-datenmodell#AC8`).

## Schicht 3 — Anzeige-App (M5)

- **Eigenständige App** (Owner-Entscheid a-1) — **kein** dev-gui-Modul; erscheint in dev-gui wie jedes andere Projekt (nur Projekt-Anzeige, kein Träger).
- **Umfang:** Portfolio-, Verlaufs-, Divergenz- und Gate-Ansicht. Ab M5 wandert das Gate von CLI/Chat in diese UI (ADR-005) — der **Schreibweg** der Gate-Aktion ist als „Text zum Kopieren" (Chat-Auftrag, kein Terminal-Befehl) entschieden (ADR-011).
- **Stack ENTSCHIEDEN (ADR-007):** statisches HTML5 + CSS + Vanilla-JS, **kein** Framework, **kein** Build-Step. Visuelle Ausprägung: [`docs/design.md`](design.md) (owner-freigegeben 2026-07-30) — bindend.
- **Betriebsmodell:** `app/index.html` wird lokal im Browser geöffnet (`file://`, Doppelklick). **Kein Server-Prozess**, kein Deployment, keine Auth, kein Netzwerkzugriff (C-002/C-004, `html/R03`).
- **Read-model-Boundary (aufgelöst, ADR-010):** die App liest `research-app.sqlite` **direkt** — über eine mitgelieferte SQLite-Engine (WASM/asm.js) im Browser. Die DB-Datei wird vom Nutzer per **Datei-Auswahl** übergeben und als **In-Memory-Lesekopie** geöffnet. Kein Export-Artefakt, kein Read-API-Prozess, keine Bewertungs-/Orchestrierungslogik in der App (die lebt in Schicht 1).

### Bindende Umsetzungs-Constraints der Anzeige (prüfbar — Verstoss = Review-Blocker)

| ID | Constraint |
|---|---|
| **UI-C1** | **Keine Netzwerk-Abhängigkeit.** Alle Assets (SQLite-Engine, CSS, Schriften, Icons) liegen unter `app/`; kein CDN, kein Request gegen einen entfernten Host (`html/R03`). Smoke: WLAN aus → Dashboard voll funktionsfähig. |
| **UI-C2** | **`file://`-Tauglichkeit.** Die Seite muss per Doppelklick auf `app/index.html` laufen. Daraus folgt hart: **keine ES-Module** (`<script type="module">`) und **kein `fetch()`/`XMLHttpRequest` auf lokale Dateien** — beides blockieren die Browser unter `file://` per Origin-Regel. Nur klassische `<script src>`/`<link href>`-Einbindungen. Die SQLite-Engine muss ohne Nachladen eines separaten Binaries starten (asm.js-Build **oder** base64-inline-WASM); welche Variante, verifiziert der `coder` per Smoke-Test, nicht per Annahme. |
| **UI-C3** | **DB-Zugang nur über Nutzer-Auswahl.** `<input type="file">` (optional zusätzlich Drag&Drop) → Bytes in den Speicher. Kein hart kodierter Dateipfad, keine Pfad-Heuristik. |
| **UI-C4** | **Read-only by construction.** Die geöffnete DB ist eine Speicherkopie und wird nie zurückgeschrieben (auch kein Download/Export der DB-Datei). Ausschliesslich `SELECT` — kein `INSERT`/`UPDATE`/`DELETE`/DDL. Damit erfüllt die App AC4 strukturell, nicht nur per Konvention. |
| **UI-C5** | **Lesemodell allein aus `research-app.sqlite`.** Ein `ATTACH` der last30days-DB ist im Browser nicht möglich. Braucht eine Ansicht ein last30days-Datum, muss **Schicht 1** es beim Lauf in die `ra_*`-Tabellen übernehmen — die Anzeige holt es nie selbst. |
| **UI-C6** | **Schnappschuss-Semantik sichtbar.** Die Anzeige nennt den Ladezeitpunkt („Stand: …") und bietet erneutes Laden an; sie behauptet nie Live-Aktualität. |
| **UI-C7** | **Fremdtext nie als HTML.** Alle DB-Werte (u.a. `rationale`, Meilenstein-Texte) werden über `textContent`/Node-APIs gerendert, nie per `innerHTML` — die Freitexte stammen aus Modellausgaben (Security-Floor). |
| **UI-C8** | **Mitgelieferte Engine mit Provenienz.** Die Engine-Datei liegt unter `app/vendor/` und trägt dokumentiert Version, Lizenz und SHA-256 der Datei. Ein Update ist ein bewusster Commit, kein Paketmanager-Lauf (es gibt keinen Build-Step). |

> **Profil-Nachzug (Owner/`/adopt`, nicht Teil dieser Story):** `.claude/profile.md` führt weiterhin `language: md`. Mit ADR-007 gehören `html`/`css`/`js` in die Sprach-Liste, damit `coder`/`reviewer` die passenden Knowledge-Packs laden. Bis dahin sind `html.md`/`css.md` über `docs/design.md` bindend referenziert.

## Repo-Struktur / Modul-Schnitt (Code lebt in diesem Repo)

```
research-app/
├── docs/                # concept · architecture · data-model (dba) · specs · glossary
├── db/                  # M1 — Schema/Migrationen der Bewertungs-Tabellen (dba-owned)
├── skills/research/     # M2–M4 — /research-Skill
│   ├── SKILL.md
│   └── scripts/         # Orchestrierungs-Pässe (discovery, judge, deep-research,
│                        #   recommend, prerequisites, businessplan, divergence,
│                        #   watchlist, gate, pm-handoff, data-access)
├── app/                 # M5 — Anzeige (statisch, ADR-007/ADR-010; kein Build-Step)
│   ├── index.html       #   Einstieg, per Doppelklick lauffähig (UI-C2)
│   ├── assets/          #   CSS/JS der App (Design-Tokens aus docs/design.md)
│   └── vendor/          #   mitgelieferte SQLite-Engine + Provenienz (UI-C8)
└── .claude/             # profile · board · lessons
```

**Meilenstein → Bausteine (bindende Reihenfolge):** M1 `db/` + `data-model.md` → M2 `skills/research/` (Flow A) → M3 Watchlist/Wiedervorlage (Flow B) → M4 Gate + PM-Handoff (Flow C) → M5 `app/` (Anzeige) → M6 Dogfooding (Flow D).

## Betrieb

- **Betriebsort Mac** (Owner-Entscheid a-4): Vault-Erreichbarkeit; VPS zurückgestellt bis autonome Tagesläufe.
- **Credentials** GPG-verschlüsselt, nie im Vault (BR-108).
- **Headless-Automatisierung später:** erst nach manueller Kostenerfahrung; **Kostenlimit** im Headless-Setup Pflicht (C-007). Deep-Research + last30days-Läufe sind die Kostentreiber.

## NFRs (prüfbar)

- **KISS/Modulith:** ein Prozess, keine Service-Splits, keine Auth, kein öffentliches Deployment (`architecture/R04`, `R05`).
- **Idempotenz nachweisbar:** identischer Input (ID+Hash) erzeugt kein Duplikat im Vault (BR-103) — testbar.
- **Divergenz reproduzierbar:** deterministisch über strukturierte Felder (BR-106).
- **Boundary-Konformität:** die drei Zugriffsgrenzen (SQLite/last30days/Vault) werden nur von den zuständigen Komponenten überschritten — Review-Blocker.
- **Anzeige serverlos + offline:** `app/index.html` per Doppelklick geöffnet rendert das Portfolio ohne Netzwerk und ohne zusätzlichen Prozess (Smoke: WLAN aus, kein Terminal-Vorlauf) — UI-C1/UI-C2.
- **Anzeige schreibfrei:** kein Schreib-Statement und kein Rückschreiben der DB-Datei im Anzeige-Code (`grep` auf `INSERT|UPDATE|DELETE|CREATE|DROP` in `app/assets/` bleibt leer — `app/tests/` ist bewusst ausgenommen, dort erzeugen Test-Fixtures per `sqlite3`-CLI gültige SQL-DDL/DML) — UI-C4.
- **Kostenkontrolle:** kein headless-Lauf ohne Kostenlimit.
- **Kopplungsminimierung:** keine Abhängigkeit vom **internen** last30days-Schema (nur JSON-Emit + externer Schlüssel).

## Entscheidungen (ADR)

Format: MADR-knapp (`architecture/R07/R08`) — Confidence + Reevaluations-Trigger je Eintrag. Akzeptierte ADRs werden nicht geändert, sondern superseded.

- **ADR-001 · 2026-07-26 · Modulith / Single-Process-Skill.** Schicht 1 ist ein modularer Monolith aus logischen Pässen, kein verteilter Dienst. *Begründung:* Single-User, Nebenprojekt (`R04/R05`). *Verworfen:* Microservices/Worker-Split (unnötige Komplexität). *Confidence:* hoch. *Reeval-Trigger:* headless-Parallelität mehrerer Themen wird nötig.
- **ADR-002 · 2026-07-26 · last30days-Store read-only, Bewertungs-Tabellen single-writer.** Die Data-Access-Komponente ist einziger Schreiber der eigenen Tabellen; last30days-Daten werden nur gelesen (JSON-Emit/dokumentierte Sicht), nie geschrieben. *Begründung:* `R09`; Schema-Instabilität von last30days (C-007) darf nicht in unsere Schreibpfade lecken. *Verworfen:* direkte Schreibzugriffe verteilt über mehrere Pässe. *Confidence:* hoch. *Reeval-Trigger:* last30days-Schemaänderung.
- **ADR-003 · 2026-07-26 · PM-Anstoss indirekt über den Vault.** PM-Handoff schreibt via pm-skills in den Obsidian-Vault; agent-flow liest per pm-import. research-app schreibt **nie** direkt ins agent-flow-Board. *Begründung:* pm-skills bleibt unverändert (C-004); nutzt bestehende, getestete Ingest-Kette. *Verworfen:* direkte Board-/API-Kopplung. *Confidence:* hoch. *Reeval-Trigger:* pm-import bietet einen stabileren direkten Vertrag.
- **ADR-004 · 2026-07-26 · Idempotenz = stabile Themen-ID + Inhalts-Hash.** Muster gespiegelt aus pm-import (`sync_hash`/`version`, AC6), eine Ebene früher. *Begründung:* konsistentes, bewährtes Idempotenz-Muster der Kette (C-006). *Confidence:* hoch. *Reeval-Trigger:* Kollisionen/Hash-Instabilität in der Praxis.
- **ADR-005 · 2026-07-26 · Gate manuell, CLI/Chat bis M5.** Bis zur Anzeige-App ist das Entscheidungs-Gate eine CLI-/Chat-Abfrage; ab M5 UI. *Begründung:* Gate nie automatisch (BR-102); Anzeige zuletzt (C-005). *Confidence:* hoch. *Reeval-Trigger:* M5-Anzeige verfügbar.
- **ADR-006 · OFFEN · Verortung/Verteilung des `/research`-Skills.** Empfehlung: projekt-lokal in `skills/research/` dieses Repos (projektspezifische Orchestrierung, keine wiederverwendbare Fabrik-Capability). Siehe Offene Fragen **F-2**.
- **ADR-007 · 2026-07-26 (hier nachgezogen 2026-07-30) · Stack der Anzeige-App (M5) = statisches HTML/JS.** Owner-Entscheid **b-1** vom 26.07.2026: statisches HTML5 + CSS + Vanilla-JS, **kein** Framework, **kein** Build-Step, kein Server. *Begründung:* Single-User-Lesedashboard mit drei Ansichten (`R04`); Flutter/Angular bringen Toolchain, Build-Pipeline und Framework-Lebenszyklus für einen Umfang, den natives HTML abdeckt. *Verworfen:* Flutter (Desktop-Toolchain + Dart-Build für eine Tabellen-Ansicht), Angular (Node-Build/Dependency-Pflege, widerspricht „kein Build-Step"). *Konsequenz:* `docs/design.md` (owner-freigegeben 2026-07-30) ist die bindende visuelle Ausprägung; die Zugriffsfrage auf SQLite wird dadurch nicht-trivial und ist separat in **ADR-010** entschieden; `profile.language` ist nachzuziehen (s. Schicht 3). *Confidence:* hoch. *Reeval-Trigger:* die Anzeige braucht Mehrbenutzer-/Remote-Betrieb, oder der Vanilla-JS-Umfang wächst über die drei Ansichten hinaus so weit, dass Zustandsverwaltung von Hand fehleranfällig wird.
- **ADR-008 · 2026-07-27 (hier nachgezogen 2026-07-30) · Bewertungs-Tabellen in eigenem File `research-app.sqlite`, last30days read-only ge-ATTACHt.** Entschieden im Datenmodell (`data-model.md` OF-03) und umgesetzt (Migrationen S-001, `research-datenmodell#AC8`). *Begründung:* schützt die Bewertungsschicht vor einem Plugin-seitigen Neuaufbau der last30days-Datei; deckungsgleich mit der ursprünglichen Architektur-Empfehlung. *Verworfen:* gemeinsames File mit Tabellen-Präfix. *Confidence:* hoch. *Reeval-Trigger:* last30days garantiert Schema-/File-Stabilität, oder Cross-DB-Joins werden im Regelbetrieb nötig.
- **ADR-009 · 2026-07-29 · PM-Handoff-Aufruf: Skill-Tool-Dispatch durch die aktive Session, kein CLI/Subprocess.** pm-skills ist kein CLI-Tool, sondern ein Satz Claude-Code-Skills/Sub-Agenten (`SKILL.md`, kein `bin`-Entry-Point). Der PM-Handoff-Pass ruft pm-skills daher **nie** aus einem eigenständigen Bash-Prozess (`orchestrator.sh`) heraus auf, sondern über das Skill-Tool derselben Claude-Session, die bereits das `/research`-Skill ausführt und die Gate-Wahl (AC1) entgegengenommen hat. `orchestrator.sh` übernimmt ausschliesslich das deterministische Bookkeeping (Idempotenz-Dispatch, Status-Transition) und erhält die Vault-Artefakt-Referenz als Eingabeparameter von der aufrufenden Session — es ermittelt sie nie selbst. *Begründung:* verifiziert gegen die installierte pm-skills-Plugin-Version — kein CLI-Interface vorhanden, nur Skill-Dateien; ein Bash-Skript kann eine Skill-Tool-Dispatch-Kette nicht wie ein CLI-Programm aufrufen (gate-pm-anstoss.md AC2). *Verworfen:* ein erfundenes pm-skills-CLI-Interface (`pm-skills generate --vault-path …`) — existiert nicht und wäre ein Fork-Risiko (widerspricht C-004 „pm-skills bleibt unverändert"). *Confidence:* hoch. *Reeval-Trigger:* pm-skills veröffentlicht ein offizielles CLI/npm-Paket mit Kommandozeilen-Interface, oder headless-Automatisierung (ADR-005-Reeval) macht einen `claude -p`-Dispatch (analog `board-feature-drain.sh#generate_dossier`) zur Regel statt zur späteren Ausnahme.
- **ADR-010 · 2026-07-30 · SQLite-Zugriff der Anzeige: mitgelieferte SQLite-Engine im Browser + Nutzer-Datei-Auswahl, In-Memory-Lesekopie.**
  *Kontext/Problem:* AC4 verlangt direktes Lesen aus `research-app.sqlite`; ADR-007/AC5 verlangen statisches HTML/JS ohne Build-Step; `html/R03` verlangt offline-first ohne CDN. Eine `file://`-Seite kann aber weder eine Datei über einen Pfad öffnen noch `fetch()` auf lokale Dateien ausführen — der Zugriffsmechanismus muss also explizit entschieden werden (Auslöser: S-021 blockiert, Spec-Lücke).
  *Entscheidung:* eine unter `app/vendor/` **mitgelieferte** SQLite-Engine (SQLite als WASM/asm.js, z.B. sql.js) läuft im Browser; der Nutzer übergibt die DB-Datei per Datei-Auswahl; die Bytes werden als **In-Memory-Lesekopie** geöffnet und ausschliesslich mit `SELECT` abgefragt. Bindende Constraints: **UI-C1..UI-C8** (Schicht 3).
  *Erwogen und verworfen:*
  (a) **Lokaler Server-Prozess** (`python3 -m http.server` oder Mini-Read-API): löst die Origin-Beschränkungen und könnte später auch den Gate-Schreibweg tragen — verworfen für den Regelbetrieb, weil er eine zweite Laufzeit und ein Start-Ritual vor jedem Blick aufs Dashboard einführt (widerspricht „leichtgewichtiges lokales Dashboard ohne Build-Step", AC5/`design.md`) und eine Read-API zur Leckstelle für Bewertungslogik würde (`R01`). **Klarstellung:** die Doku verbietet einen lokalen Prozess nicht wörtlich — C-004 verbietet Deployment, Auth und Mehrbenutzer-Betrieb; die Ablehnung ist eine KISS-Abwägung (`R04`), kein Verbot. Damit bleibt (a) der **erste Kandidat**, falls ADR-011 ohnehin einen Prozess erzwingt.
  (b) **File System Access API** (`showOpenFilePicker` + persistenter Handle): bequemer, weil die Datei nicht je Sitzung neu gewählt werden müsste — als **Basis** zu schmal: im Wesentlichen Chromium-only (Safari/Firefox bieten die Auswahl auf dem echten Dateisystem nicht), zusätzlich an Secure-Context- und Gesten-Regeln gebunden. Später als reine Bequemlichkeits-Ergänzung zulässig, aber nur mit Feature-Detection, nie als einziger Zugangsweg und nie mit Schreibrecht.
  (c) **Export-Artefakt** (Schicht 1 erzeugt eine JSON-/JS-Datei, die Seite lädt sie per `<script>`): technisch am einfachsten unter `file://` — verworfen, weil es AC4 („direkt aus `research-app.sqlite`") verletzt, vor jedem Blick einen Export-/Build-Schritt erzwingt und eine zweite Schema-Wahrheit neben `data-model.md` schafft.
  (d) **Offizielles sqlite.org-WASM mit OPFS-Backend:** OPFS ist ein Browser-Sandbox-Speicher, nicht die Datei auf der Platte, und die Auslieferung setzt ES-Module bzw. COOP/COEP-Header (also einen Server) voraus — passt weder zu UI-C2 noch zum serverlosen Betrieb.
  *Konsequenzen:* die Ansicht ist ein **Schnappschuss** (UI-C6) · **kein `ATTACH`** der last30days-DB möglich, nötige Fremddaten muss Schicht 1 in die `ra_*`-Tabellen übernehmen (UI-C5) · Read-only ist **strukturell** garantiert (UI-C4) · eine Engine-Datei wird ins Repo vendored (UI-C8) · die DB muss je Sitzung ausgewählt werden · **es entsteht kein Schreibpfad** — die Gate-Aktion (AC3) ist damit ausdrücklich **nicht** gelöst (→ ADR-011).
  *Confidence:* hoch für die Leseseite (AC1/AC2/AC4). *Reeval-Trigger:* ADR-011 entscheidet sich für einen lokalen Prozess (dann kann die Leseseite auf `http://localhost` umziehen und die Engine regulär per WASM-Streaming laden) · Safari/Firefox liefern die Datei-Auswahl-API cross-browser · die DB wächst so weit, dass eine Vollkopie im Speicher spürbar träge wird.
- **ADR-011 · 2026-07-30 · Schreibweg der Gate-Aktion aus der serverlosen Anzeige (AC3, ADR-005) = Text zum Kopieren.** Owner-Entscheid: Kandidat (a), **präzisiert** gegen ADR-009. ADR-009 hat bereits festgestellt: pm-skills ist kein CLI-Tool, der PM-Handoff läuft über Skill-Tool-Dispatch **innerhalb einer aktiven Claude-Code-Chat-Session** — es gibt also **keinen Terminal-Befehl**, der die eigentliche PM-Anstoss-Aktion auslöst. „Befehl zum Kopieren" bedeutet daher konkret: die Anzeige zeigt einen fertig formulierten **Chat-Auftragstext** (Themen-Titel, Themen-/Lauf-ID, Kontext) mit Kopieren-Button; der Nutzer fügt ihn in eine laufende oder neue Claude-Code-Session ein, die daraufhin den Skill-Tool-Dispatch (ADR-009 Schritt 1) und danach `orchestrator.sh dispatch_pm_anstoss` (ADR-009 Schritt 2) ausführt. Kein Shell-Snippet, kein `orchestrator.sh`-Aufruf direkt in der Anzeige vorformuliert (der Nutzer ruft nie selbst `dispatch_pm_anstoss` auf — das macht die Chat-Session nach dem Skill-Dispatch). *Begründung:* passt zum serverlosen, buildlosen Grundprinzip der Anzeige (ADR-007/ADR-010) und zum bereits etablierten Zwei-Schritt-Mechanismus aus ADR-009; kein Chromium-only-Pfad (verwirft (b)), keine Rücknahme der Server-Ablehnung aus ADR-010 (verwirft (c)). *Verworfen:* (b) Gate-Intent-Datei via File System Access API (asynchron, Chromium-only); (c) minimaler lokaler HTTP-Endpunkt nur für die Gate-Aktion (zweite Laufzeit, widerspricht ADR-010). *Konsequenz:* „PM anstossen" in der UI zeigt den Chat-Auftragstext inkl. Thema-/Lauf-Kontext und einen Kopieren-Button; kein Auto-Submit, keine Bestätigung im Dashboard selbst. *Confidence:* hoch. *Reeval-Trigger:* pm-skills bekommt doch ein offizielles CLI (dann würde ein echtes Shell-Snippet möglich) · die Anzeige bekommt einen begleitenden lokalen Prozess aus anderem Grund (dann würde (c) neu attraktiv).

> **Offene Architektur-Entscheide:** **ADR-006** (Skill-Verortung) ist bewusst nicht final gesetzt und braucht einen Owner-Entscheid; er wird danach hier als akzeptierte ADR nachgezogen. **ADR-007**, **ADR-008** und **ADR-011** sind entschieden (b-1, OF-03 bzw. Owner-Entscheid 2026-07-30) und oben nachgetragen.
