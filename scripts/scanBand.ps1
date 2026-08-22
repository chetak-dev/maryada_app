Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile("D:\Extras\ISKBAM\Maryada Logo.png")
for ($y = 880; $y -lt 1140; $y += 5) {
  $n = 0
  for ($x = 0; $x -lt $img.Width; $x++) {
    $c = $img.GetPixel($x, $y)
    if ($c.R -lt 232 -or $c.G -lt 232 -or $c.B -lt 232) { $n++ }
  }
  "y=$y n=$n"
}
$img.Dispose()
