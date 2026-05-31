Set-StrictMode -Version Latest

$script:BraidRuntimeImported = $false

function Get-BraidRepositoryRoot
{
    [CmdletBinding()]
    param()

    $repoRoot = Split-Path -Parent $PSScriptRoot
    $projectPath = Join-Path (Join-Path $repoRoot "src") "BraidCore.csproj"
    if (-not (Test-Path -LiteralPath $projectPath))
    {
        throw "Could not locate the Braid repository root from module path '$PSScriptRoot'."
    }

    $repoRoot
}

function Get-BraidHome
{
    [CmdletBinding()]
    param(
        [switch] $RequireBuilt
    )

    if ($env:BRAID_HOME)
    {
        $braidHome = (Resolve-Path -LiteralPath $env:BRAID_HOME).Path
    }
    else
    {
        $repoRoot = Get-BraidRepositoryRoot
        $braidHome = Join-Path $repoRoot "stage"
    }

    if ($RequireBuilt -and -not (Test-BraidStage -Path $braidHome))
    {
        throw "Braid runtime is not staged at '$braidHome'. Run Invoke-BraidBuild first."
    }

    $braidHome
}

function Test-BraidStage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    (Test-Path -LiteralPath (Join-Path $Path "braidlang.dll")) -and
        (Test-Path -LiteralPath (Join-Path $Path "BraidRepl.ps1")) -and
        (Test-Path -LiteralPath (Join-Path $Path "autoload.tl"))
}

function Get-BraidReplPath
{
    [CmdletBinding()]
    param(
        [switch] $RequireBuilt
    )

    $braidHome = Get-BraidHome -RequireBuilt:$RequireBuilt
    Join-Path $braidHome "BraidRepl.ps1"
}

function Get-BraidPowerShell
{
    [CmdletBinding()]
    param()

    $pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue
    if ($pwsh)
    {
        return $pwsh.Source
    }

    throw "pwsh was not found. Braid's default net8.0 runtime requires PowerShell 7.4 or newer."
}

function Invoke-BraidBuild
{
    [CmdletBinding()]
    param(
        [switch] $Optimize,
        [switch] $Clean,
        [switch] $NonCore
    )

    $repoRoot = Get-BraidRepositoryRoot
    $buildScript = Join-Path $repoRoot "build.ps1"
    $buildArgs = @()
    if ($Optimize) { $buildArgs += "-Optimize" }
    if ($Clean) { $buildArgs += "-Clean" }
    if ($NonCore) { $buildArgs += "-NonCore" }

    & $buildScript @buildArgs
    if ($LASTEXITCODE)
    {
        throw "Braid build failed with exit code $LASTEXITCODE."
    }

    Get-BraidHome -RequireBuilt
}

function Invoke-Braid
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Command,

        [Parameter(Position = 1, ValueFromRemainingArguments)]
        [object[]] $ArgumentList = @(),

        [switch] $NoBuild,
        [switch] $Optimize
    )

    if (-not $NoBuild -and -not (Test-BraidStage -Path (Get-BraidHome)))
    {
        Invoke-BraidBuild -Optimize:$Optimize | Out-Null
    }

    $replPath = Get-BraidReplPath -RequireBuilt
    $pwsh = Get-BraidPowerShell

    & $pwsh -NoProfile -ExecutionPolicy Bypass -File $replPath $Command @ArgumentList
    if ($LASTEXITCODE)
    {
        throw "Braid command '$Command' failed with exit code $LASTEXITCODE."
    }
}

function Start-Braid
{
    [CmdletBinding()]
    param(
        [switch] $NoBuild,
        [switch] $Optimize
    )

    if (-not $NoBuild -and -not (Test-BraidStage -Path (Get-BraidHome)))
    {
        Invoke-BraidBuild -Optimize:$Optimize | Out-Null
    }

    $replPath = Get-BraidReplPath -RequireBuilt
    $pwsh = Get-BraidPowerShell
    & $pwsh -NoProfile -ExecutionPolicy Bypass -File $replPath
}

function Import-BraidRuntime
{
    [CmdletBinding()]
    param()

    if ($script:BraidRuntimeImported)
    {
        return [BraidLang.Braid]
    }

    if (-not (Test-BraidStage -Path (Get-BraidHome)))
    {
        Invoke-BraidBuild | Out-Null
    }

    $braidHome = Get-BraidHome -RequireBuilt
    $assemblyPath = Join-Path $braidHome "braidlang.dll"
    $braidType = [type]::GetType("BraidLang.Braid, braidlang", $false)
    if (-not $braidType)
    {
        [void] [Reflection.Assembly]::LoadFrom($assemblyPath)
    }

    [BraidLang.Braid]::BraidHome = $braidHome
    [BraidLang.Braid]::Host = $Host
    [BraidLang.Braid]::Init()

    $lineEditor = [BraidLang.LineEditor]::new("braid", 200)
    if (-not $lineEditor)
    {
        throw "BraidLang.LineEditor could not be initialized."
    }

    [void] [BraidLang.Braid]::SetVariable("ExecutionContext", $ExecutionContext)
    [void] [BraidLang.Braid]::SetVariable("RunSpace", [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace)
    [void] [BraidLang.Braid]::SetVariable("PID", $PID)
    [void] [BraidLang.Braid]::SetVariable("PSHost", $Host)
    [void] [BraidLang.Braid]::SetVariable("*line-editor*", $lineEditor)
    [void] [BraidLang.Braid]::SetVariable("IsDesktop", $PSVersionTable.PSEdition -eq "Desktop")
    [void] [BraidLang.Braid]::SetVariable("IsCoreClr", $PSVersionTable.PSEdition -eq "Core")

    $isWindowsValue = if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) { $IsWindows } else { $true }
    $isLinuxValue = if (Get-Variable -Name IsLinux -ErrorAction SilentlyContinue) { $IsLinux } else { $false }
    $isMacOSValue = if (Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue) { $IsMacOS } else { $false }
    [void] [BraidLang.Braid]::SetVariable("IsWindows", $isWindowsValue)
    [void] [BraidLang.Braid]::SetVariable("IsLinux", $isLinuxValue)
    [void] [BraidLang.Braid]::SetVariable("IsMacOS", $isMacOSValue)
    [void] [BraidLang.Braid]::SetVariable("IsUnix", $isLinuxValue -or $isMacOSValue)

    $autoloadFile = Join-Path $braidHome "autoload.tl"
    $oldFile = [BraidLang.Braid]::_current_file
    $oldCaller = [BraidLang.Braid]::CallStack.Caller
    try
    {
        [BraidLang.Braid]::_current_file = "autoload.tl"
        $parsed = [BraidLang.Braid]::Parse((Get-Content -Raw -LiteralPath $autoloadFile))
        foreach ($expr in $parsed)
        {
            [BraidLang.Braid]::CallStack.Caller = $expr
            [void] [BraidLang.Braid]::Eval($expr)
        }
    }
    finally
    {
        [BraidLang.Braid]::_current_file = $oldFile
        [BraidLang.Braid]::CallStack.Caller = $oldCaller
    }

    $script:BraidRuntimeImported = $true
    [BraidLang.Braid]
}

Set-Alias -Name Build-Braid -Value Invoke-BraidBuild

Export-ModuleMember -Function Get-BraidHome, Import-BraidRuntime, Invoke-Braid, Invoke-BraidBuild, Start-Braid -Alias Build-Braid
