[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [string]$FlutterExecutable = 'flutter',
    [string]$InnoSetupCompiler = ''
)

$ErrorActionPreference = 'Stop'

function Invoke-PackagingCommand {
    param([string]$Executable, [string[]]$Arguments, [string]$Step)
    # Native stderr is diagnostic output, not the command's exit status.
    # Routing both streams through PowerShell also makes Transcript retain them.
    $ErrorActionPreference = 'Continue'
    & $Executable @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "$Step 失败，退出码 $LASTEXITCODE；打包未完成。"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$packageStartedAt = Get-Date
$distDir = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path (Join-Path (Join-Path $repoRoot 'dist') $packageStartedAt.ToString('yyyy-MM-dd')) $packageStartedAt.ToString('HH-mm')
} else {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
}
$portablePath = Join-Path $distDir 'JianpuKeyboard-v1.6.1-windows-portable.zip'
$setupPath = Join-Path $distDir 'JianpuKeyboard-v1.6.1-windows-setup.exe'
$checksumPath = Join-Path $distDir 'SHA256SUMS.txt'
$logPath = Join-Path $distDir ('build-' + $packageStartedAt.ToString('yyyyMMdd-HHmmss-fff') + '.log')
$transcriptStarted = $false

New-Item -ItemType Directory -Path $distDir -Force | Out-Null
Push-Location $repoRoot
try {
    Start-Transcript -LiteralPath $logPath | Out-Null
    $transcriptStarted = $true
    Write-Host "输出目录：$distDir"
    Write-Host "构建日志：$logPath"

    $flutter = Get-Command $FlutterExecutable -CommandType Application,ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $flutter) {
        throw "Flutter executable not found: $FlutterExecutable。请将 Flutter bin 加入 PATH，或通过 -FlutterExecutable 指定 flutter.bat 的完整路径。"
    }

    if (-not [string]::IsNullOrWhiteSpace($InnoSetupCompiler)) {
        $iscc = Get-Command $InnoSetupCompiler -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $iscc) { throw "未找到 Inno Setup 编译器：$InnoSetupCompiler" }
        $isccPath = $iscc.Source
    } else {
        $iscc = Get-Command 'ISCC.exe' -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $iscc) {
            $isccPath = $iscc.Source
        } else {
            $candidates = @(
                (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
                'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
                'C:\Program Files\Inno Setup 6\ISCC.exe'
            )
            $isccPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if ($null -eq $isccPath) {
                throw '未找到 Inno Setup 6（ISCC.exe），无法生成安装包。'
            }
        }
    }

    Write-Host '[1/3] 构建 Windows Release...'
    Invoke-PackagingCommand -Executable $flutter.Source `
        -Arguments @('build', 'windows', '--release') -Step 'Windows Release 构建'
    if (-not (Test-Path -LiteralPath (Join-Path $releaseDir 'jianpu_keyboard.exe') -PathType Leaf)) {
        throw 'Flutter 未生成 Windows Release 可执行文件，停止打包。'
    }

    Write-Host '[2/3] 生成安装包...'
    Invoke-PackagingCommand -Executable $isccPath `
        -Arguments @("/O$distDir", (Join-Path $PSScriptRoot 'jianpu_keyboard.iss')) -Step 'Inno Setup 编译'
    if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
        throw "Inno Setup 未生成预期安装包：$setupPath"
    }

    Write-Host '[3/3] 生成便携包与 SHA-256...'
    $licenseDir = Join-Path $releaseDir 'licenses'
    New-Item -ItemType Directory -Path $licenseDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') `
        -Destination (Join-Path $licenseDir 'JianpuKeyboard-LICENSE.txt') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'assets\fonts\OFL-1.1.txt') `
        -Destination (Join-Path $licenseDir 'NotoSansCJK-OFL-1.1.txt') -Force

    Compress-Archive -Path (Join-Path $releaseDir '*') `
        -DestinationPath $portablePath -Force
    if (-not (Test-Path -LiteralPath $portablePath -PathType Leaf)) {
        throw "未生成便携包：$portablePath"
    }

    $hashes = @(Get-FileHash -LiteralPath $setupPath,$portablePath -Algorithm SHA256)
    $hashes | ForEach-Object {
        $_.Hash + '  ' + [System.IO.Path]::GetFileName($_.Path)
    } | Set-Content -LiteralPath $checksumPath -Encoding Ascii
    Write-Host '打包完成：'
    foreach ($hash in $hashes) {
        Write-Host $hash.Path
        Write-Host "SHA-256: $($hash.Hash)"
    }
    Write-Host "校验文件：$checksumPath"
} catch {
    Write-Warning "打包失败：$($_.Exception.Message)"
    if ($transcriptStarted) { Write-Warning "详细日志：$logPath" }
    throw
} finally {
    try {
        if ($transcriptStarted) { Stop-Transcript | Out-Null }
    } finally {
        Pop-Location
    }
}
