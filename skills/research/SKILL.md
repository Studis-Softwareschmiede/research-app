---
name: research
description: Orchestriert eine Themen-Recherche fuer research-app (Discovery- oder Thema-Modus, last30days-Aufruf, Persistenz ueber die Data-Access-Schicht, Voraussetzungs-Ueberblick mit Meilenstein-Liste). M2-Grundgeruest (S-007) + Voraussetzungs-Ueberblick (S-011) -- SWOT/Empfehlung folgen in spaeteren Stories (S-008ff.).
---

# /research — Skill-Grundgerüst (M2, ADR-006)

> Quelle: `docs/specs/research-skill.md` (AC1, AC5, AC6, AC7), `docs/architecture.md`
> (Komponente "Orchestrator"/"Discovery/Ingest"/"Voraussetzungs-Ueberblick").
> Projekt-lokal unter `skills/research/` (ADR-006) — keine wiederverwendbare
> Fabrik-Capability.

## Zweck (Grundgerüst-Umfang S-007 + Voraussetzungs-Überblick S-011)

Startet einen Recherche-Lauf in einem von zwei Modi und legt das dazugehörige
Thema über die Data-Access-Schicht (`db_scripts/lib/`) an; im Thema-Modus wird
zusätzlich der aktuelle Voraussetzungs-Überblick (Meilenstein-Liste + fixer
Schutzrechte-Klärungspunkt) im Brief ausgewiesen (AC5, S-011). SWOT-Judge,
Deep-Research-Pass und Empfehlung (AC2–AC4) sind **nicht** Teil dieser Story —
sie folgen in S-008 ff. auf demselben Grundgerüst.

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
- **Discovery-Modus** zeigt bewusst **keinen** Voraussetzungs-Überblick (reine
  Topthemen-Sichtung, kein Tiefen-Pass je Kandidat — analog zum bisherigen
  Scope-Schnitt von SWOT/Empfehlung).

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
