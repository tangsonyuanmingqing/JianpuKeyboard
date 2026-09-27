param()

$ErrorActionPreference = 'Stop'
$packScript = Join-Path $PSScriptRoot 'build_windows_release.ps1'
$packSourceBytes = [System.IO.File]::ReadAllBytes($packScript)
if ($packSourceBytes.Length -lt 3 -or
    $packSourceBytes[0] -ne 0xEF -or
    $packSourceBytes[1] -ne 0xBB -or
    $packSourceBytes[2] -ne 0xBF) {
    throw 'Regression: packaging script must have a UTF-8 BOM for Windows PowerShell 5.1.'
}

$packTokens = $null
$packErrors = $null
$packAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $packScript, [ref]$packTokens, [ref]$packErrors)
if ($packErrors.Count -gt 0) { throw ($packErrors | Out-String) }

$packOutputAssignment = $packAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$distDir'
}, $true)
if ($null -eq $packOutputAssignment) { throw 'Output directory seam is missing.' }
$packOutputResolver = [scriptblock]::Create($packOutputAssignment.Extent.Text)
$repoRoot = Split-Path -Parent $PSScriptRoot
$packageStartedAt = [datetime]::new(2026, 9, 27, 16, 7, 0)
$OutputDirectory = ''
. $packOutputResolver
$packExpected = Join-Path $repoRoot 'dist\2026-09-27\16-07'
if ($distDir -ne $packExpected) { throw 'Default output must use the start date and zero-padded 24-hour minute.' }

$OutputDirectory = Join-Path $repoRoot 'build\installer-tests\custom-output'
. $packOutputResolver
if ($distDir -ne $OutputDirectory) { throw 'Explicit absolute output directory must remain unchanged.' }

Push-Location $PSScriptRoot
try {
    $OutputDirectory = '.\build\installer-tests\custom-output'
    . $packOutputResolver
    $packExpected = Join-Path $PSScriptRoot 'build\installer-tests\custom-output'
    if ($distDir -ne $packExpected) {
        throw 'Relative output must follow the PowerShell current location, not the process startup directory.'
    }
} finally {
    Pop-Location
}

$packProbeDirectory = Join-Path $repoRoot ('build\installer-tests\missing-flutter-' + [guid]::NewGuid().ToString('N'))
$packExpectedFailure = $false
try {
    & $packScript -OutputDirectory $packProbeDirectory -FlutterExecutable '__missing_flutter_packaging_probe__'
} catch {
    if ($_.Exception.Message -notmatch 'Flutter executable not found') { throw }
    $packExpectedFailure = $true
}
if (-not $packExpectedFailure) { throw 'Missing Flutter must stop packaging.' }
if (-not (Test-Path -LiteralPath $packProbeDirectory -PathType Container)) {
    throw 'Failure must leave a visible output directory.'
}
$packLogs = @(Get-ChildItem -LiteralPath $packProbeDirectory -Filter 'build-*.log')
if ($packLogs.Count -ne 1) { throw 'Failure must retain a build log.' }
if (@(Get-ChildItem -LiteralPath $packProbeDirectory -File -Recurse |
    Where-Object { $_.Extension -in @('.exe', '.zip') }).Count -gt 0) {
    throw 'Preflight failure must not create delivery artifacts.'
}

$packCommandDefinition = $packAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Invoke-PackagingCommand'
}, $true)
if ($null -eq $packCommandDefinition) { throw 'Native command logging seam is missing.' }
. ([scriptblock]::Create($packCommandDefinition.Extent.Text))
$packNativeLog = Join-Path $packProbeDirectory 'native-streams.log'
$packNativeFailure = $false
Start-Transcript -LiteralPath $packNativeLog | Out-Null
try {
    try {
        Invoke-PackagingCommand -Executable (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
            -Arguments @('-NoProfile', '-Command', "[Console]::Out.WriteLine('pack-stdout-probe'); [Console]::Error.WriteLine('pack-stderr-probe'); exit 7") `
            -Step 'test-native-command'
    } catch {
        if ($_.Exception.Message -notmatch '7') { throw }
        $packNativeFailure = $true
    }
    Invoke-PackagingCommand -Executable (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
        -Arguments @('-NoProfile', '-Command', "[Console]::Error.WriteLine('pack-success-stderr-probe'); exit 0") `
        -Step 'test-success-with-stderr'
} finally { Stop-Transcript | Out-Null }
if (-not $packNativeFailure) { throw 'Native nonzero exit must stop packaging.' }
$packNativeLogText = Get-Content -LiteralPath $packNativeLog -Raw
foreach ($packExpectedLine in @('pack-stdout-probe', 'pack-stderr-probe', 'pack-success-stderr-probe')) {
    if ($packNativeLogText -notmatch $packExpectedLine) { throw "Missing native log output: $packExpectedLine" }
}

Write-Output 'PASS: BOM, parser, date-time/absolute/relative paths, preflight failure, native exit codes and both log streams.'
