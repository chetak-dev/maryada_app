Add-Type -AssemblyName System.Drawing
$src = "D:\Extras\ISKBAM\Maryada Logo.png"
$resRoot = "c:\Users\CMY95QZ\StudioProjects\guardnest\parent_app\android\app\src\main\res"
$img = [System.Drawing.Bitmap]::FromFile($src)

# Launcher icons keep the artwork's white card: the mark is dark, so a
# transparent icon would vanish against a dark wallpaper.
$sizes = @{ 'mipmap-mdpi' = 48; 'mipmap-hdpi' = 72; 'mipmap-xhdpi' = 96; 'mipmap-xxhdpi' = 144; 'mipmap-xxxhdpi' = 192 }
foreach ($d in $sizes.Keys) {
  $size = $sizes[$d]
  $dir = Join-Path $resRoot $d
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::White)
  $g.DrawImage($img, 0, 0, $size, $size)
  $g.Dispose()
  $out = Join-Path $dir "ic_launcher.png"
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  "{0}/ic_launcher.png  {1}x{1}  {2:N0} KB" -f $d, $size, ((Get-Item $out).Length / 1KB)
}
$img.Dispose()
