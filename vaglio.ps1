<#
.SYNOPSIS
  Vaglio, riga di comando: aggiunge domini spam alla blacklist di SpamAssassin su uno o più account cPanel via SSH.

.DESCRIPTION
  Gli account si salvano una volta (-Salva) e si richiamano per nome (-Account) o tutti insieme (-Tutti).
  Senza -Apply mostra solo l'anteprima. Con -Apply scrive solo sugli account che hanno domini nuovi,
  con copia locale e remota prima di ogni scrittura, e rilegge il file per verificare.

.EXAMPLE
  .\vaglio.ps1 -Salva -Nome sito-a -Server sito-a -Prefs '~/.spamassassin/user_prefs'
  Salva un account (solo dati non segreti: l'accesso resta nella configurazione SSH).

.EXAMPLE
  .\vaglio.ps1 -Account sito-a,sito-b -Domain spam.com
  Anteprima su due account.

.EXAMPLE
  .\vaglio.ps1 -Tutti -FromFile .\spam.txt -Apply
  Scrive su tutti gli account salvati.

.EXAMPLE
  .\vaglio.ps1 -Elenca
  Mostra gli account salvati.
#>
[CmdletBinding()]
param(
    # Account salvati, per nome. Più nomi separati da virgola.
    [string[]]$Account,
    # Tutti gli account salvati.
    [switch]$Tutti,
    # Destinazione ad hoc, senza salvarla: alias SSH oppure utente@host.
    [string]$Server,
    [string]$Prefs = '~/.spamassassin/user_prefs',
    # Domini o indirizzi. Accetta anche URL, mailto: e più valori separati da virgola.
    [string[]]$Domain,
    # File di testo con i domini.
    [string]$FromFile,
    # Scrive davvero. Senza questo flag è solo anteprima.
    [switch]$Apply,
    # Gestione account salvati.
    [switch]$Elenca,
    [switch]$Salva,
    [switch]$Rimuovi,
    # Voci della blacklist: lettura, eliminazione e modifica per dominio.
    [switch]$Lista,
    [switch]$Elimina,
    [switch]$Modifica,
    [string]$NuovoDominio,
    [string]$Nome,
    # Cartella locale per le copie prima di scrivere. Dentro c'è una sottocartella per account.
    [string]$BackupDir = (Join-Path $HOME 'Vaglio-backup')
)

$ErrorActionPreference = 'Stop'
# Con powershell.exe -File la virgola non divide l'array: si divide qui, nomi con spazi compresi.
if ($Account) { $Account = @($Account | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
. (Join-Path $PSScriptRoot 'lib\Vaglio.Core.ps1')
. (Join-Path $PSScriptRoot 'lib\Vaglio.Config.ps1')

if ($Elenca) {
    $elenco = @(Get-VaglioAccounts)
    if (-not $elenco) { Write-Host 'Nessun account salvato. Usa -Salva per aggiungerne uno.'; return }
    $elenco | Select-Object Nome, Server, Prefs
    return
}
if ($Salva) {
    if (-not $Nome -or -not $Server) { throw '-Salva richiede -Nome e -Server.' }
    Save-VaglioAccount -Account ([pscustomobject]@{ Nome = $Nome; Server = $Server; Prefs = $Prefs })
    Write-Host "Account salvato: $Nome"
    return
}
if ($Rimuovi) {
    if (-not $Nome) { throw '-Rimuovi richiede -Nome.' }
    Remove-VaglioAccount -Nome $Nome
    Write-Host "Account rimosso: $Nome (il server e le sue copie non sono stati toccati)."
    return
}

# Voci della blacklist di un account: lettura, eliminazione e modifica. Senza -Apply solo anteprima.
if ($Lista -or $Elimina -or $Modifica) {
    if (-not $Account -or $Account.Count -ne 1) { throw 'Per le voci della blacklist serve un solo account: -Account <nome>.' }
    $acc = @(Select-VaglioAccounts -Nomi $Account)[0]

    if ($Lista) {
        Get-VaglioVoci -Account $acc | Select-Object Testo, Dominio, Modificabile
        return
    }

    if ($Elimina) {
        if (-not $Domain) { throw '-Elimina richiede -Domain.' }
        $domini = (Get-VaglioDomini $Domain).Validi
        $voci = @(Get-VaglioVoci -Account $acc | Where-Object { $_.Modificabile -and $domini -contains $_.Dominio })
        if (-not $voci) { Write-Host 'Nessuna voce trovata per questi domini.'; return }
        $voci | Select-Object Testo | Out-Host
        if (-not $Apply) { Write-Host 'Anteprima: nessuna modifica. Rilancia con -Apply per eliminare.'; return }
        $esito = Invoke-VaglioRimuoviVoci -Account $acc -Testi @($voci.Testo) -CartellaBackup $BackupDir
        Write-Host "[$($acc.Nome)] eliminate $($esito.Rimosse) voci. Copia: $($esito.Backup)"
        return
    }

    if ($Modifica) {
        if (-not $Domain -or -not $NuovoDominio) { throw '-Modifica richiede -Domain (dominio attuale) e -NuovoDominio.' }
        $vecchi = @((Get-VaglioDomini $Domain).Validi)
        if ($vecchi.Count -ne 1) { throw '-Modifica accetta un solo dominio attuale.' }
        $voce = Get-VaglioVoci -Account $acc | Where-Object { $_.Modificabile -and $_.Dominio -eq $vecchi[0] } | Select-Object -First 1
        if (-not $voce) { throw "Nessuna voce per $($vecchi[0])." }
        $nuovoNorm = ConvertTo-VaglioDominio $NuovoDominio
        if (-not $nuovoNorm) { throw "«$NuovoDominio» non è un dominio valido." }
        Write-Host "«$($voce.Testo)» diventerebbe «blacklist_from *@$nuovoNorm»."
        if (-not $Apply) { Write-Host 'Anteprima: nessuna modifica. Rilancia con -Apply per modificare.'; return }
        $esito = Invoke-VaglioModificaVoce -Account $acc -Testo $voce.Testo -NuovoDominio $NuovoDominio -CartellaBackup $BackupDir
        Write-Host "[$($acc.Nome)] voce modificata. Copia: $($esito.Backup)"
        return
    }
}

# Destinazioni: account salvati scelti per nome o tutti, oppure un server ad hoc.
if ($Server) {
    $destinazioni = @([pscustomobject]@{ Nome = 'ad-hoc'; Server = $Server; Prefs = $Prefs })
} else {
    $destinazioni = @(Select-VaglioAccounts -Nomi $Account -Tutti:$Tutti)
}
if (-not $destinazioni) { throw 'Scegli dove bloccare: -Account <nomi>, -Tutti oppure -Server <host>.' }

$entrate = @($Domain)
if ($FromFile) { $entrate += @(Get-Content -Raw -LiteralPath $FromFile) }
if (-not $entrate) {
    Write-Host 'Incolla domini o indirizzi (uno per riga, poi riga vuota e invio):'
    $entrate = @(while ($r = Read-Host) { $r })
}
$esame = Get-VaglioDomini $entrate
if ($esame.Scartati) { Write-Warning ('Scartati (non sono domini): ' + ($esame.Scartati -join ', ')) }
if (-not $esame.Validi) { throw 'Nessun dominio valido.' }

$anteprime = @(Invoke-VaglioSuAccount -Tipo Anteprima -Account $destinazioni -Domini $esame.Validi)
ConvertTo-VaglioRighePiatte $anteprime | Select-Object Account, Stato, Dominio

$anteprimeFallite = @($anteprime | Where-Object { -not $_.Ok })
foreach ($f in $anteprimeFallite) { Write-Host "[$($f.Account)] ERRORE in anteprima: $($f.Errore)" -ForegroundColor Red }

if (-not $Apply) {
    Write-Host 'Anteprima: nessuna modifica. Rilancia con -Apply per scrivere.'
    if ($anteprimeFallite) { exit 1 }
    return
}

$daScrivere = @($anteprime | Where-Object { $_.Ok -and ($_.Righe | Where-Object { $_.Tipo -eq 'NUOVO' }) } |
    ForEach-Object { $acc = $_.Account; $destinazioni | Where-Object { $_.Nome -eq $acc } })
if (-not $daScrivere) {
    Write-Host 'Nessun dominio nuovo su nessun account: nessuna scrittura.'
    if ($anteprimeFallite) { exit 1 }
    return
}

$scritture = @(Invoke-VaglioSuAccount -Tipo Scrittura -Account $daScrivere -Domini $esame.Validi -CartellaBackup $BackupDir)
foreach ($s in $scritture) {
    if ($s.Ok) { Write-Host "[$($s.Account)] scritto e verificato: $($s.Esito.Verificati) domini presenti, $($s.Esito.Aggiunti) aggiunti. Copia: $($s.Esito.Backup)" }
    else { Write-Host "[$($s.Account)] ERRORE: $($s.Errore)" -ForegroundColor Red }
}
if ($anteprimeFallite -or ($scritture | Where-Object { -not $_.Ok })) { exit 1 }
