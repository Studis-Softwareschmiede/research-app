#!/usr/bin/env bash
# Gemeinsame Helfer — NICHT direkt ausführen, nur via source.
#
# GPG-Passphrase-Auflösung (PER-APP-Modell):
#   Jede App hat ihre EIGENE Passphrase. Sie kommt vorrangig aus der Umgebung
#   ($GPG_PASSPHRASE) — genau die injiziert der Deploy-Orchestrator (dev-gui) beim
#   `docker run -e GPG_PASSPHRASE=…`, gelesen aus dem Bitwarden-Item `deploy-gpg-<app>`.
#   Der Laufzeit-Entrypoint nutzt AUSSCHLIESSLICH $GPG_PASSPHRASE; diese lokalen
#   Scripts richten sich daran aus.
#
#   Auflösungs-Reihenfolge (encrypt/decrypt/load-env, identisch):
#     $GPG_PASSPHRASE  >  $GPG_PASS_FILE (explizit, app-eigen)  >  interaktiver Prompt
#
#   BEWUSST ENTFERNT (Breaking Change): die früher automatisch bevorzugten GETEILTEN
#   Dateien /etc/softwareschmiede/gpg.pass und ~/.config/softwareschmiede/gpg.pass.
#   Sie hatten Vorrang vor $GPG_PASSPHRASE und führten dazu, dass eine App
#   versehentlich mit der FALSCHEN (geteilten) Passphrase statt ihrer eigenen
#   ver-/entschlüsselt wurde. Wer wirklich eine Datei nutzen will, setzt $GPG_PASS_FILE
#   explizit auf eine APP-eigene Datei (keine Auto-Erkennung geteilter Org-Dateien mehr).

# Liefert einen explizit gesetzten, lesbaren Passphrase-DATEIPFAD ($GPG_PASS_FILE)
# oder schlägt fehl (return 1). KEINE Auto-Erkennung geteilter Org-Dateien.
# Auflösung:  $GPG_PASS_FILE (explizit, z.B. dev-gui Headless-Injektion)
#           > Bitwarden per-App (via dev-gui-Container, Item env.gpg-passphrase-<app>)
# Bitwarden-Bezug abschaltbar mit GPG_BW_DISABLE=1.
resolve_pass_file() {
  local f="${GPG_PASS_FILE:-}"
  # 1) Explizit vorgegeben — höchste Priorität (Override / Headless-Injektion).
  [[ -n "$f" && -r "$f" ]] && { printf '%s' "$f"; return 0; }
  # 2) Bitwarden als Quelle (per-App, über die dev-gui-Container-Boundary).
  #    Erfolg -> materialisierte 0600-Tempdatei; Fehlschlag -> return 1.
  if [[ -z "${GPG_BW_DISABLE:-}" ]]; then
    local _bwf _pdir
    _pdir="$(dirname "${BASH_SOURCE[0]:-$0}")"
    _bwf="$("$_pdir/provision-gpg-pass.sh" 2>/dev/null || true)"
    [[ -n "$_bwf" && -r "$_bwf" ]] && { printf '%s' "$_bwf"; return 0; }
  fi
  return 1
}
