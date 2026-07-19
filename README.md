# research-app

Research App — Steuer-/Anzeigeebene über der Kette
**last30days → pm-skills → pm-import → agent-flow**. Das PRD liegt im
Obsidian-Vault («300 Projekte/Last30Days und PM/Research App – PRD.md») und
wird per `/from-notes` über dev-gui eingelesen.

**Status: Bootstrap.** Der Stack-Entscheid ist laut PRD bewusst offen
(Datenmodell zuerst; eigenständige App vs. dev-gui-Modul unentschieden).
Das Projekt ist stack-neutral gescaffoldet (`.claude/profile.md`,
`language: md`); der echte Stack kommt später via `architekt`/adopt.

- `docs/` — durable Doku (Konzept, Architektur, Glossar, Specs)
- `board/` — File-Board (Features/Stories, Schema V1)
- `.claude/` — Fabrik-Prozess-State (Profil, Lessons, Memory)

## Secrets

Secrets-Modell nach `docs/architecture/secrets-subsystem.md` (agent-flow):
Klartext-`.env` ist git-ignoriert, versioniert wird nur `.env.gpg`
(symmetrisch verschlüsselt) + `.env.example` (Platzhalter-Vorlage).

Workflow: `bash scripts/decrypt-env.sh` (lokal entschlüsseln) → `.env`
editieren → `bash scripts/encrypt-env.sh` → `.env.gpg` + `.env.example`
committen. Das initiale `.env.gpg` fehlt noch (Passphrase noch nicht
provisioniert) — siehe Board-Item.
