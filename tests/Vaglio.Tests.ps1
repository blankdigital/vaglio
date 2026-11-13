# Test di Vaglio, senza dipendenze. Esegui: powershell -NoProfile -File tests\Vaglio.Tests.ps1
# Esce con codice 1 al primo gruppo che fallisce.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\Vaglio.Core.ps1')
. (Join-Path $PSScriptRoot '..\lib\Vaglio.Tema.ps1')
. (Join-Path $PSScriptRoot '..\lib\Vaglio.Config.ps1')
$env:VAGLIO_CONFIG_DIR = Join-Path ([IO.Path]::GetTempPath()) ('vaglio-test-' + [guid]::NewGuid().ToString('N'))

$script:Fallimenti = 0
function Assert-Uguale($atteso, $ottenuto, [string]$nome) {
    if ($atteso -eq $ottenuto) { Write-Host "  ok   $nome" }
    else { Write-Host "  FAIL ${nome}: atteso '$atteso', ottenuto '$ottenuto'"; $script:Fallimenti++ }
}
function Assert-Vero([bool]$cond, [string]$nome) {
    if ($cond) { Write-Host "  ok   $nome" } else { Write-Host "  FAIL $nome"; $script:Fallimenti++ }
}

# Luminanza relativa e rapporto di contrasto secondo WCAG 2.x.
function Get-Luminanza([string]$hex) {
    $c = @(0, 2, 4) | ForEach-Object { [Convert]::ToInt32($hex.Substring(1 + $_, 2), 16) / 255 }
    $lin = $c | ForEach-Object { if ($_ -le 0.03928) { $_ / 12.92 } else { [math]::Pow(($_ + 0.055) / 1.055, 2.4) } }
    0.2126 * $lin[0] + 0.7152 * $lin[1] + 0.0722 * $lin[2]
}
function Get-Contrasto([string]$a, [string]$b) {
    $la = Get-Luminanza $a; $lb = Get-Luminanza $b
    [math]::Round(([math]::Max($la, $lb) + 0.05) / ([math]::Min($la, $lb) + 0.05), 2)
}

Write-Host 'Normalizzazione domini'
$esame = Get-VaglioDomini @("SPAM.it, user@a.com`nmailto:x@b.org https://www.c.net/p ", 'non valido', 'a.com')
Assert-Uguale 'spam.it,a.com,b.org,c.net' (($esame.Validi) -join ',') 'domini validi, senza duplicati'
Assert-Uguale 'non,valido' (($esame.Scartati) -join ',') 'token scartati'

Write-Host 'Parsing output remoto'
$righe = ConvertFrom-VaglioRighe @('GIA a.com', 'NUOVO b.it', 'SCRITTO 1', 'PRESENTE c.net', 'MANCANTE d.org')
Assert-Uguale 'Già presente|Nuovo|Scritto|Presente|Mancante' (($righe | ForEach-Object Stato) -join '|') 'stati in italiano'
Assert-Vero ($null -ne ($righe | Where-Object { $_.Tipo -eq 'NUOVO' -and $_.Dominio -eq 'b.it' })) 'dominio nuovo riconosciuto'
try { ConvertFrom-VaglioRighe @('ERRORE file non trovato: /x') | Out-Null; Assert-Vero $false 'errore remoto lanciato' }
catch { Assert-Vero ($_.Exception.Message -match 'file non trovato') 'errore remoto lanciato con messaggio' }

foreach ($tema in 'chiaro', 'scuro') {
    Write-Host "Contrasti tema $tema"
    $p = Get-VaglioPalette -Tema $tema
    # Testo su sfondo: almeno 4,5:1 (WCAG 1.4.3)
    foreach ($coppia in @(@('Fg', 'Bg'), @('Fg', 'Surf'), @('Muted', 'Bg'), @('Muted', 'Surf'), @('OnAcc', 'Acc'), @('Err', 'Bg'), @('Ok', 'Bg'), @('SelFg', 'Sel'), @('Fg', 'Hov'))) {
        $c = Get-Contrasto $p[$coppia[0]] $p[$coppia[1]]
        Assert-Vero ($c -ge 4.5) "$($coppia[0]) su $($coppia[1]): $c (min 4,5)"
    }
    # Bordi, anelli di focus e colore d'azione: almeno 3:1 (WCAG 1.4.11)
    foreach ($coppia in @(@('Border', 'Surf'), @('Border', 'Bg'), @('Focus', 'Bg'), @('Focus', 'Surf'), @('Acc', 'Bg'))) {
        $c = Get-Contrasto $p[$coppia[0]] $p[$coppia[1]]
        Assert-Vero ($c -ge 3) "$($coppia[0]) su $($coppia[1]): $c (min 3)"
    }
}

Write-Host 'Palette e XAML'
$stiliXaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot '..\lib\Vaglio.Stili.xaml')
$finestre = 'Vaglio.xaml', 'Vaglio.Gestione.xaml', 'Vaglio.Blacklist.xaml'
$tuttiToken = @()
foreach ($file in $finestre) {
    $xaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot "..\lib\$file")
    $tuttiToken += [regex]::Matches($xaml + $stiliXaml, '__(\w+)__') | ForEach-Object { $_.Groups[1].Value }
}
$tuttiToken = @($tuttiToken | Where-Object { $_ -ne 'STILI' } | Sort-Object -Unique)
$mancanti = @($tuttiToken | Where-Object { -not (Get-VaglioPalette -Tema chiaro).ContainsKey($_) })
Assert-Uguale 0 $mancanti.Count 'ogni token dei XAML esiste nella palette'

Write-Host 'Finestre WPF'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
foreach ($tema in 'chiaro', 'scuro') {
    $p = Get-VaglioPalette -Tema $tema
    foreach ($file in $finestre) {
        $xaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot "..\lib\$file")
        $xaml = $xaml.Replace('__STILI__', $stiliXaml)
        foreach ($k in $p.Keys) { $xaml = $xaml.Replace("__${k}__", $p[$k]) }
        $ok = $true
        try { $finestra = [System.Windows.Markup.XamlReader]::Parse($xaml) } catch { $ok = $false; $errore = $_.Exception.Message }
        Assert-Vero $ok "$file ($tema) si legge come WPF$(if (-not $ok) { ': ' + $errore })"
        if ($ok) {
            Assert-Vero ($finestra.Language.IetfLanguageTag -eq 'it-IT') "$file ($tema) lingua it-IT"
            $haElenco = ($null -ne $finestra.FindName('LstAccount')) -or ($null -ne $finestra.FindName('LstGest')) -or ($null -ne $finestra.FindName('LstVoci'))
            Assert-Vero $haElenco "$file ($tema) ha un elenco"
        }
    }
}

Write-Host 'Account salvati'
Assert-Uguale 0 @(Get-VaglioAccounts).Count 'nessun file: lista vuota'
Save-VaglioAccount -Account ([pscustomobject]@{ Nome = 'sito-a'; Server = 'alias-a'; Prefs = '~/.spamassassin/user_prefs' })
Save-VaglioAccount -Account ([pscustomobject]@{ Nome = 'sito-b'; Server = 'user@b.example'; Prefs = '~/x/prefs' })
$letti = @(Get-VaglioAccounts)
Assert-Uguale 'sito-a,sito-b' (($letti | ForEach-Object Nome) -join ',') 'salvataggio e rilettura'
Assert-Uguale 'user@b.example' (($letti | Where-Object Nome -eq 'sito-b').Server) 'server salvato come scritto'
$errDoppio = $null; try { Save-VaglioAccount -Account ([pscustomobject]@{ Nome = 'sito-a'; Server = 'x'; Prefs = 'y' }) } catch { $errDoppio = $_.Exception.Message }
Assert-Vero ($errDoppio -match 'Esiste già') 'nome duplicato rifiutato'
$errSpazi = $null; try { Save-VaglioAccount -Account ([pscustomobject]@{ Nome = 'nuovo'; Server = 'con spazio'; Prefs = 'y' }) } catch { $errSpazi = $_.Exception.Message }
Assert-Vero ($errSpazi -match 'spazi') 'server con spazi rifiutato'
Save-VaglioAccount -Account ([pscustomobject]@{ Nome = 'sito-c'; Server = 'alias-c'; Prefs = 'p' }) -NomeOriginale 'sito-b'
Assert-Uguale 'sito-a,sito-c' ((@(Get-VaglioAccounts) | ForEach-Object Nome) -join ',') 'rinomina sostituisce, non duplica'
Remove-VaglioAccount -Nome 'sito-c'
Assert-Uguale 'sito-a' ((@(Get-VaglioAccounts) | ForEach-Object Nome) -join ',') 'rimozione'
Set-Content -LiteralPath (Get-VaglioConfigPath) -Value '{ rotto' -Encoding utf8
$errCorrotto = $null; try { Get-VaglioAccounts | Out-Null } catch { $errCorrotto = $_.Exception.Message }
Assert-Vero ($errCorrotto -match 'non si legge') 'file corrotto segnalato'
Assert-Uguale '{ rotto' ((Get-Content -Raw -LiteralPath (Get-VaglioConfigPath)).Trim()) 'file corrotto non sovrascritto'

Write-Host 'Righe per account'
$piatte = @(ConvertTo-VaglioRighePiatte @(
    [pscustomobject]@{ Account = 'a'; Ok = $true; Errore = ''; Righe = @([pscustomobject]@{ Stato = 'Nuovo'; Dominio = 'x.it'; Tipo = 'NUOVO' }) },
    [pscustomobject]@{ Account = 'b'; Ok = $false; Errore = 'SSH non è riuscito'; Righe = @() }))
Assert-Uguale 'a:Nuovo:x.it|b:Errore:SSH non è riuscito' (($piatte | ForEach-Object { "$($_.Account):$($_.Stato):$($_.Dominio)" }) -join '|') 'un errore è una riga, non interrompe'

Write-Host ''
if ($script:Fallimenti -gt 0) { Write-Host "$($script:Fallimenti) test falliti"; exit 1 }
Write-Host 'Tutti i test passati.'
