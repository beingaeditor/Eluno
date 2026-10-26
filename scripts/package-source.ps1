$ErrorActionPreference = 'Stop'
$elunoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$staging = Join-Path $elunoRoot ('.eluno-local/source-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging -Force | Out-Null
$roots = @('apps','packages','scripts','tests','prototype','docs','.github')
foreach ($rootName in $roots) {
    $sourceRoot = Join-Path $elunoRoot $rootName
    Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force | Where-Object {
        $relative = $_.FullName.Substring($elunoRoot.Length + 1)
        $relative -notmatch '(^|[\\/])(build|\.gradle|node_modules)([\\/]|$)' -and
        $_.Name -ne 'local.properties' -and $_.Extension -notin @('.jks','.keystore','.pem','.p12','.log')
    } | ForEach-Object {
        $relative = $_.FullName.Substring($elunoRoot.Length + 1)
        $destination = Join-Path $staging $relative
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination
    }
}
foreach ($name in @('README.md','PROJECT_PLAN.md','package.json','package-lock.json','.gitignore')) {
    Copy-Item -LiteralPath (Join-Path $elunoRoot $name) -Destination (Join-Path $staging $name)
}
New-Item -ItemType Directory -Path (Join-Path $elunoRoot 'release') -Force | Out-Null
$archive = Join-Path $elunoRoot 'release/Eluno-0.2.0-source.zip'
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $archive -Force
Write-Output $archive
