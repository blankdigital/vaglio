# Vaglio - SpamAssassin Blacklist Manager

Un vaglio separa il grano dalla pula. Vaglio separa i domini spam dal resto e li aggiunge alla blacklist di SpamAssassin su uno o più account cPanel, via SSH, senza entrare nel pannello.

Salvi gli account una volta. Poi, per ogni lista di domini, scegli dove bloccarli: un solo server, alcuni o tutti. Vaglio mostra l'anteprima per ogni account, scrive solo dove ci sono domini nuovi, copia il file prima di toccarlo e lo rilegge dal server per verificare.

Sono disponibili due interfacce con le stesse regole: una finestra grafica e una riga di comando.

## Requisiti

- Windows 10/11 con PowerShell 5.1 o PowerShell 7.
- `ssh` e `scp` nel terminale (inclusi in Windows 10/11).
- Accesso SSH con chiave a ogni server, con bash, `base64` e `sed` (standard su cPanel).
- Un file `user_prefs` di SpamAssassin su ogni server, di solito `~/.spamassassin/user_prefs`.

Nessuna dipendenza da installare.

## Installazione

```powershell
git clone https://github.com/blankdigital/vaglio.git
cd vaglio
```

Per la finestra grafica, doppio clic su `Vaglio.vbs`. Il file avvia la GUI senza console. Per un collegamento sul Desktop: destinazione `wscript.exe //B "<percorso>\Vaglio.vbs"`.

## Account

Un account è un nome, un server SSH e il percorso di `user_prefs`. Vaglio non salva password: l'accesso passa dalla configurazione SSH, con chiavi in `~/.ssh`.

Per ogni server crea un alias in `~/.ssh/config`:

```
# ~/.ssh/config
Host sito-cliente-a
    HostName server-a.example.com
    User nome-account-a
    IdentityFile ~/.ssh/id_ed25519
```

Gli account salvati stanno in `%APPDATA%\Vaglio\accounts.json`. Il file contiene solo nome, server e percorso. Se si rompe, Vaglio non lo sovrascrive: lo segnala e lo lascia da controllare.

Dalla finestra: **Gestisci account…** apre l'elenco, con i pulsanti Nuovo, Salva ed Elimina. Eliminare un account rimuove solo la voce da Vaglio, non tocca il server.

Dalla riga di comando:

```powershell
.\vaglio.ps1 -Salva -Nome sito-cliente-a -Server sito-cliente-a -Prefs '~/.spamassassin/user_prefs'
.\vaglio.ps1 -Elenca
.\vaglio.ps1 -Rimuovi -Nome sito-cliente-a
```

## Interfaccia grafica

1. Scegli dove bloccare: **Un solo server**, **Alcuni server** o **Tutti i server**.
2. Seleziona gli account nell'elenco. Con più account usa Spazio o Ctrl+clic.
3. Incolla i domini o gli indirizzi.
4. Premi **Anteprima**. L'esito mostra, per ogni account, quali domini sono nuovi e quali già presenti. Non scrive nulla.
5. Se ci sono domini nuovi si attiva **Scrivi sul server**. Vaglio elenca gli account che verranno toccati e chiede conferma.

Se cambi account, destinazione o domini dopo l'anteprima, l'anteprima non è più valida e la scrittura si disattiva.

Un account che non risponde non blocca gli altri: il suo errore compare nell'esito e gli altri vanno avanti.

Tasti: `Alt` con la lettera sottolineata attiva il campo o il pulsante. `Invio` avvia l'anteprima. `Esc` chiude la finestra.

## Voci già in blacklist

Dalla finestra, **Voci della blacklist…** apre le voci `blacklist_from` del server dell'account selezionato. Da lì puoi:

- **leggere** tutte le voci del file;
- **eliminare** una o più voci selezionate, con conferma;
- **modificare** una voce nella forma `*@dominio`, cambiandone il dominio.

Le voci in altra forma, per esempio un indirizzo singolo, si vedono ma non si modificano.

Ogni eliminazione o modifica copia prima il file in locale e sul server, poi rilegge il file per verificare il risultato.

Dalla riga di comando, senza `-Apply` si vede solo cosa cambierebbe:

```powershell
.\vaglio.ps1 -Account sito-cliente-a -Lista
.\vaglio.ps1 -Account sito-cliente-a -Elimina -Domain spam.com -Apply
.\vaglio.ps1 -Account sito-cliente-a -Modifica -Domain vecchio.com -NuovoDominio nuovo.org -Apply
```

La gestione della whitelist non c'è ancora: arriverà in un aggiornamento successivo.

## Riga di comando

Anteprima su due account:

```powershell
.\vaglio.ps1 -Account sito-cliente-a,sito-cliente-b -Domain spam.com,mail.example.net
```

Scrittura su tutti gli account salvati, con copie e verifica:

```powershell
.\vaglio.ps1 -Tutti -FromFile .\spam.txt -Apply
```

Destinazione ad hoc, senza salvarla:

```powershell
.\vaglio.ps1 -Server alias-prova -Domain spam.com
```

Accetta anche indirizzi e URL: `user@spam.com`, `mailto:user@spam.com` e `https://www.spam.com/path` diventano tutti `spam.com`.

Codice di uscita: `0` se tutto è andato bene, `1` se almeno un account è fallito. Così lo script si può usare in un'automazione.

| Parametro | Cosa fa |
|---|---|
| `-Account` | Uno o più account salvati, per nome |
| `-Tutti` | Tutti gli account salvati |
| `-Server` | Destinazione ad hoc, senza salvataggio |
| `-Domain` / `-FromFile` | Domini da aggiungere |
| `-Apply` | Senza questo flag non scrive nulla |
| `-Elenca`, `-Salva`, `-Rimuovi` | Gestione degli account salvati |
| `-BackupDir` | Cartella locale per le copie (`$HOME\Vaglio-backup`), con una sottocartella per account |

## Come funziona

1. Normalizza ogni token in un dominio e scarta quelli non validi, con un avviso.
2. Per ogni account invia `lib/remote.sh` al server in base64, dentro il comando SSH. Il base64 è solo ASCII: niente problemi di quoting né di BOM UTF-8 lungo la pipeline verso `ssh`.
3. Il server dice per ogni dominio se è nuovo (`NUOVO`) o già presente (`GIA`).
4. Solo sugli account con domini nuovi, la scrittura: copia `user_prefs` in locale e sul server (`.bak-AAAAMMGG-HHMMSS`), aggiunge le righe dopo l'ultima `blacklist_from`, poi rilegge il file con la modalità `VERIFICA`.
5. Se un dominio non risulta nel file riletto, quell'account segnala l'errore. Gli altri non si fermano.

L'anteprima non scrive mai. Rilanciare con gli stessi domini non duplica niente.

## Accessibilità e aspetto

- Ogni campo ha un'etichetta con tasto di scelta rapida e un testo di aiuto letto dagli screen reader.
- Il focus da tastiera è sempre visibile, con un anello di 2 px.
- Lo stato e gli errori sono annunciati agli screen reader (live region).
- Il tema segue la modalità chiaro o scuro di Windows.
- Ogni coppia di colori del testo è sopra 4,5:1, e bordi e componenti sopra 3:1 (WCAG 2.2, 1.4.3 e 1.4.11). Il test verifica entrambi i temi.
- Nessuna informazione è affidata al solo colore: lo stato è sempre scritto.
- Nessuna animazione. Il testo si adatta alla dimensione scelta in Windows.

## Test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Vaglio.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Vaglio.E2E.ps1
```

Il primo copre normalizzazione, parsing dell'output, gestione degli account, contrasti nei due temi e lettura delle finestre WPF. Il secondo esegue la CLI su tre account, uno dei quali rotto, con SSH e SCP simulati in locale tramite Git bash.

## Limiti noti

- Funziona con SpamAssassin come configurato su cPanel, con `blacklist_from` in `user_prefs`. Altri setup, per esempio un `local.cf` globale, richiedono di adattare `lib/remote.sh`.
- Richiede chiavi SSH: l'accesso con password non è supportato.
- I domini internazionalizzati in forma Unicode non sono supportati: va passata la forma punycode (`xn--`).
- Il percorso di `user_prefs` non può contenere apici singoli.
- La verifica controlla che le righe siano nel file, non che la blacklist funzioni. Il risultato reale si misura dalla posta che arriva.
- La finestra di gestione account non è coperta da un test automatico di interazione: è verificata nel caricamento XAML e a mano.
- Il test su un server reale non è ancora stato fatto: la logica è verificata in locale con SSH simulato.

## Licenza

MIT, vedi [LICENSE](LICENSE). Il repo è privato finché non è pronto alla pubblicazione.
