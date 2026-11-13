# sa-blacklist

Aggiunge domini e indirizzi spam alla blacklist di SpamAssassin su un hosting cPanel, via SSH, senza entrare nel pannello.

Incolli i domini, vedi l'anteprima di cosa cambierebbe, poi scrivi. Prima di scrivere fa un backup in locale e sul server, e a fine scrittura rilegge il file dal server per verificare che i domini ci siano davvero.

> Nome provvisorio: il progetto si può rinominare senza cambiare il codice.

## Requisiti

- Windows 10/11 con PowerShell 5.1 o PowerShell 7, oppure Linux/macOS con `pwsh`.
- `ssh` e `scp` disponibili nel terminale.
- Un accesso SSH al server con bash, `base64` e `sed` (standard su cPanel).
- Un file `user_prefs` di SpamAssassin sul server, di solito `~/.spamassassin/user_prefs`.

## Installazione

```powershell
git clone https://github.com/TUO-UTENTE/sa-blacklist.git
cd sa-blacklist
```

Nessuna dipendenza da installare.

## Configurazione SSH

Lo script usa una destinazione SSH. Può essere un alias di `~/.ssh/config` oppure `utente@host`.

```
# ~/.ssh/config
Host miosito
    HostName server.example.com
    User nome-account-cpanel
    Port 22
```

Se il server ha la chiave configurata, `ssh miosito` deve entrare senza chiedere la password. Lo script non chiede mai credenziali.

## Uso

Anteprima, non scrive nulla:

```powershell
.\sa-blacklist.ps1 -Server miosito -Domain spam.com,mail.example.net
```

Scrittura vera, con backup e verifica:

```powershell
.\sa-blacklist.ps1 -Server miosito -Domain spam.com -Apply
```

Da un file di testo, uno per riga o separati da spazi e virgole:

```powershell
.\sa-blacklist.ps1 -Server miosito -FromFile .\spam.txt -Apply
```

Senza parametri, lo script chiede di incollare i domini a terminale, con una riga vuota per finire.

Accetta anche indirizzi e URL: `user@spam.com`, `mailto:user@spam.com`, `https://www.spam.com/path` diventano tutti `spam.com`.

### Parametri

| Parametro | Default | Cosa fa |
|---|---|---|
| `-Server` | obbligatorio | Destinazione SSH (alias o `utente@host`) |
| `-Prefs` | `~/.spamassassin/user_prefs` | File di SpamAssassin sul server |
| `-Domain` | | Domini da aggiungere |
| `-FromFile` | | File con i domini |
| `-Apply` | assente | Senza questo flag non scrive nulla |
| `-BackupDir` | `$HOME\sa-blacklist-backup` | Cartella locale per il backup prima di scrivere |

## Come funziona

1. Normalizza ogni token in un dominio e scarta quelli non validi, con un avviso.
2. Invia lo script remoto (`remote.sh`) al server in base64. Il base64 evita problemi di quoting e il BOM che PowerShell aggiunge ai dati passati a programmi esterni.
3. Il server controlla quali domini sono già presenti (`GIA`) e quali sono nuovi (`NUOVO`).
4. Con `-Apply`: copia il file `user_prefs` in locale e sul server (`.bak-AAAAMMGG-HHMMSS`), aggiunge le righe nuove dopo l'ultima `blacklist_from` e rilegge il file.
5. Se un dominio non risulta nel file riletto, lo script si ferma con errore.

Lo script è idempotente: rilanciarlo con gli stessi domini non duplica le righe.

## Test

Lo script contiene un self-check che parte a ogni esecuzione e blocca tutto se la normalizzazione dei domini non dà i risultati attesi.

Il test del file remoto si può fare in locale, con Git Bash, su un file di prova:

```bash
printf 'blacklist_from *@vecchio.com\n' > /tmp/prefs
bash remote.sh /tmp/prefs ANTEPRIMA vecchio.com nuovo.net
bash remote.sh /tmp/prefs APPLICA nuovo.net
cat /tmp/prefs
```

## Limiti noti

- Funziona solo con SpamAssassin come configurato su cPanel, con `blacklist_from` in `user_prefs`. Altri setup (per esempio `local.cf` globale) richiedono di adattare `remote.sh`.
- Gestisce un solo file `user_prefs` per esecuzione.
- Non gestisce domini internazionalizzati in forma Unicode: passare la forma punycode (`xn--`).
- `-Prefs` non può contenere apici singoli.
- Il controllo finale verifica che le righe ci siano, non che la blacklist funzioni. Il risultato reale si vede nei messaggi successivi.
- Lo script non è testato su tutti gli hosting. Prima di usarlo su un server di produzione, fare un'anteprima e controllare il backup.

## Licenza

MIT, vedi [LICENSE](LICENSE).
