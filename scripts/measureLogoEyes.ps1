Add-Type -AssemblyName System.Drawing
$src = "D:\Extras\ISKBAM\Maryada Logo.png"
$img = [System.Drawing.Bitmap]::FromFile($src)
$w = $img.Width; $h = $img.Height

function Measure-Red($x0, $x1, $y0, $y1) {
  $minX = [int]($w * $x0); $maxX = [int]($w * $x1)
  $minY = [int]($h * $y0); $maxY = [int]($h * $y1)
  $bx1 = 99999; $bx2 = -1; $by1 = 99999; $by2 = -1
  for ($y = $minY; $y -lt $maxY; $y++) {
    for ($x = $minX; $x -lt $maxX; $x++) {
      $c = $img.GetPixel($x, $y)
      if ($c.R -gt 150 -and $c.G -lt 90 -and $c.B -lt 90) {
        if ($x -lt $bx1) { $bx1 = $x }
        if ($x -gt $bx2) { $bx2 = $x }
        if ($y -lt $by1) { $by1 = $y }
        if ($y -gt $by2) { $by2 = $y }
      }
    }
  }
  if ($bx2 -lt 0) { return $null }
  return [pscustomobject]@{ x1 = $bx1; x2 = $bx2; y1 = $by1; y2 = $by2 }
}

foreach ($e in @(
    @{ n = 'LEFT'; x0 = 0.25; x1 = 0.46 },
    @{ n = 'RIGHT'; x0 = 0.54; x1 = 0.75 })) {
  $r = Measure-Red $e.x0 $e.x1 0.31 0.49
  if ($null -ne $r) {
    $cx = ($r.x1 + $r.x2) / 2.0; $cy = ($r.y1 + $r.y2) / 2.0
    $d = [Math]::Max($r.x2 - $r.x1, $r.y2 - $r.y1)
    "{0}: centre=({1},{2}) diameter={3}  fx={4:N4} fy={5:N4} fd={6:N4}" -f `
      $e.n, [int]$cx, [int]$cy, $d, ($cx / $w), ($cy / $h), ($d / $w)
  } else { "$($e.n): no red found" }
}
"image: $w x $h"
$img.Dispose()
