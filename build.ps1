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

# Try and find the msbuild command
if (-not (Get-Command "msbuild" -ErrorAction "SilentlyContinue"))
{
    $alias:msbuild = "${ENV:ProgramFiles}/Microsoft Visual Studio/2022/Community/MSBuild/Current/Bin/arm64/msbuild.exe"
}

$StageDir = Join-Path $PSScriptRoot "stage"

# msbuild properties
$properties = ""

if ($Optimize)
{
    $properties += "Configuration=release"
}
else
{
    $properties += "Configuration=debug"
}

if ($clean)
{
    msbuild "-t:clean" "-p:$properties"  .\src\braidlang.csproj
}

msbuild "-p:$properties"  .\src\braidlang.csproj

$StageDir = Join-Path $PSScriptRoot "stage"
if (-not (Test-Path $StageDir))
{
    $madeStagingDirectory = mkdir $StageDir
}
  
$properties = ""
    
if ($Optimize)
{
    $properties += "Configuration=release"
}
else
{
    $properties += "Configuration=debug"
}
    
if ($clean)
{
    msbuild "-t:clean" "-p:$properties"  .\src\braidlang.csproj | Out-Host
}
    
msbuild "-p:$properties"  .\src\braidlang.csproj | Out-Host
    
if ($LASTEXITCODE)
{
    Write-Host "? is $?"
    throw "Build.ps1 failed with exit code $LASTEXITCODE."
}

if ($Optimize)
{
    Copy-Item src/bin/Release/braidlang.* $StageDir -PassThru   
}
else
{
    Copy-Item src/bin/Debug/braidlang.* $StageDir -PassThru 
}

Copy-Item -verbose src/BraidRepl.ps1 $StageDir -PassThru
Copy-Item -verbose src/*.tl   $StageDir -PassThru
