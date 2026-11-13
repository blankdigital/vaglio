#requires -Version 5.1
# Test end-to-end delle voci della blacklist: lettura, eliminazione, modifica. Servono Git bash.
# SSH e SCP sono simulati in locale. Esegui: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Vaglio.Voci.E2E.ps1
$ErrorActionPreference = 'Stop'
$bash = 'C:/Program Files/Git/bin/bash.exe'
if (-not (Test-Path $bash)) { Write-Host 'Git bash non trovato: test saltato.'; exit 0 }

$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ('vaglio-voci-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
$env:VAGLIO_CONFIG_DIR = Join-Path $work 'config'

function ConvertTo-Posix([string]$p) { '/' + $p.Substring(0, 1).ToLower() + $p.Substring(2).Replace('\', '/') }

$file = Join-Path $work 'prefs'
$contenuto = @(
    'required_score 5',
    'blacklist_from *@vecchio.com',
    'blacklist_from *@doppio.net',
    'blacklist_from *@doppio.net',
    'blacklist_from user@indirizzo.it',
    'score SPAM_RULE 2.0'
)
Set-Content -LiteralPath $file -Value $contenuto -Encoding utf8

# Simulazione: l'alias viene ignorato e il comando gira in locale.
function ssh { & 'C:/Program Files/Git/bin/bash.exe' -c $args[1]; $global:LASTEXITCODE = $LASTEXITCODE }
function scp { $src = $args[0] -replace '^[^:]+:', ''; & 'C:/Program Files/Git/bin/bash.exe' -c "cp '$src' '$($args[1])'"; $global:LASTEXITCODE = $LASTEXITCODE }

$cli = Join-Path $root 'vaglio.ps1'
$fallimenti = 0
function Check([bool]$cond, [string]$nome) {
    if ($cond) { Write-Host "  ok   $nome" } else { Write-Host "  FAIL $nome"; $script:fallimenti++ }
}
function Testo-File { (Get-Content -LiteralPath $file) -join "`n" }

& $cli -Salva -Nome sito-bl -Server alias-bl -Prefs (ConvertTo-Posix $file) | Out-Null

Write-Host 'Lettura'
$voci = @(& $cli -Account sito-bl -Lista)
Check ($voci.Count -eq 4) 'quattro voci blacklist_from lette'
Check (@($voci | Where-Object Modificabile).Count -eq 3) 'tre voci in forma *@dominio modificabili'
Check (@($voci | Where-Object { -not $_.Modificabile -and $_.Testo -match 'indirizzo' }).Count -eq 1) 'indirizzo singolo non modificabile'

Write-Host 'Eliminazione: anteprima non scrive'
$prima = Testo-File
& $cli -Account sito-bl -Elimina -Domain 'doppio.net' | Out-Null
Check ((Testo-File) -eq $prima) 'senza -Apply il file resta invariato'

Write-Host 'Eliminazione con -Apply'
$out = & $cli -Account sito-bl -Elimina -Domain 'doppio.net' -Apply -BackupDir (Join-Path $work 'bk') *>&1 | Out-String
$dopo = Testo-File
Check ($dopo -notmatch 'doppio\.net') 'entrambi i duplicati eliminati'
Check ($dopo -match 'vecchio\.com' -and $dopo -match 'indirizzo\.it' -and $dopo -match 'SPAM_RULE') 'le altre righe restano intatte'
Check (@(Get-ChildItem (Join-Path $work 'bk\sito-bl') -File).Count -ge 1) 'copia locale creata prima dell''eliminazione'
Check ($out -match 'eliminate 2 voci') 'esito riporta due voci eliminate'
Check (@(Get-ChildItem -Path $work -Filter 'prefs.bak-*').Count -ge 1) 'backup remoto prefs.bak-* creato accanto al file'

Write-Host 'Modifica'
& $cli -Account sito-bl -Modifica -Domain 'vecchio.com' -NuovoDominio 'nuovo.org' | Out-Null
Check ((Testo-File) -match 'vecchio\.com') 'anteprima della modifica: file ancora con il vecchio dominio'
& $cli -Account sito-bl -Modifica -Domain 'vecchio.com' -NuovoDominio 'nuovo.org' -Apply -BackupDir (Join-Path $work 'bk') | Out-Null
Check ((Testo-File) -match 'blacklist_from \*@nuovo\.org') 'voce modificata nel nuovo dominio'
Check ((Testo-File) -notmatch 'vecchio\.com') 'vecchio dominio sparito'
Check ((Testo-File) -match 'indirizzo\.it') 'voce non modificabile intatta'

Write-Host 'Casi di errore'
$errore = $null
try { & $cli -Account sito-bl -Modifica -Domain 'assente.com' -NuovoDominio 'x.com' -Apply -BackupDir (Join-Path $work 'bk') | Out-Null } catch { $errore = $_.Exception.Message }
Check ($errore -match 'Nessuna voce') 'modifica di una voce inesistente rifiutata'
$errore = $null
try { & $cli -Account sito-bl -Modifica -Domain 'nuovo.org' -NuovoDominio 'non valido' -Apply | Out-Null } catch { $errore = $_.Exception.Message }
Check ($errore -match 'non è un dominio valido') 'dominio nuovo non valido rifiutato'
$errore = $null
try { & $cli -Lista | Out-Null } catch { $errore = $_.Exception.Message }
Check ($errore -match 'un solo account') 'senza account, il comando si ferma'

Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
Write-Host ''
if ($fallimenti -gt 0) { Write-Host "$fallimenti controlli falliti"; exit 1 }
Write-Host 'Tutti i controlli sulle voci passati.'
