<#
.SYNOPSIS
  Aggiunge domini o indirizzi email alla blacklist di SpamAssassin su un hosting cPanel via SSH.

.DESCRIPTION
  Legge un file user_prefs di SpamAssassin sul server, aggiunge una riga
  "blacklist_from *@dominio" per ogni dominio nuovo e, solo con -Apply, scrive.
  Senza -Apply mostra soltanto cosa verrebbe aggiunto (anteprima).

.EXAMPLE
  .\sa-blacklist.ps1 -Server miosito -Domain spam.com,mail.example.net
  Anteprima: non scrive nulla.

.EXAMPLE
  .\sa-blacklist.ps1 -Server miosito -FromFile .\spam.txt -Apply
  Scrive sul server, con backup locale e remoto prima, e rilegge il file per verificare.

.NOTES
  Richiede ssh e scp (inclusi in Windows 10/11 e nella maggior parte dei sistemi Unix).
  Il server deve avere bash, base64 e sed (standard su cPanel).
#>
[CmdletBinding()]
param(
    # Destinazione ssh: alias di ~/.ssh/config oppure user@host.
    [Parameter(Mandatory)][string]$Server,
    # Percorso del file user_prefs sul server. ~ è accettato.
    [string]$Prefs = '~/.spamassassin/user_prefs',
    # Domini o indirizzi da bloccare. Accetta anche URL, mailto: e più valori separati da virgola.
    [string[]]$Domain,
    # File di testo con i domini, uno per riga o separati da spazi.
    [string]$FromFile,
    # Scrive davvero sul server. Senza questo flag è solo anteprima.
    [switch]$Apply,
    # Cartella locale dove salvare il backup prima di scrivere.
    [string]$BackupDir = (Join-Path $HOME 'sa-blacklist-backup')
)

$ErrorActionPreference = 'Stop'

function ConvertTo-Domain {
    <#
      Normalizza un token in un dominio. Restituisce $null se non è un dominio valido.
      Accetta: a.com, *.a.com, @a.com, user@a.com, mailto:user@a.com, https://a.com/path, www.a.com
    #>
    param([string]$Token)
    # limite noto: niente IDN in forma Unicode, passare la forma punycode (xn--)
    $d = $Token.ToLower().Trim()
    $d = $d -replace '^mailto:', '' -replace '^https?://', '' -replace '^.*@', '' -replace '^\*?\.?', '' -replace '[/:?#].*$', '' -replace '^www\.', ''
    if ($d -match '^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9-]{2,}$') { return $d }
    return $null
}

function Get-Domains {
    <# Restituisce @{ Validi = [string[]]; Scartati = [string[]] }, senza duplicati. #>
    param([string[]]$Entrate)
    $validi = [System.Collections.Generic.List[string]]::new()
    $scartati = [System.Collections.Generic.List[string]]::new()
    foreach ($token in ($Entrate -join "`n") -split '[\s,;]+') {
        if (-not $token) { continue }
        $d = ConvertTo-Domain $token
        if (-not $d) { $scartati.Add($token); continue }
        if (-not $validi.Contains($d)) { $validi.Add($d) }
    }
    return @{ Validi = $validi.ToArray(); Scartati = $scartati.ToArray() }
}

# Self-check: se la normalizzazione si rompe, lo script si ferma prima di toccare il server.
$casi = @{
    'a.com'                    = 'a.com'
    'SPAM.it'                  = 'spam.it'
    'user@a.com'               = 'a.com'
    'mailto:user@a.com'        = 'a.com'
    '*.a.com'                  = 'a.com'
    '@a.com'                   = 'a.com'
    'https://www.a.com/x?y=1'  = 'a.com'
    'sotto.a.com'              = 'sotto.a.com'
    'non un dominio'           = $null
    'a'                        = $null
}
foreach ($k in $casi.Keys) {
    if ((ConvertTo-Domain $k) -ne $casi[$k]) { throw "Self-check fallito su '$k': atteso '$($casi[$k])'" }
}

$entrate = @($Domain)
if ($FromFile) { $entrate += @(Get-Content -Raw -LiteralPath $FromFile) }
if (-not $entrate) {
    Write-Host 'Incolla domini o indirizzi (uno per riga, poi riga vuota e invio):'
    $entrate = @(while ($r = Read-Host) { $r })
}
$esame = Get-Domains $entrate
if ($esame.Scartati) { Write-Warning ('Scartati (non sono domini): ' + ($esame.Scartati -join ', ')) }
if (-not $esame.Validi) { throw 'Nessun dominio valido.' }
$validi = $esame.Validi

# Script remoto in base64: evita problemi di quoting e del BOM che PowerShell aggiunge ai pipe verso programmi nativi.
$remoto = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'remote.sh')
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($remoto -replace "`r", '')))
$modo = if ($Apply) { 'APPLICA' } else { 'ANTEPRIMA' }

if ($Apply) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $copia = Join-Path $BackupDir ("user_prefs-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    scp "${Server}:${Prefs}" $copia
    if ($LASTEXITCODE -ne 0) { throw 'Backup locale fallito, nessuna modifica fatta.' }
    Write-Host "Backup locale: $copia"
}

$domini = $validi -join ' '
$esito = ssh $Server "echo $b64 | base64 -d | bash -s -- '$Prefs' $modo $domini"
if ($LASTEXITCODE -ne 0) { throw 'Errore SSH o file non trovato sul server.' }
$esito

if ($Apply) {
    $dopo = (ssh $Server "cat '$Prefs'") -join "`n"
    $mancanti = $validi | Where-Object { $dopo -notmatch ('(?m)^blacklist_from\s+\*?@?\.?' + [regex]::Escape($_) + '\s*$') }
    if ($mancanti) { throw ('Verifica fallita, non presenti sul server: ' + ($mancanti -join ', ')) }
    Write-Host "Verificato sul server: $($validi.Count) domini presenti."
} else {
    Write-Host 'Anteprima: nessuna modifica. Rilancia con -Apply per scrivere.'
}
