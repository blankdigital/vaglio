# Palette di Vaglio. Due temi, scelti in base alla modalità di Windows (chiaro o scuro).
# Ogni coppia testo/sfondo è verificata in tests/Vaglio.Tests.ps1: contrasto testo almeno 4,5:1,
# componenti e bordi almeno 3:1 (WCAG 2.2, criteri 1.4.3, 1.4.11).

$script:PaletteChiaro = @{
    Bg     = '#F7F6F2'   # fondo finestra, carta calda
    Surf   = '#FFFFFF'   # campi e liste
    Fg     = '#1C1B18'   # testo principale
    Muted  = '#55544D'   # testo di aiuto
    Acc    = '#1F5C4A'   # azione principale, verde bosco
    OnAcc  = '#FFFFFF'   # testo sopra l'azione principale
    Border = '#6E6C64'   # bordi dei campi e dei componenti
    Focus  = '#1C1B18'   # anello del focus da tastiera
    Ok     = '#1F5C4A'
    Err    = '#9B2318'
}

$script:PaletteScuro = @{
    Bg     = '#161714'
    Surf   = '#21221E'
    Fg     = '#ECEBE4'
    Muted  = '#B3B2A8'
    Acc    = '#8FD1B4'
    OnAcc  = '#0E1F18'
    Border = '#8F8E85'
    Focus  = '#ECEBE4'
    Ok     = '#8FD1B4'
    Err    = '#FF9A8A'
}

function Get-VaglioTema {
    # 'chiaro' o 'scuro', dalla preferenza di sistema. Se la chiave manca, si usa il chiaro.
    try {
        $v = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop
        if ($v -eq 0) { return 'scuro' }
        return 'chiaro'
    } catch {
        return 'chiaro'
    }
}

function Get-VaglioPalette {
    param([ValidateSet('chiaro', 'scuro')][string]$Tema = (Get-VaglioTema))
    if ($Tema -eq 'scuro') { $script:PaletteScuro } else { $script:PaletteChiaro }
}
