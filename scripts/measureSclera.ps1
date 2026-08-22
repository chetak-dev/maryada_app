Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile("D:\Extras\ISKBAM\Maryada Logo.png")
$w = $img.Width

# Red ring: centre (447,506) and (804,506), diameter 161.
foreach ($e in @(@{ n = 'LEFT'; cx = 447 }, @{ n = 'RIGHT'; cx = 804 })) {
  $cx = $e.cx; $cy = 506; $r = 85
  $bx1 = 99999; $bx2 = -1; $by1 = 99999; $by2 = -1
  for ($y = $cy - $r; $y -le $cy + $r; $y++) {
    for ($x = $cx - $r; $x -le $cx + $r; $x++) {
      $c = $img.GetPixel($x, $y)
      if ($c.R -gt 225 -and $c.G -gt 225 -and $c.B -gt 225) {
        if ($x -lt $bx1) { $bx1 = $x }
        if ($x -gt $bx2) { $bx2 = $x }
        if ($y -lt $by1) { $by1 = $y }
        if ($y -gt $by2) { $by2 = $y }
      }
    }
  }
  $d = [Math]::Max($bx2 - $bx1, $by2 - $by1)
  "{0} sclera: centre=({1},{2}) diameter={3}  fx={4:N4} fy={5:N4} fd={6:N4}" -f `
    $e.n, [int](($bx1 + $bx2) / 2), [int](($by1 + $by2) / 2), $d, `
    ((($bx1 + $bx2) / 2) / $w), ((($by1 + $by2) / 2) / $w), ($d / $w)
}
$img.Dispose()
