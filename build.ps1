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

$StageDir = Join-Path $PSScriptRoot "stage"

if (-not (Test-Path $StageDir))
{
    $madeStagingDirectory = mkdir $StageDir
}

if (-not $NonCore) {
    dotnet build (Join-path "src" "BraidCore.csproj") | Out-Host
} else {    
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
        write-host "? is $?"
        throw "Build failed with exit code $LASTEXITCODE."
    }            
}

if ($Optimize)
{
    Copy-Item src/bin/Release/*.* $StageDir -PassThru   
}
else
{
    Copy-Item src/bin/Debug/*.* $StageDir -PassThru 
}


Copy-Item -verbose src/BraidRepl.ps1 $StageDir -PassThru
Copy-Item -verbose src/*.tl   $StageDir -PassThru