# Vendor-Provenienz (UI-C8)

| Datei | Herkunft | Version | Lizenz | SHA-256 |
|---|---|---|---|---|
| `sql-asm.js` | npm-Paket [`sql.js`](https://www.npmjs.com/package/sql.js), Datei `dist/sql-asm.js` | 1.14.1 | MIT (© sql.js authors) | `ddabd44184435b2189fa5f98dacc6b9512723aced2a87581e26ed17a46256c09` |

## Warum diese Variante

`sql.js` liefert mehrere Builds unter `dist/`. Für `file://`-Betrieb (UI-C2 — keine ES-Module, kein `fetch()` auf lokale Dateien) scheiden die `sql-wasm*`-Builds aus: sie laden ihr `.wasm`-Binary per separatem `fetch()`, was der Browser unter `file://` per Origin-Regel blockiert. `sql-asm.js` ist laut Projekt-README "provided for compatibility reasons" genau für diesen Fall: eine einzelne, in sich geschlossene JavaScript-Datei ohne Nachladen eines zweiten Binaries — per klassischem `<script src="…">` einbindbar (kein `type="module"`).

## Update-Prozess (UI-C8: bewusster Commit, kein Paketmanager-Lauf)

1. Neue Version von `sql.js` von `https://registry.npmjs.org/sql.js` beziehen, `dist/sql-asm.js` extrahieren.
2. `shasum -a 256 sql-asm.js` neu berechnen, Tabelle oben aktualisieren (Version + Hash).
3. Manueller Smoke-Test: `app/index.html` per Doppelklick öffnen, Datei-Auswahl + Lesevorgang gegen eine `research-app.sqlite` verifizieren.
4. Commit — kein automatisierter Paketmanager-Lauf, keine `package.json`/Lockfile in `app/`.
