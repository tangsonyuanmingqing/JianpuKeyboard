param(
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$distDir = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path $repoRoot 'dist'
} else {
    [System.IO.Path]::GetFullPath($OutputDirectory)
}
$portablePath = Join-Path $distDir 'JianpuKeyboard-v1.6.0-windows-portable.zip'

Push-Location $repoRoot
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw "Windows Release 构建失败，退出码 $LASTEXITCODE；未生成安装包。"
    }

    $iscc = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($null -eq $iscc) {
        $candidates = @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
            'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
            'C:\Program Files\Inno Setup 6\ISCC.exe'
        )
        $isccPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($null -eq $isccPath) {
            throw '未找到 Inno Setup 6（ISCC.exe），无法生成安装包。'
        }
    } else {
        $isccPath = $iscc.Source
    }

    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    & $isccPath "/O$distDir" (Join-Path $PSScriptRoot 'jianpu_keyboard.iss')
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup 编译失败，退出码 $LASTEXITCODE；未生成便携包。"
    }

    $licenseDir = Join-Path $releaseDir 'licenses'
    New-Item -ItemType Directory -Path $licenseDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') `
        -Destination (Join-Path $licenseDir 'JianpuKeyboard-LICENSE.txt') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'assets\fonts\OFL-1.1.txt') `
        -Destination (Join-Path $licenseDir 'NotoSansCJK-OFL-1.1.txt') -Force

    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    Compress-Archive -Path (Join-Path $releaseDir '*') `
        -DestinationPath $portablePath -Force

    Get-FileHash (Join-Path $distDir 'JianpuKeyboard-v1.6.0-windows-*') `
        -Algorithm SHA256 | Format-Table -AutoSize
} finally {
    Pop-Location
}
