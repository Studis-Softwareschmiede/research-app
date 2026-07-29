# Detailkonzept / Architektur — research-app

> **Schicht 2 von 3.** Das **WIE konzeptionell** — logisch, sprach-/paradigma-unabhängig (Komponenten/Flows/Zustände, keine Idiome/Klassen). Geschrieben vom `architekt`. Bindend für den `coder`; Architektur-Konformität ist Review-Kriterium.
> **Herkunft:** leitet `docs/concept.md` (C-001..C-007) ab. Datenschema-Details entwirft der `dba` parallel in `docs/data-model.md` — hier steht nur die **Schnittstelle**, kein Detailmodell.

## Systemüberblick — Schichtenmodell

Drei Schichten, entlang der bindenden Meilenstein-Reihenfolge M1–M6 (C-005). Abhängigkeiten zeigen nach innen (stabiler Kern = Daten): Anzeige kennt die Skill-Logik nicht, die Skill-Logik kennt die Anzeige nicht; beide gehen über die Datenschicht bzw. definierte Verträge.

```
Schicht 3  Anzeige-App (M5, SPÄTER)          eigenständige App, Stack OFFEN
             │  liest (read-model)            Portfolio · Verläufe · Divergenz · Gate-Ansicht
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
- **Offen (dba + Owner):** ob die Bewertungs-Tabellen im **selben** DB-File (ATTACH/obendrauf) oder in einem **separaten** File mit Referenz-Schlüssel leben — siehe Offene Fragen F-3.

## Schicht 3 — Anzeige-App (M5, SPÄTER)

- **Eigenständige App** (Owner-Entscheid a-1) — **kein** dev-gui-Modul; erscheint in dev-gui wie jedes andere Projekt (nur Projekt-Anzeige, kein Träger).
- **Umfang:** Portfolio-, Verlaufs-, Divergenz- und Gate-Ansicht. Ab M5 wandert das Gate von CLI/Chat in diese UI (ADR-005).
- **Read-model-Boundary:** die App liest die Datenschicht als **Lesemodell** und enthält **keine** Bewertungs-/Orchestrierungslogik (die lebt in Schicht 1). Ob sie SQLite direkt liest oder über einen Export/Read-API-Vertrag, hängt am Stack → Offene Fragen F-1/F-4.
- **Stack OFFEN** (Flutter vs. Angular vs. HTML/JS) → Offene Fragen F-1. Bis zum Entscheid bleibt `app/` leer; Profil-`frameworks`/`db_dialect` werden dann per `architekt`/`/adopt`-Re-Run gesetzt.

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
├── app/                 # M5 — Anzeige-App (Stack OFFEN; leer bis M5)
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
- **ADR-007 · OFFEN · Stack der Anzeige-App (M5).** Flutter vs. Angular vs. HTML/JS. Siehe Offene Fragen **F-1**.
- **ADR-008 · OFFEN · Physische Kopplung der Bewertungs-Tabellen an die last30days-DB** (selbes File vs. separates File + Referenz). dba + Owner. Siehe Offene Fragen **F-3**.
- **ADR-009 · 2026-07-29 · PM-Handoff-Aufruf: Skill-Tool-Dispatch durch die aktive Session, kein CLI/Subprocess.** pm-skills ist kein CLI-Tool, sondern ein Satz Claude-Code-Skills/Sub-Agenten (`SKILL.md`, kein `bin`-Entry-Point). Der PM-Handoff-Pass ruft pm-skills daher **nie** aus einem eigenständigen Bash-Prozess (`orchestrator.sh`) heraus auf, sondern über das Skill-Tool derselben Claude-Session, die bereits das `/research`-Skill ausführt und die Gate-Wahl (AC1) entgegengenommen hat. `orchestrator.sh` übernimmt ausschliesslich das deterministische Bookkeeping (Idempotenz-Dispatch, Status-Transition) und erhält die Vault-Artefakt-Referenz als Eingabeparameter von der aufrufenden Session — es ermittelt sie nie selbst. *Begründung:* verifiziert gegen die installierte pm-skills-Plugin-Version — kein CLI-Interface vorhanden, nur Skill-Dateien; ein Bash-Skript kann eine Skill-Tool-Dispatch-Kette nicht wie ein CLI-Programm aufrufen (gate-pm-anstoss.md AC2). *Verworfen:* ein erfundenes pm-skills-CLI-Interface (`pm-skills generate --vault-path …`) — existiert nicht und wäre ein Fork-Risiko (widerspricht C-004 „pm-skills bleibt unverändert"). *Confidence:* hoch. *Reeval-Trigger:* pm-skills veröffentlicht ein offizielles CLI/npm-Paket mit Kommandozeilen-Interface, oder headless-Automatisierung (ADR-005-Reeval) macht einen `claude -p`-Dispatch (analog `board-feature-drain.sh#generate_dossier`) zur Regel statt zur späteren Ausnahme.

> **Offene Architektur-Entscheide** (ADR-006..008) sind bewusst nicht final gesetzt — der Katalog steht in der Rückgabe des `architekt`-Laufs (Stufe-b) und wird nach Owner-Entscheid hier als akzeptierte ADR nachgezogen.
