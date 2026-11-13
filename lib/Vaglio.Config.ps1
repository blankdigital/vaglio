# Account salvati di Vaglio. Nessun segreto: solo nome, destinazione SSH e percorso di user_prefs.
# L'autenticazione resta nella configurazione SSH dell'utente (chiavi in ~/.ssh).
# Il file sta in %APPDATA%\Vaglio\accounts.json. Per i test si può cambiare con $env:VAGLIO_CONFIG_DIR.

$script:PrefsDefault = '~/.spamassassin/user_prefs'

function Get-VaglioConfigDir {
    if ($env:VAGLIO_CONFIG_DIR) { return $env:VAGLIO_CONFIG_DIR }
    return (Join-Path $env:APPDATA 'Vaglio')
}

function Get-VaglioConfigPath { Join-Path (Get-VaglioConfigDir) 'accounts.json' }

function Test-VaglioAccount {
    # Restituisce un messaggio di errore, oppure $null se l'account è valido.
    param([Parameter(Mandatory)][pscustomobject]$Account, [object[]]$Esistenti = @(), [string]$NomeOriginale)
    if ([string]::IsNullOrWhiteSpace($Account.Nome)) { return 'Inserisci un nome per l''account.' }
    if ($Account.Nome -notmatch '^[\w .-]{1,40}$') { return 'Il nome può contenere lettere, numeri, spazi, punti, trattini e trattini bassi (massimo 40 caratteri).' }
    if ([string]::IsNullOrWhiteSpace($Account.Server)) { return 'Inserisci il server SSH (alias o utente@host).' }
    if ($Account.Server -match '\s') { return 'Il server SSH non può contenere spazi.' }
    if ([string]::IsNullOrWhiteSpace($Account.Prefs)) { return 'Inserisci il percorso del file user_prefs.' }
    if ($Account.Prefs -match "'") { return 'Il percorso non può contenere apici singoli.' }
    $doppio = $Esistenti | Where-Object { $_.Nome -eq $Account.Nome -and $_.Nome -ne $NomeOriginale }
    if ($doppio) { return "Esiste già un account chiamato «$($Account.Nome)»." }
    return $null
}

function Get-VaglioAccounts {
    # Legge gli account. Se il file è corrotto non lo sovrascrive: lancia un errore con il percorso da controllare.
    $path = Get-VaglioConfigPath
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try {
        $dati = Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json
    } catch {
        throw "Il file degli account non si legge: $path. Controllalo o spostalo prima di continuare."
    }
    @($dati.account | ForEach-Object {
        [pscustomobject]@{ Nome = [string]$_.nome; Server = [string]$_.server; Prefs = [string]$_.prefs }
    })
}

function Save-VaglioAccounts {
    # Scrittura atomica: prima su un file temporaneo, poi sostituzione.
    param([object[]]$Accounts)
    $dir = Get-VaglioConfigDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $oggetto = [ordered]@{
        versione = 1
        account  = @($Accounts | ForEach-Object { [ordered]@{ nome = $_.Nome; server = $_.Server; prefs = $_.Prefs } })
    }
    $tmp = Join-Path $dir 'accounts.json.tmp'
    $json = $oggetto | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination (Get-VaglioConfigPath) -Force
}

function Save-VaglioAccount {
    # Aggiunge o aggiorna un account. Con NomeOriginale si rinomina un account esistente.
    param([Parameter(Mandatory)][pscustomobject]$Account, [string]$NomeOriginale)
    $tutti = @(Get-VaglioAccounts)
    $errore = Test-VaglioAccount -Account $Account -Esistenti $tutti -NomeOriginale $NomeOriginale
    if ($errore) { throw $errore }
    $nuovi = @($tutti | Where-Object { $_.Nome -ne $NomeOriginale -and $_.Nome -ne $Account.Nome })
    $nuovi += [pscustomobject]@{ Nome = $Account.Nome; Server = $Account.Server; Prefs = $(if ($Account.Prefs) { $Account.Prefs } else { $script:PrefsDefault }) }
    Save-VaglioAccounts -Accounts $nuovi
}

function Remove-VaglioAccount {
    param([Parameter(Mandatory)][string]$Nome)
    $tutti = @(Get-VaglioAccounts)
    Save-VaglioAccounts -Accounts @($tutti | Where-Object { $_.Nome -ne $Nome })
}

function Select-VaglioAccounts {
    # Sceglie gli account di destinazione: per nome, tutti, oppure un account ad hoc passato con -Server.
    # Nota: in PowerShell i nomi di variabile non distinguono maiuscole e minuscole, quindi la lista non si chiama $tutti.
    param([string[]]$Nomi, [switch]$Tutti)
    $salvati = @(Get-VaglioAccounts)
    if ($Tutti) { return $salvati }
    if (-not $Nomi) { return @() }
    $scelti = @()
    foreach ($n in $Nomi) {
        $trovato = $salvati | Where-Object { $_.Nome -eq $n }
        if (-not $trovato) { throw "Account non trovato: $n" }
        $scelti += $trovato
    }
    $scelti
}
