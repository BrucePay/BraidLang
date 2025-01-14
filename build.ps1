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
    [switch] $Core
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

if ($LASTEXITCODE)
{
    write-host "? is $?"
    throw "Build failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path $StageDir))
{
    mkdir $StageDir
}

if ($Optimize)
{
    cp src/bin/Release/*.* $StageDir   
}
else
{
    cp src/bin/Debug/*.* $StageDir   
}

cp src/BraidRepl.ps1 $StageDir
cp src/*.tl   $StageDir

