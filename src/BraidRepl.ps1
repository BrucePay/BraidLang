using namespace System;
using namespace System.Linq;
using namespace System.Numerics;
using namespace System.Collections;
using namespace System.Text;
using namespace System.Text.RegularExpressions;
using namespace System.Collections.Generic;
using namespace System.Management.Automation;
using namespace System.Management.Automation.Runspaces;

param ($scriptToRun = $null, [switch] $wait)

$argsToPassToScript = if ($args) { $args } else { $null }

Set-StrictMode -Version latest
function say { [console]::writeline("$args")}

if ($wait)
{
    Read-Host -Prompt "Attach debugger then press enter to continue"
}

#
# Load the braid helper assemblies
#

if (test-path variable:isCoreCLR)
{
    Add-Type -Assembly (Join-Path $PSScriptRoot 'braidlang.dll')
#    Add-Type -Assembly (Join-Path $PSScriptRoot 'braidLineEditor.dll')
}
else
{
    [void][reflection.assembly]::LoadFrom((Join-Path $PSScriptRoot 'braidlang.dll'))
#    [void][reflection.assembly]::LoadFrom((Join-Path $PSScriptRoot 'braidLineEditor.dll'))
}

[BraidLang.Braid]::ExitBraid = $false

$global:lineEditor = [BraidLang.LineEditor]::new('braid', 200)
if ($lineEditor -eq $null)
{
    throw "BraidLang.LineEditor does not exist"
    exit -1
}

#
# Autoload the 'autoload.tl' file if it's newer that the one in memory
#
[HashTable] $global:watches = @{}
$global:autoloadTimeStamp = 0;
function Invoke-Autoload
{
    try
    {
        $autoLoadFile = Join-Path $PSScriptRoot "autoLoad.tl"
        if (Test-Path $autoLoadFile)
        {
            $currentTimeStamp = (Get-ChildItem $autoloadFile).LastWriteTime;
            if ($currentTimeStamp -gt $global:autoloadTimeStamp)
            {
                if ($global:autoLoadTimeStamp -ne 0)
                {
                    Write-Host -fore yellow "Importing updated 'autoload.tl'."
                }

                $old = [BraidLang.Braid]::_current_file
                $oldCaller = [BraidLang.Braid]::CallStack.Caller;
                try
                {
                    $ts = [datetime]::now
                    [BraidLang.Braid]::_current_file = "autoload.tl"
                    $global:autoloadTimeStamp = $currentTimeStamp
                    $parsed = [BraidLang.Braid]::Parse((Get-Content -Raw -Path $autoLoadFile))
                    $null = foreach ($expr in $parsed)
                    {
                        [BraidLang.Braid]::CallStack.Caller = $expr;
                        [void] [BraidLang.Braid]::Eval($expr)
                    }

                    Write-Host -fore yellow "Autoload took $(([datetime]::now-$ts).TotalMilliseconds) ms."
                }
                finally
                {
                    [BraidLang.Braid]::_current_file = $old
                    [BraidLang.Braid]::CallStack.Caller = $oldCaller 
                }
            }
        }


        foreach ($k in @($watches.Keys))
        {
            $watchedFile = $k

            if (Test-Path $watchedFile)
            {
                $watchedFileTimeStamp = (Get-ChildItem $watchedFile).LastWriteTime;
                if ($watchedFileTimeStamp -gt $watches[$k])
                {
                    Write-Host -fore yellow "Importing updated '$k'."

                    $old = [BraidLang.Braid]::_current_file
                    $oldCaller = [BraidLang.Braid]::CallStack.Caller;
                    try
                    {
                        [BraidLang.Braid]::_current_file = $watchedFile
                        $parsed = [BraidLang.Braid]::Parse((Get-Content -Raw -Path $watchedFile))
                        $null = foreach ($expr in $parsed)
                        {
                            [BraidLang.Braid]::CallStack.Caller = $expr;
                            [BraidLang.Braid]::Eval($expr)
                        }
                        $watches[$k] = $watchedFileTimeStamp
                    }
                    finally
                    {
                        [BraidLang.Braid]::_current_file = $old
                        [BraidLang.Braid]::CallStack.Caller = $oldCaller 
                    }
                }
            }
        }
    }
    catch
    {
        Write-Host "ERROR LOADING file:`n$_"
    }
}

#
# The REPL
#
$global:level = 0
function BraidRepl
{
    $global:level++
    $stopwatch = [System.Diagnostics.Stopwatch]::new()

    if ($global:level -eq 1)
    {
        # Initialize the interpreter state
        [BraidLang.Braid]::Init();

        [void] [BraidLang.Braid]::SetVariable("ExecutionContext", $ExecutionContext)
        [void] [BraidLang.Braid]::SetVariable("RunSpace", [Runspace]::DefaultRunSpace)
        [void] [BraidLang.Braid]::SetVariable("PID", $PID)
        [void] [BraidLang.Braid]::SetVariable("PSHost", $host)
        # Make the host available to the C# code.
        [BraidLang.Braid]::Host = $host;

        [void] [BraidLang.Braid]::SetVariable("IsDesktop",  
            $PSVersionTable.PSEdition -eq 'desktop')

        if (test-path variable:IsCoreCLR)
        {
            [void] [BraidLang.Braid]::SetVariable("IsWindows", $IsWindows)
            [void] [BraidLang.Braid]::SetVariable("IsLinux", $IsLinux)
            [void] [BraidLang.Braid]::SetVariable("IsMacOS", $IsMacOS)
            [void] [BraidLang.Braid]::SetVariable("IsUnix", $IsMacOS -or $IsLinux)
            [void] [BraidLang.Braid]::SetVariable("IsCoreClr", $IsCoreClr)
        }
        else
        {
            [void] [BraidLang.Braid]::SetVariable("IsWindows", $true)
            [void] [BraidLang.Braid]::SetVariable("IsLinux", $false)
            [void] [BraidLang.Braid]::SetVariable("IsMacOS", $false)
            [void] [BraidLang.Braid]::SetVariable("IsUnix", $false)
            [void] [BraidLang.Braid]::SetVariable("IsCOreClr", $false)
        }

        # Helper functions to allow Braid functions to be defined in PowerShell
        function DefineFunction([string] $name, [ScriptBlock] $action)
        {
            #[BraidLang.Braid]::SetFunction($name, $action)
            [void] [BraidLang.Braid]::SetVariable($name, $action)
        }

        function DefineSpecialForm([string] $name, [ScriptBlock] $action)
        {
            [BraidLang.Braid]::SetSpecialForm($name, $action)
        }

        #-------------------------------------------------------------------------------

        DefineFunction "dump-error" {
            $err = $error | Select-Object -First 1
            if ($err)
            {
                $err | Format-List -force * | Out-Host
                if ($err.Exception.InnerException)
                {
                    write-host ('=' *80)
                    $err.Exception.InnerException | Format-List -force * | Out-Host
                }
            }
        }

        DefineFunction "add-watch" {
            foreach ($arg in $args)
            {
                $global:watches[$arg.ToString()] = 0
            }
        }

        DefineFunction "remove-watch" {
            foreach ($arg in $args)
            {
                $global:watches.Remove($arg.ToString())
            }
        }

        DefineFunction "get-watch" {
            foreach ($arg in $args)
            {
                $global:watches
            }
        }

        DefineFunction 'PSVersionTable' {
            $psVersionTable
        }

        DefineFunction 'psvar' {
            if (-not $args)
            {
                Get-Variable | foreach name
            }
            elseif ($args.Count -eq 1)
            {
                Get-Variable ([string] $args[0])
            }
            else
            {
                Set-Variable -script ([string] $args[0]) $args[1]
            }
        }

        # Dump the command history
        DefineFunction "gh" {
            $numToShow = 100;
            $pattern = "."
            if ($args.Count -gt 0)
            {
                if ($args[0] -is [int])
                {
                    $numToShow = $args[0]
                }
                else
                {
                    $pattern = [regex] $args[0]
                }
            }

            $lineEditor.CommandHistory.Dump() |
                grep $pattern |
                select -last $numToShow
        }

        #
        # Start the REPL
        #
        if (-not $scriptToRun)
        {
            Write-Host -Fore green "`nWelcome to Braid. Type '(help)' for help or 'quit' to quit.`n"
        }

        [void] [BraidLang.Braid]::SetVariable("*line-editor*", $lineEditor)

        #
        # This is a wrapper that allows for a Braid function to be
        # used as the prompt function.
        #
        $promptScriptBlock = {
            if ($global:level -gt 1)
            {
                $promptStr = "[$global:level] DEBUG > "
            }
            else
            {
                if ($promptStr = [BraidLang.Braid]::GetValue("prompt", $true))
                {
                    if ($promptStr -is [BraidLang.s_Expr])
                    {
                        $promptStr = "" + [BraidLang.Braid]::Eval($promptstr);
                    }
                }
                else
                {
                    $promptStr = "=>"
                }
            }
            "$promptStr "
        }
    }

    try
    {
       # load the autoload file before starting the REPL or running a script
       Invoke-Autoload

       if ($scriptToRun)
       {
           # Synchronize the process and PowerShell directories.
           [environment]::CurrentDirectory = (Get-Location).Path

           $newExpr = [BraidLang.s_Expr]::new($scriptToRun);
           $end = $newExpr;
           foreach ($e in $argsToPassToScript)
           {
                $takesArg = $false
                if ($e -match "^-[a-z]")
                {
                    if ($e -match '\:$')
                    {
                        $takesArg = $true
                        $e = $e.Substring(0, $e.Length-1)
                    }

                    $e = [BraidLang.NamedParameter]::new($e.Substring(1), $true, $takesArg)
                }

                $end = $end.Add($e);
           }

           try
           {
                [BraidLang.Braid]::ExitBraid = $true;
                return [BraidLang.Braid]::Eval($newExpr)
           }
           catch [braidlang.BraidExitException]
           {
                exit 0
           }
           catch
           {
                Write-Host -ForegroundColor red $_
                exit -1
           }
       }
       else
       {
            :mainloop while (-not [BraidLang.Braid]::_stop -and -not [BraidLang.Braid]::ExitBraid)
            {
                [Console]::ForeGroundColor = "white"
                [Console]::BackgroundColor = "black"
                [console]::cursorvisible = "True"
                [BraidLang.Braid]::ExitBraid = $false;

                $host.UI.RawUI.WindowTitle =
                    "(Braid) (PID: $PID) {$((Get-Location).Path)}"

                $pssb = $promptScriptBlock;
                $txt = ""
                $expr = $null
                try
                {
                      while (-not [BraidLang.Braid]::_stop)
                      {
                        try
                        {
                            $oldText = $txt += $lineEditor.Edit($pssb)

                            # Calling close flushes the edit history to disk
                            # It doesn't actually close the editor session.
                            $lineEditor.Close()
                            if ([BraidLang.Braid]::_stop)
                            {
                                [BraidLang.Braid]::_stop = $false
                                continue mainloop
                            }

                            # Just ignore blank lines
                            if ($txt -match '^ *$')
                            {
                                continue
                            }

                            if ($txt -eq '\')
                            {
                                break
                            }

                            # If the command is not wrapped in parens add them
                            if ($txt -notmatch '^[ \t\r\n]*\(.*\)[ \t\r\n]*') {
                                $txt = "($txt)"
                            }

                            $expr = [BraidLang.Braid]::Parse($txt)
                            break;
                        }
                        catch [MethodInvocationException]
                        {
                            $ex = $_.Exception.InnerException;
                            if ($ex)
                            {
                                if ($ex -is [BraidLang.IncompleteParseException] )
                                {
                                    $txt = $oldText + " "
                                    $pssb = { ": " }
                                    continue
                                }
                                else
                                {
                                    Write-Host -fore red $ex.Message
                                    break
                                }
                            }
                        }
                    }
                }
                catch
                {
                    $_ | Format-List -force * | Out-String | Write-Host -fore red
                    $txt = ""
                    continue
                }

                if ($txt -eq 'quit')
                {
                    [BraidLang.Braid]::ExitBraid = $true;
                    break
                }

                if ($txt -eq '\')
                {
                    Write-Host -fore yellow "Multi-line mode - type ;; to exit..."
                    $txt = "";
                    while ($true)
                    {
                        $element = Read-Host -Prompt ":"
                        if ($element -eq ';;')
                        {
                            break
                        }
                        $txt += "`n" + $element;
                    }

                    # add the consolidated text to the editor history
                    $lineeditor.CommandHistory.Append($txt)
                    $expr = [BraidLang.Braid]::Parse($txt)
                }

                try
                {
                    # load the autoload file if appropriate.
                    Invoke-Autoload

                    [BraidLang.Braid]::ClearRuntimeState();
                    if ($null -ne $expr)
                    {
                        $result = $null
                        while ($true)
                        {
                            $memoryBefore = [gc]::GetTotalMemory($true)
                            $ccb = [gc]::CollectionCount(0)
                            $oldCaller = [BraidLang.Braid]::CallStack.Caller;
                            $stopwatch.Stop()
                            $stopwatch.Reset()
                            $stopwatch.Start()
                            try
                            {
                                [BraidLang.Braid]::CallStack.Caller = $expr;
                                $result = [BraidLang.Braid]::Eval($expr.Car);
                            }
                            finally
                            {
                                $stopwatch.Stop()
                                $memory = [gc]::GetTotalMemory($true) - $memoryBefore
                                [BraidLang.Braid]::CallStack.Caller = $oldCaller;
                            }

                            # Unwrap return objects
                            if ($result -is [BraidLang.BraidReturnOperation])
                            {
                                $result = $result.ReturnValue
                            }

                            $resultString = "";

                            if ($result -is [IDictionary])
                            {
                                $resultString = [BraidLang.Utils]::ToStringDict($result)
                            }
                            elseif ($result -is [HashSet[object]])
                            {
                                $resultString = [BraidLang.Utils]::ToStringHashset($result)
                            }
                            elseif ($result -is [BraidLang.s_Expr])
                            {
                                $resultString = $result.ToString()
                            }
                            elseif ($result -is [BraidLang.UserFunction])
                            {
                                $resultString = $result.ToString()
                            }
                            elseif ($result -is [BraidLang.PatternFunction])
                            {
                                $resultString = $result.ToString()
                            }
                            elseif ($result -is [BraidLang.BraidTypeBase])
                            {
                                $resultString = $result.ToString()
                            }
                            elseif ($result -is [System.Collections.DictionaryEntry])
                            {
                                $resultString = "{" + $result.Key + " " + $result.Value + "}"
                            }
                            elseif ($result -is [type])
                            {
                                $resultString = "^" + $result.ToString()
                            }
                            elseif ($result -is [System.Reflection.MemberInfo[]])
                            {
                                $resultString = ""
                                foreach ($m in $result)
                                {
                                    $resultString += $m.ToString() + "`n"
                                }
                            }
                            elseif ($result -is [System.Reflection.MemberInfo])
                            {
                                $resultString = $result.ToString()
                            }
                            # Render vectors/slices as strings only if the length is zero or the first element is a PSObject
                            elseif (
                                ($result -is [BraidLang.Vector] -or $result -is [BraidLang.Slice] -or $result -is [BraidLang.RangeList]) -and
                                ($result.Count -eq 0 -or $result[0] -isnot [PSObject]))
                            {
                                $resultString = $result.ToString()
                            }
                            else
                            {
                                $resultString = $result | Out-String;
                            }

                            # Trim the output string if necessary
                            $maxsize = 50000
                            if ($resultString.Length -gt $maxsize)
                            {
                                $resultString = $resultString.SubString(0, $maxsize) + "`n... output greater than $maxsize characters ..."
                            }

                            [console]::WriteLine($resultString);

                            $expr = $expr.Cdr
                            if ($expr -eq $null)
                            {
                                Write-Host -fore green ("Time: {0} ms, Memory Delta: {1} Mb. Collections: {2} PWD: {3}" -f
                                    @($stopwatch.Elapsed.TotalMilliseconds, ($memory -shr 10), ([gc]::CollectionCount(0) - $ccb - 1), $PWD))
                                break;
                            }
                        }
                    }
                }
                catch
                {
                    $exception = $_.Exception

                    while ($exception -is [MethodInvocationException] -and $exception.InnerException -ne $null)
                    {
                        $exception = $exception.InnerException
                    }

                    if ($exception -is [System.Management.Automation.ScriptCallDepthException])
                    {
                        Write-Host -fore green "Caught ScriptCallDepthException"
                    }
                    elseif ($exception -is [BraidLang.BraidExitException])
                    {
                        [BraidLang.Braid]::ExitBraid = $true;
                        exit 0
                    }
                    else
                    {
                        Write-Host -fore red ($exception.Message)
                    }
                }
            }
        }
    }
    finally
    {
       $global:level--
       $lineEditor.Close()
    }
}

[BraidLang.Braid]::StartBraid();

