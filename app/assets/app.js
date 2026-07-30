/* research-app — Anzeige-Ebene, Lesemodell-Grundgerüst + Portfolio-Ansicht
   (S-021 AC4/AC5, S-022 AC1). Klassisches Script (kein type="module", UI-C2)
   — läuft unter file://. Öffnet die vom Nutzer gewählte SQLite-Datei als
   In-Memory-Lesekopie (window.initSqlJs aus app/vendor/sql-asm.js) und führt
   ausschliesslich SELECT-Abfragen aus (UI-C4). Kein ATTACH der
   last30days-DB (UI-C5). */

(function () {
  "use strict";

  var fileInput = document.getElementById("db-file");
  var reloadButton = document.getElementById("reload-button");
  var errorRegion = document.getElementById("error-region");
  var stateRegion = document.getElementById("state-region");

  var sqlModulePromise = null;
  var currentDb = null;
  var latestRequestId = 0;

  var STATUS_LABELS = {
    aktiv: "aktiv",
    geparkt: "geparkt",
    im_pm: "im PM",
    verworfen: "verworfen",
  };

  var STATUS_BADGE_CLASS = {
    aktiv: "badge-status-aktiv",
    geparkt: "badge-status-geparkt",
    im_pm: "badge-status-im-pm",
    verworfen: "badge-status-verworfen",
  };

  var REC_BADGE_CLASS = {
    weiterverfolgen: "badge-rec-weiterverfolgen",
    parken: "badge-rec-parken",
    verwerfen: "badge-rec-verwerfen",
  };

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

  function renderPanel(heading, bodyLines, extraNodes) {
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

    (extraNodes || []).forEach(function (node) {
      panel.appendChild(node);
    });

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
      [stamp]
    );
  }

  function renderLoaded(loadedAt, topics) {
    reloadButton.hidden = false;
    var stamp = document.createElement("p");
    stamp.className = "timestamp";
    stamp.textContent = "Stand: " + loadedAt.toLocaleString();
    renderPanel("Portfolio", [], [stamp, renderPortfolioTable(topics)]);
  }

  function formatTimestamp(sqliteDatetime) {
    if (!sqliteDatetime) {
      return "";
    }
    var date = new Date(sqliteDatetime.replace(" ", "T") + "Z");
    if (isNaN(date.getTime())) {
      return sqliteDatetime;
    }
    return date.toLocaleString();
  }

  function createBadge(text, className) {
    var span = document.createElement("span");
    span.className = "badge " + className;
    span.textContent = text;
    return span;
  }

  function renderPortfolioTable(topics) {
    var wrap = document.createElement("div");
    wrap.className = "portfolio-table-wrap";

    var table = document.createElement("table");
    table.className = "portfolio-table";

    var thead = document.createElement("thead");
    var headRow = document.createElement("tr");
    ["Thema", "Status", "Empfehlung", "Offene Meilensteine", "Letzte Aktualisierung"].forEach(function (
      label
    ) {
      var th = document.createElement("th");
      th.scope = "col";
      th.textContent = label;
      headRow.appendChild(th);
    });
    thead.appendChild(headRow);
    table.appendChild(thead);

    var tbody = document.createElement("tbody");
    topics.forEach(function (topic) {
      tbody.appendChild(renderTopicRow(topic));
    });
    table.appendChild(tbody);

    wrap.appendChild(table);
    return wrap;
  }

  function renderTopicRow(topic) {
    var tr = document.createElement("tr");
    // design.md #Grundkomponenten 4 (bindend): Zeilen fokussierbar/klickbar ->
    // Thema-Detail. Die Zielsicht (Verlauf/Divergenz/Gate) entsteht erst mit
    // AC2 (S-023) — hier wird nur die Fokussierbarkeit vorbereitet
    // (tabindex-fähiges Element, Accessibility-Vorgabe), die eigentliche
    // Klick-/Enter-Navigation wird mit AC2 verdrahtet.
    tr.tabIndex = 0;

    var nameCell = document.createElement("td");
    nameCell.setAttribute("data-label", "Thema");
    nameCell.textContent = topic.title;
    tr.appendChild(nameCell);

    var statusCell = document.createElement("td");
    statusCell.setAttribute("data-label", "Status");
    statusCell.appendChild(
      createBadge(
        STATUS_LABELS[topic.status] || topic.status,
        STATUS_BADGE_CLASS[topic.status] || "badge-status-verworfen"
      )
    );
    tr.appendChild(statusCell);

    var recCell = document.createElement("td");
    recCell.setAttribute("data-label", "Empfehlung");
    if (topic.recommendation) {
      recCell.appendChild(
        createBadge(topic.recommendation, REC_BADGE_CLASS[topic.recommendation] || "badge-rec-parken")
      );
      if (topic.momentum_only === 1) {
        recCell.appendChild(createBadge("⚡ Momentum-Signal", "badge-momentum"));
      }
    } else {
      var noRec = document.createElement("span");
      noRec.className = "text-muted";
      noRec.textContent = "Noch keine Bewertung";
      recCell.appendChild(noRec);
    }
    tr.appendChild(recCell);

    var milestoneCell = document.createElement("td");
    milestoneCell.setAttribute("data-label", "Offene Meilensteine");
    var openMilestones = topic.open_milestones;
    if (openMilestones.length === 0) {
      milestoneCell.textContent = "0";
    } else {
      var details = document.createElement("details");
      var summary = document.createElement("summary");
      summary.textContent =
        openMilestones.length + (openMilestones.length === 1 ? " offener Meilenstein" : " offene Meilensteine");
      details.appendChild(summary);
      var ul = document.createElement("ul");
      openMilestones.forEach(function (description) {
        var li = document.createElement("li");
        li.textContent = description;
        ul.appendChild(li);
      });
      details.appendChild(ul);
      milestoneCell.appendChild(details);
    }
    tr.appendChild(milestoneCell);

    var updatedCell = document.createElement("td");
    updatedCell.setAttribute("data-label", "Letzte Aktualisierung");
    updatedCell.className = "timestamp";
    updatedCell.textContent = formatTimestamp(topic.updated_at);
    tr.appendChild(updatedCell);

    return tr;
  }

  function queryFirst(db, sql) {
    var result = db.exec(sql);
    if (result.length === 0) {
      return null;
    }
    return result[0].values[0][0];
  }

  function queryRows(db, sql) {
    var result = db.exec(sql);
    if (result.length === 0) {
      return [];
    }
    var columns = result[0].columns;
    return result[0].values.map(function (row) {
      var record = {};
      columns.forEach(function (column, index) {
        record[column] = row[index];
      });
      return record;
    });
  }

  function fetchPortfolio(db) {
    var topics = queryRows(
      db,
      "SELECT t.id AS id, t.title AS title, t.status AS status, t.updated_at AS updated_at, " +
        "r.recommendation AS recommendation, r.momentum_only AS momentum_only " +
        "FROM ra_topic t " +
        "LEFT JOIN ra_run r ON r.id = (" +
        "SELECT r2.id FROM ra_run r2 WHERE r2.topic_id = t.id ORDER BY r2.id DESC LIMIT 1" +
        ") " +
        "ORDER BY t.updated_at DESC, t.id"
    );

    var milestoneRows = queryRows(
      db,
      "SELECT topic_id AS topic_id, description AS description " +
        "FROM ra_milestone WHERE status = 'offen' ORDER BY topic_id, created_at"
    );
    var openMilestonesByTopic = {};
    milestoneRows.forEach(function (row) {
      if (!openMilestonesByTopic[row.topic_id]) {
        openMilestonesByTopic[row.topic_id] = [];
      }
      openMilestonesByTopic[row.topic_id].push(row.description);
    });

    topics.forEach(function (topic) {
      topic.open_milestones = openMilestonesByTopic[topic.id] || [];
    });

    return topics;
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

      var topics = fetchPortfolio(db);

      if (currentDb) {
        currentDb.close();
      }
      currentDb = db;

      var loadedAt = new Date();
      if (topics.length === 0) {
        renderEmpty(loadedAt);
      } else {
        renderLoaded(loadedAt, topics);
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
