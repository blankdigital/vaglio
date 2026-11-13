<#
.SYNOPSIS
  Vaglio, interfaccia a riga di comando: aggiunge domini spam alla blacklist di SpamAssassin su hosting cPanel via SSH.

.DESCRIPTION
  Senza -Apply mostra solo l'anteprima. Con -Apply salva un backup locale, scrive sul server
  (con backup remoto) e rilegge il file per verificare che ogni dominio sia presente.
  Per l'interfaccia grafica usare vaglio-gui.ps1 (o Vaglio.cmd).

.EXAMPLE
  .\vaglio.ps1 -Server miosito -Domain spam.com,mail.example.net
  Anteprima: non scrive nulla.

.EXAMPLE
  .\vaglio.ps1 -Server miosito -FromFile .\spam.txt -Apply
  Scrive sul server, con backup locale e remoto prima, e verifica il risultato.
#>
[CmdletBinding()]
param(
    # Destinazione SSH: alias di ~/.ssh/config oppure utente@host.
    [Parameter(Mandatory)][string]$Server,
    # File user_prefs di SpamAssassin sul server. ~ è accettato.
    [string]$Prefs = '~/.spamassassin/user_prefs',
    # Domini o indirizzi. Accetta anche URL, mailto: e più valori separati da virgola.
    [string[]]$Domain,
    # File di testo con i domini, uno per riga o separati da spazi.
    [string]$FromFile,
    # Scrive davvero sul server. Senza questo flag è solo anteprima.
    [switch]$Apply,
    # Cartella locale per il backup prima di scrivere.
    [string]$BackupDir = (Join-Path $HOME 'Vaglio-backup')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Vaglio.Core.ps1')

$entrate = @($Domain)
if ($FromFile) { $entrate += @(Get-Content -Raw -LiteralPath $FromFile) }
if (-not $entrate) {
    Write-Host 'Incolla domini o indirizzi (uno per riga, poi riga vuota e invio):'
    $entrate = @(while ($r = Read-Host) { $r })
}
$esame = Get-VaglioDomini $entrate
if ($esame.Scartati) { Write-Warning ('Scartati (non sono domini): ' + ($esame.Scartati -join ', ')) }
if (-not $esame.Validi) { throw 'Nessun dominio valido.' }

$anteprima = Invoke-VaglioAnteprima -Server $Server -Prefs $Prefs -Domini $esame.Validi
$anteprima | Format-Table -AutoSize Stato, Dominio | Out-Host

if (-not $Apply) {
    Write-Host 'Anteprima: nessuna modifica. Rilancia con -Apply per scrivere.'
    return
}
if (-not ($anteprima | Where-Object { $_.Tipo -eq 'NUOVO' })) {
    Write-Host 'Tutti i domini sono già presenti: nessuna scrittura.'
    return
}

$esito = Invoke-VaglioScrittura -Server $Server -Prefs $Prefs -Domini $esame.Validi -CartellaBackup $BackupDir
Write-Host "Backup locale: $($esito.Backup)"
Write-Host "Verificato sul server: $($esito.Verificati) domini presenti, $($esito.Aggiunti) aggiunti."
