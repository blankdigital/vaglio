# Vaglio, interfaccia grafica. Avvio: doppio clic su Vaglio.cmd, oppure
#   powershell -STA -File vaglio-gui.ps1

# WPF richiede un thread STA. Se lo script arriva in MTA, si riavvia con -STA.
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $PSCommandPath
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
. (Join-Path $PSScriptRoot 'lib\Vaglio.Core.ps1')
. (Join-Path $PSScriptRoot 'lib\Vaglio.Config.ps1')
. (Join-Path $PSScriptRoot 'lib\Vaglio.Tema.ps1')

$script:Palette = Get-VaglioPalette

# Carica una finestra: inserisce gli stili condivisi e i colori del tema, poi la legge come XAML.
function New-VaglioFinestra([string]$file) {
    $xaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot "lib\$file")
    $stili = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'lib\Vaglio.Stili.xaml')
    $xaml = $xaml.Replace('__STILI__', $stili)
    foreach ($chiave in $script:Palette.Keys) { $xaml = $xaml.Replace("__${chiave}__", $script:Palette[$chiave]) }
    [System.Windows.Markup.XamlReader]::Parse($xaml)
}

function Get-Controlli($finestra, [string[]]$nomi) {
    $mappa = @{}
    foreach ($n in $nomi) { $mappa[$n] = $finestra.FindName($n) }
    $mappa
}

$win = New-VaglioFinestra 'Vaglio.xaml'
$ui = Get-Controlli $win @('LstAccount', 'TxtAccountVuoto', 'BtnGestisci', 'RbUno', 'RbAlcuni', 'RbTutti',
    'TxtDestinazione', 'TxtDomini', 'BtnAnteprima', 'BtnScrivi', 'TxtErrore', 'LstEsito', 'TxtStato', 'TxtBackup', 'BtnChiudi')

$cartellaBackup = Join-Path $HOME 'Vaglio-backup'
$ui.TxtBackup.Text = "Copie di sicurezza in: $cartellaBackup"

# Stato della sessione. Cambiare account, destinazione o domini invalida l'anteprima.
$script:Ultima = $null
$script:Occupato = $false
$script:Accounts = @()

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
    foreach ($c in @($ui.BtnAnteprima, $ui.BtnGestisci, $ui.RbUno, $ui.RbAlcuni, $ui.RbTutti, $ui.LstAccount)) { $c.IsEnabled = -not $on }
    $ui.BtnScrivi.IsEnabled = (-not $on) -and ($null -ne $script:Ultima) -and ($script:Ultima.DaScrivere.Count -gt 0)
    $win.Cursor = if ($on) { [System.Windows.Input.Cursors]::Wait } else { $null }
}

function Invalidate-Anteprima {
    if ($script:Occupato) { return }
    if ($script:Ultima) {
        $script:Ultima = $null
        $ui.BtnScrivi.IsEnabled = $false
        Set-Stato 'Hai cambiato i dati. Rifai l''anteprima prima di scrivere.'
    }
}

function Update-Accounts {
    try {
        $script:Accounts = @(Get-VaglioAccounts)
    } catch {
        Show-Errore $_.Exception.Message $null
        $script:Accounts = @()
    }
    $ui.LstAccount.ItemsSource = $script:Accounts
    $ui.TxtAccountVuoto.Visibility = if ($script:Accounts) { 'Collapsed' } else { 'Visible' }
    Set-Modalita
}

# Destinazione: un solo server, alcuni, o tutti. Con "Tutti" l'elenco è bloccato su tutti gli account.
function Set-Modalita {
    if ($ui.RbUno.IsChecked) {
        $ui.LstAccount.SelectionMode = 'Single'
        $ui.LstAccount.IsEnabled = $true
        $ui.TxtDestinazione.Text = 'Seleziona un account nell''elenco.'
        if ($ui.LstAccount.SelectedItems.Count -gt 1) { $ui.LstAccount.SelectedItems.Clear(); $ui.LstAccount.SelectedIndex = 0 }
    } elseif ($ui.RbAlcuni.IsChecked) {
        $ui.LstAccount.SelectionMode = 'Extended'
        $ui.LstAccount.IsEnabled = $true
        $ui.TxtDestinazione.Text = 'Scegli più account con Spazio oppure Ctrl+clic.'
    } else {
        $ui.LstAccount.SelectionMode = 'Extended'
        $ui.LstAccount.IsEnabled = $false
        $ui.LstAccount.SelectAll()
        $ui.TxtDestinazione.Text = "Tutti gli account salvati ($($script:Accounts.Count))."
    }
}

function Get-Destinazioni {
    if ($ui.RbTutti.IsChecked) { return @($script:Accounts) }
    return @($ui.LstAccount.SelectedItems | ForEach-Object { $_ })
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
            @{ Ok = $true; Dati = @(Invoke-VaglioSuAccount -Tipo $tipo -Account $p.Account -Domini $p.Domini -CartellaBackup $p.Cartella) }
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

$ui.LstAccount.Add_SelectionChanged({ Invalidate-Anteprima })
$ui.TxtDomini.Add_TextChanged({ Invalidate-Anteprima })
foreach ($r in @($ui.RbUno, $ui.RbAlcuni, $ui.RbTutti)) {
    $r.Add_Checked({ Set-Modalita; Invalidate-Anteprima })
}

$ui.BtnAnteprima.Add_Click({
    Hide-Errore
    $destinazioni = Get-Destinazioni
    if (-not $script:Accounts) { Show-Errore 'Nessun account salvato. Premi Gestisci account per aggiungerne uno.' $ui.BtnGestisci; return }
    if (-not $destinazioni) { Show-Errore 'Scegli almeno un account nell''elenco.' $ui.LstAccount; return }
    $esame = Get-VaglioDomini @($ui.TxtDomini.Text)
    if (-not $esame.Validi) { Show-Errore 'Nessun dominio valido. Controlla il testo dei domini.' $ui.TxtDomini; return }

    $avviso = if ($esame.Scartati) { ' Non sono domini e vengono ignorati: ' + ($esame.Scartati -join ', ') + '.' } else { '' }
    $domini = $esame.Validi
    Set-Occupato $true
    Set-Stato ('Controllo su ' + $destinazioni.Count + ' account in corso.' + $avviso)
    Start-VaglioLavoro -Tipo 'Anteprima' -Parametri @{ Account = $destinazioni; Domini = $domini } -AllaFine {
        param($r)
        Set-Occupato $false
        if (-not $r.Ok) { Show-Errore $r.Errore $ui.LstAccount; return }
        $esiti = @($r.Dati)
        $righe = @(ConvertTo-VaglioRighePiatte $esiti)
        $ui.LstEsito.ItemsSource = $righe
        $daScrivere = @($esiti | Where-Object { $_.Ok -and (@($_.Righe | Where-Object { $_.Tipo -eq 'NUOVO' })).Count -gt 0 } | ForEach-Object { $_.Account })
        $nuovi = @($righe | Where-Object { $_.Tipo -eq 'NUOVO' }).Count
        $presenti = @($righe | Where-Object { $_.Tipo -eq 'GIA' }).Count
        $fallite = @($esiti | Where-Object { -not $_.Ok } | ForEach-Object { $_.Account })
        $script:Ultima = [pscustomobject]@{ Destinazioni = $destinazioni; Domini = $domini; DaScrivere = $daScrivere }
        $ui.BtnScrivi.IsEnabled = ($daScrivere.Count -gt 0)
        $testo = "Anteprima: $nuovi nuovi, $presenti già presenti, su $($esiti.Count) account. Non è stato scritto nulla."
        if ($fallite) { $testo += ' Non raggiungibili: ' + ($fallite -join ', ') + '.' }
        Set-Stato ($testo + $avviso)
    }.GetNewClosure()
})

$ui.BtnScrivi.Add_Click({
    if (-not $script:Ultima -or $script:Ultima.DaScrivere.Count -eq 0) { return }
    $u = $script:Ultima
    $daAccount = @($u.Destinazioni | Where-Object { $u.DaScrivere -contains $_.Nome })
    $elenco = ($daAccount | ForEach-Object { $_.Nome }) -join ', '
    $testo = "Scrivo i domini nuovi su $($daAccount.Count) account: $elenco.`nPer ogni account copio prima il file user_prefs, in locale e sul server."
    $scelta = [System.Windows.MessageBox]::Show($win, $testo, 'Confermi la scrittura?', 'YesNo', 'Question', 'No')
    if ($scelta -ne 'Yes') { Set-Stato 'Scrittura annullata. Non è stato scritto nulla.'; return }

    Hide-Errore
    Set-Occupato $true
    Set-Stato ('Scrittura in corso su ' + $daAccount.Count + ' account.')
    Start-VaglioLavoro -Tipo 'Scrittura' -Parametri @{ Account = $daAccount; Domini = $u.Domini; Cartella = $cartellaBackup } -AllaFine {
        param($r)
        Set-Occupato $false
        if (-not $r.Ok) { Show-Errore $r.Errore $ui.LstAccount; return }
        $esiti = @($r.Dati)
        $righe = @($esiti | ForEach-Object {
            if ($_.Ok) {
                [pscustomobject]@{ Account = $_.Account; Stato = 'Scritto'; Dominio = "$($_.Esito.Verificati) domini verificati sul server, $($_.Esito.Aggiunti) aggiunti" }
            } else {
                [pscustomobject]@{ Account = $_.Account; Stato = 'Errore'; Dominio = $_.Errore }
            }
        })
        $ui.LstEsito.ItemsSource = $righe
        $script:Ultima = $null
        $ui.BtnScrivi.IsEnabled = $false
        $ko = @($esiti | Where-Object { -not $_.Ok })
        $testo = "Scrittura completata su $($esiti.Count - $ko.Count) di $($esiti.Count) account. Copie locali in: $cartellaBackup. Rifai l'anteprima per aggiornare l'elenco."
        if ($ko) { $testo += ' Errori: ' + (($ko | ForEach-Object { $_.Account }) -join ', ') + '.' }
        Set-Stato $testo
    }.GetNewClosure()
})

$ui.BtnGestisci.Add_Click({ Open-Gestione })

# Finestra di gestione: elenco in alto, modulo sotto. Ogni salvataggio va subito nel file degli account.
function Open-Gestione {
    $script:GestWin = New-VaglioFinestra 'Vaglio.Gestione.xaml'
    $script:G = Get-Controlli $script:GestWin @('LstGest', 'BtnNuovo', 'TxtNome', 'TxtServerG', 'TxtPrefsG',
        'BtnSalva', 'BtnElimina', 'TxtGestErrore', 'TxtGestStato', 'BtnGestChiudi')
    $script:GestEditing = $null
    $script:GestWin.Owner = $win

    function script:Gest-Ricarica([string]$selezione) {
        $lista = @(Get-VaglioAccounts)
        $script:G.LstGest.ItemsSource = $lista
        if ($selezione) {
            $voce = $lista | Where-Object { $_.Nome -eq $selezione } | Select-Object -First 1
            if ($voce) { $script:G.LstGest.SelectedItem = $voce }
        }
    }
    function script:Gest-Errore([string]$testo, $controllo) {
        $script:G.TxtGestErrore.Text = $testo
        $script:G.TxtGestErrore.Visibility = 'Visible'
        $script:G.TxtGestStato.Text = ''
        if ($controllo) { [void]$controllo.Focus() }
    }
    function script:Gest-Pulisci {
        $script:G.TxtGestErrore.Visibility = 'Collapsed'
        $script:G.TxtGestErrore.Text = ''
    }

    $script:G.LstGest.Add_SelectionChanged({
        $sel = $script:G.LstGest.SelectedItem
        if ($sel) {
            $script:GestEditing = $sel.Nome
            $script:G.TxtNome.Text = $sel.Nome
            $script:G.TxtServerG.Text = $sel.Server
            $script:G.TxtPrefsG.Text = $sel.Prefs
            $script:G.BtnElimina.IsEnabled = $true
            Gest-Pulisci
        }
    })

    $script:G.BtnNuovo.Add_Click({
        $script:GestEditing = $null
        $script:G.LstGest.SelectedItem = $null
        $script:G.TxtNome.Text = ''
        $script:G.TxtServerG.Text = ''
        $script:G.TxtPrefsG.Text = '~/.spamassassin/user_prefs'
        $script:G.BtnElimina.IsEnabled = $false
        $script:G.TxtGestStato.Text = 'Nuovo account: compila i campi e premi Salva.'
        Gest-Pulisci
        [void]$script:G.TxtNome.Focus()
    })

    $script:G.BtnSalva.Add_Click({
        Gest-Pulisci
        $nuovo = [pscustomobject]@{
            Nome   = $script:G.TxtNome.Text.Trim()
            Server = $script:G.TxtServerG.Text.Trim()
            Prefs  = $script:G.TxtPrefsG.Text.Trim()
        }
        try {
            Save-VaglioAccount -Account $nuovo -NomeOriginale $script:GestEditing
            $script:GestEditing = $nuovo.Nome
            $script:G.BtnElimina.IsEnabled = $true
            Gest-Ricarica $nuovo.Nome
            $script:G.TxtGestStato.Text = "Account salvato: $($nuovo.Nome)."
        } catch {
            Gest-Errore $_.Exception.Message $script:G.TxtNome
        }
    })

    $script:G.BtnElimina.Add_Click({
        if (-not $script:GestEditing) { return }
        $nome = $script:GestEditing
        $scelta = [System.Windows.MessageBox]::Show($script:GestWin, "Elimino l'account «$nome» dall'elenco di Vaglio?`nIl server non viene toccato.", 'Confermi l''eliminazione?', 'YesNo', 'Question', 'No')
        if ($scelta -ne 'Yes') { return }
        Remove-VaglioAccount -Nome $nome
        $script:GestEditing = $null
        $script:G.TxtNome.Text = ''
        $script:G.TxtServerG.Text = ''
        $script:G.TxtPrefsG.Text = ''
        $script:G.BtnElimina.IsEnabled = $false
        Gest-Ricarica $null
        $script:G.TxtGestStato.Text = "Account eliminato: $nome."
    })

    $script:G.BtnGestChiudi.Add_Click({ $script:GestWin.Close() })

    Gest-Ricarica $null
    [void]$script:GestWin.ShowDialog()
    Update-Accounts
}

$ui.BtnChiudi.Add_Click({ $win.Close() })

$win.Add_Loaded({ Update-Accounts })
Set-Stato 'Scegli gli account, scrivi i domini e premi Anteprima. Nulla viene scritto senza conferma.'
[void]$win.ShowDialog()
