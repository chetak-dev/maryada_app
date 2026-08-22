Add-Type -AssemblyName System.Drawing
$src = "D:\Extras\ISKBAM\Maryada Logo.png"
$appDir = "c:\Users\CMY95QZ\StudioProjects\guardnest\parent_app"
$resRoot = Join-Path $appDir "android\app\src\main\res"
$assets = Join-Path $appDir "assets"
if (-not (Test-Path $assets)) { New-Item -ItemType Directory -Path $assets | Out-Null }

$orig = [System.Drawing.Bitmap]::FromFile($src)
# The wordmark's ascenders reach up to ~y=995; keep only the emblem above it.
$crop = New-Object System.Drawing.Rectangle 0, 0, $orig.Width, 985
$emblem = $orig.Clone($crop, $orig.PixelFormat)
$orig.Dispose()

# Drop the white card: clear only white reachable from a corner, so the white
# brows and eyes inside the shield survive.
$w = $emblem.Width; $h = $emblem.Height
$seen = New-Object 'bool[,]' $w, $h
$stack = New-Object System.Collections.Generic.Stack[int[]]
$stack.Push([int[]]@(0, 0)); $stack.Push([int[]]@(($w - 1), 0))
$stack.Push([int[]]@(0, ($h - 1))); $stack.Push([int[]]@(($w - 1), ($h - 1)))
while ($stack.Count -gt 0) {
  $p = $stack.Pop(); $x = $p[0]; $y = $p[1]
  if ($x -lt 0 -or $y -lt 0 -or $x -ge $w -or $y -ge $h) { continue }
  if ($seen[$x, $y]) { continue }
  $seen[$x, $y] = $true
  $c = $emblem.GetPixel($x, $y)
  if ($c.R -lt 232 -or $c.G -lt 232 -or $c.B -lt 232) { continue }
  $emblem.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
  $stack.Push([int[]]@(($x + 1), $y)); $stack.Push([int[]]@(($x - 1), $y))
  $stack.Push([int[]]@($x, ($y + 1))); $stack.Push([int[]]@($x, ($y - 1)))
}

# Trim the empty margin, then centre on a square so the mark never distorts.
$bx1 = $w; $bx2 = -1; $by1 = $h; $by2 = -1
for ($y = 0; $y -lt $h; $y++) {
  for ($x = 0; $x -lt $w; $x++) {
    if ($emblem.GetPixel($x, $y).A -gt 24) {
      if ($x -lt $bx1) { $bx1 = $x }
      if ($x -gt $bx2) { $bx2 = $x }
      if ($y -lt $by1) { $by1 = $y }
      if ($y -gt $by2) { $by2 = $y }
    }
  }
}
$cw = $bx2 - $bx1 + 1; $ch = $by2 - $by1 + 1
$side = [Math]::Max($cw, $ch)
$square = New-Object System.Drawing.Bitmap $side, $side
$g = [System.Drawing.Graphics]::FromImage($square)
$g.Clear([System.Drawing.Color]::Transparent)
$g.DrawImage($emblem, [int](($side - $cw) / 2), [int](($side - $ch) / 2), `
  (New-Object System.Drawing.Rectangle $bx1, $by1, $cw, $ch), [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$emblem.Dispose()
"trimmed emblem: ${cw}x${ch} -> square ${side}"

function Save-Png($size, $path) {
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $g2 = [System.Drawing.Graphics]::FromImage($bmp)
  $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g2.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g2.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g2.Clear([System.Drawing.Color]::Transparent)
  $g2.DrawImage($square, 0, 0, $size, $size)
  $g2.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  "{0} -> {1:N0} KB" -f (Split-Path $path -Leaf), ((Get-Item $path).Length / 1KB)
}

Save-Png 512 (Join-Path $assets "logo.png")

$sizes = @{ 'mipmap-mdpi' = 48; 'mipmap-hdpi' = 72; 'mipmap-xhdpi' = 96; 'mipmap-xxhdpi' = 144; 'mipmap-xxxhdpi' = 192 }
foreach ($d in $sizes.Keys) {
  $dir = Join-Path $resRoot $d
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  Save-Png $sizes[$d] (Join-Path $dir "ic_launcher.png")
}
$square.Dispose()
