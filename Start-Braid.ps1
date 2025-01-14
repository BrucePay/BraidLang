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

if ($cmd)
{
    # Just run the command
    ./stage/BraidRepl $cmd @args
}
else
{
    # Build and start braid.
    if (-not $nobuild)
    {
        & "$PSScriptRoot/build.ps1" -optimize:$Optimize
    }

    if ($PSVersionTable.PSEdition -eq "Desktop")
    {
        powershell  "$PSScriptRoot/stage/BraidRepl.ps1"
    }
    else
    {
        pwsh "$PSScriptRoot/stage/BraidRepl.ps1"
    }
}

