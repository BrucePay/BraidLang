
param (
    [Switch] $RunExamples
)

#-------------------------------------------------------------------------------------
# General utility functions, not Braid specific
#-------------------------------------------------------------------------------------

<#
.SYNOPSIS
    Returns the full name of the type of the given object.
.PARAMETER object
    The object to get the type of. 
#>
function Type-Of
{
    param ([object] $obj)

    $obj.GetType().FullName
}


<#
.SYNOPSIS
    Measures the execution time of a script block, optionally taking the 
    number of iterations to run as a parameter. It returns the execution time in milliseconds.
    Any output from the script block is discarded.
.PARAMETER Sb
    The script block to execute.
.PARAMETER Iterations
    The number of iterations to run the script block for. This is optional and defaults to
#>
function time
{
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        <# The number of iterations to run the script block for. This is optional and defaults to 1. #>
        [Parameter()]
        [int] 
            $Iterations = 1,
            
        <# The block of code to run #>
        [Parameter(Position = 0, ParameterSetName = "Default")]
        [ScriptBlock]
            $Sb

    )

    $sw = [Diagnostics.Stopwatch]::StartNew()
    foreach ($i in $Iterations)
    {
        [void] (& $sb)
    }

    $sw.Stop()
    $sw.Elapsed.TotalMilliseconds / 50
}

function base ($obj)
{
    if ($obj -is [System.Management.Automation.PSObject])
    {
        $obj.psobject.BaseObject
    }
    else
    {
        $obj
    }
}

<#
.SYNOPSIS
    Returns the string representation of the argument object.
.PARAMETER object
    The object to convert to a string.
#>
function ToString
{
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true)]
            [object] $obj
    )

    if ($obj)
    {
        return $obj.ToString()
    }

    ""
}

#-------------------------------------------------------------------------------------
# Braid-specific helper functions for calling into Braid from PowerShell.
#-------------------------------------------------------------------------------------

<#
.SYNOPSIS
    Retrieves a Braid function by its name.
.PARAMETER name
    The name of the function to retrieve.
#>
function Get-BraidFunction
{
    param ($name)

    if ($name -is [System.Collections.IEnumerable] -and $name -isnot [string])
    {
        return $name
    }

    # if the name starts with a dot, it's a member literal e.g. .length
    if ($name -match '^\.')
    {
        return ([BraidLang.MemberLiteral]::new($name, 0, ""))
    }

    # if the name starts with a caret followed by a letter, it's a type literal e.g. ^string
    if ($name -match '^\^[a-z]')
    {
        return ([BraidLang.TypeLiteral]::new($name.Substring(1), 0, ""))
    }

    $fn = [BraidLang.Braid]::GetFunc([BraidLang.Braid]::Callstack, $name, $false)
    if ($fn)
    {
        return $fn
    }

    throw "Get-BraidFunction: unrecognized function name '$name'."
}
$alias:gbf = "Get-BraidFunction"

<#
.SYNOPSIS
    Invokes a Braid function with the specified arguments.
.PARAMETER Function
    The function to invoke.
.PARAMETER Args
    The arguments to pass to the function.
#>
function Invoke-BraidFunction
{
    if ($args.length -eq 0)
    {
        throw "Invoke-BraidFunction requires at least one argument: the function to invoke."
    }

    $function = $args[0]

    if ($function -is [string])
    {
        $f = Get-BraidFunction $function
        if ($f)
        {
            $function = $f
        }
        else
        {
            throw "Invoke-BraidFunction: could not resolve function name '$function'."
        }
    }

    if ($Function -is [System.Management.Automation.CommandInfo])
    {
        # if it's a PowerShell command, we need to invoke it differently.
        $_,$psArgs = $args

        # if it's not [object[]], then it's a single argument andwe need to wrap it in an array to splat it.
        if ($psArgs -isnot [object[]])
        {
            $psargs = ,$psargs
        }

        if ($psArgs)
        {
            return & $Function @psArgs
        }

        return & $Function
    }

    if ($Function -is [BraidLang.TypeLiteral])
    {
        if ($args.length -ne 2)
        {
            throw "Invoking a type literal only supports one argument. You passed $($args.length - 1)."
        } 

        return (,$Function.Invoke($args[1]))
    }

    $result = switch ($args.length)
    {
        1 { ,$Function.Invoke(@()) }
        2 { ,$Function.Invoke((,$args[1])) }
        3 { ,$Function.Invoke(($args[1],$args[2])) }
        4 { ,$Function.Invoke(($args[1],$args[2],$args[3])) }
        5 { ,$Function.Invoke(($args[1],$args[2],$args[3],$args[4])) }
        6 { ,$Function.Invoke(($args[1],$args[2],$args[3],$args[4],$args[5])) }
        default { throw "Invoke-BraidFunction currently only supports up to 5 arguments. You passed $($args.length - 1)." }
    }

    if ($result -is [BraidLang.Vector])
    {
        return (,$result)
    }

    $result
}
$Alias:ibf = "Invoke-BraidFunction"

<#
.SYNOPSIS
    Creates a new Braid expression from the specified elements.
.PARAMETER Elements
    The elements to include in the expression.
#>
function New-BraidExpression
{
    [CmdletBinding()]
    param (
        [Parameter(ValueFromRemainingArguments, Position=0)]
            $Elements = @()
    )

    # ibr to-list $Elements
    $first, $rest = $Elements
    $l = [BraidLang.s_Expr]::new($first)

    if ($rest -is [BraidLang.s_Expr])
    {
        $rest = ,$rest
    }

    foreach ($e in $rest)
    {
        [void] $l.Add($e)
    }
    , $l
}
$alias:nbe = "New-BraidExpression"

<#
.SYNOPSIS
    Invokes a Braid expression.
.PARAMETER Expression
    The expression to invoke.
#>
function Invoke-BraidExpression
{
    param ([BraidLang.s_Expr] $Expression)
    
    , [BraidLang.Braid]::Eval($expression)
}
$Alias:ibe = "Invoke-BraidExpression"

<#
.SYNOPSIS
    Creates a new Braid pipe expression from the specified elements.
.PARAMETER Elements
    The elements to include in the pipe expression.
#>
function New-BraidPipeExpression 
{
    [CmdletBinding()]
    param (
        [Parameter(ValueFromRemainingArguments, Position=0)]
            $Elements = @()
    )

    [BraidLang.s_Expr] $pipeline = [BraidLang.s_Expr]::new((gbf pipe))
    foreach ($e in $Elements)
    {
        [void] $pipeline.Add($e)
    }
    , $pipeline
}
$alias:nbpe = "New-BraidPipeExpression"

<#
.SYNOPSIS
    Creates a new Braid function with the specified name, parameters, and body.
.PARAMETER Name
    The name of the function to create.
.PARAMETER Parameters
    The parameters for the function.
.PARAMETER Body
    The body of the function.
#>
function New-BraidFunction
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
            [string] $Name,

        [Parameter(Position = 1)]
            [string[]] $Parameters,

        [Parameter(ValueFromRemainingArguments, Position=0)]
            $Body = @()
    )

    $pv = [BraidLang.Vector]::new()
    foreach ($p in $Parameters)
    {
        [void] $pv.Add((gbs $p))
    }
    
    $expr = New-BraidExpression (gbs lambda)
    [void] $expr.Add($pv)
    foreach ($e in $Body)
    {
        [void] $expr.Add($e)
    }

    # bind the function to the specified.
    ibf let (gbs $Name) (ibe $expr)  
}
$alias:nbf = "New-BraidFunction"

<#
.SYNOPSIS
    Creates a new Braid lambda function with the specified parameters and body.
.PARAMETER Parameters
    The parameters for the lambda function.
.PARAMETER Body
    The body of the lambda function.
#>
function New-BraidLambda
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 1)]
            [string[]] $Parameters,

        [Parameter(ValueFromRemainingArguments)]
            $Body = @()
    )

    $pv = [BraidLang.Vector]::new()
    foreach ($p in $Parameters)
    {
        [void] $pv.Add((gbs $p))
    }
    
    $expr = New-BraidExpression (gbs lambda)
    [void] $expr.Add($pv)

    # assemble the lambda's body. If the body is a single s_Expr, we can add it directly.
    # If it's a list of expressions, we need to add each one separately.
    if ($Body -is [BraidLang.s_Expr])
    {
        [void] $expr.Add($Body)
    }
    else
    {
        foreach ($e in $Body)
        {
            [void] $expr.Add($e)
        }
    }

    # create the function object from the S-Expression
    (ibe $expr)  
}
$alias:nbl = "New-BraidLambda"

<#
.SYNOPSIS
    Retrieves a Braid symbol by its name.
.PARAMETER Name
    The name of the symbol to retrieve.
#>
function Get-BraidSymbol
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
            [string] $Name
    )

    [braidlang.Symbol]::FromString($Name)
}
$alias:gbs = "Get-BraidSymbol"

<#
.SYNOPSIS
    Retrieves the value of a Braid variable by its name.
.PARAMETER Name
    The name of the variable to retrieve.
#>
function Get-BraidVariableValue
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
            [string] $Name
    )

    [BraidLang.Braid]::GetVariable($Name).Value
}
$alias:gbvv = "Get-BraidVariableValue"

<#
.SYNOPSIS
    Sets the value of a Braid variable by its name.
.PARAMETER Name
    The name of the variable to set.
.PARAMETER Value
    The value to set for the variable.
#>
function Set-BraidVariableValue
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
            [string] $Name,

        [Parameter(Position = 1)]
            $Value
    )

    [BraidLang.Braid]::SetVariable($Name, $Value)
}
$alias:sbvv = "Set-BraidVariableValue"
    
<#
.SYNOPSIS
    Converts Braid source text into a Braid expression.
.PARAMETER SourceText
    The Braid source text to convert.
#>
function ConvertFrom-BraidSourceText
 { 
    param (
        $sourceText
    )
    
    ibf Parse-Text $sourceText
 }
$alias:cfbst = "ConvertFrom-BraidSourceText"


<#
.SYNOPSIS
    Retrieves a Braid symbol by its name.
.PARAMETER Name
    The name of the symbol to retrieve.
#>
function Get-BraidSymbol
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
            [string] $Name
    )

    ibf symbol $Name
}
$alias:gbs = "Get-BraidSymbol"

<#
.SYNOPSIS
    Retrieves help information for a Braid function.
.PARAMETER Name
    The name of the function for which to retrieve help.
.PARAMETER SearchAll
    Indicates whether to search all help text for matches.
.PARAMETER WebView
    Indicates whether to open the help in a web view.
#>
function Get-BraidHelp
{
    param (
        [Parameter(Position = 0)]
            [object] $Name = $null,
        [Parameter()]
            [switch] $SearchAll,
        [Parameter()]
            [switch] $WebView
    )

    if ($WebView)
    {
        Invoke-Item (Join-Path (Split-Path -Parent ([braidlang.PatternFunction].Assembly.Location)) "helptext.html")
        return
    }

    if ($name)
    {
        if ($SearchAll)
        {
            ibf help ([regex] $name)
        }
        else
        {
            $result = $null
            try
            {
                # Help is associated with the actual function object not name.
                $result = ibf doc (gbf $name)
            }
            catch {}

            if (-not $result)
            {
                 "Get-BraidHelp:No help found for '$name'. Try using the -SearchAll switch to search all help text for matches."
            }
            $result
        }
    }
    else
    {
        @"

        To get help on a Braid function, pass the name of the function to lookup.
        By defaulth the name passed will be used as a regular expression to match against the help text for all Braid
        functions, and the help text for any matching functions will be returned.
        
        For example:
            Get-BraidHelp "foreach"   # get help on the 'foreach' function.
            Get-BraidHelp "for"       # Find all functions with "for" in the name, e.g. 'foreach', 'format', etc.
            Get-BraidHelp "."         # get a list of all functions and their help text.
"@
    }
}
$alias:gbh = "Get-BraidHelp"

<#
.SYNOPSIS
    Creates a new Braid property pattern with the specified property-value pairs.
.PARAMETER PropertyValues
    The property-value pairs for the pattern.
#>
function New-BraidPropertyPattern
{
    if ($args.Count % 2 -ne 0)
    {
        throw "New-BraidPropertyPattern requires an even number of arguments representing property-value pairs."
    }

    [braidlang.DictionaryLiteral]::new($args, "", 0, "", 0)
}
$alias:nbpp = "New-BraidPropertyPattern"

#######################################################################################
#
# Examples showing how to use these functions to invoke Braid from PowerShell.
#

if (-not $RunExamples)
{
    return
}

#-------------------------------------------------------------------------------------

write-host "Getting help for the 'sqr' function using Get-BraidHelp:"
Get-BraidHelp sqr

write-host "Getting help for all functions with 'for' in the name using the -SearchAll switch:"
Get-BraidHelp for -SearchAll

write-host "Getting help for all functions & displaying it in a web view using the -WebView switch:"
# Get-BraidHelp -WebView

#-------------------------------------------------------------------------------------
# Basic function calling...

# Call a Braid user function
write-host "ibf sqr 10:" (ibf sqr 10)

# Invoke a property as a function
write-host "ibf .length '1234':" (ibf .length '1234')

# Invoke a PowerShell function through the braid function system.
write-host "ibf get-date: " (ibf get-date)

# Another test invoking a PowerShell command with arguments.
write-host "Current UTC time:" (ibf get-date -AsUtc)
write-host "Current UTC time again:" (ibf get-date -Format u)

# call the braid 'edit-distance' function on two words
write-host "Edit distance:" (ibf edit-distance "foo" "bOo") # should be two

# count a list of numbers
write-host 'ibf count (ibf list 5 6):' (ibf count (ibf list 5 6))

# count a PowerShell array of numbers
write-host 'ibf count (1,2,3):' (ibf count (1,2,3))

# count the number of files in the current directory using 'Get-ChildItem'
write-host 'ibf count (ls):' (ibf count (Get-ChildItem))

#-------------------------------------------------------------------------------------
# 
# Braid Expressions

$e = (nbe + 1 2 3)
write-host 'Braid expression:' $e.ToString()
write-host 'Evaluating the expression:' (ibe $e) # should be 6

$e = (nbe (gbf +) 1 2 (nbe (gbf *) 3 4) 5)
write-host 'Nested Braid expression:' $e.ToString()
write-host 'Evaluating the expression:' (ibe $e) # should be 20

#-------------------------------------------------------------------------------------
#
# Higher order functions...

# Sum the lengths of the files in the current directory using the 'map' function
write-host 'ibf sum (ibf map (Get-ChildItem) (gbf .?length)):' `
    (ibf sum (ibf map (Get-ChildItem) (gbf .?length)))

# Square a list numbers using 'map'
write-host 'ibf map (ibf list 5 6) (gbf sqr):' (ibf map (ibf list 5 6) (gbf sqr))

# Use map on a single element list
write-host 'ibf map (ibf list 5) (gbf sqr):' (ibf map (ibf list 5) (gbf sqr))

# square the numbers in a PowerShell array using map.
write-host 'ibf map (1,2,3) (gbf sqr):' (ibf map (1,2,3) (gbf sqr))

# *** Use the 'reduce' function to compute the product of a list of numbers
write-host 'ibf reduce (ibf vector 1 2 3) *:' (ibf reduce (ibf vector 1 2 3) *)

# Sort files by length, extracting the biggest one
write-host 'ibf last (ibf sort (ls) (gbf .?length)):' (ibf last (ibf sort (ls) (gbf .?length)))

#-------------------------------------------------------------------------------------

# *** Manually construct a Braid pipeline
$pe = (nbe (gbf pipe) (nbe (gbf range) 10) (nbe (gbf filter) (nbe (gbf %) 2)) (nbe (gbf sum)))
write-host "pipeline: " $pe.tostring() "result:" (ibe $pe)

# Create a pipe expression (list 1 2 3 | map sqr) using nbpe and evaluate it.
$e = (nbpe (nbe (gbs list) 1 2 3) (nbe (gbs map) (gbf sqr)))
write-host "Evaluating pipe expression (list 1 2 3 | map sqr):" (ibe $e) # should be (1 4 9)
$e = (nbpe (nbe (gbf range) 10) (nbe (gbf filter) (gbf even?)) (nbe (gbf map) (gbf sqr)))
write-host "Evaluating pipe expression (range 10 | filter even? | map sqr):" (ibe $e) # should be (4 16 36 64 100)

# Use the parse-text function to parse a pipeline
write-host 'Parsing (range 10 | filter even? | sum)'
$e = (ibf parse-text '(range 10 | filter even? | sum)')
$e.ToString()
ibe $e

#-------------------------------------------------------------------------------------
# Building functions
#
# *** Create a new braid lambda function that adds 1 to its argument, and then invoke it.  
$f = (nbe (gbs lambda) (ibf vector (gbs x)) (nbe (gbs +) (gbs x) 1))
$ff = ibe $f   # eval the expression to get a callable function
write-host "ff(5):" (ibf $ff 5) # should be 6

# define another lambda function
$e = (nbe (gbs lambda) ([BraidLang.Vector] @((gbs x))) (nbe (gbs +) (gbs x) 2))
ibf .tostring $e # call tostring using braid; this let's us see the expression we created
ibf (ibe $e) 3 # should be 5

# bind the function to a variable using 'let' so we can call it by name.
(ibf let (gbs add2) (ibe $e)).ToString()
# invoke the new function
ibf add2 10 # should be 12

# Use New-BraidLambda to create a lambda function that uses the 'while' function.
$f = (nbl x `
    (nbe (gbf while) (gbs x) `
        (nbe (gbf print) (gbs x) " ") (nbe (gbf let) (gbs x) `
        (nbe (gbf -) (gbs x) 1)) `
    ) `
)
$f.ToString()
write-host "Printing the numbers from 20 down to 1:"
ibf $f 20

# Create a function "addpair" using'let' that takes two arguments and returns their sum.
ibf let (gbs addpair) (nbl (gbs x),(gbs y) (nbe (gbf +) (gbs x) (gbs y)))
write-host "addpair(3,4):" (ibf addpair 3 4) # should be 7

# Defining a function using New-BraidFunction, which is easier than constructing it manually.
# This function will add 3 to its argument, but also print "Hello there" as a side effect.
[void] (New-BraidFunction add3 x (nbe (gbf println) "Hello there") (nbe (gbf +) (gbs x) 3))
(gbf add3).ToString() # print the defined function
write-host "Invoking add3(7):" (ibf add3 7) # should print "Hello there" and then return 10

write-host "Define a Braid function with a ScriptBlock body"
sbvv "pstest" {param ($x, $y) $x * $y}
ibf pstest 13 14
write-host "Create a curried function using Braid's 'partial' function and then call it:" 
sbvv by10 (ibf partial (gbf pstest) 10) | ToString
write-host "Now call the curried function by10 with an argument of 5:" (ibf by10 5) # should be 50

#-------------------------------------------------------------------------------------

# Use the 'list/split' function to split a list of numbers into two lists: one with numbers less than 4,
# and one with numbers greater than or equal to 4. We'll use a lambda as the splitting function.
write-host "split list with lambda:" `
    ((ibf list/split (ibf vector 1 2 3 4 5) (nbl x (nbe (gbf "<") (gbs x) 4))).tostring()) # should be ((1 2 3) (4 5))

# parse braid source text
write-host 'Parsing braid source text:' (cfbst '(+ 1 2 (* 3 10) 4)' ).ToString()

# Call the 'tobraidsourcestring' function on a list
write-host 'call tobraidsourcestring on an expression' `
    (ibf tosourcestring (nbe (gbf +) 1 2 (nbe (gbf *) 3 10) 4))

# bind the lambda to a symbol to create a function
Write-Host "Create a new lambda expression."
$l = nbl (nbe x y) (nbe (gbf +) (gbs x) (gbs y))
(ibf let (gbs addpair) $l).ToString()
ibf addpair 2 3
Write-host "addpair(2,3):" (ibf addpair 2 3) # should be 5

# Filter a list using a regex
write-host "Filtering a list of numbers using a regex"
$e = (nbe (gbf filter) (nbe (gbf range) 20) ([regex] "[234]"))
Write-Host "filter expression:" $e.ToString()
ibe $e

# use a curried operation filter a list of numbers
write-host "Filtering a list of numbers using a curried operation"
$op = ibe (nbe (gbf %) 2)
$op.ToString()
ibf filter (ibf range 20) $op

write-host "Compare the two lists:" (ibf == (cfbst "(+ 1 2 3)") (nbe (gbf +) 1 2 3))

#-------------------------------------------------------------------------------------

write-host "`n----------------------------------------------------------------`n"

write-host "Testing a pattern function with 3 different values"
$f = ibf eval-string '(defn say-type2 | ^int -> "integer" | ^string -> "string" | -> "other")'
write-host "say-type2 123:" (ibf say-type2 123) # should be "integer"
write-host "say-type2 'abc':" (ibf say-type2 'abc') # should be "string"
write-host "say-type2 1.23:" (ibf say-type2 1.23) # should be "other"

# Use property patterns to filter the list of files
ibf filter (ls -file) (nbpp "extension" (nbl n (nbe (gbf "==") (gbs n) ".tl")) "name" ([regex] "^g")) | format-table

# Do it again but in seperate steps
Write-host "Just get the name of the files that have an extension of .tl and start with g:"
$pp = (
    nbpp `
       extension  (nbl n (nbe (gbf "==") (gbs n) ".tl")) `
       name       ([regex] "^g")
 )
ibf map (ibf filter (ls -file) $pp) (gbf .name)

write-host "`n----------------------------------------------------------------`n"

# Filter the event log with a property pattern that matches entries with 
# an EntryType of "error" and a message that contains the word "timeout"
if ( -not $elogdata)
{
    # Only do this once since getting the eventlog data is slow and we want to focus on the speed of the filtering.
    write-host "`n`nGetting eventlog data..."
    # $elogdata = get-eventlog system
}
write-host "Filtering eventlog data with a property pattern, get last 5 matches" 
ibf last (ibf filter $elogdata (nbpp EntryType "error" message ([regex] "timeout"))) 5 | format-table

write-host "Filtering eventlog data with a property pattern using a scriptblock, get last 5 matches"
ibf last (ibf filter $elogdata (nbpp EntryType {param ($o) $o -eq "Error"} message ([regex] "timeout"))) 5

<# PERFORMANCE: Compare times For PowerShell vs Braid:

# filter eventlog data using PowerShell native commands
PS[1] (57) > time {$elogdata | where {$_.entrytype -eq "error" -and $_.message -match "timeout"} | select -last 5}
255.074128 ms

# filter eventlog data using Braid propery patterns with a Braid lambda
PS[1] (58) > time {ibf last (ibf filter $elogdata (nbpp EntryType "error" message ([regex] "timeout"))) 5}
77.014396 ms

# filter eventlog data using Braid propery patterns with a PowerShell lambda (scriptblock)
PS[1] (59) > time {ibf last (ibf filter $elogdata (nbpp EntryType {param ($o) $o -eq "Error"} message ([regex] "timeout"))) 5}
161.845024 ms

#>

#-------------------------------------------------------------------------------------

write-host "`n----------------------------------------------------------------n"

# Destructuring assignment example with variables x & xs
write-host "Destructuring assignment example into variables x & xs from the list (1,2,3,4,5)"
ibf let (gbs x:xs) (1,2,3,4,5)
write-host "x: " (gbvv x)
write-host "xs:" (gbvv xs) 

write-host "`n----------------------------------------------------------------`n"

# defining a function by setting a variable "ee" to a lambda expression
sbvv (gbs ee) (nbl n (nbe (gbf if) (nbe (gbf even?) (gbs n)) (gbs true) (gbs false))) > $null
write-host "Function ee:" (gbf ee).ToString()
write-host "Testing the function ee that we defined using Set-BraidVariableValue with a lambda expression.`nee should return true for even numbers and false for odd numbers."
write-host "ee(2):" (ibf ee 2) # should be true
write-host "ee(3):" (ibf ee 3) # should be false

#-------------------------------------------------------------------------------------

write-host "`n`----------------------------------------------------------------`n"

# This example shows how to use the Braid async and await functions to make 
# an asynchronous http request to microsoft.com and await the result.
write-host "Async example: making an http request to microsoft.com using the http/get function from braid, and awaiting the result."
ibf using-module http  # make sure the http module is loaded so we can use the http/get function in the example below.
$l = nbl $null (nbe (gbf http/get) "http://microsoft.com")   # lambda that makes an http request to microsoft.com when invoked
$t = ibf async $l # invoke the lambda asynchronously, which will return a task object

# await the result of the http request and print the length of the response body
write-host "http/get returned" (ibf await $t | foreach ToString | foreach length) "characters"

#-------------------------------------------------------------------------------------

write-host "`n`----------------------------------------------------------------`n"

write-host "An example showing how to define a type/class in Braid using 'deftype'"
$t = ibe (nbe (gbs deftype) ([braidlang.typeLiteral]::new("footype", 0, "")) (gbs x) (gbs y))
write-Host "New type defined:" $t.ToString()
write-host "Looking at the properties of the defined type:`n"
ibf members-of $t

#-------------------------------------------------------------------------------------

write-host "`n`----------------------------------------------------------------`n"

Write-Host "Map/reduce (sum-of-products) of (1,2,3) and (4,5,6) with the zip function:"
(ibf sum (ibf zip (1,2,3) (4,5,6) (gbf *))).ToString()
Write-Host "Bind a function implementing a single node in a neural network:"
nbf neuralnode (gbs input) (nbe (nbe (gbs sum) (nbe (gbf zip) (gbs input) (ibf vector 4 5 6) (gbf *))))
write-host "neuralnode function:" (gbf neuralnode).ToString()
write-host "Testing the neuralnode function with input (1,2,3):" `
    (ibf neuralnode (1,2,3)) # should be 32 (1*4 + 2*5 + 3*6)