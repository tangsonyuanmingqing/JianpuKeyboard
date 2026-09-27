param(
    [ValidateRange(1, 10)]
    [int]$Runs = 3,
    [ValidateSet('default-valid', 'default-errors', 'large-valid', 'large-errors')]
    [string]$Scenario = 'default-valid',
    [string]$FlutterExecutable = 'flutter'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$reportDirectory = Join-Path $repoRoot 'build\performance'
$runPrefix = "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$Scenario"
$previousRunName = $env:UI_PERFORMANCE_RUN
$operationNames = @('input', 'selection', 'vertical_scroll', 'horizontal_scroll', 'undo')

try {
    $existingMutex = [System.Threading.Mutex]::OpenExisting('Local\JianpuKeyboard.SingleInstance')
    $existingMutex.Dispose()
    throw '请先保存并正常关闭 Jianpu Keyboard；单实例锁会阻止性能测试程序启动。'
} catch [System.Threading.WaitHandleCannotBeOpenedException] {
    # No running application owns the single-instance mutex.
}

function Get-PerformanceDistribution {
    param([double[]]$Values)
    if ($Values.Count -eq 0) { throw '性能样本为空。' }
    $sorted = @($Values | Sort-Object)
    return [ordered]@{
        sample_count = $sorted.Count
        p50_ms = $sorted[[int][Math]::Ceiling($sorted.Count * 0.50) - 1]
        p95_ms = $sorted[[int][Math]::Ceiling($sorted.Count * 0.95) - 1]
        max_ms = $sorted[-1]
    }
}

function Get-SourceHashes {
    $paths = @(
        'integration_test\smart_grid_performance_test.dart',
        'test_driver\smart_grid_performance_driver.dart',
        'tools\run_windows_ui_performance.ps1',
        'pubspec.lock'
    ) + @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'lib') -Recurse -Filter '*.dart' |
        ForEach-Object { $_.FullName.Substring($repoRoot.Length + 1) })
    return @($paths | Sort-Object | ForEach-Object {
        [ordered]@{
            path = $_
            sha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot $_) -Algorithm SHA256).Hash
        }
    })
}

Push-Location -LiteralPath $repoRoot
try {
    $flutterVersion = (& $FlutterExecutable --version --machine | Out-String | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0) { throw '无法读取 Flutter 版本。' }
    $sourceHashes = Get-SourceHashes
    $reports = @()
    $runResults = @()
    for ($runIndex = 1; $runIndex -le $Runs; $runIndex++) {
        $env:UI_PERFORMANCE_RUN = "$runPrefix-run$runIndex"
        Write-Output "Windows UI performance $Scenario run $runIndex/$Runs"
        & $FlutterExecutable drive --profile -d windows `
            --driver=test_driver/smart_grid_performance_driver.dart `
            --target=integration_test/smart_grid_performance_test.dart `
            --dart-define="UI_PERFORMANCE_SCENARIO=$Scenario" `
            --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
        $runExitCode = $LASTEXITCODE
        $reportPath = Join-Path $reportDirectory "smart_grid_ui_performance_$($env:UI_PERFORMANCE_RUN).json"
        if (-not (Test-Path -LiteralPath $reportPath)) {
            throw "本轮没有产生实测报告（退出码 $runExitCode）：$reportPath"
        }
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        if ($report.validation_only -eq $true) {
            throw "仅验证操作链路的报告不能用于性能验收：$reportPath"
        }
        if ($report.enhanced_tracing -eq $true -or $report.scenario -ne $Scenario -or
            $report.expected_error_count -ne $report.observed_error_count) {
            throw "场景或错误格覆盖不一致：$reportPath"
        }
        if ($reports.Count -gt 0) {
            foreach ($field in @('physical_width', 'physical_height', 'device_pixel_ratio',
                    'table_scale_percent', 'panel_width', 'panel_height')) {
                if ($report.$field -ne $reports[0].$field) {
                    throw "同场景各轮配置不一致：$field。证据保留在 $reportPath"
                }
            }
        }
        foreach ($operationName in $operationNames) {
            if (-not $report.operations.$operationName) {
                throw "本轮操作覆盖不完整：$operationName。已有证据保留在 $reportPath"
            }
            if ($report.operations.$operationName.response.sample_count -ne 50) {
                throw "正式样本数不完整：$operationName。已有证据保留在 $reportPath"
            }
        }
        $reports += $report
        $runResults += [ordered]@{
            run = $runIndex
            report_file = Split-Path -Leaf $reportPath
            exit_code = $runExitCode
            passed = ($runExitCode -eq 0 -and $report.passed -eq $true)
        }
    }

    $operations = [ordered]@{}
    foreach ($operationName in $operationNames) {
        $responseSamples = @()
        $buildSamples = @()
        $rasterSamples = @()
        $runP95 = @()
        foreach ($report in $reports) {
            $operation = $report.operations.$operationName
            $responseSamples += $operation.response.samples_ms
            $buildSamples += $operation.build.samples_ms
            $rasterSamples += $operation.raster.samples_ms
            $runP95 += $operation.response.p95_ms
        }
        $response = Get-PerformanceDistribution -Values $responseSamples
        $operations[$operationName] = [ordered]@{
            response = $response
            build = Get-PerformanceDistribution -Values $buildSamples
            raster = Get-PerformanceDistribution -Values $rasterSamples
            per_run_p95_ms = $runP95
            passed = ($response.p95_ms -lt 100 -and @($runP95 | Where-Object { $_ -ge 100 }).Count -eq 0)
        }
    }
    $sourceUnchanged = (($sourceHashes | ConvertTo-Json -Depth 5 -Compress) -eq
        ((Get-SourceHashes) | ConvertTo-Json -Depth 5 -Compress))
    $summary = [ordered]@{
        recorded_at = (Get-Date).ToUniversalTime().ToString('o')
        cpu = (Get-CimInstance Win32_Processor).Name.Trim()
        gpus = @((Get-CimInstance Win32_VideoController).Name)
        ram_bytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
        os = (Get-CimInstance Win32_OperatingSystem).Caption
        os_version = (Get-CimInstance Win32_OperatingSystem).Version
        flutter = $flutterVersion
        grid_rows = 100
        grid_columns = 100
        scenario = $Scenario
        expected_error_count = $reports[0].expected_error_count
        observed_error_counts = @($reports | ForEach-Object { $_.observed_error_count })
        warmup_per_operation_per_run = 10
        samples_per_operation_per_run = 50
        budget_ms = 100
        percentile_method = 'nearest rank, ceil(n * 0.95)'
        measurement = $reports[0].measurement
        ui_configurations = @($reports | ForEach-Object {
            [ordered]@{
                physical_width = $_.physical_width
                physical_height = $_.physical_height
                device_pixel_ratio = $_.device_pixel_ratio
                table_scale_percent = $_.table_scale_percent
                panel_width = $_.panel_width
                panel_height = $_.panel_height
                scroll_coverage = $_.scroll_coverage
            }
        })
        source_hashes = $sourceHashes
        source_unchanged_during_run = $sourceUnchanged
        runs = $runResults
        operations = $operations
        passed = ($sourceUnchanged -and
            @($runResults | Where-Object { -not $_.passed }).Count -eq 0)
    }
    $summaryPath = Join-Path $reportDirectory "smart_grid_ui_performance_$runPrefix-summary.json"
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryPath -Encoding utf8
    foreach ($operationName in $operationNames) {
        $result = $operations[$operationName]
        Write-Output "$operationName : P95=$($result.response.p95_ms) ms; passed=$($result.passed)"
    }
    Write-Output "Performance summary: $summaryPath"
    if (-not $summary.passed) { throw '真实界面性能验收未全部达标；各轮原始样本与汇总报告已保留。' }
} finally {
    $env:UI_PERFORMANCE_RUN = $previousRunName
    Pop-Location
}
