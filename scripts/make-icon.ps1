# Genera assets/vaglio.ico: una V bianca su fondo verde bosco, colore d'accento di Vaglio.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\make-icon.ps1
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$uscita = Join-Path $root 'assets\vaglio.ico'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $uscita) | Out-Null

$misure = 16, 32, 48, 256
$png = @{}
foreach ($s in $misure) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml('#1F5C4A'))
    $font = New-Object System.Drawing.Font('Segoe UI', [single]($s * 0.62), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $formato = New-Object System.Drawing.StringFormat
    $formato.Alignment = 'Center'
    $formato.LineAlignment = 'Center'
    $area = New-Object System.Drawing.RectangleF 0, 0, $s, $s
    $g.DrawString('V', $font, [System.Drawing.Brushes]::White, $area, $formato)
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $png[$s] = $ms.ToArray()
    $ms.Dispose(); $font.Dispose(); $formato.Dispose(); $g.Dispose(); $bmp.Dispose()
}

# Formato ICO con immagini PNG (supportato da Windows Vista in poi).
$fs = [IO.File]::Create($uscita)
$w = New-Object IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$misure.Count)
$offset = 6 + 16 * $misure.Count
foreach ($s in $misure) {
    $dim = if ($s -ge 256) { 0 } else { $s }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$png[$s].Length); $w.Write([uint32]$offset)
    $offset += $png[$s].Length
}
foreach ($s in $misure) { $w.Write($png[$s]) }
$w.Close(); $fs.Close()
"icona scritta: $uscita"
