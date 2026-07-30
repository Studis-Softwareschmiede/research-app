---
owner_approved: '2026-07-30T07:38:06Z'
---

# Design-System — research-app (Anzeige-Ebene, M5)

> **Freigegeben** (`owner_approved: 2026-07-30T07:38:06Z`) — bindend für den `coder`. Grundlage: [`docs/specs/anzeige-portfolio.md`](specs/anzeige-portfolio.md) (AC1–AC5), [`docs/architecture.md`](architecture.md) (Schicht 3, ADR-007), [`docs/data-model.md`](data-model.md).
>
> Alle fünf offenen Gestaltungsfragen (s. „Offene Punkte") wurden vom Owner mit dem jeweiligen **Standard-Vorschlag** entschieden (keine der Alternativen).

## Kontext

Ein **eigenständiges, lokales HTML/JS-Dashboard** (ADR-007, kein Framework, kein Build-Step nötig — statisches HTML5 + CSS + Vanilla-JS, `html.md`/`css.md`-Packs). Single-User, kein Deployment, keine Auth (C-004). Reines Lesemodell (AC4) — einzige Schreib-Interaktion ist die Gate-Aktion (AC3). Drei Ansichten: **Portfolio** (AC1), **Verlauf & Divergenz** (AC2), **Gate** (AC3, inline im Portfolio/Thema-Detail, kein eigener Screen).

**Leitprinzip:** ein Analyse-Werkzeug für eine einzelne Person, kein Marketing-/Consumer-Produkt — Dichte und Klarheit vor Dekoration. Offline-first (`html/R03`): keine externen Fonts/CDNs, System-Font-Stack.

## Farb-Tokens

Alltagssprachlich: **Blau als ruhige Grundfarbe**, Statuswerte über **Text + Farbe + Form** (nie Farbe allein — WCAG 1.4.1), damit Rot/Grün-Sehschwäche die Bedienbarkeit nicht einschränkt. Alle Kontrastwerte unten sind **berechnet** (WCAG-Relativluminanz-Formel), nicht geschätzt.

```css
:root {
  /* Neutrals */
  --color-bg:          #FFFFFF;
  --color-surface:     #F5F7FA;  /* Kartenflächen, Tabellen-Streifen */
  --color-border:      #D8DEE6;  /* rein dekorativ, kein Text-Kontrast nötig */
  --color-text:        #1B2430;  /* Fließtext */               /* 15.65:1 auf --color-bg */
  --color-text-muted:  #4B5563;  /* Metadaten, Zeitstempel */    /* 7.56:1 auf --color-bg */

  /* Primär / Aktionen */
  --color-primary:      #1D4ED8;
  --color-primary-text: #FFFFFF; /* 6.70:1 auf --color-primary */

  /* Thema-Status (AC1) — Text/Border in Kontrastfarbe, helle Tint-Fläche */
  --color-status-aktiv-bg:      #DBEAFE;  --color-status-aktiv-fg:      #1D4ED8; /* 5.49:1 */
  --color-status-geparkt-bg:    #FEF3C7;  --color-status-geparkt-fg:    #92400E; /* 6.37:1 */
  --color-status-im-pm-bg:      #EDE9FE;  --color-status-im-pm-fg:      #6D28D9; /* 5.98:1 */
  --color-status-verworfen-bg:  #E5E7EB;  --color-status-verworfen-fg:  #374151; /* 8.33:1 */

  /* Empfehlung (AC1/AC2) */
  --color-rec-weiterverfolgen-bg: #DCFCE7; --color-rec-weiterverfolgen-fg: #166534; /* 6.49:1 */
  --color-rec-parken-bg:          #FEF3C7; --color-rec-parken-fg:          #92400E; /* 6.37:1 */
  --color-rec-verwerfen-bg:       #FEE2E2; --color-rec-verwerfen-fg:       #991B1B; /* 6.80:1 */

  /* Momentum-Kennzeichen (BR-104/momentum_only) — eigene Farbe, NIE als einziges Signal (immer + Icon + Text „Momentum-Signal") */
  --color-momentum-bg: #E0E7FF; --color-momentum-fg: #3730A3; /* 8.06:1 */

  /* Divergenz-Delta (AC2) */
  --color-delta-added:   #166534;  /* SWOT-Claim hinzugekommen, mit „+"-Präfix, nicht nur Farbe */
  --color-delta-removed: #991B1B;  /* SWOT-Claim entfallen, mit „−"-Präfix */

  /* Zustand / Feedback */
  --color-danger:      #B91C1C;  --color-danger-text: #FFFFFF; /* 6.47:1 */
  --color-focus-ring:  #1D4ED8;  /* ≥3:1 non-text UI-Kontrast, s. Accessibility */
}
```

**Dark Mode:** bewusst **nicht** Teil dieses Entwurfs (KISS-Priorität M5, s. „Offene Punkte" #4). Tokens sind so benannt, dass ein späteres `light-dark()`-Overlay (`css/R05`) ohne Umbenennung nachgerüstet werden kann.

## Spacing-Skala

4px-Grundraster, als Custom Properties (`css/R01` — keine Magic-Werte im coder-Code):

```css
:root {
  --space-1: 4px;   --space-2: 8px;   --space-3: 12px;  --space-4: 16px;
  --space-5: 24px;  --space-6: 32px;  --space-7: 48px;  --space-8: 64px;
}
```

Tabellen-/Listen-Zeilen: `--space-3` vertikal, `--space-4` horizontal (kompakte Dichte, viele Themen gleichzeitig sichtbar — s. „Offene Punkte" #2). Abschnittsabstände (zwischen Portfolio-Header und Tabelle etc.): `--space-6`. Seitenränder: `--space-5` (mobil) / `--space-7` (Desktop, ab Breakpoint).

## Typografie

System-Font-Stack (kein externes Laden, `html/R03`):

```css
:root {
  --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  --font-mono: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; /* Hashes, IDs, Zeitstempel */
}
```

| Rolle | Grösse | Line-height | Gewicht |
|---|---|---|---|
| H1 (Seitentitel) | 24px | 1.25 | 600 |
| H2 (Abschnitt, z. B. Thema-Name) | 20px | 1.3 | 600 |
| Body | 16px | 1.5 | 400 |
| Small (Metadaten, Zeitstempel) | 14px | 1.4 | 400 |
| Badge-Text | 12px | 1.2 | 600 |

`text-wrap: balance` (`css/R11`) für H1/H2 — kurze Mehrzeiler, Baseline abgedeckt.

## Layout / Responsive

- **Ein-Spalten-Menüband oben** statt Seitenleiste (nur zwei Hauptansichten: Portfolio, Thema-Detail mit Verlauf/Divergenz/Gate — Sidebar wäre für diesen Umfang Overhead, s. „Offene Punkte" #3).
- Mobile-first (`css/R02`), Breakpoint `--bp-desktop: 768px` für breitere Tabellen-Layouts (Meilenstein-Spalte erst ab Desktop sichtbar, mobil als Detail-Expand).
- Portfolio-Tabelle nutzt `@container` (`css/R04`) statt globaler Media Queries für die Zeilen-Darstellung (Karte auf schmalem Container, Tabellen-Zeile auf breitem) — Elternelement braucht `container-type: inline-size`.

## Grundkomponenten

### 1. App-Shell
Header (Produktname „research-app" + aktive Ansicht) als `<header>`, `<nav>` mit den zwei Ansichten, `<main>` für den Inhalt (`html/R01`, Landmarks).

### 2. Status-Badge (AC1)
Pille (`border-radius: 999px`, Padding `--space-1 --space-3`), Text = Statuswort (`aktiv`/`geparkt`/`im PM`/`verworfen`) + Farbpaar aus den Status-Tokens. Farbe **und** Text immer zusammen (1.4.1).

### 3. Empfehlungs-Badge + Momentum-Kennzeichen (AC1, BR-104)
Wie Status-Badge, mit Empfehlungs-Tokens. Ist `momentum_only=1`, zusätzliches, separates Badge „Momentum-Signal" (eigenes Icon ⚡ + `--color-momentum-*`) direkt daneben — nie die Empfehlungsfarbe selbst ändern, um Verwechslung mit „geringerer Konfidenz als Statusfarbe" zu vermeiden.

### 4. Portfolio-Tabelle (AC1)
Zeile je Thema: Name, Status-Badge, Empfehlungs-Badge (+Momentum), Anzahl offener Meilensteine (Zahl + `<details>`-Expand für die Liste, `html/R07`), letzte Aktualisierung (`--font-mono`, `--color-text-muted`). Zeilen fokussierbar/klickbar → Thema-Detail (Verlauf/Divergenz/Gate).

### 5. Verlaufs-Zeitleiste + Divergenz-Ansicht (AC2)
Vertikale Liste der Läufe (neuester oben) mit Datum, Empfehlung, Momentum-Kennzeichen je Lauf. Auswahl zweier Läufe (zwei `<select>` oder Checkbox-Paar, Default: neuester vs. Vorgänger) → Divergenz-Panel darunter:
- **Empfehlungs-Wechsel:** hervorgehoben als „X → Y" mit beiden Empfehlungs-Badges, wenn `recommendation_changed=1`.
- **SWOT-Delta:** je Kategorie gruppiert, hinzugekommene Claims mit `+`-Präfix (`--color-delta-added`), entfallene mit `−`-Präfix (`--color-delta-removed`) — Präfix-Zeichen **und** Farbe (1.4.1).
- **Meilenstein-Delta:** Liste geänderter `(Meilenstein, Status)`-Paare, Status als kleines Status-Badge-Äquivalent.

Keine eigene Divergenz-Berechnung (`ra_divergence` wird nur gelesen, s. AC4/Verträge).

### 6. Gate-Aktion (AC3, ADR-011)
„PM anstossen" ist **kein** Button, der selbst etwas auslöst — pm-skills ist kein CLI-Tool (ADR-009), die Anzeige kann den Handoff nicht selbst starten. Stattdessen: ein Textblock mit dem fertig formulierten **Chat-Auftragstext** (Themen-Titel, Themen-/Lauf-ID) in einem `<pre>`/`<code>`-Element plus einem „Kopieren"-Button (Zwischenablage-API, Fallback `execCommand('copy')` für `file://`-Kompatibilität falls nötig) — der Nutzer fügt den Text in eine Claude-Code-Chat-Session ein. Direkt daneben ein kurzer Hinweistext („Text kopieren und in einer Claude-Code-Session einfügen"). Kein Bestätigungs-Dialog nötig (Kopieren ist folgenlos, keine echte Aktion wird ausgelöst). Ist das Thema gerade gesperrt (E2, `ra_topic_lock`), wird der Chat-Auftragstext samt Kopieren-Button durch den Hinweistext „Lauf läuft" ersetzt — kein disabled Button, kein Restanzeige des Auftragstexts. „Warten" ist der Nicht-Klick — kein eigener Button nötig.

### 7. Leerer Zustand (E1)
Zentrierter Block in `<main>`: kurzer Text „Noch keine Recherche-Läufe vorhanden" + Handlungsanweisung als Text (welcher Befehl/Skill den ersten Lauf startet — reine Anzeige, kein Auslöse-Button, da AC4 keinen Schreibpfad ausser Gate erlaubt). Kein Fehler-Icon/-Farbe (kein Fehlerzustand, sondern Ausgangszustand) — neutrale Darstellung.

## Accessibility (WCAG 2.1 AA, ergänzt um relevante WCAG 2.2-Kriterien aus `html.md`)

- **Kontrast:** alle Text/Hintergrund-Paare oben ≥ 4.5:1 (berechnet, s. Tabelle in „Farb-Tokens"); finale Verifikation der tatsächlichen coder-Umsetzung bleibt Reviewer-Pflicht (`css.md`-Checklist).
- **Fokus sichtbar:** `:focus-visible { outline: 2px solid var(--color-focus-ring); outline-offset: 2px; }` auf allen interaktiven Elementen (Zeilen, Buttons, `<select>`, `<details>`-Summary).
- **Tastatur-Navigation:** komplette Bedienung ohne Maus — Tabellen-Zeilen als `<button>`/`tabindex`-fähige Elemente, Divergenz-Auswahl über native `<select>`, Kopieren-Button per Tastatur fokussierbar/auslösbar (kein Dialog, s. `:focus-visible` oben).
- **Touch-Targets:** ≥ 44×44px für den Kopieren-Button und Zeilen-Klickfläche (übertrifft WCAG 2.2 AA 2.5.8-Minimum von 24px bewusst, da Analyse-Werkzeug auch am Trackpad/Touch bedienbar bleiben soll).
- **2.4.11 Focus Not Obscured:** kein Sticky-Header, der fokussierte Elemente überdeckt.
- **2.5.7 Dragging Movements:** keine Drag-Interaktionen im Scope (AC1–AC3 sind alle klick-/tastaturbasiert) — Kriterium trivial erfüllt.
- **3.3.8 Accessible Authentication:** kein Login (C-004, keine Auth) — Kriterium nicht anwendbar.
- **3.2.6 Consistent Help:** entfällt, da keine Hilfe-Funktion im Scope.
- **`prefers-reduced-motion`:** `<details>`-Expand und Dialog-Öffnen ohne Bewegungsanimation, oder mit `@media (prefers-reduced-motion: reduce)` abgeschaltet (`css/R03`), falls der coder eine Transition ergänzt.
- **Farbe nie alleiniges Signal:** durchgängig Text/Icon + Farbe (Status-, Empfehlungs-, Momentum-Badges, Divergenz-Delta) — s. Komponenten oben.

## Entschiedene Gestaltungsfragen (Owner-Freigabe 2026-07-30)

Die folgenden fünf Fragen waren beim headless-Entwurfslauf offen (Owner nicht erreichbar) und wurden bei der Freigabe **alle mit dem Standard-Vorschlag** entschieden (keine Alternative gewählt):

1. **Farbrichtung:** „Blau als Grundfarbe" (ruhig, analytisch) — entschieden.
2. **Dichte/Weissraum:** „kompakte Tabellen-Dichte" (`--space-3`-Zeilen) — entschieden.
3. **Platzierung Navigation:** „schlankes Menüband oben" (nur zwei Ansichten) — entschieden.
4. **Dark Mode:** „nur Light Mode für M5" (KISS, Scope-Minimum) — entschieden, kein Dark Mode in dieser Story.
5. **Stilrichtung:** „sachlich-neutrales Analyse-Dashboard" (Datentabellen-fokussiert, wenig Dekoration) — entschieden.
