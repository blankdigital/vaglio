#!/bin/bash
# copy-guard: ignore (GIA è il codice di stato del protocollo, non testo)
# Eseguito sul server via ssh, lanciato da Vaglio.Core.ps1.
# Uso: bash -s -- <file_prefs> <ANTEPRIMA|APPLICA|VERIFICA> <dominio>...
#   ANTEPRIMA: dice NUOVO o GIA per ogni dominio, non scrive.
#   APPLICA:   come ANTEPRIMA, poi scrive le righe nuove (con backup del file).
#   VERIFICA:  dice PRESENTE o MANCANTE per ogni dominio.
set -u
prefs="${1/#\~/$HOME}"; modo="$2"; shift 2

if [ ! -f "$prefs" ]; then
  echo "ERRORE file non trovato: $prefs"
  exit 2
fi

# Regex che trova una riga blacklist_from per il dominio, con o senza *@ davanti.
presente() {
  local esc=${1//./\\.}
  grep -qiE "^blacklist_from[[:space:]]+\*?@?\.?${esc}[[:space:]]*$" "$prefs"
}

if [ "$modo" = "VERIFICA" ]; then
  for d in "$@"; do
    if presente "$d"; then echo "PRESENTE $d"; else echo "MANCANTE $d"; fi
  done
  exit 0
fi

nuove=$(mktemp)
for d in "$@"; do
  if presente "$d"; then
    echo "GIA $d"
  else
    echo "NUOVO $d"
    echo "blacklist_from *@$d" >> "$nuove"
  fi
done

if [ "$modo" = "APPLICA" ] && [ -s "$nuove" ]; then
  cp "$prefs" "$prefs.bak-$(date +%Y%m%d-%H%M%S)"
  # Newline finale: senza, la prima riga aggiunta si attacca all'ultima esistente.
  [ -n "$(tail -c1 "$prefs")" ] && echo >> "$prefs"
  riga=$(grep -n '^blacklist_from' "$prefs" | tail -1 | cut -d: -f1)
  if [ -n "$riga" ]; then
    # limite noto: inserisce dopo l'ultima blacklist_from. Se il file non ne ha, si accoda in fondo.
    sed -i "${riga}r $nuove" "$prefs"
  else
    cat "$nuove" >> "$prefs"
  fi
  echo "SCRITTO $(wc -l < "$nuove")"
fi

rm -f "$nuove"
