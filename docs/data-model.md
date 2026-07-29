---
db_dialect: sqlite
---

# Datenmodell — research-app (M1)

> **Schicht-2-Artefakt (Daten-Achse), Source of Truth fürs Persistenzmodell.** Entwurf des `dba` im Design-Modus. Migrationen/DDL schreibt später der `coder` mit dem SQLite-Pack (`knowledge/sql-sqlite.md`), NICHT dieses Dokument. Inhalt ist bewusst dialekt-neutral gehalten (Entitäten/Beziehungen/Constraints); SQLite-spezifische Umsetzungshinweise stehen gesammelt in §9.
>
> **Profil-Hinweis (Handlungsbedarf):** `.claude/profile.md` trägt aktuell `db_dialect: none`. Das ist der stack-offene Platzhalterzustand vor M1. Mit diesem Modell ist der Dialekt entschieden — **`db_dialect: sqlite` in `profile.md` setzen**, bevor der `coder`/`dba`-Review-Lauf gegen dieses Modell startet (sonst bricht der DBA-Review mit „db_dialect: none" ab). Siehe OFFENE FRAGE OF-00.

## 0. Geltungsbereich & BR-Namensraum

- Deckt **M1** (C-005 Baustein 1): stabile Themen-ID, versionierte Läufe mit Hash, Divergenz über strukturierte Felder, Meilenstein-Format, Persistenz auf last30days-`--store`-Basis.
- **BR-Namensraum-Aufteilung** (shared Namespace mit `architecture.md`, vgl. dessen §Geschäftsregeln): dieses Dokument belegt **datenvalidierende** Regeln **BR-001…BR-099**. Der `architekt` beginnt seine **verhaltensbezogenen** BRs ab **BR-100**, um Kollisionen zu vermeiden. Beide Dateien nummerieren stabil (nicht umnummerieren).
- Single-User, lokal auf dem Mac, SQLite-Datei (C-002). Keine Auth, keine Mandantenfähigkeit, kein RLS.

## 1. Persistenz-Topologie (Bewertungsschicht auf last30days-Basis)

Die App führt eine **eigene Bewertungsschicht** über der bestehenden last30days-Recherche-Persistenz (C-004: „kein Neubau der Wiedervorlage"; C-007: last30days-Schema extern & **nicht garantiert stabil**).

**Harte Abgrenzung (BR-018):**
- Die App legt **ausschließlich eigene Tabellen** an (Präfix-Konvention: `ra_…`, „research-app").
- Die App **liest/schreibt niemals** last30days-Plugin-Tabellen und baut das Fremdschema **nicht** um.
- Verweise auf last30days-Datensätze sind **weiche externe Schlüssel** (`TEXT`, kein Foreign-Key über Schemagrenzen) — sie dürfen „dangeln", wenn das Plugin sein Schema ändert, purged oder neu aufsetzt. Der App-Datensatz bleibt gültig; die Referenz wird dann als „Quelle nicht mehr auflösbar" behandelt.

**Topologie provisorisch = separates App-DB-File** (`research-app.sqlite`) mit read-only-ATTACH der last30days-`--store`-Datei bei Bedarf. Begründung: schützt die Bewertungsschicht vor einem Plugin-seitigen File-Neuaufbau. **Alternative (gleiches File, Präfix) siehe OF-03** — bewusst nicht selbst entschieden.

## 2. Entitäten (dialekt-neutral)

Notation: `PK` Primärschlüssel, `FK→` Fremdschlüssel (nur innerhalb des App-Schemas), `soft→` weiche externe Referenz (kein FK), `enum{…}` per CHECK erzwungen, `!` = NOT NULL.

### 2.1 `ra_topic` — Thema (Portfolio-Kern)
| Feld | Typ | Constraints | Bedeutung |
|---|---|---|---|
| `id` | TEXT | PK | **Stabile Themen-ID** — über Läufe/Artefakte/PM-Anstoss unverändert (BR-001). Generierungsstrategie siehe OF-01. |
| `title` | TEXT | ! , CHECK `length(trim(title)) >= 1` | Themen-String; leer wird abgelehnt (BR-002). |
| `status` | TEXT | ! , enum{`aktiv`,`geparkt`,`im_pm`,`verworfen`} | Lebenszyklus (BR-003, Automat §7). |
| `created_at` | TEXT | ! default now | Anlagezeit. |
| `updated_at` | TEXT | ! default now | Letzte Statusänderung. |
| `discarded_at` | TEXT | nullable | Gesetzt gdw. `status='verworfen'` (BR-005). |

### 2.2 `ra_run` — Lauf (versioniert, mit Ergebnisstand-Hash)
| Feld | Typ | Constraints | Bedeutung |
|---|---|---|---|
| `id` | INTEGER | PK | Technischer Schlüssel. |
| `topic_id` | TEXT | ! , FK→`ra_topic(id)` | Zugehöriges Thema. |
| `kind` | TEXT | ! , enum{`recherche`,`pm`} | Lauf-Art (BR-008). |
| `version` | INTEGER | ! , UNIQUE(`topic_id`,`kind`,`version`) | Monoton steigend je (Thema, Art) — BR-007. Skopus siehe OF-04. |
| `result_hash` | TEXT | ! | **Ergebnisstand-Hash** nur über strukturierte Felder (BR-009, §5). |
| `recommendation` | TEXT | ! , enum{`weiterverfolgen`,`parken`,`verwerfen`} | Strukturierte Empfehlung (BR-013). |
| `has_deep_research` | INTEGER | ! , enum{0,1} | Deep-Research-Pass als 2. Evidenzquelle vorhanden (C-006). |
| `momentum_only` | INTEGER | ! , enum{0,1} | =1 gdw. `has_deep_research=0` → Empfehlung als „Momentum-Signal" markiert (BR-014). |
| `l30d_source_ref` | TEXT | soft→ last30days | Weiche Referenz auf den zugrundeliegenden last30days-Emit/Digest (BR-018). |
| `created_at` | TEXT | ! default now | Laufzeitpunkt. |

### 2.3 `ra_swot_item` — strukturierte SWOT-Einträge
Die **strukturierte** SWOT-Repräsentation ist das Fundament der determinismus-sicheren Divergenz (Freitext bleibt außen vor).
| Feld | Typ | Constraints | Bedeutung |
|---|---|---|---|
| `id` | INTEGER | PK | Technischer Schlüssel. |
| `run_id` | INTEGER | ! , FK→`ra_run(id)` ON DELETE CASCADE | Zugehöriger Lauf. |
| `category` | TEXT | ! , enum{`strength`,`weakness`,`opportunity`,`threat`} | SWOT-Kategorie (strukturiert). |
| `claim_key` | TEXT | ! | **Normalisierter** Aussagenschlüssel — kanonisch, formulierungsunabhängig (BR-012). Kanonisierung siehe OF-06. |
| `evidence_source` | TEXT | ! , enum{`last30days`,`deep_research`} | Herkunft der Evidenz (Fundamentals vs. Momentum). |
| `rationale` | TEXT | nullable | **Freitext-Begründung — von Hash & Divergenz AUSGESCHLOSSEN** (BR-012). |
| UNIQUE | | (`run_id`,`category`,`claim_key`) | Ein strukturierter Claim je Kategorie und Lauf. |

### 2.4 `ra_milestone` — Meilenstein (je Thema)
| Feld | Typ | Constraints | Bedeutung |
|---|---|---|---|
| `id` | INTEGER | PK | Technischer Schlüssel. |
| `topic_id` | TEXT | ! , FK→`ra_topic(id)` ON DELETE CASCADE | Meilensteine gehören zum **Thema**, nicht zum Lauf (C-005). |
| `description` | TEXT | ! , CHECK `length(trim(description)) >= 1` | Meilenstein-Beschreibung. |
| `responsibility` | TEXT | ! , enum{`extern`,`eigen`} | Zuständigkeit: extern → Watchlist prüft; eigen → parallel schaffen (BR-015). |
| `status` | TEXT | ! , enum{`offen`,`erfuellt`,`hinfaellig`} | Meilenstein-Status (BR-016). Genaues Enum siehe OF-12. |
| `watch_ref` | TEXT | soft→ last30days-Watchlist; NULL bei `responsibility='eigen'` | Referenz auf den Watchlist-Eintrag, der den extern-Meilenstein prüft (BR-015). |
| `created_at` | TEXT | ! default now | |
| `fulfilled_at` | TEXT | nullable | Gesetzt bei `status='erfuellt'`. |

### 2.5 `ra_divergence` — Divergenz zwischen zwei Läufen
Materialisiert je Folgelauf (Vorlauf → Folgelauf) — „jeder Wiederholungslauf zeigt die Divergenz zum Vorlauf" (C-003.3). Speicherung provisorisch, siehe OF-07.
| Feld | Typ | Constraints | Bedeutung |
|---|---|---|---|
| `id` | INTEGER | PK | |
| `topic_id` | TEXT | ! , FK→`ra_topic(id)` | Redundant zwecks Filter/Index. |
| `kind` | TEXT | ! , enum{`recherche`,`pm`} | Beide Läufe gleicher Art (BR-011). |
| `from_run_id` | INTEGER | ! , FK→`ra_run(id)` | Vorlauf. |
| `to_run_id` | INTEGER | ! , FK→`ra_run(id)` | Folgelauf. |
| `is_empty` | INTEGER | ! , enum{0,1} | =1 gdw. `hash(from)=hash(to)` (idempotenter Wiederholungslauf, BR-010). |
| `recommendation_changed` | INTEGER | ! , enum{0,1} | Empfehlung geändert? |
| `swot_delta` | TEXT (JSON) | nullable | Strukturiertes Delta: added/removed SWOT-Claims je (category, claim_key). Granularität siehe OF-05. |
| `milestone_status_delta` | TEXT (JSON) | nullable | Strukturiertes Delta der Meilenstein-Status. |
| `computed_at` | TEXT | ! default now | |
| UNIQUE | | (`from_run_id`,`to_run_id`) | Eine Divergenz je Laufpaar. |

### 2.6 `ra_pm_dispatch` — PM-Anstoss (idempotent)
Protokolliert das Entscheidungs-Gate-Ergebnis + PM-Anstoss (C-005 M4); Idempotenz über (Themen-ID + Hash), analog pm-import-Muster (C-006).
| Feld | Typ | Constraints | Bedeutung |
|---|---|---|---|
| `id` | INTEGER | PK | |
| `topic_id` | TEXT | ! , FK→`ra_topic(id)` | |
| `run_id` | INTEGER | ! , FK→`ra_run(id)` | Der auslösende PM-Lauf (`kind='pm'`). |
| `result_hash` | TEXT | ! | Hash-Stand zum Dispatch-Zeitpunkt. |
| `artifact_ref` | TEXT | ! | Obsidian-Pfad / pm-import-Version-Anker der erzeugten PM-Artefakte. |
| `dispatched_at` | TEXT | ! default now | |
| UNIQUE | | (`topic_id`,`result_hash`) | **Idempotenz (BR-017):** gleicher Hash ⇒ kein neuer Dispatch, nur Divergenz-Ausweis. |

### 2.7 `ra_topic_lock` — Serialisierungssperre (Nebenläufigkeit)
Advisory-Lock gegen gleichzeitige In-Flight-Läufe auf dasselbe Thema (Watchlist-Job ↔ manueller `/research`-Lauf). Granularität provisorisch je Thema, siehe OF-11.
| Feld | Typ | Constraints | Bedeutung |
|---|---|---|---|
| `topic_id` | TEXT | PK , FK→`ra_topic(id)` | Ein Lock-Row je Thema. |
| `holder` | TEXT | ! , enum{`watchlist`,`research`} | Wer hält die Sperre. |
| `acquired_at` | TEXT | ! default now | |
| `expires_at` | TEXT | ! | Ablauf (Stale-Lock-Schutz, falls Prozess abbricht). |

## 3. Beziehungen (Übersicht)

```
ra_topic 1──n ra_run          (topic_id)
ra_topic 1──n ra_milestone    (topic_id)
ra_topic 1──n ra_divergence   (topic_id)
ra_topic 1──n ra_pm_dispatch  (topic_id)
ra_topic 1──1 ra_topic_lock   (topic_id, optional)
ra_run   1──n ra_swot_item    (run_id, CASCADE)
ra_run   1──n ra_divergence   (from_run_id / to_run_id)
ra_run   1──n ra_pm_dispatch  (run_id)
last30days-Store  soft◄── ra_run.l30d_source_ref, ra_milestone.watch_ref   (kein FK)
```

**Pflicht-Indizes** (jede FK- und Filterspalte): `ra_run(topic_id, kind, version)` (UNIQUE deckt ab), `ra_topic(status)`, `ra_swot_item(run_id)`, `ra_swot_item(category)`, `ra_milestone(topic_id)`, `ra_milestone(status)`, `ra_milestone(responsibility)`, `ra_divergence(topic_id)`, `ra_divergence(to_run_id)`, `ra_pm_dispatch(topic_id)`. (SQLite legt auf FKs **keinen** Auto-Index an — explizit nötig.)

## 4. Geschäftsregeln (datenvalidierend, BR-001…)

- **BR-001** — Die Themen-ID (`ra_topic.id`) ist **stabil und eindeutig** (PK); sie ändert sich über Läufe, Artefakte und PM-Anstoss hinweg nie. Duplikat-ID wird abgelehnt.
- **BR-002** — `ra_topic.title` darf nicht leer sein: `length(trim(title)) >= 1`. Leerer Themen-String wird abgelehnt.
- **BR-003** — `ra_topic.status ∈ {aktiv, geparkt, im_pm, verworfen}`.
- **BR-004** — `status='geparkt'` ist nur zulässig, wenn das Thema **≥1 externen Meilenstein** (`responsibility='extern'`) hat (Parken-Bedingung, präzisiert durch `wiedervorlage-meilensteine#AC1`, S-012); rein `eigen`e Meilensteine genügen nicht, da nur externe Meilensteine die Watchlist-Kopplung (BR-015) für die automatische Wiedervorlage tragen.
- **BR-005** — `status='verworfen'` ist **Endzustand ohne Meilenstein** und **dauerhaft von der Wiedervorlage ausgeschlossen** (terminal). `discarded_at` ist dann gesetzt.
- **BR-006** — Statusänderungen folgen ausschließlich dem Zustandsautomaten (§7); andere Übergänge werden abgelehnt.
- **BR-007** — `ra_run.version` ist **monoton steigend und eindeutig** je (`topic_id`,`kind`); keine Doppel-Version.
- **BR-008** — `ra_run.kind ∈ {recherche, pm}`.
- **BR-009** — Der **Ergebnisstand-Hash** (`result_hash`) wird **deterministisch nur über strukturierte Felder** gebildet (§5); Freitext, Zeitstempel und technische IDs fließen NICHT ein. Ziel: Judge-Nichtdeterminismus erzeugt keinen Hash-Unterschied.
- **BR-010** — Divergenz wird **nur über strukturierte Felder** berechnet; bei `hash(from)=hash(to)` ist die Divergenz **leer** (`is_empty=1`) — idempotenter Wiederholungslauf.
- **BR-011** — Divergenz besteht nur zwischen **zwei Läufen desselben Themas und derselben Art**.
- **BR-012** — Ein SWOT-Eintrag ist strukturiert: **Kategorie-Enum {strength, weakness, opportunity, threat} + normalisierter `claim_key`**. Die Freitext-`rationale` ist von Hash **und** Divergenz ausgeschlossen.
- **BR-013** — `recommendation ∈ {weiterverfolgen, parken, verwerfen}` und ist **aus dem Meilenstein-Status ableitbar** (nicht reiner Judge-Entscheid). Exakte Ableitungsregel siehe OF-09.
- **BR-014** — Fehlt der Deep-Research-Pass (`has_deep_research=0`), ist die Empfehlung als **Momentum-Signal** zu markieren (`momentum_only=1`). Kein hartes Blocking (C-007).
- **BR-015** — Meilenstein-Zuständigkeit `∈ {extern, eigen}`. Bei `extern` ist `watch_ref` (Watchlist-Referenz) Pflicht; bei `eigen` ist `watch_ref` NULL.
- **BR-016** — `ra_milestone.status ∈ {offen, erfuellt, hinfaellig}`.
- **BR-017** — PM-Anstoss ist **idempotent**: `UNIQUE(topic_id, result_hash)`. Gleicher Hash ⇒ kein neues PM-Artefakt, nur Divergenz-Ausweis (analog pm-import-Muster, C-006).
- **BR-018** — Die App **verändert niemals** last30days-Plugin-Tabellen (kein Fremdschema-Umbau). Referenzen auf last30days sind ausschließlich **weiche externe Schlüssel** (kein FK über Schemagrenzen).
- **BR-019** — **Nebenläufigkeit:** Ein Lauf auf einem Thema erfordert das Halten der Themen-Serialisierungssperre (`ra_topic_lock`). Zwei gleichzeitige In-Flight-Läufe auf **dasselbe** Thema sind verboten.
- **BR-020** — **Wiedervorlage** erfolgt nur für Themen im Status `geparkt` mit erfülltem Meilenstein bzw. erkanntem Delta; `verworfen`-Themen werden nie wiedervorgelegt (folgt aus BR-005).

## 5. Ergebnisstand-Hash — Bildungsregel (BR-009)

**Kanonische Serialisierung** eines Laufs, danach `SHA-256` über die UTF-8-Bytes:

1. Nur diese Felder gehen ein (alles andere ausgeschlossen):
   - `recommendation` (Enum-Wert)
   - die Menge der SWOT-Claims als `(category, claim_key)`-Paare **ohne** `rationale`, `evidence_source`, IDs
   - der Meilenstein-Statusstand des Themas zum Laufzeitpunkt als `(milestone_stable_key, status, responsibility)`-Tripel
2. **Normalisierung:** Enum-Werte kleingeschrieben; Strings getrimmt; Listen **stabil sortiert** (lexikografisch nach Tupel).
3. **Ausgeschlossen:** `rationale`-Freitext, alle Zeitstempel, `run.id`/`version`, `l30d_source_ref`, sowie `has_deep_research`/`momentum_only` (Metadaten — **provisorisch**, siehe OF-08).
4. Serialisierung als kanonisches JSON (sortierte Schlüssel, keine Whitespace-Varianz).

→ Zwei Läufe mit identischem strukturiertem Ergebnis erzeugen denselben Hash, unabhängig von der Judge-Formulierung.

## 6. Divergenz — Bildungsregel (BR-010/011)

Eingabe: Vorlauf `A` (from), Folgelauf `B` (to), gleiches Thema, gleiche Art.
- `is_empty = 1` gdw. `A.result_hash = B.result_hash`.
- Sonst je Dimension:
  - `recommendation_changed = (A.recommendation != B.recommendation)`.
  - `swot_delta` = Symmetrische Differenz der `(category, claim_key)`-Mengen (added in B / removed vs. A). Granularität (Einzel-Item vs. Kategorie-Aggregat) → OF-05.
  - `milestone_status_delta` = geänderte `(milestone_stable_key, status)`-Tripel.
- Nur strukturierte Felder — `rationale` bleibt außen vor (BR-012). Deshalb erscheint Judge-Nichtdeterminismus **nicht** als Divergenz.

## 7. Zustandsautomat — Thema (BR-003/006)

```
             (Anlage)
                │
                ▼
            ┌────────┐   ≥1 externer MS     ┌─────────┐
            │ aktiv  │ ───────────────────▶ │ geparkt │
            │        │ ◀─────────────────── │         │
            └────────┘   Wiedervorlage       └─────────┘
              │   │      (Meilenstein erfüllt/Delta)
              │   │
   Gate+PM    │   │ 0 Meilensteine
              ▼   ▼
         ┌───────┐  ┌──────────┐
         │ im_pm │  │ verworfen│  (terminal, nie Wiedervorlage)
         └───────┘  └──────────┘
```

Gesicherte Kanten:
- `→ aktiv` bei Anlage.
- `aktiv → geparkt` nur mit ≥1 externem Meilenstein (BR-004).
- `geparkt → aktiv` durch Wiedervorlage (Watchlist: Meilenstein erfüllt / Delta; BR-020).
- `aktiv → im_pm` durch manuelles Entscheidungs-Gate + PM-Anstoss (C-004: nie automatisch).
- `aktiv → verworfen` nur ohne Meilenstein (BR-005); terminal.

**Nicht selbst entschiedene Kanten** (→ OF-10): `im_pm → ?` (zurück nach `aktiv` nach PM-Lauf?), `geparkt → verworfen` direkt?, ob beim Verwerfen eines Themas mit Meilensteinen diese zuvor entfernt werden müssen.

## 8. Empfehlung ↔ Meilenstein-Kopplung (BR-013)

Die Empfehlung soll **aus dem Meilenstein-Status ableitbar** sein (C-003.2), nicht reiner Judge-Entscheid. Das Modell hält `recommendation` als strukturiertes Feld vor und koppelt es an den Meilensteinstand; Ableitungs-Default (Owner-Entscheid b-2, Hybrid): kein offener externer Meilenstein (unabhängig vom `eigen`-Stand) → **weiterverfolgen**; ≥1 offener externer Meilenstein → **parken**; explizite Owner-Wahl oder Duplikat/nicht tragfähig → **verwerfen**. Der Owner kann am Gate begründet übersteuern (protokolliert, nie still).

**Präzisierung (S-010, AC4):** „eigener Meilenstein" bezieht sich auf `responsibility='eigen'`-Meilensteine (§2.4). Da diese laut Feldbeschreibung **parallel** geschaffen werden und keine Watchlist-Kopplung tragen (§2.4, BR-015), blockiert ein offener `eigen`-Meilenstein die automatische Ableitung allein **nicht** — maßgeblich für die Automatik ist ausschließlich der **externe** Meilenstein-Status: ≥1 offener externer Meilenstein → `parken`, sonst (keine offenen externen Meilensteine, unabhängig vom `eigen`-Stand) → `weiterverfolgen`. `verwerfen` ist **kein** aus dem Meilenstein-Status automatisch ableitbarer Zweig — dieser bleibt der begründeten Owner-/Judge-Entscheidung vorbehalten (Hybrid-Charakter der Regel).

## 9. SQLite-Umsetzungshinweise für den `coder` (Pack `sql-sqlite.md`)

Bindend fürs Migrationsdesign (`db_scripts/001_init.sql` ff.), Regel-IDs aus dem Pack:
- `sqlite/R02` — `PRAGMA foreign_keys = ON;` je Verbindung (FK sonst still ignoriert). Für BR-018-Soft-Refs bewusst **kein** FK.
- `sqlite/R03` — `PRAGMA journal_mode = WAL;` — nötig, da **zwei schreibende Prozesse** (Watchlist-Job + `/research`) gleichzeitig aktiv sein können (BR-019).
- `sqlite/R10` — **Kritisch bei diesem Nebenläufigkeitsprofil:** WAL-Reset-Data-Race (Korruption in SQLite 3.7.0–3.51.2). Da mehrere schreibende Verbindungen vorgesehen sind, muss die **tatsächlich gebundene** SQLite-Library-Version des Sprach-Treibers `≥ 3.51.3` (bzw. Backport 3.44.6/3.50.7) sein — vor Produktiv-Einsatz verifizieren.
- `sqlite/R01` — Multi-Replica verboten; hier unkritisch (Single-User, ein Mac-Prozess-Paar), aber App **nicht** horizontal skalieren.
- `sqlite/R04` — neue Tabellen als `STRICT` anlegen (Typ-Koersion vermeiden).
- `sqlite/R06` — Migrationskonvention: `db_scripts/<NNN>_name.sql` (3-stellig, lückenlos, forward-only), Marker-Tabelle `_schema_migrations`, `CREATE TABLE/INDEX IF NOT EXISTS`. PRAGMA-Zeilen in `001_init.sql`.
- **Serialisierung (BR-019):** `BEGIN IMMEDIATE` + gesetztes `busy_timeout` für den physischen Single-Writer-Lock; zusätzlich der logische `ra_topic_lock`-Advisory-Lock gegen versehentliche Doppel-Läufe je Thema (Stale-Lock via `expires_at`).
- **last30days-ATTACH** read-only; keinerlei DDL/DML gegen Fremdtabellen (BR-018).

---

# Gestaltungsentscheide (Stufe b, 26.07.2026)

> Aufgelöst aus den offenen Fragen des Design-Laufs. Technische Punkte: per Empfehlung/provisorischem Default entschieden (Orchestrator, Stufe b des Obsidian-Ingests). Owner-Punkte: per Fragenkatalog b entschieden.

- **OF-00 (Profil-Dialekt):** `db_dialect: sqlite` wird gesetzt (separater Config-Commit ausserhalb des Ingests).
- **OF-01 (Themen-ID):** UUIDv7, app-generiert (zeitsortierbar, kollisionsfrei).
- **OF-02 (Duplikat-Titel):** erlaubt, aber Warnung + Merge-Vorschlag beim Anlegen (nur die ID ist hart eindeutig, BR-001).
- **OF-03 (Persistenz-Topologie):** separates File `research-app.sqlite` + read-only-ATTACH der last30days-DB (deckungsgleich mit Architektur-Empfehlung F-3; schützt vor Plugin-File-Neuaufbau).
- **OF-04 (Versions-Skopus):** je (Thema, Lauf-Art) — Recherche- und PM-Läufe zählen getrennt.
- **OF-05 (SWOT-Divergenz-Granularität):** beides — Einzel-Item-Delta `(category, claim_key)` + Kategorie-Rollup (Divergenz-Ansicht ist Kern-Feature).
- **OF-06 (claim_key):** kontrolliertes Vokabular / feste Taxonomie — der Judge wählt aus einer versionierten Liste; freie Slugs sind unzulässig (determinismus-kritisch, BR-009/BR-012).
- **OF-07 (Divergenz-Speicherung):** materialisiert je Folgelauf in `ra_divergence` (Portfolio-/Verlaufs-Ansicht liest, statt zu rechnen).
- **OF-08 (Hash-Umfang):** `has_deep_research`/`momentum_only` bleiben AUSSERHALB des Hashs (Metadaten); die Divergenz-Ansicht weist einen Flag-Wechsel separat aus.
- **OF-09 (Empfehlungs-Ableitung):** ENTSCHIEDEN (Owner b-2, 26.07.2026): **Hybrid** — die deterministische Ableitung aus dem Meilenstein-Status ist der Default; der Owner kann am Gate begründet übersteuern. Der Override wird als eigenes Feld protokolliert (`recommendation_overridden=1` + Begründungstext), fliesst aber NICHT in den result_hash ein (BR-009-Logik unverändert).
- **OF-10 (Zustandsautomat-Restkanten):** `im_pm → aktiv` nach abgeschlossenem PM-Lauf (Thema bleibt im Portfolio aktiv); `geparkt → verworfen` ist erlaubt — offene Meilensteine werden dabei auf `hinfaellig` gesetzt (Historie bleibt, nichts wird gelöscht); BR-005 ist als „ohne offene Meilensteine" zu lesen.
- **OF-11 (Sperr-Granularität):** je Thema (`ra_topic_lock`) + globaler Engine-Lock (`BEGIN IMMEDIATE` + `busy_timeout`) — wie modelliert.
- **OF-12 (Meilenstein-Enum/Delta):** `{offen, erfuellt, hinfaellig}` (BR-016); „Delta" = das last30days-Watchlist-Delta-Signal (kein eigener Schwellwert-Mechanismus).
- **OF-13 (Aufbewahrung):** unbegrenzt — der Verlauf ist Feature; Single-User-Datenmengen bleiben klein (kein Retention-Mechanismus).
