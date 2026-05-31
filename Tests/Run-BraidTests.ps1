param(
    [string] $Pattern = "^(typetest|tostring|vector|hashset|contains\?|in\?|if|and|or|not|comparison|==|!=|defn|let|return|regex|matchp)",
    [switch] $All,
    [switch] $NoBuild,
    [switch] $Optimize
)

$ErrorActionPreference = "Stop"

function Test-BraidStage
{
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    (Test-Path -LiteralPath (Join-Path $Path "braidlang.dll")) -and
        (Test-Path -LiteralPath (Join-Path $Path "BraidRepl.ps1")) -and
        (Test-Path -LiteralPath (Join-Path $Path "autoload.tl"))
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$stageDir = Join-Path $repoRoot "stage"
$replPath = Join-Path $stageDir "BraidRepl.ps1"
$testScript = Join-Path $PSScriptRoot "unittests.tl"

if (-not $NoBuild -and -not (Test-BraidStage -Path $stageDir))
{
    & (Join-Path $repoRoot "build.ps1") -Optimize:$Optimize
    if ($LASTEXITCODE)
    {
        throw "Braid build failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-BraidStage -Path $stageDir))
{
    throw "Braid runtime is not staged at '$stageDir'. Run .\build.ps1 first."
}

$pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue
if (-not $pwsh)
{
    throw "pwsh was not found. Braid's default net8.0 runtime requires PowerShell 7.4 or newer."
}

$braidArgs = @($testScript)
if (-not $All -and $Pattern)
{
    $braidArgs += $Pattern
}
$patternDescription = if ($All -or -not $Pattern) { "<all>" } else { $Pattern }

$output = & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $replPath @braidArgs 2>&1
$exitCode = $LASTEXITCODE
$text = $output | Out-String
if ($text)
{
    Write-Host $text.TrimEnd()
}

if ($exitCode)
{
    throw "Braid test run failed with exit code $exitCode."
}

$totalMatch = [regex]::Matches($text, "Total number of tests:\s*(\d+)") | Select-Object -Last 1
if (-not $totalMatch)
{
    throw "Braid test run did not report a total test count."
}

$totalTests = [int] $totalMatch.Groups[1].Value
if ($totalTests -le 0)
{
    throw "Braid test run reported zero tests. Check the test pattern and harness invocation."
}

$failureMatch = [regex]::Matches($text, "Tests failed:\s*(\d+)\s+failures") | Select-Object -Last 1
if (-not $failureMatch)
{
    throw "Braid test run did not report a failure count."
}

$failedTests = [int] $failureMatch.Groups[1].Value
if ($failedTests -gt 0)
{
    throw "Braid test run reported $failedTests failing tests."
}

Write-Host "Braid test run passed: $totalTests tests matched '$patternDescription'."
