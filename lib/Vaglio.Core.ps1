# copy-guard: ignore (il token GIA è il codice di stato del protocollo remoto, non testo)
# Vaglio, nucleo condiviso da GUI e CLI.
# Nessuna interazione qui: ogni funzione restituisce dati o lancia un'eccezione con un messaggio leggibile.

$script:RemotoPath = Join-Path $PSScriptRoot 'remote.sh'

function ConvertTo-VaglioDominio {
    # Normalizza un token in un dominio. Restituisce $null se non è un dominio valido.
    # limite noto: niente IDN in forma Unicode, serve la forma punycode (xn--)
    param([string]$Token)
    $d = $Token.ToLower().Trim()
    $d = $d -replace '^mailto:', '' -replace '^https?://', '' -replace '^.*@', '' -replace '^\*?\.?', '' -replace '[/:?#].*$', '' -replace '^www\.', ''
    if ($d -match '^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9-]{2,}$') { return $d }
    return $null
}

function Get-VaglioDomini {
    # Da testo libero (a capo, virgole, spazi) a domini validi senza duplicati, più i token scartati.
    param([string[]]$Entrate)
    $validi = [System.Collections.Generic.List[string]]::new()
    $scartati = [System.Collections.Generic.List[string]]::new()
    foreach ($token in ($Entrate -join "`n") -split '[\s,;]+') {
        if (-not $token) { continue }
        $d = ConvertTo-VaglioDominio $token
        if (-not $d) { $scartati.Add($token); continue }
        if (-not $validi.Contains($d)) { $validi.Add($d) }
    }
    [pscustomobject]@{ Validi = $validi.ToArray(); Scartati = $scartati.ToArray() }
}

function Test-VaglioNormalizzazione {
    # Self-check: se la normalizzazione cambia comportamento, nulla tocca il server.
    $casi = @{
        'a.com'                   = 'a.com'
        'SPAM.it'                 = 'spam.it'
        'user@a.com'              = 'a.com'
        'mailto:user@a.com'       = 'a.com'
        '*.a.com'                 = 'a.com'
        'https://www.a.com/x?y=1' = 'a.com'
        'sotto.a.com'             = 'sotto.a.com'
        'non un dominio'          = $null
        'a'                       = $null
    }
    foreach ($k in $casi.Keys) {
        if ((ConvertTo-VaglioDominio $k) -ne $casi[$k]) { throw "Self-check fallito su '$k'." }
    }
}

function Invoke-VaglioRemoto {
    # Esegue lib/remote.sh sul server. Il payload va in base64 come argomento: niente quoting né BOM lungo la pipeline.
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$Prefs,
        [Parameter(Mandatory)][ValidateSet('ANTEPRIMA', 'APPLICA', 'VERIFICA')][string]$Modo,
        [string[]]$Domini = @()
    )
    $remoto = (Get-Content -Raw -LiteralPath $script:RemotoPath) -replace "`r", ''
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoto))
    $argDomini = if ($Domini) { $Domini -join ' ' } else { '' }
    $cmd = "echo $b64 | base64 -d | bash -s -- '$Prefs' $Modo $argDomini"
    $righe = @(ssh $Server $cmd 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { throw ('SSH non è riuscito: ' + ($righe -join ' ')) }
    return $righe
}

function ConvertFrom-VaglioRighe {
    # Dall'output remoto a oggetti per la GUI e la CLI. Ogni riga ha un tipo e un dominio.
    param([string[]]$Righe)
    foreach ($r in $Righe) {
        if ($r -match '^(GIA|NUOVO|PRESENTE|MANCANTE|SCRITTO) ?(\S*)$') {
            $stato = switch ($Matches[1]) {
                'GIA'      { 'Già presente' }
                'NUOVO'    { 'Nuovo' }
                'PRESENTE' { 'Presente' }
                'MANCANTE' { 'Mancante' }
                'SCRITTO'  { 'Scritto' }
            }
            [pscustomobject]@{ Stato = $stato; Dominio = $Matches[2]; Tipo = $Matches[1] }
        } elseif ($r -match '^ERRORE') {
            throw ($r -replace '^ERRORE\s*', '')
        }
    }
}

function Invoke-VaglioAnteprima {
    # Solo lettura: confronta i domini con il file sul server. Non scrive nulla.
    param([Parameter(Mandatory)][string]$Server, [Parameter(Mandatory)][string]$Prefs, [Parameter(Mandatory)][string[]]$Domini)
    @(ConvertFrom-VaglioRighe (Invoke-VaglioRemoto -Server $Server -Prefs $Prefs -Modo ANTEPRIMA -Domini $Domini))
}

function Invoke-VaglioScrittura {
    # Backup locale, scrittura remota (con backup remoto), poi rilettura: ogni dominio deve risultare presente.
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$Prefs,
        [Parameter(Mandatory)][string[]]$Domini,
        [Parameter(Mandatory)][string]$CartellaBackup
    )
    New-Item -ItemType Directory -Force -Path $CartellaBackup | Out-Null
    $copia = Join-Path $CartellaBackup ('prefs-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $esitoScp = & scp "${Server}:${Prefs}" $copia 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Backup locale fallito, nessuna modifica fatta. $esitoScp" }

    $scritti = @(ConvertFrom-VaglioRighe (Invoke-VaglioRemoto -Server $Server -Prefs $Prefs -Modo APPLICA -Domini $Domini) | Where-Object { $_.Tipo -eq 'SCRITTO' -or $_.Tipo -eq 'NUOVO' })
    if (-not ($scritti | Where-Object { $_.Tipo -eq 'SCRITTO' })) {
        # Nessun SCRITTO vuol dire che tutti i domini c'erano già: non è un errore.
        $nuovi = @($scritti | Where-Object { $_.Tipo -eq 'NUOVO' })
        if ($nuovi.Count -gt 0) { throw 'Il server non ha confermato la scrittura.' }
    }

    $verifica = @(ConvertFrom-VaglioRighe (Invoke-VaglioRemoto -Server $Server -Prefs $Prefs -Modo VERIFICA -Domini $Domini))
    $mancanti = @($verifica | Where-Object { $_.Tipo -eq 'MANCANTE' } | ForEach-Object { $_.Dominio })
    if ($mancanti) { throw ('Verifica fallita, non presenti sul server: ' + ($mancanti -join ', ')) }

    [pscustomobject]@{
        Backup     = $copia
        Verificati = $verifica.Count
        Aggiunti   = @($scritti | Where-Object { $_.Tipo -eq 'NUOVO' }).Count
    }
}

function Invoke-VaglioSuAccount {
    # Anteprima o scrittura su più account. Un errore su un account non ferma gli altri: ognuno ha il suo esito.
    param(
        [Parameter(Mandatory)][ValidateSet('Anteprima', 'Scrittura')][string]$Tipo,
        [Parameter(Mandatory)][object[]]$Account,
        [Parameter(Mandatory)][string[]]$Domini,
        [string]$CartellaBackup
    )
    foreach ($a in $Account) {
        try {
            if ($Tipo -eq 'Anteprima') {
                $righe = @(Invoke-VaglioAnteprima -Server $a.Server -Prefs $a.Prefs -Domini $Domini)
                [pscustomobject]@{ Account = $a.Nome; Ok = $true; Errore = ''; Righe = $righe; Esito = $null }
            } else {
                $cartella = Join-Path $CartellaBackup $a.Nome
                $esito = Invoke-VaglioScrittura -Server $a.Server -Prefs $a.Prefs -Domini $Domini -CartellaBackup $cartella
                [pscustomobject]@{ Account = $a.Nome; Ok = $true; Errore = ''; Righe = @(); Esito = $esito }
            }
        } catch {
            [pscustomobject]@{ Account = $a.Nome; Ok = $false; Errore = $_.Exception.Message; Righe = @(); Esito = $null }
        }
    }
}

function ConvertTo-VaglioRighePiatte {
    # Dagli esiti per account a un elenco unico, una riga per dominio, con la colonna Account. Un errore diventa una riga.
    param([object[]]$Esiti)
    foreach ($e in $Esiti) {
        if (-not $e.Ok) {
            [pscustomobject]@{ Account = $e.Account; Stato = 'Errore'; Dominio = $e.Errore; Tipo = 'ERRORE' }
            continue
        }
        foreach ($r in $e.Righe) {
            [pscustomobject]@{ Account = $e.Account; Stato = $r.Stato; Dominio = $r.Dominio; Tipo = $r.Tipo }
        }
    }
}

Test-VaglioNormalizzazione
