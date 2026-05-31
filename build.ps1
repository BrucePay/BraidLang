#######################################################
#
# Script to build and stage the Braid programming language.
#
#######################################################

param (
    [switch] $Optimize,
    [switch] $Clean,
    [switch] $Force,
    [switch] $BuildOnly,
    [switch] $NonCore
)

$ErrorActionPreference = "stop"

function Get-MSBuildCommand
{
    $msBuildCommand = Get-Command "msbuild" -ErrorAction SilentlyContinue
    if ($msBuildCommand)
    {
        return $msBuildCommand.Source
    }

    if (Get-Module -ListAvailable VsDevShell)
    {
        Import-Module VsDevShell
        Enter-VsDevShell -Arch x64 -HostArch x64 -NoLogo

        $msBuildCommand = Get-Command "msbuild" -ErrorAction SilentlyContinue
        if ($msBuildCommand)
        {
            return $msBuildCommand.Source
        }
    }

    $candidatePaths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe"
    ) | Where-Object { $_ }

    foreach ($candidate in $candidatePaths)
    {
        if (Test-Path -LiteralPath $candidate)
        {
            return $candidate
        }
    }

    throw "MSBuild was not found. Install Visual Studio Build Tools, add MSBuild to PATH, or run without -NonCore to use dotnet build."
}

$configuration = if ($Optimize) { "Release" } else { "Debug" }
$StageDir = Join-Path $PSScriptRoot "stage"

if ($NonCore)
{
    $msBuild = Get-MSBuildCommand
    $project = Join-Path $PSScriptRoot "src\braidlang.csproj"

    if ($Clean)
    {
        & $msBuild "-t:clean" "-p:Configuration=$configuration" $project | Out-Host
    }

    & $msBuild "-p:Configuration=$configuration" $project | Out-Host

    if ($LASTEXITCODE)
    {
        throw "Build.ps1 failed with exit code $LASTEXITCODE."
    }

    $buildOutputDir = Join-Path $PSScriptRoot "src\bin\$configuration"
}
else
{
    $dotnet = Get-Command "dotnet" -ErrorAction SilentlyContinue
    if (-not $dotnet)
    {
        throw "dotnet was not found. Install the .NET SDK or run with -NonCore to use MSBuild."
    }

    $project = Join-Path $PSScriptRoot "src\BraidCore.csproj"
    [xml] $projectXml = Get-Content -LiteralPath $project
    $targetFramework = $projectXml.Project.PropertyGroup.TargetFramework | Where-Object { $_ } | Select-Object -First 1
    if (-not $targetFramework)
    {
        throw "Could not determine TargetFramework from $project."
    }

    if ($Clean)
    {
        & $dotnet.Source clean $project --configuration $configuration | Out-Host
    }

    & $dotnet.Source build $project --configuration $configuration --nologo | Out-Host

    if ($LASTEXITCODE)
    {
        throw "Build.ps1 failed with exit code $LASTEXITCODE."
    }

    $buildOutputDir = Join-Path $PSScriptRoot "src\bin\$configuration\$targetFramework"
}

if (-not (Test-Path -LiteralPath $StageDir))
{
    $null = New-Item -ItemType Directory -Path $StageDir
}

if ($NonCore)
{
    Copy-Item (Join-Path $buildOutputDir "braidlang.*") $StageDir -PassThru
}
else
{
    Copy-Item (Join-Path $buildOutputDir "*") $StageDir -Recurse -Force -PassThru
}

Copy-Item -Verbose (Join-Path $PSScriptRoot "src\BraidRepl.ps1") $StageDir
Copy-Item -Verbose (Join-Path $PSScriptRoot "src\*.tl") $StageDir
Copy-Item -Verbose (Join-Path $PSScriptRoot "src\*.html") $StageDir
