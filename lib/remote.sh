#!/bin/bash
# copy-guard: ignore (GIA è il codice di stato del protocollo, non testo)
# Eseguito sul server via ssh, lanciato da Vaglio.Core.ps1. Autore: Alessandro De Cenzo, https://alessandrodecenzo.it
# Uso: bash -s -- <file_prefs> <modo> <argomenti...>
#   ANTEPRIMA <dominio>...: dice NUOVO o GIA per ogni dominio, non scrive.
#   APPLICA <dominio>...:   come ANTEPRIMA, poi scrive le righe nuove (con backup del file).
#   VERIFICA <dominio>...:  dice PRESENTE o MANCANTE per ogni dominio.
#   LISTA:                  dice LINEA <base64> per ogni blacklist_from.
#   RIMUOVI <base64>...:    elimina le righe identiche alle voci passate.
#   MODIFICA <b64 vecchia> <b64 nuova>: sostituisce le righe identiche alla vecchia.
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

# LISTA: una riga "LINEA <base64>" per ogni blacklist_from, così il contenuto arriva intatto.
if [ "$modo" = "LISTA" ]; then
  grep '^blacklist_from' "$prefs" | while IFS= read -r l; do
    printf 'LINEA %s\n' "$(printf '%s' "$l" | base64 | tr -d '\n')"
  done
  exit 0
fi

# RIMUOVI <base64>...: elimina le righe identiche (intere) alle voci passate. Copia prima, poi scrive.
if [ "$modo" = "RIMUOVI" ]; then
  tmp=$(mktemp)
  for b in "$@"; do printf '%s' "$b" | base64 -d; echo; done > "$tmp"
  n=$(grep -cFxf "$tmp" "$prefs" || true)
  if [ "$n" -gt 0 ]; then
    cp "$prefs" "$prefs.bak-$(date +%Y%m%d-%H%M%S)"
    awk 'NR==FNR { del[$0] = 1; next } !($0 in del)' "$tmp" "$prefs" > "$prefs.new" && cat "$prefs.new" > "$prefs" && rm -f "$prefs.new"
  fi
  rm -f "$tmp"
  echo "RIMOSSE $n"
  exit 0
fi

# MODIFICA <base64 vecchia> <base64 nuova>: sostituisce ogni riga identica alla vecchia.
if [ "$modo" = "MODIFICA" ]; then
  old=$(printf '%s' "$1" | base64 -d)
  new=$(printf '%s' "$2" | base64 -d)
  n=$(grep -cFx -- "$old" "$prefs" || true)
  if [ "$n" -gt 0 ]; then
    cp "$prefs" "$prefs.bak-$(date +%Y%m%d-%H%M%S)"
    OLD="$old" NEW="$new" awk '{ if ($0 == ENVIRON["OLD"]) { print ENVIRON["NEW"]; next } print }' "$prefs" > "$prefs.new" && cat "$prefs.new" > "$prefs" && rm -f "$prefs.new"
  fi
  echo "MODIFICATE $n"
  exit 0
fi

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
