---
name: research
description: Orchestriert eine Themen-Recherche fuer research-app (Discovery- oder Thema-Modus, last30days-Aufruf, Persistenz ueber die Data-Access-Schicht, Voraussetzungs-Ueberblick mit Meilenstein-Liste, strukturierte SWOT-Bewertung + deterministisch abgeleitete Empfehlung + Businessplan-Template + manuelles Entscheidungs-Gate). M2-Grundgeruest (S-007) + Voraussetzungs-Ueberblick (S-011) + Bewertungsschicht (S-008) + Empfehlungs-Kopplung (S-010) + Entscheidungs-Gate (S-016) -- Deep-Research folgt in S-009.
---

# /research — Skill-Grundgerüst (M2, ADR-006)

> Quelle: `docs/specs/research-skill.md` (AC1, AC2, AC4, AC5, AC6, AC7), `docs/architecture.md`
> (Komponente "Orchestrator"/"Discovery/Ingest"/"Voraussetzungs-Ueberblick"/
> "SWOT-Judge"/"Recommendation"/"Businessplan-Emitter"). Projekt-lokal unter
> `skills/research/` (ADR-006) — keine wiederverwendbare Fabrik-Capability.

## Zweck (Grundgerüst-Umfang S-007 + Voraussetzungs-Überblick S-011 + Bewertungsschicht S-008 + Empfehlungs-Kopplung S-010)

Startet einen Recherche-Lauf in einem von zwei Modi und legt das dazugehörige
Thema über die Data-Access-Schicht (`db_scripts/lib/`) an; im Thema-Modus wird
zusätzlich der aktuelle Voraussetzungs-Überblick (Meilenstein-Liste + fixer
Schutzrechte-Klärungspunkt) im Brief ausgewiesen (AC5, S-011). Die Empfehlung
wird deterministisch aus dem Meilenstein-Status abgeleitet (AC4, S-010) statt
frei vom Judge entschieden. Deep-Research-Pass (AC3) ist **nicht** Teil dieser
Story — er folgt in S-009.

## Bewertungsschicht (AC2, S-008)

Nach dem last30days-Aufruf wertet Claude (der Skill-Ausführende) die Ergebnisse
aus last30days aus und persistiert die Bewertung — **niemals** per direktem
SQLite-Zugriff (Boundary-Regel), sondern ausschließlich über die Data-Access-
Schicht:

1. **SWOT-Judge (strukturiert, BR-012/OF-06):** Für jede belastbare SWOT-Aussage
   ruft Claude `db_scripts/lib/swot_item.sh#create_swot_item <db> <run-id>
   <strength|weakness|opportunity|threat> <claim_key> <last30days|deep_research>
   [rationale]` auf. `claim_key` MUSS ein Begriff aus dem kontrollierten
   Vokabular sein (`RA_CLAIM_VOCABULARY` in `swot_item.sh`, aktuell Version
   `v1`) — ein Begriff außerhalb des Vokabulars wird (nach Trim/Kleinschreibung)
   abgewiesen, **nie** wird ein freier Slug persistiert (E2). Fehlt ein
   passender Vokabular-Begriff für eine wichtige Beobachtung, ist das eine
   Lücke im Vokabular selbst (Spec-Präzisierung/neue Version), kein Grund, den
   Claim wegzulassen oder frei zu benennen.
2. **Empfehlung ableiten (AC4/BR-013, S-010):** BEVOR der Lauf angelegt wird,
   ruft Claude `skills/research/scripts/orchestrator.sh recommend <topic-id>`
   auf (Env `RA_DB_PATH` wie gewohnt). Der Befehl liefert die deterministisch
   aus dem aktuellen Meilenstein-Status abgeleitete Default-Empfehlung
   (`docs/data-model.md` §8, Hybrid-Regel: ≥1 offener externer Meilenstein →
   `parken`, sonst → `weiterverfolgen`) samt Begründung. **Empfehlung ist
   damit kein freier Judge-Entscheid mehr:** Claude übernimmt diesen Default,
   **außer** ein expliziter Grund verlangt `verwerfen` (Duplikat, nicht
   tragfähig — dieser Zweig ist der Ableitungsfunktion bewusst nicht
   zugänglich, §8) oder eine begründete Owner-Vorgabe überstimmt ihn — jede
   Abweichung vom Default wird im Brief-Freitext explizit begründet (nie
   still).
3. **Lauf anlegen:** Sobald die SWOT-Items feststehen, bildet Claude den
   `<swot-pairs>`-Parameter (`category|claim_key`-Zeilen) und ruft
   `db_scripts/lib/run.sh#compute_result_hash` (mit dem Meilenstein-Stand aus
   `list_milestones`) und danach `create_run <db> <topic-id> recherche
   <result_hash> <recommendation> <has_deep_research> <momentum_only>
   [l30d_source_ref]` auf — `<recommendation>` ist die in Schritt 2 ermittelte
   (Default- oder begründet abweichende) Empfehlung. Bis zum Deep-Research-Pass
   (S-009, AC3) sind `has_deep_research=0`/`momentum_only=1` (Momentum-Signal,
   BR-014) die konsistente Kombination.
4. **SWOT-Items am Lauf verankern:** Erst NACH `create_run` (liefert die
   `run_id`) ruft Claude `create_swot_item` je Claim mit dieser `run_id` auf.
5. **Businessplan-Template (BR-107):** Ist `recommendation = weiterverfolgen`,
   füllt Claude das im Brief gerenderte Businessplan-Template
   (`orchestrator.sh#print_businessplan_template`) im Freitext aus.
6. **Brief rendern:** `skills/research/scripts/orchestrator.sh evaluation
   <run-id>` rendert die SWOT-Zusammenfassung + Empfehlung (inkl.
   Businessplan-Template bei `weiterverfolgen`) sowie das Entscheidungs-Gate
   als Teil des Recherche-Briefs.

## Entscheidungs-Gate (AC1, `docs/specs/gate-pm-anstoss.md`, S-016)

Ist die Empfehlung des gerade gerenderten Laufs `weiterverfolgen`, hängt
`orchestrator.sh#print_gate_prompt` an den Brief eine **explizite** Wahl an:
den Lauf jetzt per PM-Anstoss an den PM-Prozess übergeben, oder
zurückstellen. Die Wahl ist bis M5 eine reine CLI-/Chat-Abfrage (ADR-005) —
Claude stellt sie dem Owner im Chat und wartet auf eine explizite Antwort.
**Ohne diese Entscheidung passiert nichts** (C-004/BR-102, kein
Automatik-Anstoss) — der eigentliche PM-Anstoss (pm-skills-Aufruf über den
PM-Handoff-Pass, AC2–AC6) ist **nicht** Teil dieser Story und wird hier noch
nicht ausgelöst. Bei `parken`/`verwerfen` erscheint das Gate nicht (kein Pfad
nach `im_pm` aus diesen Empfehlungen, architecture.md Zustandsautomat).

## Voraussetzungs-Überblick (AC5, S-011)

- **Meilenstein-Liste anlegen/aktualisieren:** Stellt die Recherche fest, dass
  ein Thema eine extern oder eigen zu erfüllende Voraussetzung hat (z. B.
  "Pilotkunde bestätigt", "API-Zugang verfügbar"), legt Claude während der
  Recherche je Voraussetzung einen Meilenstein über
  `db_scripts/lib/milestone.sh#create_milestone <db> <topic-id> <description>
  <extern|eigen> [watch-ref]` an — **niemals** per direktem SQLite-Zugriff
  (Boundary-Regel). `extern` erfordert eine last30days-Watchlist-Referenz
  (`watch_ref`, BR-015); `eigen` verbietet sie. Ändert sich der Stand eines
  bereits bekannten Meilensteins (erfüllt/hinfällig), aktualisiert
  `set_milestone_status <db> <milestone-id> <offen|erfuellt|hinfaellig>` ihn —
  **kein** neuer Meilenstein für dieselbe Voraussetzung.
- **Schutzrechte NUR als Klärungspunkt (C-004, kein Rechtsmodul):** Stellt
  Claude während der Recherche eine schutzrechtliche Fragestellung fest (Patent/
  Marke/Urheberrecht), wird das **nie** als eigener Meilenstein oder eigenes
  Datenfeld persistiert und **nie** rechtlich bewertet — der Brief weist den
  fixen Klärungspunkt "Klärungspunkt Schutzrechte: zu prüfen, kein
  automatisiertes Rechtsmodul (C-004)" ohnehin bei jedem Thema-Lauf aus
  (`orchestrator.sh#print_milestone_overview`); ein konkreter Verdacht gehört
  als Freitext-Hinweis in den Brief, nicht in die Datenschicht.
- **Anzeige:** `research_thema` rendert die aktuell in `ra_milestone`
  hinterlegte Liste (Status + Zuständigkeit, plus Watchlist-Referenz bei
  `extern`) automatisch im Brief — auch wenn noch kein Meilenstein existiert
  (dann "Noch keine Meilensteine für dieses Thema hinterlegt.").
- **Discovery-Modus** zeigt bewusst **keinen** Voraussetzungs-Überblick und legt
  bewusst **keinen** Lauf/keine SWOT-Bewertung an (reine Topthemen-Sichtung,
  kein Tiefen-Pass je Kandidat) — die Bewertungsschicht (AC2, `evaluation`-
  Subbefehl) ist ausschliesslich für den Thema-Modus vorgesehen.

## Modi (AC1)

- **`discovery`** — autonome Topthemen-Suche (last30days `--discover`, kein
  positionelles Thema).
- **`thema <string>`** — vorgegebenes Thema (last30days mit dem String als
  positionellem Suchbegriff).

Beide Modi rufen last30days ausschliesslich über `--emit=json --save-dir <dir>
--store` auf (kein Scraping-Eigenbau, architecture.md Boundary 2: nur
Discovery/Ingest und Watchlist rufen last30days auf).

## Aufruf

```bash
skills/research/scripts/orchestrator.sh discovery [save-dir]
skills/research/scripts/orchestrator.sh thema "<Thema-String>" [save-dir]
skills/research/scripts/orchestrator.sh recommend <topic-id>
skills/research/scripts/orchestrator.sh evaluation <run-id>
```

Env-Overrides:
- `RA_DB_PATH` — Pfad zur `research-app.sqlite` (Default: `research-app.sqlite`).
- `RA_LAST30DAYS_CMD` — last30days-Kommando (Default: `last30days`, auf PATH
  aufgelöst).
- `RA_LOCK_HOLDER` — `ra_topic_lock.holder`-Wert (Default: `research`).
- `RA_LOCK_TTL_SECONDS` — Lock-TTL in Sekunden (Default: `1800`).

## Verhalten

- **Persistenz (AC6):** Themen-Anlage läuft ausschliesslich über
  `db_scripts/lib/topic.sh` (`create_topic`/`find_topic_by_title`) — kein
  direkter SQLite-Zugriff aus diesem Skill. Exakt gleicher Titel wie ein
  bereits bestehendes Thema wird wiederverwendet (BR-109, stabile
  Themen-Identität über mehrere Läufe); andernfalls legt `create_topic` ein
  neues Thema an (Titel-Duplikat zwischen zwei *verschiedenen* Themen ⇒
  Warnung + Merge-Vorschlag, OF-02 — unverändert aus S-002).
- **Quellen-Resilienz (AC7):** last30days meldet je Quelle einen Status
  (`source_status`, last30days-Agent-JSON-Vertrag). Status ausserhalb von
  `ok`/`no-results`/`partial`/`skipped-unconfigured` (z. B. `auth-failed` =
  Credential abgelaufen, `rate-limited` = Kontingent erschöpft) gilt als
  ausgefallen — der Lauf läuft mit den verbleibenden Quellen durch, die
  fehlenden werden im Brief ausgewiesen (kein Abbruch).
- **E1 (last30days fehlt / Store fehlt):** vor jedem last30days-Aufruf prüft
  der Skill (a) ob das Kommando auflösbar ist und (b) ob `research-app.sqlite`
  existiert und migriert ist (Tabelle `ra_topic` vorhanden). Fehlt eines von
  beiden, bricht der Lauf mit einer klaren Handlungsanweisung ab, **bevor**
  last30days aufgerufen wird (kein Halb-Lauf, kein verbrauchter
  last30days-Call ohne Persistenz-Ziel).
- **E3 (gleichzeitiger Lauf auf dasselbe Thema):** vor jeder last30days-
  Bearbeitung eines Themas wird `ra_topic_lock` (BR-019,
  `db_scripts/lib/topic_lock.sh`) erworben; ist das Thema bereits gesperrt,
  bricht der Skill mit Klartext ab (Thema-Modus) bzw. überspringt das Thema
  mit Klartext-Hinweis (Discovery-Modus, mehrere Themen je Lauf) — kein
  Doppel-Lauf auf demselben Thema.
