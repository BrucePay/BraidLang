param(
    [ValidateSet("portable", "windows", "interactive", "all", "custom")]
    [string] $Suite = "portable",

    [string] $Pattern,
    [string[]] $ExcludePattern = @(),
    [int] $MinimumTests = 1,

    [switch] $All,
    [switch] $NoBuild,
    [switch] $Optimize,
    [string] $LogPath
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion -lt [Version] "7.4")
{
    throw "Braid tests require PowerShell 7.4 or newer. Current version is $($PSVersionTable.PSVersion)."
}

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

function Get-BraidTestNames
{
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $content = Get-Content -Raw -LiteralPath $Path
    [regex]::Matches($content, '\(test/exec\s+:?([^\s\)]+)') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
}

function New-TestNamePattern
{
    param(
        [Parameter(Mandatory)]
        [string[]] $Name,
        [string[]] $Exclude = @()
    )

    $includedNames = foreach ($testName in $Name)
    {
        $isExcluded = $false
        foreach ($excludeItem in $Exclude)
        {
            if ($testName -match $excludeItem)
            {
                $isExcluded = $true
                break
            }
        }

        if (-not $isExcluded)
        {
            $testName
        }
    }

    $includedNames = @($includedNames)
    if ($includedNames.Count -eq 0)
    {
        throw "Test suite selection excluded every test."
    }

    "^(?:$((($includedNames | ForEach-Object { [regex]::Escape($_) }) -join '|')))$"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$stageDir = Join-Path $repoRoot "stage"
$replPath = Join-Path $stageDir "BraidRepl.ps1"
$testScript = Join-Path $PSScriptRoot "unittests.tl"

$testNames = @(Get-BraidTestNames -Path $testScript)

$knownFailureExclusions = @(
    "^sum",
    "^prod",
    "^average",
    "^median",
    "^max",
    "^min",
    "^number\?",
    "^slice[89]$",
    "^-2$",
    "^-3$",
    "^thenSort[12]$"
)

$platformExclusions = @(
    "^powershell(?:1|2|3|16)$",
    "^shell1$",
    "^file/(?:filename3|basename3|dirname3)$"
)

$interactiveExclusions = @(
    "^complet(?:e|er)"
)

if ($All)
{
    $Suite = "all"
}

switch ($Suite)
{
    "portable" {
        $suiteExclusions = @(
            $knownFailureExclusions
            $platformExclusions
            $interactiveExclusions
            $ExcludePattern
        )
        $Pattern = New-TestNamePattern -Name $testNames -Exclude $suiteExclusions
        if ($MinimumTests -le 1) { $MinimumTests = 500 }
    }
    "windows" {
        $suiteNames = @($testNames | Where-Object { $_ -match "^(powershell|shell|file/)" })
        $Pattern = New-TestNamePattern -Name $suiteNames -Exclude @($knownFailureExclusions + $interactiveExclusions + $ExcludePattern)
        if ($MinimumTests -le 1) { $MinimumTests = 20 }
    }
    "interactive" {
        $Pattern = "^(completer|complete)"
    }
    "all" {
        $Pattern = $null
    }
    "custom" {
        if (-not $Pattern)
        {
            throw "-Pattern is required when -Suite custom is used."
        }
    }
}

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
if ($Pattern)
{
    $braidArgs += $Pattern
}
$patternDescription = if ($Suite -eq "custom" -and $Pattern) { $Pattern } elseif ($Pattern) { "<generated $Suite suite>" } else { "<all>" }

Push-Location -LiteralPath $stageDir
try
{
    $output = & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $replPath @braidArgs 2>&1
    $exitCode = $LASTEXITCODE
}
finally
{
    Pop-Location
}
$text = $output | Out-String

if ($LogPath)
{
    $logDirectory = Split-Path -Parent $LogPath
    if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory))
    {
        $null = New-Item -ItemType Directory -Path $logDirectory
    }

    Set-Content -LiteralPath $LogPath -Value $text
}

if ($text)
{
    Write-Host $text.TrimEnd()
}

if ($exitCode)
{
    throw "Braid test run failed with exit code $exitCode."
}

if ($text -match "ERROR LOADING file:")
{
    throw "Braid autoload reported an error. Check the test log for details."
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

if ($totalTests -lt $MinimumTests)
{
    throw "Braid test run reported $totalTests tests, below the required minimum of $MinimumTests for suite '$Suite'."
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

Write-Host "Braid test run passed: $totalTests tests in suite '$Suite' matched '$patternDescription'."
