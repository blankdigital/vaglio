#!/bin/bash
# Eseguito sul server via ssh. Uso: bash -s -- <file_prefs> <ANTEPRIMA|APPLICA> <dominio>...
# Non è pensato per essere lanciato a mano: lo richiama sa-blacklist.ps1.
set -u
prefs="${1/#\~/$HOME}"; modo="$2"; shift 2

if [ ! -f "$prefs" ]; then
  echo "ERRORE file non trovato: $prefs"
  exit 2
fi

nuove=$(mktemp)
for d in "$@"; do
  esc=${d//./\\.}
  if grep -qiE "^blacklist_from[[:space:]]+\*?@?\.?${esc}[[:space:]]*$" "$prefs"; then
    echo "GIA $d"
  else
    echo "NUOVO $d"
    echo "blacklist_from *@$d" >> "$nuove"
  fi
done

if [ "$modo" = "APPLICA" ] && [ -s "$nuove" ]; then
  cp "$prefs" "$prefs.bak-$(date +%Y%m%d-%H%M%S)"
  # Assicura il newline finale, altrimenti la prima riga aggiunta si attacca all'ultima esistente.
  [ -n "$(tail -c1 "$prefs")" ] && echo >> "$prefs"
  riga=$(grep -n '^blacklist_from' "$prefs" | tail -1 | cut -d: -f1)
  if [ -n "$riga" ]; then
    # limite noto: inserisce dopo l'ultima blacklist_from esistente. Se il file non ne ha, si accoda in fondo.
    sed -i "${riga}r $nuove" "$prefs"
  else
    cat "$nuove" >> "$prefs"
  fi
  echo "SCRITTO $(wc -l < "$nuove")"
fi

rm -f "$nuove"
