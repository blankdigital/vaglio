#requires -Version 5.1
# copy-guard: ignore (i literal con accenti sono output da verificare, non testo rivolto all'utente)
# Test end-to-end della CLI su più account. Servono Git bash e la cartella temporanea.
# SSH e SCP sono simulati: eseguono bash in locale sui file di prova, ignorando l'alias del server.
# Esegui: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Vaglio.E2E.ps1
$ErrorActionPreference = 'Stop'
$bash = 'C:/Program Files/Git/bin/bash.exe'
if (-not (Test-Path $bash)) { Write-Host 'Git bash non trovato: test saltato.'; exit 0 }

$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ('vaglio-e2e-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
$env:VAGLIO_CONFIG_DIR = Join-Path $work 'config'

# Percorsi POSIX per bash: /c/Users/... invece di C:/Users/...
function ConvertTo-Posix([string]$p) { '/' + $p.Substring(0, 1).ToLower() + $p.Substring(2).Replace('\', '/') }

$fileA = Join-Path $work 'a-prefs'; $fileB = Join-Path $work 'b-prefs'
Set-Content -LiteralPath $fileA -Value "required_score 5`nblacklist_from *@vecchio.com" -Encoding utf8 -NoNewline
Set-Content -LiteralPath $fileB -Value "required_score 5" -Encoding utf8
$mancante = Join-Path $work 'non-esiste'

# Simulazione: il primo argomento (alias) viene ignorato, il comando gira in locale.
function ssh { & 'C:/Program Files/Git/bin/bash.exe' -c $args[1]; $global:LASTEXITCODE = $LASTEXITCODE }
function scp { $src = $args[0] -replace '^[^:]+:', ''; & 'C:/Program Files/Git/bin/bash.exe' -c "cp '$src' '$($args[1])'"; $global:LASTEXITCODE = $LASTEXITCODE }

$cli = Join-Path $root 'vaglio.ps1'
$fallimenti = 0
function Check([bool]$cond, [string]$nome) {
    if ($cond) { Write-Host "  ok   $nome" } else { Write-Host "  FAIL $nome"; $script:fallimenti++ }
}

Write-Host 'Salvataggio account dalla CLI'
& $cli -Salva -Nome sito-a -Server alias-a -Prefs (ConvertTo-Posix $fileA)
& $cli -Salva -Nome sito-b -Server alias-b -Prefs (ConvertTo-Posix $fileB)
& $cli -Salva -Nome sito-rotto -Server alias-c -Prefs (ConvertTo-Posix $mancante)
$elenco = & $cli -Elenca | Out-String
Check ($elenco -match 'sito-a' -and $elenco -match 'sito-b' -and $elenco -match 'sito-rotto') 'tre account visibili con -Elenca'

Write-Host 'Anteprima su tutti, con un account rotto'
$out = & $cli -Tutti -Domain 'spam.com' *>&1 | Out-String
$codice = $LASTEXITCODE
Check ($out -match 'sito-a' -and $out -match 'sito-b') 'anteprima mostra gli account funzionanti'
Check ($out -match 'sito-rotto' -and $out -match 'ERRORE') 'account rotto segnalato in anteprima'
Check ($codice -eq 1) 'codice di uscita 1 se un account fallisce'
Check ((Get-Content -Raw $fileA) -notmatch 'spam\.com') 'anteprima non ha scritto'

Write-Host 'Scrittura solo sugli account con domini nuovi'
$out = & $cli -Tutti -Domain 'spam.com,vecchio.com' -Apply -BackupDir (Join-Path $work 'bk') *>&1 | Out-String
$codice = $LASTEXITCODE
Check ((Get-Content -Raw $fileA) -match 'blacklist_from \*@spam\.com') 'account A ha ricevuto spam.com'
Check ((Get-Content -Raw $fileB) -match 'blacklist_from \*@spam\.com') 'account B ha ricevuto spam.com'
Check ((Get-Content -Raw $fileA) -match 'blacklist_from \*@vecchio\.com' -and ([regex]::Matches((Get-Content -Raw $fileA), 'vecchio\.com')).Count -eq 1) 'vecchio.com non duplicato su A'
Check ((Get-ChildItem (Join-Path $work 'bk') -Recurse -File).Count -ge 2) 'copia locale per account prima della scrittura'
Check ($out -match 'sito-a' -and $out -match 'sito-b') 'esito riportato per ogni account scritto'
Check ($codice -eq 1) 'l''account rotto resta segnalato con codice 1'

Write-Host 'Rilancio: nessun duplicato'
& $cli -Account sito-a -Domain 'spam.com' -Apply -BackupDir (Join-Path $work 'bk') | Out-Null
Check (([regex]::Matches((Get-Content -Raw $fileA), 'spam\.com')).Count -eq 1) 'nessuna riga duplicata'

Write-Host 'Destinazione ad hoc, senza salvataggio'
& $cli -Server alias-x -Prefs (ConvertTo-Posix $fileB) -Domain 'ad-hoc.net' | Out-Null
$elencoDopo = & $cli -Elenca | Out-String
Check ($elencoDopo -notmatch 'alias-x') 'ad hoc non entra negli account salvati'

Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
Write-Host ''
if ($fallimenti -gt 0) { Write-Host "$fallimenti controlli falliti"; exit 1 }
Write-Host 'Tutti i controlli end-to-end passati.'
