/* research-app — Anzeige-Ebene, Lesemodell-Grundgerüst + Portfolio-Ansicht
   (S-021 AC4/AC5, S-022 AC1) + Verlauf & Divergenz-Ansicht (S-023 AC2).
   Klassisches Script (kein type="module", UI-C2) — läuft unter file://.
   Öffnet die vom Nutzer gewählte SQLite-Datei als In-Memory-Lesekopie
   (window.initSqlJs aus app/vendor/sql-asm.js) und führt ausschliesslich
   SELECT-Abfragen aus (UI-C4). Kein ATTACH der last30days-DB (UI-C5). Liest
   die Divergenz aus ra_divergence, berechnet sie nie selbst (Verträge). */

(function () {
  "use strict";

  var fileInput = document.getElementById("db-file");
  var reloadButton = document.getElementById("reload-button");
  var navPortfolioButton = document.getElementById("nav-portfolio");
  var activeViewLabel = document.getElementById("active-view-label");
  var errorRegion = document.getElementById("error-region");
  var stateRegion = document.getElementById("state-region");

  var sqlModulePromise = null;
  var currentDb = null;
  var currentLoadedAt = null;
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

  // Meilenstein-Status (ra_milestone.status) hat in design.md keine eigenen
  // Farb-Tokens — Wiederverwendung der bestehenden Status-/Empfehlungs-Paletten
  // (Simplicity-Leiter Stufe 2) statt neuer Tokens für AC2.
  var MILESTONE_BADGE_CLASS = {
    offen: "badge-status-geparkt",
    erfuellt: "badge-rec-weiterverfolgen",
    hinfaellig: "badge-status-verworfen",
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

  function setActiveViewLabel(text) {
    activeViewLabel.textContent = text ? "— " + text : "";
  }

  function mutedNote(text) {
    var p = document.createElement("p");
    p.className = "text-muted";
    p.textContent = text;
    return p;
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
    navPortfolioButton.hidden = true;
    setActiveViewLabel("");
    renderPanel("Noch keine Datenbank ausgewählt", [
      "Wähle deine research-app.sqlite über die Datei-Auswahl oben, um das Lesemodell zu laden.",
    ]);
  }

  function renderEmpty(loadedAt) {
    reloadButton.hidden = false;
    navPortfolioButton.hidden = false;
    setActiveViewLabel("Portfolio");
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
    navPortfolioButton.hidden = false;
    setActiveViewLabel("Portfolio");
    var stamp = document.createElement("p");
    stamp.className = "timestamp";
    stamp.textContent = "Stand: " + loadedAt.toLocaleString();
    renderPanel("Portfolio", [], [stamp, renderPortfolioTable(topics)]);
  }

  // showPortfolio (AC2 Navigation) — Rücksprung aus dem Thema-Detail bzw.
  // Header-Nav; fragt das Portfolio frisch ab statt einen alten Snapshot zu
  // behalten (derselbe In-Memory-Snapshot, kein neuer DB-Zugriff).
  function showPortfolio(db, loadedAt) {
    if (!db) {
      return;
    }
    var topics = fetchPortfolio(db);
    if (topics.length === 0) {
      renderEmpty(loadedAt);
    } else {
      renderLoaded(loadedAt, topics);
    }
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

  // isInteractiveDescendant (AC2) — die Meilenstein-Expand (<details>, AC1)
  // lebt in derselben Zeile wie die neue Klick-/Enter-Navigation zum
  // Thema-Detail; ein Klick/Enter INNERHALB von <details> darf nicht
  // zusätzlich zur Zeilen-Navigation führen (sonst schliesst/öffnet der
  // Expand nie ohne ungewollten Sprung ins Thema-Detail).
  function isInteractiveDescendant(target) {
    return !!(target && target.closest && target.closest("details"));
  }

  function renderTopicRow(topic) {
    var tr = document.createElement("tr");
    // design.md #Grundkomponenten 4 (bindend): Zeilen fokussierbar/klickbar ->
    // Thema-Detail. Mit AC2 (S-023) ist die Klick-/Enter-Navigation zum
    // Thema-Detail (Verlauf/Divergenz) jetzt verdrahtet.
    tr.tabIndex = 0;
    tr.addEventListener("click", function (event) {
      if (isInteractiveDescendant(event.target)) {
        return;
      }
      showTopicDetail(currentDb, topic.id, currentLoadedAt);
    });
    tr.addEventListener("keydown", function (event) {
      if (event.key !== "Enter" || isInteractiveDescendant(event.target)) {
        return;
      }
      event.preventDefault();
      showTopicDetail(currentDb, topic.id, currentLoadedAt);
    });

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

  function queryFirst(db, sql, params) {
    var result = params ? db.exec(sql, params) : db.exec(sql);
    if (result.length === 0) {
      return null;
    }
    return result[0].values[0][0];
  }

  function queryRows(db, sql, params) {
    var result = params ? db.exec(sql, params) : db.exec(sql);
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

  function fetchTopic(db, topicId) {
    var rows = queryRows(db, "SELECT id, title, status FROM ra_topic WHERE id = ?", [topicId]);
    return rows[0] || null;
  }

  function fetchRuns(db, topicId) {
    return queryRows(
      db,
      "SELECT id, kind, version, recommendation, momentum_only, created_at " +
        "FROM ra_run WHERE topic_id = ? ORDER BY id DESC",
      [topicId]
    );
  }

  function fetchDivergence(db, topicId, fromRunId, toRunId) {
    var rows = queryRows(
      db,
      "SELECT is_empty, recommendation_changed, swot_delta, milestone_status_delta " +
        "FROM ra_divergence WHERE topic_id = ? AND from_run_id = ? AND to_run_id = ?",
      [topicId, fromRunId, toRunId]
    );
    return rows[0] || null;
  }

  function findRunById(runs, id) {
    for (var i = 0; i < runs.length; i++) {
      if (runs[i].id === id) {
        return runs[i];
      }
    }
    return null;
  }

  function runLabel(run) {
    return "V" + run.version + " · " + (run.kind === "pm" ? "PM" : "Recherche") + " · " + formatTimestamp(run.created_at);
  }

  // renderRunTimeline (AC2, design.md #Grundkomponenten 5) — vertikale Liste
  // der Läufe, neuester oben (runs kommt bereits ORDER BY id DESC aus
  // fetchRuns), mit Datum, Empfehlung, Momentum-Kennzeichen je Lauf.
  function renderRunTimeline(runs) {
    if (runs.length === 0) {
      return mutedNote("Noch keine Läufe für dieses Thema.");
    }
    var ul = document.createElement("ul");
    ul.className = "run-timeline";
    runs.forEach(function (run) {
      var li = document.createElement("li");
      li.className = "run-timeline-item";

      var meta = document.createElement("span");
      meta.className = "timestamp";
      meta.textContent = runLabel(run);
      li.appendChild(meta);

      li.appendChild(createBadge(run.recommendation, REC_BADGE_CLASS[run.recommendation] || "badge-rec-parken"));
      if (run.momentum_only === 1) {
        li.appendChild(createBadge("⚡ Momentum-Signal", "badge-momentum"));
      }
      ul.appendChild(li);
    });
    return ul;
  }

  // renderSwotDelta (AC2, BR-106/OF-05) — Einzel-Item-Delta (category,
  // claim_key) je hinzugekommenem/entfallenem Claim PLUS Kategorie-Rollup, wie
  // von db_scripts/lib/divergence.sh#compute_swot_delta materialisiert. Reines
  // Lesen des gespeicherten JSON, keine eigene Divergenz-Berechnung.
  function renderSwotDelta(delta) {
    var section = document.createElement("div");
    section.className = "swot-delta";

    var heading = document.createElement("h4");
    heading.textContent = "SWOT-Delta";
    section.appendChild(heading);

    if (!delta || (delta.added.length === 0 && delta.removed.length === 0)) {
      section.appendChild(mutedNote("Keine SWOT-Änderungen."));
      return section;
    }

    var ul = document.createElement("ul");
    ul.className = "delta-list";
    delta.added.forEach(function (pair) {
      var li = document.createElement("li");
      li.className = "delta-item delta-added";
      li.textContent = "+ " + pair[0] + ": " + pair[1];
      ul.appendChild(li);
    });
    delta.removed.forEach(function (pair) {
      var li = document.createElement("li");
      li.className = "delta-item delta-removed";
      li.textContent = "− " + pair[0] + ": " + pair[1];
      ul.appendChild(li);
    });
    section.appendChild(ul);

    var byCategory = delta.by_category || {};
    var categories = Object.keys(byCategory).sort();
    if (categories.length > 0) {
      var rollupUl = document.createElement("ul");
      rollupUl.className = "delta-rollup";
      categories.forEach(function (category) {
        var counts = byCategory[category];
        var li = document.createElement("li");
        li.textContent = category + ": +" + counts.added + " / −" + counts.removed;
        rollupUl.appendChild(li);
      });
      section.appendChild(rollupUl);
    }

    return section;
  }

  // renderMilestoneDelta (AC2) — geänderte (Meilenstein, Status)-Paare, wie von
  // db_scripts/lib/divergence.sh#compute_milestone_delta materialisiert
  // (from_status/to_status können fehlen: neu hinzugekommener bzw. entfallener
  // Meilenstein).
  function renderMilestoneDelta(delta) {
    var section = document.createElement("div");
    section.className = "milestone-delta";

    var heading = document.createElement("h4");
    heading.textContent = "Meilenstein-Delta";
    section.appendChild(heading);

    if (!delta || delta.changed.length === 0) {
      section.appendChild(mutedNote("Keine Meilenstein-Änderungen."));
      return section;
    }

    var ul = document.createElement("ul");
    ul.className = "delta-list";
    delta.changed.forEach(function (entry) {
      var li = document.createElement("li");
      var keySpan = document.createElement("span");
      keySpan.textContent = entry.milestone_stable_key + ": ";
      li.appendChild(keySpan);

      if (entry.from_status !== null && entry.from_status !== undefined) {
        li.appendChild(createBadge(entry.from_status, MILESTONE_BADGE_CLASS[entry.from_status] || "badge-status-geparkt"));
        var arrow = document.createElement("span");
        arrow.textContent = " → ";
        li.appendChild(arrow);
      }
      if (entry.to_status !== null && entry.to_status !== undefined) {
        li.appendChild(createBadge(entry.to_status, MILESTONE_BADGE_CLASS[entry.to_status] || "badge-status-geparkt"));
      } else {
        var removedSpan = document.createElement("span");
        removedSpan.textContent = "entfernt";
        li.appendChild(removedSpan);
      }
      ul.appendChild(li);
    });
    section.appendChild(ul);

    return section;
  }

  // renderDivergencePanel (AC2, Verträge "Divergenz wird gelesen, nicht neu
  // berechnet") — liest genau die für dieses Laufpaar materialisierte
  // ra_divergence-Zeile. Existiert keine (Läufe sind nicht unmittelbar
  // aufeinanderfolgend — ra_divergence wird laut OF-07 nur je Folgelauf
  // materialisiert), zeigt sie das transparent an statt selbst zu rechnen.
  function renderDivergencePanel(divergence, fromRun, toRun) {
    var container = document.createElement("div");
    container.className = "divergence-panel";

    if (!divergence) {
      container.appendChild(
        mutedNote(
          "Keine Divergenz-Daten für diese Kombination — Divergenz wird nur zwischen unmittelbar aufeinanderfolgenden Läufen materialisiert (ra_divergence)."
        )
      );
      return container;
    }

    if (divergence.is_empty === 1) {
      container.appendChild(mutedNote("Kein Unterschied — identischer Ergebnisstand."));
      return container;
    }

    if (divergence.recommendation_changed === 1 && fromRun && toRun) {
      var recRow = document.createElement("p");
      recRow.className = "divergence-recommendation-change";
      recRow.appendChild(createBadge(fromRun.recommendation, REC_BADGE_CLASS[fromRun.recommendation] || "badge-rec-parken"));
      var arrow = document.createElement("span");
      arrow.textContent = " → ";
      recRow.appendChild(arrow);
      recRow.appendChild(createBadge(toRun.recommendation, REC_BADGE_CLASS[toRun.recommendation] || "badge-rec-parken"));
      container.appendChild(recRow);
    }

    var swotDelta = divergence.swot_delta ? JSON.parse(divergence.swot_delta) : null;
    container.appendChild(renderSwotDelta(swotDelta));

    var milestoneDelta = divergence.milestone_status_delta ? JSON.parse(divergence.milestone_status_delta) : null;
    container.appendChild(renderMilestoneDelta(milestoneDelta));

    return container;
  }

  // defaultDivergencePair (AC2) — Default "neuester Lauf vs. Vorgänger" MUSS
  // zwei Läufe DERSELBEN Art vergleichen (BR-011: ra_divergence wird nur
  // zwischen zwei Läufen derselben Art materialisiert). Ein Thema, das
  // mindestens einmal ans PM weitergegeben wurde, hat als neuesten Lauf
  // typischerweise kind='pm' (BR-008) — die zwei zeitlich letzten Läufe
  // überhaupt wären dann artverschieden und träfen nie eine materialisierte
  // Zeile, obwohl zwischen den beiden letzten echten kind='recherche'-Läufen
  // längst eine vorliegt. Default vergleicht deshalb die zwei neuesten
  // kind='recherche'-Läufe; existieren davon keine zwei, bleibt der Fallback
  // "zeitlich letzte zwei Läufe überhaupt" (deckt sich dann ohnehin mit dem
  // bisherigen E-Case "keine Divergenz-Daten"). runs kommt bereits
  // ORDER BY id DESC aus fetchRuns.
  function defaultDivergencePair(runs) {
    var rechercheRuns = runs.filter(function (run) {
      return run.kind === "recherche";
    });
    if (rechercheRuns.length >= 2) {
      return { toId: rechercheRuns[0].id, fromId: rechercheRuns[1].id };
    }
    return { toId: runs[0].id, fromId: runs[1].id };
  }

  // renderDivergenceSection (AC2, design.md #Grundkomponenten 5) — Auswahl
  // zweier Läufe (zwei <select>, Default: neuester vs. Vorgänger, je
  // defaultDivergencePair). Die chronologische Reihenfolge (from = älter,
  // to = neuer) wird unabhängig davon bestimmt, welches Select welchen Lauf
  // trägt (ra_run.id steigt monoton mit der Anlage).
  function renderDivergenceSection(db, topicId, runs) {
    var wrap = document.createElement("div");
    wrap.className = "divergence-section";

    if (runs.length < 2) {
      wrap.appendChild(mutedNote("Für eine Divergenz-Ansicht werden mindestens zwei Läufe benötigt."));
      return wrap;
    }

    var selectors = document.createElement("div");
    selectors.className = "divergence-selectors";

    var fromLabel = document.createElement("label");
    fromLabel.appendChild(document.createTextNode("Vorlauf"));
    var fromSelect = document.createElement("select");
    fromSelect.className = "divergence-select";

    var toLabel = document.createElement("label");
    toLabel.appendChild(document.createTextNode("Folgelauf"));
    var toSelect = document.createElement("select");
    toSelect.className = "divergence-select";

    runs.forEach(function (run) {
      [fromSelect, toSelect].forEach(function (select) {
        var option = document.createElement("option");
        option.value = String(run.id);
        option.textContent = runLabel(run);
        select.appendChild(option);
      });
    });

    var defaultPair = defaultDivergencePair(runs);
    toSelect.value = String(defaultPair.toId);
    fromSelect.value = String(defaultPair.fromId);

    fromLabel.appendChild(fromSelect);
    toLabel.appendChild(toSelect);
    selectors.appendChild(fromLabel);
    selectors.appendChild(toLabel);
    wrap.appendChild(selectors);

    var panelRegion = document.createElement("div");
    wrap.appendChild(panelRegion);

    function renderSelectedDivergence() {
      var idA = parseInt(fromSelect.value, 10);
      var idB = parseInt(toSelect.value, 10);
      clearChildren(panelRegion);
      if (idA === idB) {
        panelRegion.appendChild(mutedNote("Bitte zwei unterschiedliche Läufe wählen."));
        return;
      }
      var earlierId = Math.min(idA, idB);
      var laterId = Math.max(idA, idB);
      var divergence = fetchDivergence(db, topicId, earlierId, laterId);
      panelRegion.appendChild(
        renderDivergencePanel(divergence, findRunById(runs, earlierId), findRunById(runs, laterId))
      );
    }

    fromSelect.addEventListener("change", renderSelectedDivergence);
    toSelect.addEventListener("change", renderSelectedDivergence);
    renderSelectedDivergence();

    return wrap;
  }

  // showTopicDetail (AC2) — Thema-Detail-Ansicht: Lauf-Verlauf + Divergenz
  // zwischen zwei wählbaren Läufen. Fragt bei jedem Aufruf frisch ab (kein
  // gecachter Zwischenzustand) — derselbe In-Memory-Snapshot wie das Portfolio.
  function showTopicDetail(db, topicId, loadedAt) {
    if (!db) {
      return;
    }
    var topic = fetchTopic(db, topicId);
    var runs = fetchRuns(db, topicId);

    reloadButton.hidden = false;
    navPortfolioButton.hidden = false;
    setActiveViewLabel(topic ? topic.title : "Thema-Detail");

    clearChildren(stateRegion);
    var panel = document.createElement("div");
    panel.className = "panel";

    var h2 = document.createElement("h2");
    h2.textContent = topic ? topic.title : "Thema";
    panel.appendChild(h2);

    if (topic) {
      panel.appendChild(
        createBadge(STATUS_LABELS[topic.status] || topic.status, STATUS_BADGE_CLASS[topic.status] || "badge-status-verworfen")
      );
    }

    var stamp = document.createElement("p");
    stamp.className = "timestamp";
    stamp.textContent = "Stand: " + loadedAt.toLocaleString();
    panel.appendChild(stamp);

    var historyHeading = document.createElement("h3");
    historyHeading.textContent = "Lauf-Verlauf";
    panel.appendChild(historyHeading);
    panel.appendChild(renderRunTimeline(runs));

    var divergenceHeading = document.createElement("h3");
    divergenceHeading.textContent = "Divergenz";
    panel.appendChild(divergenceHeading);
    panel.appendChild(renderDivergenceSection(db, topicId, runs));

    stateRegion.appendChild(panel);
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
      currentLoadedAt = loadedAt;
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

  navPortfolioButton.addEventListener("click", function () {
    showPortfolio(currentDb, currentLoadedAt);
  });

  renderInitial();
})();
