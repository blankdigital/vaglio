# Vaglio, interfaccia grafica. Avvio: doppio clic su Vaglio.cmd, oppure
#   powershell -STA -File vaglio-gui.ps1

# WPF richiede un thread STA. Se lo script arriva in MTA, si riavvia con -STA.
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $PSCommandPath
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
. (Join-Path $PSScriptRoot 'lib\Vaglio.Core.ps1')
. (Join-Path $PSScriptRoot 'lib\Vaglio.Tema.ps1')

$palette = Get-VaglioPalette
$xaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'lib\Vaglio.xaml')
foreach ($chiave in $palette.Keys) { $xaml = $xaml.Replace("__${chiave}__", $palette[$chiave]) }

$win = [System.Windows.Markup.XamlReader]::Parse($xaml)
$ui = @{}
foreach ($nome in 'TxtServer', 'TxtPrefs', 'TxtDomini', 'BtnAnteprima', 'BtnScrivi', 'BtnChiudi',
                   'LstEsito', 'TxtErrore', 'TxtStato', 'TxtBackup') {
    $ui[$nome] = $win.FindName($nome)
}

$cartellaBackup = Join-Path $HOME 'Vaglio-backup'
$ui.TxtBackup.Text = "Copie di sicurezza in: $cartellaBackup"

# Stato della sessione: l'ultima anteprima valida. Cambiare un campo la invalida.
$script:Ultima = $null
$script:Occupato = $false

function Set-Stato([string]$testo) { $ui.TxtStato.Text = $testo }

function Show-Errore([string]$testo, $controllo) {
    $ui.TxtErrore.Text = $testo
    $ui.TxtErrore.Visibility = 'Visible'
    Set-Stato ('Errore: ' + $testo)
    if ($controllo) { [void]$controllo.Focus() }
}

function Hide-Errore {
    $ui.TxtErrore.Text = ''
    $ui.TxtErrore.Visibility = 'Collapsed'
}

function Set-Occupato([bool]$on) {
    $script:Occupato = $on
    $ui.BtnAnteprima.IsEnabled = -not $on
    $ui.BtnScrivi.IsEnabled = (-not $on) -and ($null -ne $script:Ultima) -and ($script:Ultima.Nuovi -gt 0)
    $win.Cursor = if ($on) { [System.Windows.Input.Cursors]::Wait } else { $null }
}

function Get-Input {
    $prefs = $ui.TxtPrefs.Text.Trim()
    if (-not $prefs) { $prefs = '~/.spamassassin/user_prefs' }
    $esame = Get-VaglioDomini @($ui.TxtDomini.Text)
    [pscustomobject]@{
        Server   = $ui.TxtServer.Text.Trim()
        Prefs    = $prefs
        Domini   = $esame.Validi
        Scartati = $esame.Scartati
    }
}

# Lavoro sul server in un runspace separato: la finestra resta reattiva durante ssh.
function Start-VaglioLavoro {
    param([string]$Tipo, [hashtable]$Parametri, [scriptblock]$AllaFine)
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($core, $tipo, $p)
        try {
            . $core
            if ($tipo -eq 'Anteprima') {
                @{ Ok = $true; Dati = @(Invoke-VaglioAnteprima -Server $p.Server -Prefs $p.Prefs -Domini $p.Domini) }
            } else {
                @{ Ok = $true; Dati = (Invoke-VaglioScrittura -Server $p.Server -Prefs $p.Prefs -Domini $p.Domini -CartellaBackup $p.Cartella) }
            }
        } catch {
            @{ Ok = $false; Errore = $_.Exception.Message }
        }
    }).AddArgument((Join-Path $PSScriptRoot 'lib\Vaglio.Core.ps1')).AddArgument($Tipo).AddArgument($Parametri)

    $handle = $ps.BeginInvoke()
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        if (-not $handle.IsCompleted) { return }
        $timer.Stop()
        $out = @($ps.EndInvoke($handle))
        $ps.Dispose()
        $rs.Close()
        $rs.Dispose()
        & $AllaFine ($out | Select-Object -First 1)
    }.GetNewClosure())
    $timer.Start()
}

# Qualsiasi modifica ai campi rende l'anteprima non più valida: non si può scrivere su una vecchia.
$cambio = {
    if ($script:Occupato) { return }
    if ($script:Ultima) {
        $script:Ultima = $null
        $ui.BtnScrivi.IsEnabled = $false
        Set-Stato 'Hai cambiato i dati. Rifai l''anteprima prima di scrivere.'
    }
}
$ui.TxtServer.Add_TextChanged($cambio)
$ui.TxtPrefs.Add_TextChanged($cambio)
$ui.TxtDomini.Add_TextChanged($cambio)

$ui.BtnAnteprima.Add_Click({
    Hide-Errore
    $in = Get-Input
    if (-not $in.Server) { Show-Errore 'Inserisci il server SSH.' $ui.TxtServer; return }
    if (-not $in.Domini) { Show-Errore 'Nessun dominio valido. Controlla il testo dei domini.' $ui.TxtDomini; return }

    $avviso = if ($in.Scartati) { ' Non sono domini e vengono ignorati: ' + ($in.Scartati -join ', ') + '.' } else { '' }
    Set-Occupato $true
    Set-Stato ('Controllo sul server in corso.' + $avviso)
    Start-VaglioLavoro -Tipo 'Anteprima' -Parametri @{ Server = $in.Server; Prefs = $in.Prefs; Domini = $in.Domini } -AllaFine {
        param($r)
        Set-Occupato $false
        if (-not $r.Ok) {
            $script:Ultima = $null
            $ui.LstEsito.ItemsSource = $null
            Show-Errore $r.Errore $ui.TxtServer
            return
        }
        $righe = @($r.Dati)
        $nuovi = @($righe | Where-Object { $_.Tipo -eq 'NUOVO' }).Count
        $ui.LstEsito.ItemsSource = $righe
        $script:Ultima = [pscustomobject]@{ Server = $in.Server; Prefs = $in.Prefs; Domini = $in.Domini; Nuovi = $nuovi }
        $ui.BtnScrivi.IsEnabled = ($nuovi -gt 0)
        Set-Stato ("Anteprima: $nuovi nuovi, $($righe.Count - $nuovi) già presenti. Non è stato scritto nulla." + $avviso)
    }.GetNewClosure()
})

$ui.BtnScrivi.Add_Click({
    if (-not $script:Ultima) { return }
    $u = $script:Ultima
    $testo = "Scrivo $($u.Nuovi) domini nuovi su $($u.Server).`nPrima copio il file user_prefs in locale e sul server."
    $scelta = [System.Windows.MessageBox]::Show($win, $testo, 'Confermi la scrittura?', 'YesNo', 'Question', 'No')
    if ($scelta -ne 'Yes') { Set-Stato 'Scrittura annullata. Non è stato scritto nulla.'; return }

    Hide-Errore
    Set-Occupato $true
    Set-Stato 'Scrittura sul server in corso.'
    Start-VaglioLavoro -Tipo 'Scrittura' -Parametri @{ Server = $u.Server; Prefs = $u.Prefs; Domini = $u.Domini; Cartella = $cartellaBackup } -AllaFine {
        param($r)
        Set-Occupato $false
        if (-not $r.Ok) {
            Show-Errore $r.Errore $ui.TxtServer
            return
        }
        $d = $r.Dati
        $script:Ultima = $null
        $ui.BtnScrivi.IsEnabled = $false
        Set-Stato "Scritto e verificato: $($d.Verificati) domini presenti sul server, $($d.Aggiunti) aggiunti. Copia locale: $($d.Backup). Rifai l'anteprima per aggiornare l'elenco."
    }.GetNewClosure()
})

$ui.BtnChiudi.Add_Click({ $win.Close() })

Set-Stato 'Compila i campi e premi Anteprima. Nulla viene scritto senza una conferma.'
[void]$win.ShowDialog()
