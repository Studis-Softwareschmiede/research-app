---
id: gate-pm-anstoss
title: Entscheidungs-Gate + idempotenter PM-Anstoss mit Divergenz-Ausweis (M4)
status: active
version: 1
spec_format: use-case-2.0
---

# Spec: Entscheidungs-Gate & PM-Anstoss  (`gate-pm-anstoss`)  *(← C-005, C-006)*

> **Schicht 3 von 3.** Source of Truth für `coder`/`tester`/`reviewer`. Detailkonzepte: [`docs/architecture.md`](../architecture.md) (ADR-003/ADR-004, PM-Handoff-Boundary), [`docs/data-model.md`](../data-model.md) (BR-017).

## Zweck

Der Übergang vom bewerteten Thema in den PM-Prozess bleibt eine bewusste menschliche Entscheidung: Nach jedem bewerteten Lauf bietet das System den PM-Anstoss als explizite Wahl an; der Anstoss selbst erzeugt via pm-skills die PM-Artefakte im Obsidian und übergibt an agent-flow (pm-import) — idempotent, mit ausgewiesener Divergenz. (PRD FR-11–FR-13, ← IDEA-003/IDEA-004.)

## Acceptance-Kriterien

- **AC1 — Gate ist manuell:** Nach jedem bewerteten Lauf wird der PM-Anstoss als explizite Wahl angeboten (bis M5 als CLI-/Chat-Abfrage, ADR-005); ohne menschliche Entscheidung passiert nichts (C-004 — kein Automatik-Anstoss).
- **AC2 — PM-Anstoss über die Kette:** Der Anstoss erzeugt via pm-skills (ganzes Plugin, Entscheid a-2) Konzept-/Spec-Artefakte, legt sie im Obsidian-Vault ab und übergibt an agent-flow über pm-import — nie direkt ins agent-flow-Board (ADR-003). Das Thema wechselt `aktiv → im_pm`; nach abgeschlossenem PM-Lauf zurück `im_pm → aktiv` (OF-10). Ein Anstoss ist auch aus Status `im_pm` heraus zulässig (wiederholter oder divergierender Dispatch zu einem Thema, das bereits im PM-Prozess ist, z. B. ein weiterer Recherche-Lauf während dieser Zeit) — der Status bleibt dabei `im_pm` (keine erneute Transition).
- **AC3 — Idempotenz:** Ein wiederholter Anstoss zum selben Thema mit gleichem `result_hash` erzeugt kein neues PM-Artefakt (`UNIQUE(topic_id, result_hash)`, BR-017) und wird als „keine Divergenz" protokolliert (PRD Edge).
- **AC4 — Divergenz-Ausweis:** Bei verändertem Ergebnisstand aktualisiert der Anstoss die PM-Ergebnisse und weist die Divergenz zum Vorlauf strukturiert aus (Datenmodell-Spec AC3). „Vorlauf" ist hier der beim vorherigen PM-Anstoss zu diesem Thema dispatchte Lauf (letzter `ra_pm_dispatch`-Eintrag vor diesem Aufruf) — ohne vorherigen PM-Anstoss (Erst-Anstoss) gibt es keinen Vorlauf, der Divergenz-Ausweis entfällt dann ersatzlos.
- **AC5 — Abbruch-Sicherheit:** Bricht ein Anstoss mittendrin ab, erlaubt die Idempotenz den gefahrlosen Neustart; kein halb aktualisierter Stand wird als „aktuell" markiert (PRD Edge).
- **AC6 — Manuelle Vault-Änderung:** Wurde ein PM-Artefakt zwischen zwei Läufen manuell im Obsidian bearbeitet (Hash-Mismatch gegen erwarteten Vorlauf-Stand), löst der Anstoss eine Rückfrage aus statt still zu überschreiben (PRD Edge).

## Verträge
- Nur der PM-Handoff-Pass berührt Vault + pm-skills (architecture.md Boundary 3). Die Empfehlungs-/Override-Semantik am Gate ist entschieden (Owner b-2): Hybrid — deterministische Ableitung als Default, begründeter Owner-Override am Gate, protokolliert (data-model §8).
- Tests taggen `@trace gate-pm-anstoss#AC<n>`.

### AC2 — Technischer Aufrufmechanismus (verbindlich, ADR-009)

pm-skills ist **kein CLI-Tool** — es ist ausschliesslich ein Satz Claude-Code-Skills/Sub-Agenten (`SKILL.md`-Dateien unter `skills/`, verteilt als Claude-Code-Plugin). Es gibt keinen `bin`-Eintrag, kein installierbares npm/pip-Paket mit eigener Kommandozeile (verifiziert gegen die installierte Plugin-Version: `plugin.json` ohne CLI-Interface, `package.json` enthält nur Validator-Tooling für pm-skills' eigene CI). Ein eigenständiger Bash-Prozess (`orchestrator.sh`) kann pm-skills daher **nicht** wie ein CLI-Programm per `exec`/Subprocess aufrufen — jeder so geformte Vertrag (z. B. `pm-skills generate --vault-path … --topic-id …`) ist ein erfundenes Interface und **ungültig**.

Der PM-Handoff-Pass läuft stattdessen zweigeteilt:

1. **Skill-Dispatch (agentisch, kein Subprocess):** Die aktive Claude-Code-Session, die bereits das `/research`-Skill ausführt und dort die Gate-Wahl (AC1, ADR-005) entgegengenommen hat, ruft **im selben Turn** über das **Skill-Tool** den passenden pm-skills-Workflow/Skill auf — mit dem Themen-Brief (Titel, Empfehlung, SWOT, Meilenstein-Status) als Prompt-Kontext. Welcher konkrete pm-skills-Workflow (z. B. `pm-skills:chain` oder ein passender `workflow-*`) gewählt wird, ist Ausgestaltung des PM-Handoff-Passes selbst, nicht Gegenstand dieser Klärung. pm-skills schreibt die erzeugten Konzept-/Spec-Artefakte selbst in den Obsidian-Vault (eigene Dateioperationen der Skill-Session) — kein Rückkanal an ein Bash-Skript nötig.
2. **Deterministisches Bookkeeping (bash, kein pm-skills-Zugriff):** Erst NACH abgeschlossenem Skill-Dispatch ruft dieselbe Session `orchestrator.sh dispatch_pm_anstoss <topic-id> <run-id> <artifact-ref>` auf. `<artifact-ref>` ist die Vault-Pfad-Referenz der eben erzeugten Artefakte — die Session kennt sie aus der Beobachtung des Skill-Ergebnisses, sie wird nicht von einem Subprozess zurückgegeben. `orchestrator.sh` berührt pm-skills nie direkt; es übernimmt ausschliesslich: Vorbedingungen prüfen (Empfehlung `weiterverfolgen`, Thema-Status `aktiv`), Idempotenz-Dispatch via `db_scripts/lib/pm_dispatch.sh#dispatch_pm_handoff` (Hash-Vergleich, `ra_pm_dispatch`-Eintrag, BR-017), Status-Transition `aktiv → im_pm`.

**Eingabe/Ausgabe-Schnittstelle des `orchestrator.sh`-Aufrufers (verbindlich):**
- Eingabe: `<topic-id>` (UUID), `<run-id>` (Ganzzahl), `<artifact-ref>` (Vault-Pfad-String, vom Aufrufer geliefert — **nie** von `orchestrator.sh` selbst ermittelt).
- Vorbedingung Thema-Status: `aktiv` (Erst-Anstoss, Status wird auf `im_pm` gesetzt) **oder** `im_pm` (Thema bereits im PM-Prozess — wiederholter/divergierender Dispatch, Status bleibt unverändert `im_pm`, da `im_pm → im_pm` keine Transition, sondern ein No-op ist). Jeder andere Ausgangsstatus (`geparkt`, `verworfen`) wird abgelehnt.
- Ausgabe: `rc=0` neuer Dispatch + Status gesetzt (`aktiv → im_pm`) bzw. Status bleibt `im_pm` (falls Ausgangsstatus bereits `im_pm` war); `rc=2` idempotenter Wiederholdispatch (kein neues Artefakt, Divergenz-Ausweis separat AC3/AC4) — bei ausstehendem Statuswechsel (Abbruch zwischen Dispatch-Bookkeeping und Statuswechsel) wird `aktiv → im_pm` nachgeholt (AC5); `rc=1` Fehler (Vorbedingung, DB-Fehler) — **kein** Statuswechsel. Diese `rc=1`-Garantie gilt nur für Fehlerpfade **vor** dem Dispatch-Bookkeeping-Commit + Statuswechsel; scheitert die nachgelagerte Divergenz-Materialisierung (AC4 — z. B. ein raum-/zeitgleicher zweiter Anstoss auf dasselbe Vorlauf/Folgelauf-Paar), sind Dispatch und Statuswechsel bereits real erfolgt — dieser Fehlschlag wird als Warnung protokolliert, nicht als `rc=1`, und der Divergenz-Ausweis entfällt für diesen Aufruf ersatzlos.
- `orchestrator.sh` hat **kein** `RA_PM_SKILLS_CMD`/pm-skills-Kommando-Resolving und keinen Vault-Pfad-Zugriff — beides entfällt, weil pm-skills nicht subprocess-aufrufbar ist.

**Späterer Headless-Betrieb (nicht Scope von S-017):** Wird PM-Anstoss irgendwann ohne interaktive Chat-Session ausgelöst (architecture.md „Headless-Automatisierung später"), ersetzt ein `claude -p "/pm-skills:<workflow> …"`-Dispatch (analog `board-feature-drain.sh#generate_dossier` in agent-flow) den Skill-Tool-Aufruf aus Schritt 1 — Schritt 2 (Bookkeeping-Vertrag) bleibt unverändert, da `<artifact-ref>` weiterhin vom Aufrufer (jetzt: dem headless-Wrapper, der die `claude -p`-Ausgabe parst) geliefert wird.

## Edge-Cases & Fehlerverhalten
- **E1** Vault nicht erreichbar (Mac-Pfad, iCloud-Sync) → klarer Abbruch vor jedem Schreiben, kein Teil-Artefakt.
- **E2** pm-skills-Plugin in der aktiven Session nicht verfügbar (Skill/Sub-Agent nicht auffindbar bzw. Plugin nicht installiert) → Skill-Dispatch (Schritt 1) schlägt fehl/wird von Claude erkannt; PM-Handoff bricht **vor** jedem `orchestrator.sh dispatch_pm_anstoss`-Aufruf ab (kein Halb-Artefakt, kein DB-Schreibversuch ohne `artifact-ref`); das Thema bleibt unverändert `aktiv`.

## NFRs
- Jeder Anstoss protokolliert Thema, Lauf-Version, Hash und Entscheid — nachvollziehbar ohne Log-Archäologie.

## Nicht-Ziele
- Kein automatischer Anstoss (C-004). Keine Änderungen an pm-skills selbst (Idempotenz lebt in der Orchestrierung). Kein direktes agent-flow-Board-Schreiben.

## Abhängigkeiten
- Specs `research-datenmodell`, `research-skill` (depends). pm-skills installiert; agent-flow pm-import (existiert, agent-flow S-095–S-097); Obsidian-Vault erreichbar (Mac, Entscheid a-4).
