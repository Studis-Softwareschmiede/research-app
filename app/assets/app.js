/* research-app — Anzeige-Ebene, Lesemodell-Grundgerüst (S-021, AC4/AC5).
   Klassisches Script (kein type="module", UI-C2) — läuft unter file://.
   Öffnet die vom Nutzer gewählte SQLite-Datei als In-Memory-Lesekopie
   (window.initSqlJs aus app/vendor/sql-asm.js) und führt ausschliesslich
   SELECT-Abfragen aus (UI-C4). Kein ATTACH der last30days-DB (UI-C5). */

(function () {
  "use strict";

  var fileInput = document.getElementById("db-file");
  var reloadButton = document.getElementById("reload-button");
  var errorRegion = document.getElementById("error-region");
  var stateRegion = document.getElementById("state-region");

  var sqlModulePromise = null;
  var currentDb = null;
  var latestRequestId = 0;

  function getSqlModule() {
    if (!sqlModulePromise) {
      sqlModulePromise = window.initSqlJs();
    }
    return sqlModulePromise;
  }

  function clearError() {
    errorRegion.textContent = "";
    errorRegion.hidden = true;
  }

  function showError(message) {
    errorRegion.textContent = message;
    errorRegion.hidden = false;
  }

  function clearChildren(node) {
    while (node.firstChild) {
      node.removeChild(node.firstChild);
    }
  }

  function renderPanel(heading, bodyLines, extraNode) {
    clearChildren(stateRegion);
    var panel = document.createElement("div");
    panel.className = "panel";

    var h2 = document.createElement("h2");
    h2.textContent = heading;
    panel.appendChild(h2);

    bodyLines.forEach(function (line) {
      var p = document.createElement("p");
      p.textContent = line;
      panel.appendChild(p);
    });

    if (extraNode) {
      panel.appendChild(extraNode);
    }

    stateRegion.appendChild(panel);
  }

  function renderInitial() {
    reloadButton.hidden = true;
    renderPanel("Noch keine Datenbank ausgewählt", [
      "Wähle deine research-app.sqlite über die Datei-Auswahl oben, um das Lesemodell zu laden.",
    ]);
  }

  function renderEmpty(loadedAt) {
    reloadButton.hidden = false;
    var stamp = document.createElement("p");
    stamp.className = "timestamp";
    stamp.textContent = "Stand: " + loadedAt.toLocaleString();
    renderPanel(
      "Noch keine Recherche-Läufe vorhanden",
      ["Starte den ersten Lauf mit dem /research-Skill in Claude Code."],
      stamp
    );
  }

  function renderLoaded(loadedAt, topicCount) {
    reloadButton.hidden = false;
    var stamp = document.createElement("p");
    stamp.className = "timestamp";
    stamp.textContent = "Stand: " + loadedAt.toLocaleString();
    renderPanel(
      "Datenbank geladen",
      [
        topicCount +
          (topicCount === 1 ? " Thema" : " Themen") +
          " gefunden. Die Portfolio-Ansicht folgt in einer späteren Story.",
      ],
      stamp
    );
  }

  function queryFirst(db, sql) {
    var result = db.exec(sql);
    if (result.length === 0) {
      return null;
    }
    return result[0].values[0][0];
  }

  function handleFile(file) {
    if (!file) {
      return;
    }
    var requestId = ++latestRequestId;
    clearError();

    var reader = new FileReader();
    reader.onerror = function () {
      if (requestId !== latestRequestId) {
        return;
      }
      showError("Datei konnte nicht gelesen werden — bitte erneut versuchen.");
    };
    reader.onload = function () {
      if (requestId !== latestRequestId) {
        return;
      }
      getSqlModule()
        .then(function (SQL) {
          if (requestId !== latestRequestId) {
            return;
          }
          openDatabase(SQL, reader.result, requestId);
        })
        .catch(function () {
          if (requestId !== latestRequestId) {
            return;
          }
          showError("SQLite-Engine konnte nicht gestartet werden.");
        });
    };
    reader.readAsArrayBuffer(file);
  }

  function openDatabase(SQL, arrayBuffer, requestId) {
    var db;
    try {
      db = new SQL.Database(new Uint8Array(arrayBuffer));
      var tableRow = queryFirst(
        db,
        "SELECT name FROM sqlite_master WHERE type='table' AND name='ra_topic'"
      );
      if (!tableRow) {
        db.close();
        showError(
          "Die ausgewählte Datei ist keine gültige research-app.sqlite (keine ra_topic-Tabelle gefunden)."
        );
        return;
      }

      var topicCount = queryFirst(db, "SELECT COUNT(*) FROM ra_topic");

      if (currentDb) {
        currentDb.close();
      }
      currentDb = db;

      var loadedAt = new Date();
      if (topicCount === 0) {
        renderEmpty(loadedAt);
      } else {
        renderLoaded(loadedAt, topicCount);
      }
    } catch (err) {
      if (db) {
        db.close();
      }
      showError(
        "Die ausgewählte Datei ist kein gültiges SQLite oder enthält keine research-app-Tabellen."
      );
    }
  }

  fileInput.addEventListener("change", function (event) {
    var file = event.target.files && event.target.files[0];
    handleFile(file);
  });

  reloadButton.addEventListener("click", function () {
    fileInput.click();
  });

  renderInitial();
})();
