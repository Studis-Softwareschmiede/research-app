#!/usr/bin/env node
// Smoke-Test — Anzeige-Ebene Grundgerüst + Lesemodell (S-021) + Portfolio-Ansicht (S-022).
// Treibt echtes, headless Chrome per Chrome DevTools Protocol (CDP) gegen
// app/index.html unter file:// (UI-C2) und prüft AC1/AC4/AC5 end-to-end.
// Keine npm-Abhängigkeit (nur Node-Builtins: fetch/WebSocket/child_process/
// node:sqlite fehlt hier absichtlich — Fixtures werden über die `sqlite3`-CLI
// erzeugt, dieselbe Abhängigkeit, die db_scripts/ bereits voraussetzt).
// Aufruf: node app/tests/smoke.mjs  (Voraussetzung: Google Chrome installiert)
//
// Erfüllt die Spec-Vertragszeile "Tests taggen @trace anzeige-portfolio#AC<n>"
// (docs/specs/anzeige-portfolio.md "Verträge").
//
// Covers (anzeige-portfolio): AC1 (Portfolio — alle Themen mit Status-Badge
// inkl. `im_pm` -> "im PM"-Mapping, letzter Bewertung [Empfehlungs-Badge +
// Momentum-Kennzeichen bei momentum_only=1, "Noch keine Bewertung" ohne Lauf]
// und offenen Meilensteinen [Zahl + <details>-Expand-Liste, 0 ohne Expand],
// Zeilen fokussierbar [tabindex-fähig, design.md #Grundkomponenten 4 —
// Klick-/Enter-Navigation zum Thema-Detail folgt erst mit AC2/S-023] —
// sortiert nach letzter Aktualisierung absteigend), AC4 (Lesemodell-Boundary —
// direktes Lesen von research-app.sqlite als In-Memory-Lesekopie,
// ausschliesslich SELECT, Schnappschuss-Zustand E1/E3 — E3 mit je eigener
// Fixture pro Teilbedingung: (a) kein gültiges SQLite, (b) gültiges SQLite
// ohne ra_*-Tabellen —, read-only-by-construction per Byte-Vergleich der
// Quelldatei vor/nach dem Lesen), AC5 (Stack — lädt per file:// ohne
// Netzwerk-Request ausserhalb von file://, kein ES-Modul/`type="module"`
// nötig für die Ausführung dieses Tests selbst — der Browser-Code bleibt
// klassisches Script, s. app/assets/app.js). AC2/AC3 sind nicht Teil dieser
// Story (Verlauf/Divergenz bzw. Gate-Aktion, spätere Stories) und daher hier
// nicht getestet.

import { spawn, execFileSync } from "node:child_process";
import { mkdtemp, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));
const APP_DIR = join(__dirname, "..");
const INDEX_URL = "file://" + join(APP_DIR, "index.html");

const CHROME_CANDIDATES = [
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "google-chrome",
  "chromium",
];
const CDP_PORT = 9464;
const CDP_BASE = `http://127.0.0.1:${CDP_PORT}`;

let failures = 0;

function check(trace, label, ok) {
  const status = ok ? "PASS" : "FAIL";
  if (!ok) failures++;
  console.log(`[${status}] @trace anzeige-portfolio#${trace} — ${label}`);
}

function sha256(buf) {
  return createHash("sha256").update(buf).digest("hex");
}

async function waitForCdp(timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`${CDP_BASE}/json/version`);
      if (res.ok) return;
    } catch {
      // Chrome noch nicht bereit — weiter warten.
    }
    await new Promise((r) => setTimeout(r, 150));
  }
  throw new Error("Chrome CDP endpoint nicht erreichbar (Timeout)");
}

function connectWs(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    ws.addEventListener("open", () => resolve(ws));
    ws.addEventListener("error", reject);
  });
}

async function main() {
  const fixtureDir = await mkdtemp(join(tmpdir(), "s021-smoke-"));
  const validDb = join(fixtureDir, "valid.sqlite");
  const emptyDb = join(fixtureDir, "empty.sqlite");
  const invalidDb = join(fixtureDir, "invalid.sqlite");
  const noRaTablesDb = join(fixtureDir, "no-ra-tables.sqlite");
  const portfolioDb = join(fixtureDir, "portfolio.sqlite");

  const RA_SCHEMA =
    "CREATE TABLE ra_topic (id TEXT PRIMARY KEY, title TEXT, status TEXT, updated_at TEXT); " +
    "CREATE TABLE ra_run (id INTEGER PRIMARY KEY, topic_id TEXT, recommendation TEXT, momentum_only INTEGER); " +
    "CREATE TABLE ra_milestone (id INTEGER PRIMARY KEY, topic_id TEXT, description TEXT, status TEXT, created_at TEXT); ";

  execFileSync("sqlite3", [
    validDb,
    RA_SCHEMA +
      "INSERT INTO ra_topic VALUES ('t1','Thema Eins','aktiv','2026-07-20 10:00:00'); " +
      "INSERT INTO ra_run VALUES (1,'t1','weiterverfolgen',0); " +
      "INSERT INTO ra_milestone VALUES (1,'t1','Externe Finanzierung sichern','offen','2026-07-20 10:05:00'); " +
      "INSERT INTO ra_milestone VALUES (2,'t1','Prototyp bauen','offen','2026-07-20 10:06:00'); " +
      "INSERT INTO ra_milestone VALUES (3,'t1','Altes Ziel','erfuellt','2026-07-20 10:07:00');",
  ]);
  execFileSync("sqlite3", [emptyDb, RA_SCHEMA]);
  execFileSync("sqlite3", [
    portfolioDb,
    RA_SCHEMA +
      "INSERT INTO ra_topic VALUES ('a','Momentum-Thema','geparkt','2026-07-21 09:00:00'); " +
      "INSERT INTO ra_topic VALUES ('b','PM-Thema','im_pm','2026-07-22 09:00:00'); " +
      "INSERT INTO ra_topic VALUES ('c','Ohne Bewertung','aktiv','2026-07-19 09:00:00'); " +
      "INSERT INTO ra_topic VALUES ('d','Verworfenes Thema','verworfen','2026-07-18 09:00:00'); " +
      "INSERT INTO ra_run VALUES (1,'a','parken',1); " +
      "INSERT INTO ra_run VALUES (2,'b','weiterverfolgen',0);",
  ]);
  await (await import("node:fs/promises")).writeFile(invalidDb, "keine echte sqlite-datei\n");
  execFileSync("sqlite3", [
    noRaTablesDb,
    "CREATE TABLE unrelated (id TEXT PRIMARY KEY);",
  ]);

  const validBefore = sha256(await readFile(validDb));

  const userDataDir = await mkdtemp(join(tmpdir(), "s021-chrome-profile-"));
  let chrome;
  let lastSpawnError;
  for (const bin of CHROME_CANDIDATES) {
    try {
      chrome = spawn(
        bin,
        [
          "--headless=new",
          "--disable-gpu",
          "--no-sandbox",
          `--remote-debugging-port=${CDP_PORT}`,
          `--user-data-dir=${userDataDir}`,
          "about:blank",
        ],
        { stdio: "ignore" }
      );
      break;
    } catch (err) {
      lastSpawnError = err;
    }
  }
  if (!chrome) {
    throw new Error("Kein Chrome-Binary gefunden: " + lastSpawnError);
  }

  try {
    await waitForCdp(10000);

    const tabRes = await fetch(`${CDP_BASE}/json/new?about:blank`, { method: "PUT" });
    const tab = await tabRes.json();
    const ws = await connectWs(tab.webSocketDebuggerUrl);

    const netLog = [];
    const consoleErrors = [];
    let msgId = 1;
    const pending = new Map();
    ws.addEventListener("message", (event) => {
      const msg = JSON.parse(event.data);
      if (msg.id !== undefined && pending.has(msg.id)) {
        const { resolve, reject } = pending.get(msg.id);
        pending.delete(msg.id);
        if (msg.error) reject(new Error(JSON.stringify(msg.error)));
        else resolve(msg.result);
      }
      if (msg.method === "Network.requestWillBeSent") {
        netLog.push(msg.params.request.url);
      }
      if (msg.method === "Runtime.exceptionThrown") {
        consoleErrors.push(JSON.stringify(msg.params.exceptionDetails));
      }
    });

    function send(method, params = {}) {
      const id = msgId++;
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        ws.send(JSON.stringify({ id, method, params }));
      });
    }

    async function evalExpr(expression) {
      const r = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
      return r.result.value;
    }

    await send("Network.enable");
    await send("Runtime.enable");
    await send("Page.enable");
    await send("DOM.enable");

    await send("Page.navigate", { url: INDEX_URL });
    await new Promise((r) => setTimeout(r, 800));

    const initialHeading = await evalExpr("document.querySelector('#state-region h2').textContent");
    check("AC5", "Grundgerüst lädt per file:// ohne Auswahl in den Leerzustand", initialHeading === "Noch keine Datenbank ausgewählt");

    const localOnly = netLog.every((url) => url.startsWith("file://"));
    check("AC5", "keine Netzwerk-Requests ausserhalb file:// (offline-first, UI-C1)", localOnly && netLog.length > 0);

    const doc = await send("DOM.getDocument");
    const { nodeId } = await send("DOM.querySelector", { nodeId: doc.root.nodeId, selector: "#db-file" });

    async function selectFile(path) {
      await send("DOM.setFileInputFiles", { files: [path], nodeId });
      await new Promise((r) => setTimeout(r, 500));
    }

    await selectFile(validDb);
    const loadedHeading = await evalExpr("document.querySelector('#state-region h2').textContent");
    check("AC4", "gültige research-app.sqlite wird direkt gelesen (In-Memory-Lesekopie)", loadedHeading === "Portfolio");

    const validRow = await evalExpr(
      "(function(){var tr=document.querySelector('.portfolio-table tbody tr');" +
        "var summary=tr.children[3].querySelector('summary');" +
        "return {" +
        "title: tr.children[0].textContent," +
        "status: tr.children[1].textContent," +
        "rec: tr.children[2].textContent," +
        "hasMomentum: !!tr.children[2].querySelector('.badge-momentum')," +
        "milestoneSummary: summary ? summary.textContent : tr.children[3].textContent," +
        "updated: tr.children[4].textContent" +
        "};})()"
    );
    check("AC1", "Portfolio-Zeile zeigt den Thema-Namen", validRow.title === "Thema Eins");
    check("AC1", "Status-Badge zeigt 'aktiv'", validRow.status === "aktiv");
    check(
      "AC1",
      "Empfehlungs-Badge zeigt 'weiterverfolgen' ohne Momentum-Kennzeichen (has_deep_research)",
      validRow.rec === "weiterverfolgen" && validRow.hasMomentum === false
    );
    check(
      "AC1",
      "offene Meilensteine gezählt (2 offen, 1 erfüllt ausgeschlossen)",
      validRow.milestoneSummary === "2 offene Meilensteine"
    );
    check("AC1", "letzte Aktualisierung wird angezeigt (nicht leer)", validRow.updated.length > 0);

    const rowTabIndex = await evalExpr(
      "document.querySelector('.portfolio-table tbody tr').tabIndex"
    );
    check(
      "AC1",
      "Portfolio-Zeile ist fokussierbar (tabindex-fähig, design.md #Grundkomponenten 4)",
      rowTabIndex === 0
    );

    const validMilestoneList = await evalExpr(
      "Array.from(document.querySelectorAll('.portfolio-table tbody tr:first-child li')).map(function(li){return li.textContent;})"
    );
    check(
      "AC1",
      "Meilenstein-Expand listet nur offene Meilensteine (kein 'Altes Ziel')",
      validMilestoneList.length === 2 &&
        validMilestoneList.includes("Externe Finanzierung sichern") &&
        validMilestoneList.includes("Prototyp bauen") &&
        !validMilestoneList.includes("Altes Ziel")
    );

    await selectFile(emptyDb);
    const emptyHeading = await evalExpr("document.querySelector('#state-region h2').textContent");
    check("AC4", "E1 — leere DB zeigt Leere-Zustands-Ansicht mit Handlungsanweisung", emptyHeading === "Noch keine Recherche-Läufe vorhanden");

    await selectFile(invalidDb);
    const afterInvalidHeading = await evalExpr("document.querySelector('#state-region h2').textContent");
    const errorHidden = await evalExpr("document.getElementById('error-region').hidden");
    const errorText = await evalExpr("document.getElementById('error-region').textContent");
    check("AC4", "E3 — kein gültiges SQLite: vorheriger Anzeigezustand bleibt unverändert", afterInvalidHeading === "Noch keine Recherche-Läufe vorhanden");
    check("AC4", "E3 — kein gültiges SQLite: verständliche Fehlermeldung ohne Fehler-Stack", errorHidden === false && errorText.length > 0 && !errorText.includes("at "));

    await selectFile(noRaTablesDb);
    const afterNoRaTablesHeading = await evalExpr("document.querySelector('#state-region h2').textContent");
    const noRaTablesErrorHidden = await evalExpr("document.getElementById('error-region').hidden");
    const noRaTablesErrorText = await evalExpr("document.getElementById('error-region').textContent");
    check("AC4", "E3 — gültiges SQLite ohne ra_*-Tabellen: vorheriger Anzeigezustand bleibt unverändert", afterNoRaTablesHeading === "Noch keine Recherche-Läufe vorhanden");
    check("AC4", "E3 — gültiges SQLite ohne ra_*-Tabellen: verständliche Fehlermeldung ohne Fehler-Stack", noRaTablesErrorHidden === false && noRaTablesErrorText.length > 0 && !noRaTablesErrorText.includes("at "));

    await selectFile(portfolioDb);
    const portfolioRows = await evalExpr(
      "Array.from(document.querySelectorAll('.portfolio-table tbody tr')).map(function(tr){" +
        "return {" +
        "title: tr.children[0].textContent," +
        "status: tr.children[1].textContent," +
        "rec: tr.children[2].textContent," +
        "hasMomentum: !!tr.children[2].querySelector('.badge-momentum')," +
        "milestones: tr.children[3].textContent" +
        "};})"
    );
    check(
      "AC1",
      "Portfolio sortiert nach letzter Aktualisierung absteigend",
      portfolioRows.map((r) => r.title).join("|") === "PM-Thema|Momentum-Thema|Ohne Bewertung|Verworfenes Thema"
    );
    check("AC1", "Status im_pm wird als 'im PM' angezeigt", portfolioRows[0].status === "im PM");
    check("AC1", "kein Momentum-Kennzeichen ohne momentum_only=1 (PM-Thema)", portfolioRows[0].hasMomentum === false);
    check(
      "AC1",
      "Momentum-Kennzeichen erscheint bei momentum_only=1",
      portfolioRows[1].hasMomentum === true && portfolioRows[1].rec.startsWith("parken")
    );
    check("AC1", "Thema ohne Lauf zeigt 'Noch keine Bewertung' statt Badge", portfolioRows[2].rec === "Noch keine Bewertung");
    check("AC1", "Status verworfen wird korrekt angezeigt", portfolioRows[3].status === "verworfen");
    check(
      "AC1",
      "0 offene Meilensteine zeigen die Zahl '0' ohne Expand",
      portfolioRows.every((r) => r.milestones === "0")
    );

    check("AC4", "kein unbehandelter Laufzeitfehler während aller Ladevorgänge", consoleErrors.length === 0);

    const validAfter = sha256(await readFile(validDb));
    check("AC4", "Read-only by construction — Quelldatei nach dem Lesen byteidentisch (kein Rückschreiben, UI-C4)", validBefore === validAfter);

    ws.close();
  } finally {
    chrome.kill("SIGKILL");
    await rm(fixtureDir, { recursive: true, force: true });
    await rm(userDataDir, { recursive: true, force: true });
  }
}

main()
  .then(() => {
    if (failures > 0) {
      console.error(`\n${failures} Prüfung(en) fehlgeschlagen.`);
      process.exit(1);
    }
    console.log("\nAlle Prüfungen bestanden.");
  })
  .catch((err) => {
    console.error("Smoke-Test-Fehler:", err);
    process.exit(1);
  });
