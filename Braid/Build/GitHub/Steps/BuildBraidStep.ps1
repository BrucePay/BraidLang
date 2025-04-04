$ErrorActionPreference = 'continue'

$msBuildCommand = Get-Command msbuild -ErrorAction Ignore
$dotNetCommand = Get-command dotnet -ErrorAction Ignore

if (-not $msBuildCommand) {
    $msBuildCommand = $dotNetCommand | 
        Split-Path | 
        Split-Path | 
        Get-ChildItem -Filter msbuild* -Recurse -file |
        Select-Object -First 1 -ExpandProperty FullName 
}


if (-not $msBuildCommand) {
    Write-Warning "Could not find MSBuild, using .NET"
    & $dotNetCommand restore ./src/BraidCore.csproj
    & $dotNetCommand build ./src/BraidCore.csproj
    return
} else {
    Set-Alias msbuild $msBuildCommand
    .\build.ps1
}


