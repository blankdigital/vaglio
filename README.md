# Vaglio

Un vaglio separa il grano dalla pula. Vaglio separa i domini spam dal resto e li aggiunge alla blacklist di SpamAssassin su un hosting cPanel, via SSH, senza entrare nel pannello.

Incolli i domini, vedi l'anteprima di cosa cambierebbe, poi scrive. Prima di scrivere copia il file `user_prefs` in locale e sul server. Dopo aver scritto rilegge il file dal server e controlla che ogni dominio ci sia davvero.

Sono disponibili due interfacce, con le stesse regole: una finestra grafica e una riga di comando.

## Requisiti

- Windows 10/11 con PowerShell 5.1 o PowerShell 7.
- `ssh` e `scp` nel terminale (inclusi in Windows 10/11).
- Accesso SSH al server con chiave, con bash, `base64` e `sed` (standard su cPanel).
- Un file `user_prefs` di SpamAssassin sul server, di solito `~/.spamassassin/user_prefs`.

Nessuna dipendenza da installare.

## Installazione

```powershell
git clone https://github.com/TUO-UTENTE/vaglio.git
cd vaglio
```

Per la finestra grafica, doppio clic su `Vaglio.cmd`.

## Configurazione SSH

Vaglio usa una destinazione SSH: un alias di `~/.ssh/config` oppure `utente@host`.

```
# ~/.ssh/config
Host miosito
    HostName server.example.com
    User nome-account-cpanel
    Port 22
```

Se `ssh miosito` entra senza chiedere la password da terminale, Vaglio funziona. Non chiede mai credenziali.

## Interfaccia grafica

1. Inserisci il server SSH. Il file user_prefs è precompilato con il percorso più comune.
2. Incolla i domini o gli indirizzi.
3. Premi **Anteprima**. L'elenco mostra per ogni dominio se è nuovo o già presente. Non scrive nulla.
4. Se ci sono domini nuovi si attiva **Scrivi sul server**. Vaglio chiede conferma prima di scrivere.

Se cambi un campo dopo l'anteprima, l'anteprima non è più valida e il pulsante di scrittura si disattiva. Serve sempre un'anteprima recente.

Tasti: `Alt` con la lettera sottolineata attiva il campo o il pulsante. `Invio` avvia l'anteprima. `Esc` chiude la finestra.

## Riga di comando

Anteprima, non scrive nulla:

```powershell
.\vaglio.ps1 -Server miosito -Domain spam.com,mail.example.net
```

Scrittura, con backup e verifica:

```powershell
.\vaglio.ps1 -Server miosito -FromFile .\spam.txt -Apply
```

Accetta anche indirizzi e URL: `user@spam.com`, `mailto:user@spam.com` e `https://www.spam.com/path` diventano tutti `spam.com`.

| Parametro | Default | Cosa fa |
|---|---|---|
| `-Server` | obbligatorio | Destinazione SSH (alias o `utente@host`) |
| `-Prefs` | `~/.spamassassin/user_prefs` | File di SpamAssassin sul server |
| `-Domain` | | Domini da aggiungere |
| `-FromFile` | | File con i domini |
| `-Apply` | assente | Senza questo flag non scrive nulla |
| `-BackupDir` | `$HOME\Vaglio-backup` | Cartella locale per le copie prima di scrivere |

## Come funziona

1. Normalizza ogni token in un dominio e scarta quelli non validi, con un avviso.
2. Invia lo script `lib/remote.sh` al server in base64, dentro il comando SSH. Il base64 è solo ASCII: niente problemi di quoting né di BOM UTF-8 lungo la pipeline verso `ssh`.
3. Il server dice per ogni dominio se è nuovo (`NUOVO`) o già presente (`GIA`).
4. Con la scrittura: copia `user_prefs` in locale e sul server (`.bak-AAAAMMGG-HHMMSS`), aggiunge le righe nuove dopo l'ultima `blacklist_from`, poi rilegge il file con la modalità `VERIFICA`.
5. Se un dominio non risulta nel file riletto, Vaglio si ferma con errore e lo segnala.

L'anteprima non scrive mai. Rilanciare con gli stessi domini non duplica niente.

## Accessibilità e aspetto

- Ogni campo ha un'etichetta collegata con tasto di scelta rapida, e un testo di aiuto letto dagli screen reader.
- Il focus da tastiera è sempre visibile, con un anello di 2 px.
- Il messaggio di stato e l'errore sono annunciati agli screen reader (live region).
- Il tema segue la modalità chiaro o scuro di Windows.
- Ogni coppia di colori del testo è sopra 4,5:1, e bordi e componenti sopra 3:1 (WCAG 2.2, 1.4.3 e 1.4.11). Il test verifica entrambi i temi.
- Nessuna informazione è affidata al solo colore: lo stato è sempre scritto.
- Nessuna animazione. Il testo si adatta alla dimensione scelta in Windows.

## Test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Vaglio.Tests.ps1
```

Il test copre la normalizzazione dei domini, il parsing dell'output remoto e i contrasti dei due temi.

Il file remoto si può provare in locale con Git Bash su un file di prova:

```bash
printf 'blacklist_from *@vecchio.com\n' > /tmp/prefs
bash lib/remote.sh /tmp/prefs ANTEPRIMA vecchio.com nuovo.net
bash lib/remote.sh /tmp/prefs APPLICA nuovo.net
bash lib/remote.sh /tmp/prefs VERIFICA nuovo.net
```

## Limiti noti

- Funziona con SpamAssassin come configurato su cPanel, con `blacklist_from` in `user_prefs`. Altri setup, per esempio un `local.cf` globale, richiedono di adattare `lib/remote.sh`.
- Gestisce un file `user_prefs` per esecuzione.
- I domini internazionalizzati in forma Unicode non sono supportati: va passata la forma punycode (`xn--`).
- Il percorso in `-Prefs` e nel campo della GUI non può contenere apici singoli.
- La verifica controlla che le righe siano nel file, non che la blacklist funzioni. Il risultato reale si misura dalla posta che arriva.
- Il test sul server reale non è ancora stato fatto: la logica è verificata in locale con SSH simulato.

## Licenza

MIT, vedi [LICENSE](LICENSE).
