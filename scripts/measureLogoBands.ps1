Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile("D:\Extras\ISKBAM\Maryada Logo.png")
$w = $img.Width; $h = $img.Height
# Count non-white pixels per row to find the gap between the emblem and the
# wordmark underneath it.
$prev = -1
for ($y = 0; $y -lt $h; $y += 4) {
  $n = 0
  for ($x = 0; $x -lt $w; $x += 3) {
    $c = $img.GetPixel($x, $y)
    if ($c.A -gt 40 -and ($c.R -lt 232 -or $c.G -lt 232 -or $c.B -lt 232)) { $n++ }
  }
  $filled = if ($n -gt 2) { 1 } else { 0 }
  if ($filled -ne $prev) { "y=$y  ->  $(if($filled){'CONTENT'}else{'blank'})  (n=$n)" ; $prev = $filled }
}
"image: $w x $h"
$img.Dispose()
