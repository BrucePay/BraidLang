#######################################################
#
# Loader for the braid programming language.
#
#######################################################

param (
    [switch] $Optimize,
    [switch] $NoBuild,
    $cmd = $null
)

$stagePath = Join-Path $PSScriptRoot "stage"
$replPath = Join-Path $stagePath "BraidRepl.ps1"
$pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue
if (-not $pwsh)
{
    throw "pwsh was not found. Braid's default net8.0 runtime requires PowerShell 7.4 or newer."
}

if ($cmd)
{
    if (-not (Test-Path -LiteralPath $replPath))
    {
        if ($NoBuild)
        {
            throw "Braid runtime is not staged at '$stagePath'. Run .\build.ps1 first."
        }

        & (Join-Path $PSScriptRoot "build.ps1") -Optimize:$Optimize
    }

    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $replPath $cmd @args
}
else
{
    # Build and start braid.
    if (-not $nobuild)
    {
        & (Join-Path $PSScriptRoot "build.ps1") -Optimize:$Optimize
    }

    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $replPath
}
