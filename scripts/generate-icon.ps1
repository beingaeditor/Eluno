Add-Type -AssemblyName System.Drawing
$elunoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bitmap = New-Object System.Drawing.Bitmap 256,256
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::FromArgb(23,98,76))
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(245,244,236)),24
$graphics.DrawArc($pen,60,55,136,146,35,300)
$graphics.DrawLine($pen,62,126,191,126)
$graphics.Dispose()
$pen.Dispose()
$stream = New-Object System.IO.MemoryStream
$bitmap.Save($stream,[System.Drawing.Imaging.ImageFormat]::Png)
$png = $stream.ToArray()
$bitmap.Dispose()
$stream.Dispose()
$file = [System.IO.File]::Create((Join-Path $elunoRoot 'apps/desktop/icon.ico'))
$writer = New-Object System.IO.BinaryWriter $file
$writer.Write([UInt16]0); $writer.Write([UInt16]1); $writer.Write([UInt16]1)
$writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0)
$writer.Write([UInt16]1); $writer.Write([UInt16]32); $writer.Write([UInt32]$png.Length); $writer.Write([UInt32]22)
$writer.Write($png)
$writer.Dispose()
Write-Output 'Generated apps/desktop/icon.ico from the Eluno monogram.'
