---
language: md
domains: []
build: "true"
test: "true"
lint: "true"
db_dialect: sqlite
companions: []
frameworks: []
merge_policy: direct
board: file
deploy: none
default_branch: main
cost_mode: balanced
obsidian_source: /Users/alex/Library/Mobile Documents/iCloud~md~obsidian/Documents/AlexSecondBrain/300 Projekte/Last30Days und PM
---

# Projekt-Profil — research-app

Research App — Steuer-/Anzeigeebene über der Kette
last30days → pm-skills → pm-import → agent-flow. Das PRD liegt im Obsidian
(«300 Projekte/Last30Days und PM/Research App – PRD.md») und wird per
`/from-notes` (über dev-gui) eingelesen.

**Stack-Entscheid ist laut PRD BEWUSST OFFEN** (Datenmodell zuerst; App-Form
unentschieden: eigenständige App vs. dev-gui-Modul). Daher stack-neutrales
Profil analog zum agent-flow-Repo selbst:

- `language: md` — kein Sprach-Pack; Arbeit an Konzept/Specs/Datenmodell.
- `build`/`test`/`lint: "true"` — No-Op-Befehle (exit 0), es gibt noch keinen
  Build/Test-Lauf.
- `db_dialect: none`, `companions: []`, `frameworks: []` — der echte Stack
  kommt später via `architekt`/`/adopt`-Re-Run, wenn der Owner entschieden hat.
- `deploy: none` — kein Docker-Rollout, kein Image-Ziel.
- `merge_policy: direct` — direkter Push auf `main` (kein PR-Zwang).
- `board: file` — File-Board unter `board/`.
