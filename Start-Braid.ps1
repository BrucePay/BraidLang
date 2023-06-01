#######################################################
#
# Loader for the braid programming language.
#
#######################################################

if ($cmd)
{
    # Just run the command
    ./stage/BraidRepl $cmd @args
}
elseif ($IsCoreClr)
{
    # Don't build under core; the build setup doesn't work.
    pwsh "$PSScriptRoot/stage/BraidRepl.ps1"
}
else
{
    # Build and start braid.
    & "$PSScriptRoot/build.ps1"
    powershell "$PSScriptRoot/stage/BraidRepl.ps1"
}

