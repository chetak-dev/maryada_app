Add-Type -AssemblyName System.Drawing
$src = "D:\Extras\ISKBAM\Maryada Logo.png"
$outDir = "c:\Users\CMY95QZ\StudioProjects\guardnest\parent_app\assets"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$img = [System.Drawing.Bitmap]::FromFile($src)

# The eyelid must match the dark face behind the eyes, so sample just under the
# left eye ring (measured centre 447,506 with diameter 161).
foreach ($y in @(600, 620, 640)) {
  foreach ($x in @(447, 520, 627)) {
    $c = $img.GetPixel($x, $y)
    "sample ($x,$y) = #{0:X2}{1:X2}{2:X2}" -f $c.R, $c.G, $c.B
  }
}

$size = 512
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)
$g.DrawImage($img, 0, 0, $size, $size)
$g.Dispose()
$img.Dispose()

# The artwork sits on a white card. Clear only white connected to a corner, so
# the white brows and eyes inside the shield survive.
$w = $bmp.Width; $h = $bmp.Height
$seen = New-Object 'bool[,]' $w, $h
$stack = New-Object System.Collections.Generic.Stack[int[]]
$stack.Push([int[]]@(0, 0))
$stack.Push([int[]]@(($w - 1), 0))
$stack.Push([int[]]@(0, ($h - 1)))
$stack.Push([int[]]@(($w - 1), ($h - 1)))
$cleared = 0
while ($stack.Count -gt 0) {
  $p = $stack.Pop(); $x = $p[0]; $y = $p[1]
  if ($x -lt 0 -or $y -lt 0 -or $x -ge $w -or $y -ge $h) { continue }
  if ($seen[$x, $y]) { continue }
  $seen[$x, $y] = $true
  $c = $bmp.GetPixel($x, $y)
  if ($c.R -lt 232 -or $c.G -lt 232 -or $c.B -lt 232) { continue }
  $bmp.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
  $cleared++
  $stack.Push([int[]]@(($x + 1), $y))
  $stack.Push([int[]]@(($x - 1), $y))
  $stack.Push([int[]]@($x, ($y + 1)))
  $stack.Push([int[]]@($x, ($y - 1)))
}
$out = Join-Path $outDir "logo.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"cleared $cleared background pixels"
"logo.png -> {0:N0} KB" -f ((Get-Item $out).Length / 1KB)
