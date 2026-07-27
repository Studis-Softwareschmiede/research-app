---
name: research
description: Orchestriert eine Themen-Recherche fuer research-app (Discovery- oder Thema-Modus, last30days-Aufruf, Persistenz ueber die Data-Access-Schicht). M2-Grundgeruest (S-007) -- SWOT/Empfehlung/Voraussetzungs-Ueberblick folgen in spaeteren Stories (S-008ff.).
---

# /research — Skill-Grundgerüst (M2, ADR-006)

> Quelle: `docs/specs/research-skill.md` (AC1, AC6, AC7), `docs/architecture.md`
> (Komponente "Orchestrator"/"Discovery/Ingest"). Projekt-lokal unter
> `skills/research/` (ADR-006) — keine wiederverwendbare Fabrik-Capability.

## Zweck (Grundgerüst-Umfang dieser Story, S-007)

Startet einen Recherche-Lauf in einem von zwei Modi und legt das dazugehörige
Thema über die Data-Access-Schicht (`db_scripts/lib/`) an. SWOT-Judge,
Deep-Research-Pass, Empfehlung und Voraussetzungs-Überblick (AC2–AC5) sind
**nicht** Teil dieser Story — sie folgen in S-008 ff. auf demselben Grundgerüst.

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
