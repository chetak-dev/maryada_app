Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$src = "C:\Users\CMY95QZ\Downloads\logo_30kb.png"
$root = "c:\Users\CMY95QZ\StudioProjects\guardnest"
$img = [System.Drawing.Bitmap]::FromFile($src)

function New-Png([int]$size, [string]$out, [double]$scale = 1.0, [bool]$white = $false) {
  $dir = Split-Path $out -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  if ($white) { $g.Clear([System.Drawing.Color]::White) } else { $g.Clear([System.Drawing.Color]::Transparent) }
  $inner = [int]($size * $scale)
  $off = [int](($size - $inner) / 2)
  $g.DrawImage($img, $off, $off, $inner, $inner)
  $g.Dispose()
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  "{0}  {1}x{1}  {2:N0} KB" -f $out.Replace($root, ''), $size, ((Get-Item $out).Length / 1KB)
}

# Parent app in-app logo.
New-Png 512 "$root\parent_app\assets\logo.png"

# Parent launcher icons — transparent, the artwork ships its own backdrop.
$mips = @{ 'mipmap-mdpi' = 48; 'mipmap-hdpi' = 72; 'mipmap-xhdpi' = 96; 'mipmap-xxhdpi' = 144; 'mipmap-xxxhdpi' = 192 }
foreach ($d in $mips.Keys) {
  New-Png $mips[$d] "$root\parent_app\android\app\src\main\res\$d\ic_launcher.png"
}

# Web console icons.
New-Png 32  "$root\parent_app\web\favicon.png"
New-Png 192 "$root\parent_app\web\icons\Icon-192.png"
New-Png 512 "$root\parent_app\web\icons\Icon-512.png"
New-Png 192 "$root\parent_app\web\icons\Icon-maskable-192.png" 0.78
New-Png 512 "$root\parent_app\web\icons\Icon-maskable-512.png" 0.78

# Child app launcher icons + manifest icon.
foreach ($d in $mips.Keys) {
  New-Png $mips[$d] "$root\child_android\app\src\main\res\$d\ic_launcher.png"
}

# Child block screen (native overlay drawable + HTML asset).
New-Png 512 "$root\child_android\app\src\main\res\drawable\maryada_logo.png"
New-Png 512 "$root\child_android\app\src\main\assets\logo.png"

$img.Dispose()
"done"
