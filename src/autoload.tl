;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This is the Braid prelude file defining additional functions
; for the environment.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Some PowerShell command aliases - these should be the same on all platforms
(let start  (Get-command 'Start-Process | baseobject))
(let ls     (Get-command 'Get-ChildItem | baseobject))
(let cat    (Get-command 'Get-Content   | baseobject))
(let rm     (Get-Command 'Remove-Item   | baseobject))
(let mv     (Get-Command 'Move-Item     | baseobject))
(let cp     (Get-Command 'Copy-Item     | baseobject))

;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Global Macros
;
; - macro definitions need to be defined before any usage since they
; both bound and evaluated at compile time
;

;--------------------------------------------------------------------------
;
(defmacro using-assembly
"
A macro for loading a .NET assembly at compile time.

Examples:
    (using-assembly winforms)

See also: load using-module
"
    [&args]

    (foreach asm args
        (.reflection.assembly/LoadWithPartialName (^string? asm))
    )
)

;--------------------------------------------------------------------------
;
(defmacro for
"""
Macro implementing the for "statement" built on top of the while function.

Examples:
    (for (def i 0) (<= i 10) (incr i)
        (println "Hi there")
        (println "i is" i)
    )
"""
    [init-expr test-expr incr-expr &args]

    `(do ~init-expr (while ~test-expr ~@args ~incr-expr))
)

;--------------------------------------------------------------------------
;
(defmacro when
"
'when' macro: when the condition is true, execute the block of statements.
"
    [cond-expr &args]

    `(if ~cond-expr (do ~@args))
)

;--------------------------------------------------------------------------
;
(defmacro unless
"
'unless' macro: when the condition is false; execute the block of statements.
"
    [cond-expr &args]

    `(if (not ~cond-expr) (do ~@args))
)

;--------------------------------------------------------------------------
;
(defmacro comment
"
macro to comment out a list of forms (but that list must be well-formed).
"
    [&args]
    
)

;--------------------------------------------------------------------------
;
(defmacro fn
"
Macro for creating function literals of the form (\ <args> -> <body>).

Examples:
    (\ a b c -> (+ a b c))                         ; define a function literal that adds 3 values
    (range 10 | map (\ x -> (* x x)) | sum)        ; use a function literal for squaring numbers
    (range 10 | map (\ x -> (println x) (* x x)))  ; Multiple expressions are allowed
    (def sqr (\ x -> (* x x))) (sqr 4)             ; define a 'sqr' function then call it - returns 16
    (\ (^int a) (^int b 1) -> (+ a b)              ; arguments can have type constraints and initializers
"
    [&args]

    (if (== (count args) 0)
        (return (list (get-symbol "fn")))
    )

    ; compile a pattern function: (\ | x -> y | ...)
    (if (car args | == .BraidLang.symbol/sym_pipe)
        (do
            (let lam (.BraidLang.Braid/parsepattern "*fn-macro*" (to-vector args) 0 false))
            (let lamlit (new ^BraidLang.FunctionLiteral lam))
            (return lamlit)
        )
    )

    ; Seperate the arguments from the lambda body.
    (let fargs:fbody: (list/split args '->))

    ; see if this is a typed function: (\ ^int a b -> (+ a b))
    (let a (car fargs))
    (let returnType null)
    (if (is? a ^TypeLiteral)
        (do
            (let returnType a)
            (let fargs (cdr fargs))
        )
    )

    ; make sure all the args are either symbols or parameter specifications
    ; i.e. name, (name initializer) (^type name) (^type name initialValue)
    (foreach arg fargs
        (matchp @arg
            | ^Symbol
            | ^TypeLiteral ^Symbol
            | ^TypeLiteral ^Symbol _
            | ^Symbol _  -> arg
            |            -> (throw (str "fn: tokens before the '->' in a function literal must be "
                                "parameter specifications, not '${arg}' (${(type-of arg)})"))
        )
    )

    ; put the arguments into a vector literal as required
    (let argsvect (new ^BraidLang.vectorliteral (aslist fargs) 0))

    (let fbody (or fbody '(null)))

    ; Insert a "compiled" function reference.
    (let lam (.BraidLang.Braid/BuildUserFunction [argsvect @fbody]))
    (if returnType
        (.ReturnType lam returnType)
    )

    (new ^BraidLang.FunctionLiteral lam)
)

; alias \ to fn so you can write (\ x y -> (+ x y))
(let \ fn)

;--------------------------------------------------------------------------
;
(defmacro case
"""
A macro for the 'case' expression. A case expression looks like:
  (case (+ 2 3) 1 "One" 2 "Two" 3 "three")
which will generate a cond statement that looks like:
  (do
    (def sym_140875202 (+ 2 3))
    (cond (== sym_140875202 1)
        "One" (== sym_140875202 2)
        "Two" (== sym_140875202 3)
        "three"
    )
  )

See also: if cond matchp
"""
    [&args]

    ; the variable used to hold the value being tested
    (let condvar    (gen-symbol))
    (let caseexpr   nil)
    (let final      nil)
    (let result     nil)
    (let valToTest  nil)
    (let action     nil)

    ; set up the case variable binding
    (let caseexpr (car args))
    (let args (cdr args))
    (let final
        (list (get-symbol 'do)
            (list (get-symbol 'def) condvar caseexpr)
        )
    )

    ; now set up the cond binding
    (let result (list (get-symbol 'cond)))
    (while args
        (let valToTest:action:args args)
        ; if it's the symbol default then mark as true
        (if (== valToTest (get-symbol 'default))
            (list-add result true)
            (list-add result (list (get-Symbol '==) condvar valToTest))
        )
        (list-add result action)
    )
    (list-add final result)
    final
)

;--------------------------------------------------------------------------
;
(defmacro lazy-each
"
A macro to support 'lazy each' functionality.
"
    [args expr]

    (drain (lazy-map args expr))
)

;--------------------------------------------------------------------------
;
(defmacro =
"
A macro that parses and transforms infix arithmetic expressions with
conventional operator precedence into prefix notation. The net effect
is similar to the 'expr' function in TCL but has no runtime impact.

Examples:
    (= 2+2)
    (= a * (b + 6))
"
    [&args]

    ; Regular expression for the expression 'language' tokens. Numbers go last.
    (const expression_pattern  #"(?x)
        \*\*
        |>=
        |<=
        |==
        |!=
        |[.+*/%()<>-]
        |>=
        |<=
        |==
        |!=
        |\s+
        |[a-z]+
        |[0-9][0-9_]*([.][0-9_]+)?(e[+-]?[0-9_]+)?
        ")

    ;----------------------------------------------
    ;
    ; Creates a token "stream" from a string accessed through the
    ; closure returned.
    ;
    (defn Tokenize [(^string? string)]

        ; Split the string into tokens with the 'matches' operator
        (const tokens (.matches expression_pattern string | map .value | filter -not #"\s+"))
        (let tindex 0)
        ; Return a closure that can be used to return the next token
        (lambda []
            (let result null)
            (when (< tindex (count tokens))
                (let result (!! tokens tindex))
                (incr tindex)
            )
            result
        )
    )

    ;----------------------------------------------
    ;
    ; Precedence table for operators expressed as a pattern function.
    ;
    (defn prec
         | "<"  -> 1
         | "<=" -> 1
         | ">"  -> 1
         | ">=" -> 1
         | "==" -> 1
         | "!=" -> 1
         | "+"  -> 2
         | "-"  -> 2
         | "*"  -> 3
         | "/"  -> 3
         | "%"  -> 3
         | "**" -> 4
         | "."  -> 5
         | bad  -> (throw "Invalid operator '${bad}'")
    )

    ;----------------------------------------------
    ;
    ; Parse a stream of numbers and operators like
    ;   2 + 4 * 5
    ; into an executable expression that looks like:
    ;   (+ 2 (* 4 5))
    ;
    (defn ParseExpr [next]

        ; the value and operator stacks; just plain old vectors
        ; since Braid Vector types have .push() and .pop() methods
        (let valstk [])
        (let opstk  [])

        ; parse the tokens into an executable expression
        (let doloop true)
        (while (and doloop (let token (next)))
            (matchp token
                ; nested expressions
                | "("   ->
                    (.push valstk (ParseExpr next))
                | ")"   ->
                    ; need to use loop variable because break is eaten by the pattern matcher
                    (let doloop false)
                ; numbers
                | #"^[0-9_]+(\.[0-9_]+)?(e[+-]?[0-9]+)?$" ->
                    (.push valstk (^double? token))
                ; variables
                | #"^[a-z_][a-z0-9_]*" ->
                    (.push valstk (get-symbol %0))
                ; Process operators
                | ->
                    (while (and (.count opstk) (>= (prec (!! opstk 0)) (prec %0)))
                        (let v2 (.pop valstk))
                        (let v1 (.pop valstk))
                        (let op (get-symbol (.pop opstk)))
                        (if (== op (get-symbol "."))
                            (do
                                (.push valstk (list op v1 "${v2}"))
                            )
                            (do
                                (.push valstk (list op v1 v2))
                            )
                        )
                    )
                    (.push opstk %0)
            )
        )

        ; drain the stacks
        (while (> (count opstk) 0)
            (let v2:v1:op: (list (.pop valstk) (.pop valstk) (get-symbol (.pop opstk))))
            (if (== op (get-symbol "."))
                (.push valstk (list op v1 "${v2}"))
                (.push valstk (list op v1 v2))
            )
        )

        ; and return the resulting expression
        (if (count valstk)
            (!! valstk 0)
        )
    )

    ; gather the args, join them into a string, tokenize then parse them into s-expressions
    (echo args | join | tokenize | parseexpr )
)

;--------------------------------------------------------------------------
;
; A Macro that parses and transforms infix arithmetic expressions with
; conventional operator precedence into prefix notation in a let expression
;
; (Net effect is similar to the 'expr' function in TCL but has no runtime impact
;

(defmacro let= [varToSet &args]

    ; Regular expression for the expression 'language' tokens. Numbers go last.
    (const expression_pattern  #"(?x)
        \*\*
        |>=
        |<=
        |==
        |!=
        |[.+*/%()<>-]
        |>=
        |<=
        |==
        |!=
        |\s+
        |[a-z]+
        |[0-9][0-9_]*([.][0-9_]+)?(e[+-]?[0-9_]+)?
        ")
    ;----------------------------------------------
    ;
    ; Creates a token "stream" from a string accessed through the
    ; closure returned.
    ;
    (defn Tokenize [(^string? string)]

        ; Split the string into tokens with the 'matches' operator
        (with [
                tokens (.matches expression_pattern string | map .value | filter -not #"\s+")
                tindex 0
            ]

            ; Return a closure that can be used to return the next token
            (lambda []
                (let result null)
                (when (< tindex (.count tokens))
                    (let result (!! tokens tindex));
                    (incr tindex)
                )
                result
            )
        )
    )

    ; Precedence table for operators expressed as a pattern function.
    (defn prec
         | "<"  -> 1
         | "<=" -> 1
         | ">"  -> 1
         | ">=" -> 1
         | "==" -> 1
         | "!=" -> 1
         | "+"  -> 2
         | "-"  -> 2
         | "*"  -> 3
         | "/"  -> 3
         | "%"  -> 3
         | "**" -> 4
         | "."  -> 5
         | bad  -> (throw "Invalid operator '${bad}'")
    )

    ;----------------------------------------------
    ;
    ; Parse a stream of numbers and operators like
    ;   2 + 4 * 5
    ; into an executable expression that looks like:
    ;   (+ 2 (* 4 5))
    ;
    (defn ParseExpr [next]

        ; the value and operator stacks; just plain old lists
        ; since BraidLists have .push() and .pop() methods
        (let valstk [])
        (let opstk  [])

        ; parse the tokens into an executable expression
        (let doloop true)
        (while (and doloop (let token (next)))
            (matchp token
                ; nested expressions
                | "("   ->
                    (.push valstk (ParseExpr next))
                | ")"   ->
                    ; need to use loop variable because break is eaten by the pattern matcher
                    (let doloop false)
                ; numbers
                | #"^[0-9_]+(\.[0-9_]+)?(e[+-]?[0-9]+)?$" ->
                    (.push valstk (^double? token))
                ; variables
                | #"^[a-z_][a-z0-9_]*" ->
                    (.push valstk (get-symbol %0))
                ; Process operators
                | ->
                    (while (and (.count opstk) (>= (prec (!! opstk 0)) (prec %0)))
                        (let v2 (.pop valstk))
                        (let v1 (.pop valstk))
                        (let op (get-symbol (.pop opstk)))
                        (if (== op (get-symbol "."))
                            (do
                                (.push valstk (list op v1 "${v2}"))
                            )
                            (do
                                (.push valstk (list op v1 v2))
                            )
                        )
                    )
                    (.push opstk %0)
            )
        )

        ; drain the stacks
        (while (> (count opstk) 0)
            (let v2:v1:op: (list (.pop valstk) (.pop valstk) (get-symbol (.pop opstk))))
            (if (== op (get-symbol "."))
                (.push valstk (list op v1 "${v2}"))
                (.push valstk (list op v1 v2))
            )
        )

        ; and return the resulting expression
        (if (count valstk)
            (!! valstk 0)
        )
    )

    ; gather the args, join them into a string, tokenize then parse them into s-expressions
    `(let ~varToSet ~(args | join | tokenize | parseexpr))
)

;--------------------------------------------------------------------------
;
(defmacro from
"
The 'from' macro is a list comprehension operator that iterates over multiple lists.
It is structurally similar to 'let' in that the first argument is a vector composed
of variable/list pairs and the remaining args represent the executable body of the
'statement'. Implementation-wise, this macro uses 'forall -flatten' to maintain a
result depth of 1.

Examples:
  (from [a [1 2 3] b (range 5) c [10 20 30]]
      [a b c]
  )
"

    [(^VectorLiteral vars) &args]

    (let result nil)
    (foreach [vn lst] (.valueList vars)
        (if (not result)
            (do
                (let result `(with [~vn null] (forall ~vn ~lst ~@args)))
            )
            (do
                (let result `(with [~vn null] (forall -flatten ~vn ~lst ~result)))
            )
        )
    )

    result
)

;--------------------------------------------------------------------------
;
(defmacro let?
"
Macro shortcut to 'let -success ...'
"
    [symbol value]

    `(let -success ~symbol ~value)
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; System utilities
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defn help
    "Gets help information about commands. The first argument is unevaluated."
    [:syntax (pattern null)]

    (let ^regex? pattern
        (matchp pattern
            | null -> #"."
            | (^callable f) -> (^regex? (str "^" (.name f) "$"))
            | (^regex? re)  -> re
            | x             -> (^regex? (tostring x))))

    (if syntax
        (do
            ; only show the syntax line from each entry
            (functions
            | filter (\ n -> (.key n | re/match pattern)) ; filter on the name
            | map .value
            | map doc
            | re/split-all #"\n"
            | filter #"Syntax:"
            | join "\n"
            )
        )
        (do
            ; show all the text
            (functions
            | filter (\ n -> (.key n | re/match pattern))
            | map .value
            | map doc
            | join "\n\n"
            )
        )
    )
)

;--------------------------------------------------------------------------
;
; Computed variable returning the most recent 100 entries in command history
; BUGBUGBUG - disabled because its annoying - should be able to use single letters as variables.
;(undef h)
;(let h null -getter: (\ _ -> (.CommandHistory *line-editor* | .Dump | last 100 | tostring-all | join "\n")))

;--------------------------------------------------------------------------
;
(defn parse-text
"""
Parses a string into s-Expressions. This can be useful to see what a macro
expands to.

Examples:
    (.BraidLang.Braid/parse "(for (let i 0) (< i 10) (incr i))")
    ; after macro expansion, resolves to:
    ((do (let i 0) (while (< i 10) (incr i))))
    ; with the macro fully expanded.

See also: file/parse eval
"""
    [text]

    (.BraidLang.Braid/parse text)
)

;--------------------------------------------------------------------------
;
(defn tokenize-file
"
Parses the contents of a file and returns the tokens it contains

See also: parse-text file/parse eval
"
    [filename]

    (tokenize-text (read-text filename))
)

;--------------------------------------------------------------------------
;
(defn walk-tree
"
Walks a parsed tree applying an action to each subtree.

Examples:
    (walk-tree '(do (+ 1 2) (* 3 4) (% (- c a) b)) (\ n -> (info n)))

See also: file/parse parse-text tokenize-file tokenize-text
"
    | (^ISeq t) action ->
        (if (not (quote? t))
            (do
                (if (is? (car t) ^ISeq)
                    (walk-tree (cdr t) action)
                    (action t)
                )
            )
       )

    | (^iseq t) -> (recur t (\ n -> (println n)))
    | ->
)

;--------------------------------------------------------------------------
;
; Gets the current (active) stack frame object.
(undef *CallStack*)
(let *CallStack* null -getter: (fn _ -> (upDo (.Braid/CallStack | .parent))))

;--------------------------------------------------------------------------
;
; Gets the current (active) stack frame object.
(undef *now*)
(let *now* null -getter: (fn _ -> (.datetime/now)) )

;--------------------------------------------------------------------------
;
; Gets the list of defined Braid types.
(undef *types*)
(let *types* null -getter: (fn _ -> (upDo '(.Braid/CallStack | .gettypes))))

;--------------------------------------------------------------------------
;
; Macro shortcut to "(void (let name value))"
;
(defmacro vlet
    | (^TypeLiteral tlit) (^symbol symbol) value ->
        `(let ~tlit ~symbol ~value | void)
    | (^symbol symbol) value ->
        `(let ~symbol ~value | void)
    | -> (throw "vlet: invalid syntax. (vlet [<type>] <symbol> <value>)") 
)

;--------------------------------------------------------------------------
;
(defn doc
"A function to quickly get the documentation string for a function"
    [function]

    (get-assoc function "helptext" | tostring | .trim)
)

;--------------------------------------------------------------------------
;
(defn loaded-functions
"
Find the functions loaded from the file matching the argument pattern.

Examples:
    (loaded-functions)

See also: loaded-files loaded-types
"
    [(^regex? pattern #".")]

    ((functions)
        | map .value
        | filter ^Callable
        | map .Name
        | filter (\ f -> (re/match f pattern))
     )
)

;--------------------------------------------------------------------------
;
(defn where-defined
"Function to figure out where a function was defined (i.e. what source file.)"
    | ^Callable      -> (file/filename (.file %0))
    | ^CommandInfo   -> "external powershell"
    | ^ScriptBlock   -> "powershell"
    |                -> "built-in"
)


;--------------------------------------------------------------------------
;
(defn loaded-files
"
Find all of the loaded source files.

Examples:
    (loaded-files)

See also: loaded-types loaded-functions"
    []

    ([
        ; regular functions
        @((functions)
            | map .value
            | filter ^Callable
            | map .File
        )

        ; types
        @(.GetTypes *CallStack*
            | .values
            | filter ^BraidLang.BraidTypeBase
            | map #(get-assoc %0 :FileInfo | re/split ":" | !! 0)
        )]
            | distinct
                | sort)
)

;--------------------------------------------------------------------------
;
(defn loaded-types
"
Find all of the Braid-based types that have been loaded.

Examples:
    (loaded-types)

See also: loaded-files loaded-functions
"
    []

    (.GetTypes *callstack*
    | .values
    ; BUGBUGBUG - now that braid can extend existing types, this is not sufficient  
    | filter ^BraidLang.BraidTypeBase
    | map (\ ty -> (str "type: " (. ty 'name) " file: "  (get-assoc ty :FileInfo )))
    )
)

;--------------------------------------------------------------------------
;
(defn getmacro
"
Get the macro associated with the argument symbol. If the argument is null
then the entire table is returned.
"
    [(^regex? namePattern #".")]

    (functions namePattern
    | where (\ f -> (.value f | .?ftype | == .BraidLang.FunctionType/macro))
    | map .key
    )
)

;--------------------------------------------------------------------------
;
(defn call
"
Utility to call a function on a set of args; (Not sure this really needs
to exist...).

Examples:
    (call <function> <args...>)

See also: apply
"
    [function &args]

    (eval (cons (getfunc function) args))
)

;--------------------------------------------------------------------------
;
(defspecial background
"
Run an expression in the background using a .NET ^Task. This ^Task will be
run in memory but on a seperate thread so it doesn't block the REPL thread.

Examples:
    (background (textedit 'autoload.tl))
"
    [expr]

    (if (not (pair? expr))
        (let expr (list expr))
    )

    (let t (async (\ -> (try (eval expr) -catch: ""))))
    "Started task ${(.Id t)}"
)

;--------------------------------------------------------------------------
;
(defn partial
"
The 'partial' function takes a function of n-arguments and returns
a new function of n-1 arguments. The signature of the function
is:
(partial function value &args)
The first argument is the function to be curried, the second and remaining
arguments will be passed to that function by default when the new function is applied.
For example, consider the following definition:
(let +1 (partial + 1))
This takes the plus function which takes 2 arguments and returns a new function
'+1' which takes 1 argument. This new function can be applied as follows.

Examples:
    (+1 1)      ; returns 2
    (+1 (+1 1)) ; returns 3

See also: compliment compose
"
    [func-to-call value &args]

    (let func-to-call (getfunc -caller func-to-call))
    (lambda [&args]
        (func-to-call @args value)
    )
)

;--------------------------------------------------------------------------
;
(defn compliment
"
The 'compliment' function is identical to 'partial' except that a call
to 'not' is wrapped around the expression.

Examples:
    (let isNot2 (compliment == 2))
    (isnot2 3)                          ; returns true

See also: partial compose
"
    [func-to-call value &args]

    (let func-to-call (getfunc -caller func-to-call))
    (lambda [&args]
        (not (func-to-call @args value))
    )
)

;--------------------------------------------------------------------------
;
(defspecial compose
"
The 'compose' function takes a list of functions and returns a new function
composed of the individual functions piped together.

Examples:
    ; define a function that adds 1 to its argument, then 2 then multiplies by 3
    (let f (compose ++ (+ 2) (* 3)))
    (f 5)                                    ; returns 24
    (range 10 | filter (compose (% 2) not))  ; returns the even numbers

See also: partial compliment
"
    [&args]
    
    (eval
        (list lambda ['val]
            (list pipe '(echo val)
                @(forall a args
                    (if (pair? a)
                        (cond
                            (car a | == 'partial)
                                (upDo a)
                            (car a | == 'compose)
                                (upDo a)
                            true
                                a
                        )
                        (getfunc -caller a)
                    )
                )
            )
        )
    )
)
(def $ compose)

;--------------------------------------------------------------------------
;
(defspecial or$
"
The 'or$' ('or compose') function takes a list of functions and returns
a new function composed of the individual functions with the results or'ed
together. The argument to the outer function is passed to each of the
inner functions. The results of these functions are or'ed together to
produce a final result.


Examples:
    ; the following returns all members of the range divisible by 3 or 5
    (range 20 | filter (or$ ($ (% 3) not) ($ (% 5) not) false))
    ; define a function that returns true for numbers > 10 or < 5
    (let f (or$ (> 10) (< 5)))
    (f 12)                      ; returns true
    (f 7)                       ; returns false
    (f 3)                       ; returns true

See also: partial compliment compose
"
    [&args]
    
    (eval
        (list lambda ['val]
            (list or 
                @(forall a args
                    (if (pair? a)
                        (cond
                            (car a | == 'partial)
                                (list (upDo a) 'val)
                            (car a | == 'compose)
                                (list (upDo a) 'val)
                            true
                                (list a 'val)
                        )
                        (do
                            (let func (getfunc -caller (upDo a)))
                            (if (null? func)
                                (throw "or$: no function corresponding to '${a}' was found.")
                            )
                            (list func 'val)
                        )
                    )
                )
            )
        )
    )
)

;--------------------------------------------------------------------------
;
(defspecial and$
"
The 'and$' ('and compose') function takes a list of functions and returns
a new function composed of the individual functions with the results and'ed
together. The argument to the outer function is passed to each of the
inner functions. The results of these functions are and'ed together to
produce a final result.


Examples:
    (let f (and$ (< 10) (> 5)))
    (f 12)                      ; returns false
    (f 7)                       ; returns true
    (f 3)                       ; returns false

See also: partial compliment compose
"
    [&args]
    
    (eval
        (list lambda ['val]
            (list and 
                @(forall a args
                    (if (pair? a)
                        (cond
                            (car a | == 'partial)
                                (list (upDo a) 'val)
                            (car a | == 'compose)
                                (list (upDo a) 'val)
                            true
                                (list a 'val)
                        )
                        (do
                            (let func (getfunc -caller (upDo a)))
                            (if (null? func)
                                (throw "and$: no function corresponding to '${a}' was found.")
                            )
                            (list func 'val)
                        )
                    )
                )
            )
        )
    )
)

;--------------------------------------------------------------------------
;
(defn memoize
"
This function wraps a single argument function in a memoization closure
by doing
(let fib (memoize fib))
which replaces the current 'fib' binding in the variable table with a
memoized version.  A memoized function will remember each input/output
pair and return the result if it has already been calculated.
This makes the naive recursive fib function many time faster.

Examples: (let fib (memoize fib))
"
    [fnToMemoize]

    (let data (new ^Dictionary[object,object]))
    (fn n ->
        (if (.containsKey data n)
            (!! data n)
            (do
                (let result (fnToMemoize n))
                (!! data n result)
                result
            )
        )
    )
)

;--------------------------------------------------------------------------
;
; Implement a trampoline function for Braid
;
(defn trampoline
"""
A 'trampoline' function for Braid. This takes a function of one argument
that will either return a new function of no arguments or a value. If a function
is returned, it's called it with no arguments. This is repeated until a non-function
value is returned.

Examples:
    (defn foo [x] (if x (do (info :x x) #(foo (-- x))) "All Done"))  ; function to trampoline
    (trampoline foo 10)                                                ; trampoline it.
"""
    [func arg]

    (let res (func arg))
    (while (function? res)
        (let res (res))
    )
    res
)

;--------------------------------------------------------------------------
;
(defspecial >let
"
This special form allows left-to right assignment.

Examples:
    (ls '*.tl | map .length | sum | >let total)         ; 'total' contains the length of all of the files
    ([1 2 3] | >let a:b:c:)                             ; multiple assignment works
"
    [expression varsym]

    (upDo (list 'let varsym expression))
)

;--------------------------------------------------------------------------
;
(defspecial let-default
"
This special form sets the value of the identified variable if the variable is unbound or empty
or constrains it if it is bound.

Examples:
    (let-default foo 123)           ; if foo is null or unbound, sets it to 123.
    (let-default ^int foo 123)      ; if foo is null or unbound, sets it to 123 with a type constraint.
    (let-default foo 10 20)         ; if foo is set, constrain the value to be between 10 and 20.
    (let-default ^int foo 10 20)    ; if foo is set, constrain the value to be between 10 and 20.

See also: let let?
"
    | (^symbol sym) expr ->
        (upvar sym 'lcl)
        (if (null? lcl)
            (void (upDo (list 'let sym expr)))
        )

     | (^TypeLiteral t) (^symbol sym) expr ->
        (upvar sym 'lcl)
        
        (if (null? lcl)
            (void (upDo (list 'let t sym expr)))
            (void (upDo (list 'let t sym lcl)))
        )


    | (^symbol sym) low high ->
        (upvar sym 'lcl)
        (cond
            (null? lcl)
                (let lcl low)
            (< lcl low)
                (let lcl low)
            (> lcl high)
                (let lcl high)
        )

    | (^TypeLiteral type) (^symbol sym) low high ->
        (upvar sym 'lcl)
        (cond
            (or (null? lcl) (isnot? lcl type))
                (upDo (list 'let type sym low))
            (< lcl low)
                (upDo (list 'let type sym low))
            (> lcl high)
                (upDo (list 'let type sym high))
        )

     | ->
        (throw (str
            "Argument error in 'let-default'. This function takes 2-4 arguments, not <<"
            (.trim (.braid/truncate (get-args)) "[]")
            ">> The syntax is:\n"
            "           (let-default [<type>] <sym> <expression>)\n"
            "           (let-default [^type] <sym> <lower> <upper>)."))
)

;--------------------------------------------------------------------------
;
(defn vars
"
Function to print out the variables in the current scope. An optional
regular expression can be specified to filter the results.
"
    [(^regex? varname #"")]

    (.BraidLang.Braid/callstackstack
    | .GetEnumerator
    | flatmap .vars
    | flatmap .keys
    | distinct
    | where -not (\ vname -> (getfunc -noexternals vname))
    | filter varname)
)

;--------------------------------------------------------------------------
;
; Define a computed variable for 'pwd' instead of a function.
;
(undef pwd)
;(let pwd -getter: (\ _ -> (.environment/CurrentDirectory)) nil)
(defn pwd [] (.environment/CurrentDirectory))

;--------------------------------------------------------------------------
;
; Initialize the directory stack
;
(if (not (bound? 'DIRLIST) | or (not DIRLIST))
    (global "DIRLIST" {(pwd) true})
)

; load the previously stored list of directories
;(global "DIRS_PATH"  (join-path (resolve-path "~/.config") "braid.dirs"))
(global "DIRS_PATH" (join-path (.historydir *line-editor*) "braid.dirs"))
(if (test-path DIRS_PATH)
    (read-lines DIRS_PATH | map (\ p -> (!! DIRLIST p true)))
)

;--------------------------------------------------------------------------
;
; Initialize the OLDPATH variable used for "cd -"
;
(if (not (bound? 'OLDPATH) | or (not OLDPATH))
    (global "OLDPATH" .environment/CurrentDirectory)
)

;--------------------------------------------------------------------------
;
(defmacro my
    "Changes directory relative to the user's document directory"
    | path  -> `(cd -my ~path)
    |       -> `(cd -my)
)

;--------------------------------------------------------------------------
;
(defspecial cd
"Directory stack aware 'cd' change directory function."
    [(path "~") :parent :replace: :my]

    (matchp path
    | (^symbol sym) :where (file/dir-exists (.value sym)) -> (let path (.value sym))
    | -> (let path (^string? (upDo path)))
    )

    (when replace
        (let path (re/replace path replace))
    )
  
    (when parent
        (let path (Split-Path path))
    )
  
    (when my
        (if (== path "~") (let path ""))
        (let path (str "~/documents/" path))
    )

    ; .'ing shortcuts
    (matchp path
    | "..."     -> (let path "../..")
    | "...."    -> (let path "../../..")
    | ->
    )

    (when (let index (as path ^int?))
        (dirs path)
        (return)
    )

    (matchp path
    | "-" ->
            (if (bound? 'OLDPATH)
                (do
                    ; pop back to your old path
                    (alert "cd'ing back to" (global "OLDPATH"))
            
                    (let temp .environment/CurrentDirectory)
                    (Set-Location (global "OLDPATH"))
                    (.environment/CurrentDirectory (^string? (get-location)))
                    (global "OLDPATH" temp)
                )
                (warn "OLDPATH not set")
            )
     | ->
            (let temp .environment/CurrentDirectory)
            (Set-Location path)
            (.environment/CurrentDirectory (^string? (get-location)))
            (global "OLDPATH" temp)
            (!! DIRLIST .environment/CurrentDirectory true)
            ; save the current dir list
            (.keys DIRLIST | sort | write-lines DIRS_PATH)
            .environment/CurrentDirectory
    )
)

;--------------------------------------------------------------------------
;
(defn dirs
"function to list and navigate the directory stack"
    [(^int? entry -1)]

    (let dl (.keys DIRLIST | sort))
    (if dl
        (if (<= 0 entry (count dl | - 1))
            (do
                (cd (!! dl entry))
            )
            ; otherwise
            (do
                (let cnt 0)
                (foreach d dl
                    (info (fmt "{0,3} {1}" (pincr cnt) d))
                )
            )
        )
    )
)

;--------------------------------------------------------------------------
;
(defn sleep
"
This function sleeps for the specified number of milliseconds.
Note that it sleeps in chunks so it can be interrupted with ctrl-C.

Examples:
    (sleep 1000)        ; sleep 1 second
    (sleep (* 1000 60)) ; sleep 1 minute
"
    [(^int duration-ms)]

   (let iter (div duration-ms 100))
   (let rest (^int (% duration-ms 100)))

   (repeat iter (.System.Threading.Thread/sleep 100))
   (.System.Threading.Thread/sleep rest)
)

;--------------------------------------------------------------------------
;
; BUGBUGBUG - MAKING PID a const causes problems - undef doesn't seem to work - investigate
; Constant variable that contains the current process ID
;(if (not (bound? 'PID))
;    (const PID ((.System.Diagnostics.Process/GetCurrentProcess) | .id))
;)
(defn pid [] ((.System.Diagnostics.Process/GetCurrentProcess) | .id))

;--------------------------------------------------------------------------
;
(defn tid
    "Get the managed thread ID of the current thread."
    []

    (.System.Threading.Thread/CurrentThread | .ManagedThreadID)
)

;--------------------------------------------------------------------------
;
(defn path
    "Get the current value of the PATH environment variable."
    []

    (.Environment/GetEnvironmentVariable "PATH")
)

(if (not (bound? '*path*))
    (const *path* -getter: (\ _ -> (.environment/GetEnvironmentVariable "PATH")) nil)
)

;--------------------------------------------------------------------------
;
(defn get-env
"
This function gets the named environment variable. The '-scope:' option
allows variables to be retrieved at either machine or user scope
as well at process scope (the default).

Examples:
    (get-env 'zork)

See also: set-env env
"
    [(^string? varName) (^EnvironmentVariableTarget scope .EnvironmentVariableTarget/Process)]

    (if scope
        (.Environment/GetEnvironmentVariable varName scope)
        (.Environment/GetEnvironmentVariable varName)
    )
)

;--------------------------------------------------------------------------
;
(defn set-env
"
This function sets an environment variable. The '-scope:' option
allows variables to be set at either machine or user scope
as well at process scope (the default).

Examples:
    (set-env 'zork 13)

See also: get-env env
"
    [(^string? varName) (^string? value) (^EnvironmentVariableTarget scope .EnvironmentVariableTarget/Process)]

    (if scope
        (.Environment/SetEnvironmentVariable varName value scope)
        (.Environment/SetEnvironmentVariable varName value)
    )
)

;--------------------------------------------------------------------------
;
(defn env
"""
Gets all of the defined environment variables. An optional pattern (regex) can
be specified to filter the list. An option '-scope:' can be specified to
choose whether to dump the process, user or machine environment variables.

Examples:
    (env)                         ; get all process-scoped environment variables
    (env #"pro")                  ; get all process-scoped variables whose name matches 'pro'
    (env #"pro" -scope: 'machine) ; get all machine-scoped variables matching 'pro'

See also: get-env set-env
"""
    [(^regex? pattern #".") :scope]

    (let result
        (if (some? scope)
            (.Environment/GetEnvironmentVariables (^EnvironmentVariableTarget scope))
            (.Environment/GetEnvironmentVariables (.EnvironmentVariableTarget/process))
        | map echo ; BUGBUGBUG filter doesn't handle enumerables properly
        | filter #(pattern (.key %0))
        )
    )
    (if (.count result | == 1)
        (first result | .Value)
        ; otherwise
        result
    )
)

;--------------------------------------------------------------------------
;
(defn taskid
    "Get the current Task id. In the main context, this will be null."
    []

    (.System.Threading.Tasks.Task/CurrentID)
)

;--------------------------------------------------------------------------
;
(defn iterator
"
The iterator function is a way to produce a (possibly) infinite sequence
of values. Each new value in the sequence is computed by taking the
current value and passing it to the argument <function>. The result of evaluating
that function becomes the new current value. Instead of an array or list,
invoking iterator returns a .Net ^IEnumerable. Consumers can then get the enumerator
and iterate over that enumerator. If no 'max' is provided, the enumerator will
produce new values forever on until the consumer stops requesting values.
If 'max' is specified, values will be produced until 'max' is reached.

(Note: 'unfold' is an alias for 'iterator'.)

Examples:
    (iterator ++ 1 | take 100)        ; get integers from 1-100.
    (iterator (+ 2) 2 10)             ; even numbers from 2-10 inclusive.
    ; the following computes (fib 10)
    (iterator (\ x:y: -> [y (+ x y)]) [1 1] | take 10 | last | last)

See also: reduce foldl roldr unfold
"
    | func initialValue finalValue ->
        (new ^BraidLang.BraidEnumerable func initialValue finalValue)
    | func initialValue ->
        (new ^BraidLang.BraidEnumerable func initialValue)
    | func ->
        (new ^BraidLang.BraidEnumerable func)
    | ->
        (throw "invalid arguments to 'iterator'; syntax: (iterator <func> [<initialValue> [<finalValue>]])")
)
; Alias unfold to iterator.
(def unfold iterator)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; String utilities
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;--------------------------------------------------------------------------
;
(defn tostring-all
"
Turn all of the elements in a list into individual strings.
"
    [data]

    (map data ToString)
)

;--------------------------------------------------------------------------
;
(defn toSourceString
"""
Convert an object to a source-formatted string (i.e. escapes are included
in the strings, etc.)

Examples:
    (toSourceString "abc")      ; returns '"abc"' not 'abc'
    (toSourceString 3.0)        ; returns '3.0' not '3'
    (toSourceString #"[a-z]")   ; returns '#"[a-z]"' not '[a-z]'
"""
    [data]

    (.BraidLang.Utils/toSourceString data)
)

;--------------------------------------------------------------------------
;
(defn str/truncate
"
Truncate a string for printing to the console or a file. This function returns a single
string that will fit on one line on the console.
"
    [&args]

    (.BraidLang.Braid/truncate (join args))
)

;--------------------------------------------------------------------------
;
(defn str/startsWith
"""
The 'str/startswith' function returns true if that argument
string starts with the string fragment in the second argument.
The comparison is done case-insensitively by default. Use -case
to specify case-sensitive comparisons.

Examples:
    (str/startswith "abcd" "ab")        ; returns true
    (str/startswith "ABCD" "ab")        ; returns true
    (str/startswith -case "ABCD" "ab")  ; returns false
    (str/startswith "123abcd" "ab")     ; returns false
"""
    [(^string? str ) (^string? frag) :case]

    (if case
        (.startswith str frag)
        (.startswith str frag .StringComparison/OrdinalIgnoreCase)
    )
)

;--------------------------------------------------------------------------
;
(defn re/match
    "Match a single string against a regular expression."
    [(^string? targetString) (^regex? regex) (func nil) :notmatch]

    (let ^bool result (regex targetString | xor notmatch))

    (if (result | and func)
        (func targetString)
        result
    )
)

;--------------------------------------------------------------------------
;
(defn re/not-match
    "Match a single string that doesn't match a regular expression."
    [ (^string? targetString) (^regex? regex)]

    (.Match regex targetString | .Success | not)
)

;--------------------------------------------------------------------------
;
(defn re/match-all
"
Return all of the elements from a list that match the argument regex.
"
    [listOfStrings (^regex? pattern) :notmatch]

    (if notmatch
        (listOfStrings | filter -not pattern)
        (listOfStrings | filter pattern)
    )
)

;--------------------------------------------------------------------------
;
(defn re/not-match-all
"
Return all of the elements from a list that don't match the argument regex.
"
    [listOfStrings (^regex? pattern)]

    (listOfStrings | filter -not pattern)
)

;--------------------------------------------------------------------------
;
(defspecial ifmap
"""
The 'ifmap' special form can be used when processing data in a pipeline.
The first argument must be a list to process. The second argument is the
conditional expression. The third and optional fourth arguments are the 'if part'
and 'else part' which will be evaluated based on the result of the conditional
expression. To provide accesss to the current pipeline object, 'ifmap'
binds that value to the variable 'it' in the current scope.

Examples:
   (range 10 | ifmap (% it 2) "odd" "even")

See also: if map
"""
    [lst (cond-expr) (if-part) (else-part null)]

    (upvar 'it 'it)
    (if (not (null? else-part))
        (forall it (upDo lst)
            (if (upDo cond-expr)
                (upDo if-part)
                (upDo else-part))
        )
        ; else
        (forall it (upDo lst)
            (if (upDo cond-expr)
                (upDo if-part))
        )
    )
)

;--------------------------------------------------------------------------
;
(defn re/replace
"""
Replace all occurances of a substring in a string with an optional
replacement string. If the replacement string is not provided
then the empty string will be used.

Examples:
    (re/replace "abcd" #"[bd]+")          ; returns "ab"
    (re/replace "abcd" #"[bd]+" "---")    ; returns "a---d"

See also: re/replace-all
"""
    | (^string? string) (^regex? regex) (^string? replaceStr) ->
        (.replace (^regex? regex) (^string? string) (^string? replaceStr))
    | (^string? string) (^regex regex) ->
        (.replace regex string "")
    | ->
        (throw "re/replace invalid arguments: (re/replace <string> <regex> [<replaceStr>])")
)

;--------------------------------------------------------------------------
;
(defn re/replace-all
"""
Process a list of strings, replacing all occurances of the target string
in each list item with the provided replacement string. If no replacement
string has been provided, the empty string will be used.

Examples:
    (ls | .name | re/replace-add #"\.tl")       ; remove the .tl extension
    (ls | .name | re/replace-add #"\.tl" ".br") ; replace the .tl extension with .br

See also: re/replace
"""
    [lst (^regex? regexToReplace) (^string? replaceStr "")]

    (lst | map (\ it -> (.replace regexToReplace (^string? it) replaceStr)))
)

;--------------------------------------------------------------------------
;
(defn re/split
"""
The 'split' function will split a string into a number of pieces based on a provided
regular expression or using the default expression which is #" +". If the pattern is
empty i.e. #"", the string will be split into individual 1-character strings.

Examples:
    (re/split "a,b,c" #",")    ; returns ["a", "b", "c"]
    (re/split "a,b,c" , #"")   ; An empty pattern will split the string into individual characters.

See also: re/split-all
"""
    | stringToSplit (^symbol by) ->
        (.split (tostring stringToSplit) (.value by) | to-vector)

    | stringToSplit (^regex by) ->
        (.split by (tostring stringToSplit) | to-vector)

    | stringToSplit (^char by) ->
        (.split (tostring stringToSplit) by | to-vector)

    | stringToSplit (^string by) ->
        (.split (tostring stringToSplit) by | to-vector)

    | stringToSplit ->
        (.split #" +" (tostring stringToSplit) | to-vector)
)

;--------------------------------------------------------------------------
;
(defn re/split-all
"
Splits each string in the argument list, flattens the result then
returns the new vector containing all of the individual strings. An
optional regular expression can be provided to use during the splits.
The default split pattern is 1 or more whitespaces.
"
    [lst (^regex? by #" +") :dontFlatten]

    (if (is? lst ^string)
        (return (re/split lst by))
    )

    (if dontFlatten
        (map lst (\ (^string? string) -> (re/split string by)))
        (flatmap lst (\ (^string? string) -> (re/split string by)))
    )
)

;--------------------------------------------------------------------------
;
(defn Str-To-Upper
    "Make the first character in a string into an uppercase letter."
    [(^string? stringToProcess)]

    (if (null? stringToProcess | or (length stringToProcess | == 0))
        (return "")
    )

    (if (length stringToProcess | == 1)
        (.char/toupper (!! stringToProcess 0) | tostring)
        (.char/toUpper (!! stringToProcess 0) | ^string? | + (.substring stringToProcess 1))
    )
)

;--------------------------------------------------------------------------
;
(defn Str-To-Upper-All
    "Make all the characters in a string uppercase."
    [(^string? stringToProcess)]

    (.tochararray stringToProcess | map (\ c -> (.char/ToUpper c)) | join "")
)

;--------------------------------------------------------------------------
;
(defn Str-To-Lower
    "Makes the first character in a string a lowercase letter."
    [(^string? stringToProcess)]

    (.char/toLower (!! stringToProcess 0) | tostring | + (.substring stringToProcess 1))
)

;--------------------------------------------------------------------------
;
(defn Str-To-Lower-All
    "Make all the characters in a string uppercase."
    [(^string? stringToProcess)]

    (.tochararray stringToProcess | map (\ c -> (.char/ToLower c)) | join "")
)

;--------------------------------------------------------------------------
;
(defn fmt
    "Utility to format strings (using String.Format)"
    [&args]

    (let fmtstr:args args)
    (.string/format (tostring fmtstr) (asarray args))
)

;--------------------------------------------------------------------------
;
(defn hex
"
Function to take numeric arguments and turn them into hex strings. Normally
the strings are prefixed with '0x' but if -noprefix is specified, then the
'0x' prefix will be omitted. If a single value is converted, then it's returned
a a string. If more than one value is converted, then the results are aggregated
into a vector.
"
    [:noprefix &args]

    (if noprefix
        (args | map (\ num -> (fmt "{0:x4}" num)) | scalarize)
        (args | map (\ num -> (fmt "0x{0:x4}" num)) | scalarize)
    )
)

;--------------------------------------------------------------------------
;
(defn binary
"
Function to take numeric arguments and turn them into binary strings. Normally
the strings are prefixed with '0b' but if -noprefix is specified, then the
'0b' prefix will be omitted.
"
    [:noprefix n]

    (let result
        (str
            (repeat-all 32
                (let b (band n 1))
                (let n (shiftr n 1))
                b
            | reverse
            | join ""
            | re/replace #"^0+"
            )
        )
    )

    (if noprefix
        result
        (str "0b" result)
    )
)

;--------------------------------------------------------------------------
;
(defn normalize-string
"
Concatenates all arguments into a string, reduces multiple whitespace chars
to a single space then returns the result.

See also: + join qstr
"
    [ &args ]

    (join args " " | re/replace #"[\r\n\t ]+" " ")
)

;--------------------------------------------------------------------------
;
(defn str/reverse
    "Turns it's argument into a string then reverses that string."
    [(^string? argstr)]

    (join (chars argstr | reverse) "")
)

;--------------------------------------------------------------------------
;
(defspecial qstr
"""
Concatenates all unevaluated arguments into a string. Unquoted
elements are evaluated.

Examples:
     (let 1) (let y 2)
     (qstr this is a test x is ~x y is ~y)
returns the string
    "this is a test x is 1 y is 2"

See also: + join str
"""
    [ &args ]

    (let unquotesym (get-symbol 'unquote))
    (map args (\ e ->
            (if (and (pair? e) (== unquotesym (car e)))
                (eval (cdr e))
                e
            )
        )
        | join " "
    )
)

;--------------------------------------------------------------------------
;
(defn insert-string
"""
Inserts a substring into a string at the specified location. If the specified
location is negative, it will be treated as the offset from the end of the
string instead of from the beginning.

Examples:
    (insert-string "\abcdef" 3 "123") ; returns 'abc123def'
    (insert-string "abcdef" -4 "123") ; returns 'ad123cdef'

See also: str join
"""
    [(^string source) (^int index) (^string newStr)]

    (cond
        (== index 0)
            (str newStr source)

        (> index (length source))
            (str source newStr)

        (< index 0)
            (do
                ; negative index is treated as the offset from the end
                (let index (+ (length source) index))
                (if (< index 0)
                    (str newStr source)
                    (. source 'Insert index newStr)
                )
            )

        true
            (. source 'Insert index newStr)
    )
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Dictionary utilities
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;--------------------------------------------------------------------------
;
(defn ToHash
"
Convert a list of items into a dictionary where the keys are the items
and the values are item counts. By default, case-insensitive string
comparisons are used but you can specify case-sensitive comparisons with
the '-case' flag.

Examples:
    ; get the 10 most common words in a file
    (read-text 'foo.txt | re/split | tohash | sort -descending .value | take 10)
    ; get the 10 most common words in a file, case-sensitive
    (read-text 'foo.txt | re/split | tohash -case | sort -descending .value | take 10)

See also: group

"
    [lst :case]

    ; choose case-sensitive dictionary if desired
    (let hash
        (if case
            (new-dict ^object ^object)
            (new ^hashtable .StringComparer/OrdinalIgnoreCase)
        )
    )

    (foreach item lst
        (hash item
            (+ 1 (hash item))
        )
    )

    hash
)

;--------------------------------------------------------------------------
;
(defn assoc-in
"
Update a dictionary given a list of keys and a value to
assign/insert. The list of keys represents a path into the object.
If any nodes don't exist or are not dictionaries, new dictionary nodes
are assigned/added (like mkdir -p).
"
    [(^IDictionary data) (^Vector path) value]

    ; save the top level object to return
    (let origdata data)
    (let path-len (length path | --))

    ; if the path is not empty...
    (when (>= path-len 0)
        ; traverse all path elements stopping at the last one.
        (for (let index 0) (index | < path-len) (incr index)
            (let path-elem (!! path index))
            (when (not (!! data path-elem | is? ^IDictionary))
                (!! data path-elem {})
            )
            (let data (!! data path-elem))
        )
        (!! data (!! path index) value)
    )
    ; return the original dictionary
    origdata
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Math Functions
;

;--------------------------------------------------------------------------
;
(defn truncate-number
    "Truncate a floating-point number returning an integer (^int)."
    [ num ]

    (^int? (.Math/Truncate num))
)

;--------------------------------------------------------------------------
;
(defn floor
    "Compute the floor of a number."
    [ num ]

    (.Math/Floor num | ^int?)
)

;--------------------------------------------------------------------------
;
(defn ceiling
    "Compute the ceiling of a number."
    [ num ]

    (.Math/Ceiling num | ^int?)
)

;--------------------------------------------------------------------------
;
(defn round
"
Round the argument value. An option number of places to round to can be specified.
By default, the number is rounded with 0 decimal places.

Examples:
    (round 3.1415)      ; returns 3
    (round 3.1415 2)    ; returns 3.14
"
    [num (places 0)]

    (.Math/Round num places)
)

;--------------------------------------------------------------------------
;
(defn **
"
The ** operator lets you compute the exponentiation of numbers.

Examples:
    (** v n)        ; Compute the nth exponent of v
    (** 2 10)       ; returns 1024
"
    ^double
    [(^double? x) (^double? y)]

    (.Math/pow x y)
)

;--------------------------------------------------------------------------
;
(defn sin
    "Compute the sine of a number"
    [ num ]

    (.Math/sin num)
)

;--------------------------------------------------------------------------
;
(defn cos
    "Compute the cosine of a number."
    [ num ]

    (.Math/cos num)
)

;--------------------------------------------------------------------------
;
(defn tan
    "Compute the tangent of a number."
    [ num ]

    (.Math/tan num)
)

;--------------------------------------------------------------------------
;
(defn log
    "Compute the log of two values e.g. (log n m)"
    | (^double? n) (^double? m) -> (.math/log n m)
    | (^double? n) 10.0 -> (.math/log10 n)
    | (^double? n) -> (.math/log n)
)

;-------------------------------------------------------------------------
;
(defn abs
"
Function to get the absolute value of its argument.

Examples:
    (abs -1.5) ; returns 1.5 (double)
    (abs -5)   ; returns 5 (int)

See also: sign round ceiling floor
"
    [num]

    (if (not (number? num))
        (let num (try (^int? num) -catch: (^double? num)))
    )

    (.math/abs num)
)

;--------------------------------------------------------------------------
;
(defn sign
"
The 'sign' function returns the 'sign' of its argument: -1
if negative; 1 if it's positive. An error will be returned
if the argument is not numeric.

Examples:
    (sign -5) ; returns -1
    (sign 5)	 ; returns 1

See also: abs round ceiling floor
"
    [num]

    (.math/sign num)
)

;--------------------------------------------------------------------------
;
(defn sqrt
"
Computes the sqrt of the argument value.

Examples:
    (sqrt 16 ; returns 4

See also: sqr
"
    [(^double? num)]

    (.Math/sqrt num)
)

;--------------------------------------------------------------------------
;
(defn div
"
Performs the 'div' operation on the arguments returning the integer part of the division.

Examples:
    (div 9 2) ; returns 4

See also: / %
"
    | m n   -> (^int? (/ m n | ^double? | .Math/Truncate))
    | m     -> (fn n -> (div n m)) ; "curry" this function
    |       -> (throw "The 'div' function requires two numeric arguments e.g (div 9 2).")
)

;--------------------------------------------------------------------------
;
(defn sqr
"
Squares a number.

Examples:
    (sqr 3) ; returns 9

See also: sqrt
"
    [number]

    (* number number)
)

;--------------------------------------------------------------------------
;
(defn rfact
"
Computes the factorial of the argument recursively. Big integers
are used.

Examples:
    (fact 1)    ; reults in 1
    (fact 10)   ; results in 3628800
"
    | 0      (result 1i) -> result
    | number (result 1i) -> (recur (-- number) (* number result))
)

;--------------------------------------------------------------------------
;
(defn fact
    "Compute the factorial of the argument. Big integers are used."
    | 0     -> 0
    | 1     -> 1
    | num   -> (* @(range 1i num))
)

;--------------------------------------------------------------------------
;
(defn combinations
"
Calculate the number of combinations choosing k items from a set of n items.

Examples:
    (combinations 52 5) ; returns 2_598_960

See also: choose fact
"
    [n k]

    (fact n | / (fact k | *(fact (- n k))))
)

;--------------------------------------------------------------------------
;
(defn choose
"
Choose n elements from a sequence of items.

See also: combinations
"
    | nil _     ->
    | xs 1      -> xs
    | x:xs n    ->
        (concat
            (forall y (choose xs (-- n)) (concat x y))
            (choose xs n)
        )
)

;--------------------------------------------------------------------------
;
(defn permute
"
Generate the all of the permutations of a sequence of items.

See also: choose combinations
"
    | x:   -> [x]
    | x:xs ->
        (permute xs | filter some? | flatmap (\ lst ->
            (forall i (range 0 (length lst))
                (concat (take lst i) x (skip lst i))
            )
        )
    )
)

;--------------------------------------------------------------------------
;
(defn combine
"
Generate the all of the combinations of a sequence of items.

See also: choose combinations permute
"
     | x:   -> [x]
     | x:xs ->
        (let combs (combine xs))
        (concat
            x
            combs
            (forall comb combs
                (concat x comb)
            )
        )
)

;--------------------------------------------------------------------------
;
(defn sum
"
Sum all of the values in the argument list. An optional accessor function
can be provided to select the property on the input objects to sum.

Examples:
    (range 10 | sum)
    (sum (range 10))
    (ls -file | sum .length)    ; get the total length of all the files in the current directory

See also: prod + reduce
"
    | (^IEnumerable listOfNumbers) accessor ->
        (matchp (length listOfNumbers)
        | 0 -> 0
        | 1 -> (!! listOfNumbers 0  | accessor)
        |   -> (apply + (listOfNumbers | map accessor))
        )
    | (^IEnumerable listOfNumbers) ->
        (matchp (length listOfNumbers)
        | 0 -> 0
        | 1 -> (!! listOfNumbers 0)
        |   -> (apply + listOfNumbers)
        )
    
    | %none? (accessor null) -> 0
    | n (accessor echo)      -> (accessor n)
    | &args -> (throw "The 'sum' function expects either a list or a list & an accessor function, not '${args}'")
)

;--------------------------------------------------------------------------
;
(defn prod
    "Compute the product of the numbers in the argument list."
    | (^ISeq listOfNumbers) ->
        (matchp (length listOfNumbers)
        | 0 -> 0
        | 1 -> (!! listOfNumbers 0)
        |   -> (* @listOfNumbers)
        )
    | (^ISeq listOfNumbers) accessor ->
        (matchp (length listOfNumbers)
        | 0 -> 0
        | 1 -> (!! listOfNumbers 0  | accessor)
        |   -> (* @(listOfNumbers | map accessor))
        )
    | %none? (accessor null) -> 0
    | n (accessor echo)      -> (accessor n)    ; handle scalar case
    | &args -> (throw "The 'prod' function expects either a list or a list & an accessor function, not '${args}'")
)

;--------------------------------------------------------------------------
;
(defn fib
    "Compute the fibonocci number for the argument using the naive recursive algorithm and bigints."
    | 0      -> 1i
    | 1      -> 1i
    | number -> (+ (fib (- number 1)) (fib (- number 2)))
)

;--------------------------------------------------------------------------
;
(defn fastfib
    "A fast tail-recursive implementation of the 'fib' function"
    | 0 _ (current 0i) -> current
    | number (prev 0i) (current 1i) -> (recur (-- number) current (+ current prev))
)

;--------------------------------------------------------------------------
;
(defn iterfib
"
Compute the nth element in the Fibonacci sequence.
This is computed lazily using the 'unfold' function.

Examples:
    (iterfib 10)    ; returns 89

See also: fib rpfib
"
    [n]

    (unfold (\ p:c: -> [c (+ p c)]) [1i 1i]
        | take n
        | last
        | last)
)

;--------------------------------------------------------------------------
;
(defn isPrime
"
Simple function to determine if a number is prime.

Examples:
    (isPrime 19) ; returns true
    (isPrime 10) ; returns false
"
    | 3 -> true
    | n :where (even? n) -> false;
    | n ->
        ; get the upper bound by computing the square root of the argument
        (let ^long? upper (n | ^double? | sqrt))

        ; test all odd numbers in that range to see if they are divisors of n
        (range 3 upper 2 | list/all (fn x -> (% n x)))
)

;--------------------------------------------------------------------------
;
; This code was adapted from a common Haskell example. It computes the primes
; below a specified maximum.
;
(defn sieve
"Find all primes in the range 1 to n using a 'Sieve of Eratosthenes'-like algorithm."
    | x:xs r -> (recur (filter xs (% x)) (nconc x r))
    | _ r -> r
    | n -> (recur (range 3 n 2) [])
)

;--------------------------------------------------------------------------
;
(defn gcd
    "Compute the greatest common divisor for two numbers"
    | x 0 -> x
    | x y -> (recur y (% x y))
)

;--------------------------------------------------------------------------
;
(defn average
"
The 'average' function computes the average of it's arguments,
with an optional function to get the value to average.

Examples:
    (range 10 | average)         ; returns 5
    (ls -file | average .length) ; returns average length of the files

"
    | %none? (func null) -> 0
    | lst    (func null) -> (sum lst @func | ^double? | / (length lst))
)

;--------------------------------------------------------------------------
;
(defn median
    "Compute the median value of a list of numbers."
    | %none? (func null) -> 0
    | lst (func null)    ->
        (let ll   (length lst))
        (let ll/2 (/ ll 2))
        (let slst (sort lst @func))

        (let func (or func echo))
        (if (% ll 2)
            ; if there's an odd number of elements, take the middle element
            (!! slst (round ll/2) | func)
            ; otherwise average the two adjacent elements as doubles
            (do
                ; need an actual function for the next step so default to echo
                (average [
                        (^double? (func (!! slst ll/2)))
                        (^double? (func (!! slst (- ll/2 1))))
                    ]
                )
            )
        )
)

;--------------------------------------------------------------------------
;
(defn max
    "Return the max of two items."
    | x y           -> (bigger x y)
    | x y func :where (>= (func x) (func y)) -> x
    | x y func      -> y
    | x             -> (bigger x)   ; return curried function
)

;--------------------------------------------------------------------------
;
(defn max-list
"
The 'max-list' function returns the maximum-valued element from a sequence.
An optional 'accessor' function can be specified which provides the value
of the property to be compared. Note that 'max-list' returns the original
value from the list, not the value returned from the accessor function.
The accessor function is only used in comparisons and is never returned.
If a scalar value is passed instead of a sequence, that value will simply
be returned and no error will be raised.

Examples:
    (max-list [3 2 6 7 5 4 1 9])        ; returns 9
    (max-list [3 2 6 7 5 4 1 9] neg)    ; returns 1 since -1 is the largest value.
    (ls -file | max-list .length)       ; returns the FileInfo object for the largest file
    (ls -file | map .length | max-list) ; returns the length of the largest file.

See also: min max min-list smaller bigger
"
    | %none?            -> nil
    | [x]               -> x ; use [x] instead of x: for testing purposes
    | (^ISeq lst)       -> (reduce lst bigger)
    | scalar            -> scalar
    | %none? func       -> nil
    | [x] func          -> x
    | (^ISeq lst) func  -> (reduce lst (\ x y  -> (max x y func)))
    | scalar func       -> scalar
)

;--------------------------------------------------------------------------
;
(defn max-list-index
"
Find the first index of the maximum element in a list.
"
    | x:          -> [x 0]
    | x:xs        -> (recur x xs 0 0)
    | s x:xs i is :where (<= x s) -> (recur s xs (++ i) is)
    | s x:xs i is -> (recur x xs (++ i) (++ i))
    | s nil _  is -> [s is]
)

;--------------------------------------------------------------------------
;
(defn min
    "Return the smaller of two items."
    | x y func -> (if (<= (func x) (func y)) x y)
    | x y      -> (smaller x y)
    | x        -> (smaller x) ; curried
)

;--------------------------------------------------------------------------
;
(defn min-list
"
The 'min-list' function returns the minimum-valued element from a sequence.
An optional 'accessor' function can be specified which provides the value
of the property to be compared. Note that 'min-list' returns the original
value from the list. The accessor function is only used in comparisons and is
never returned. If a scalar value is passed instead of a sequence, that
value will simply be returned and no error will be raised.

Examples:
    (min-list [3 2 6 7 5 4 1 9])        ; returns 1
    (min-list [3 2 6 7 5 4 1 9] neg)    ; returns 9 since -9 is the smallest value.
    (ls -file | min-list .length)       ; returns the FileInfo object for the smallest file
    (ls -file | map .length | min-list) ; returns the length of the smallest file.

See also: min max max-list smaller bigger
"
    | x:     (func nil) -> x
    | (^ISeq lst)       -> (reduce lst smaller)
    | (^ISeq lst) func  -> (reduce lst (\ x y  -> (min x y func)))
    | scalar (func nil) -> scalar
)

;--------------------------------------------------------------------------
;
(defn min-list-index
"
Find the first index of the minimum element in a list.
"
    | x:    -> [x 0]
    | x:xs  -> (recur x xs 0 0)
    | s x:xs i is :where (>= x s) -> (recur s xs (++ i) is)
    | s x:xs i is -> (recur x xs (++ i) (++ i))
    | s nil _ is -> [s is]
)

;--------------------------------------------------------------------------
;
(defn extract-min
"
Extract (remove and return) the n smallest items from a vector.
"
    | %none? _     -> []
    | _ 0 (r nil)  -> r
    | (^vector lst) (^int? n) (r []) ->
        (let s:i: (min-list-index lst))
        (.removeat lst i)
        (recur lst (-- n) (nconc s r))

)

;--------------------------------------------------------------------------
;
(defn get-min
"
Find and return the n smallest items from a list.
"
    | nil _ (r [])  -> r
    | _   0 (r [])  -> r
    | lst n (r [])  ->
        (let m (min-list lst))
        (recur (where lst (> m)) (-- n) (nconc m r))
)

;--------------------------------------------------------------------------
;
(defn qsort
"
Recursive 'quicksort' (after the Haskell equivalent). Uses list/split to
avoid double filtering.

Examples:
    (qsort [5 2 6 9 1 3 4 8 7])     ; returns [1 2 3 4 5 6 7 8 9]

See also: sort
"
    | %none? -> nil
    | pivot:xs ->
        (list/split xs (<= pivot) | (\ smaller:larger: ->
            [ @(qsort smaller) pivot @(qsort larger) ]))
)

;--------------------------------------------------------------------------
;
(defn roll
"
Roll the argument integer left by the specified number of bits

Examples:
    (roll 0xDEADBEEF 4)  ; will return 0xEADBEEFD
    (roll 0xDEADBEEF 16) ; will return 0xBEEFDEAD

See also: roll band bor bxor bnot
"
    [r  (^int n 1)]

    (repeat n
        (let c (band r 0x8000_0000))
        (let r (bor (shiftl r 1) (if c 1 0)))
    )
    r
)

;--------------------------------------------------------------------------
;
(defn rolr
"
Roll the argument integer right by the specified number of bits

Examples:
    (rolr 0xDEADBEEF 4)  ; will return 0xFDEADBEE
    (rolr 0xDEADBEEF 8)  ; will return 0xEFDEADBE
    (rolr 0xDEADBEEF 16) ; will return 0xBEEFDEAD

See also: roll band bor bxor bnot
"
    [r  (^int n 1)]

    (repeat n
        (let r (shiftr r 1 | bor (if (band r 0x1) 0x8000_0000 0)))
    )
    r
)

;--------------------------------------------------------------------------
;
(defn leap-year?
    "True if the passed argument is a leap year."
    [(^int year)]

    (or
        (zero? (% year 400))
        (and
            (zero? (% year 4))
            (some? (% year 100))))
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; List utilities
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;--------------------------------------------------------------------------
;
(defn cadr
    "Returns the second item in a sequence"
    [lst]

    (echo lst | cdr | car)
)

;--------------------------------------------------------------------------
;
(defn second
    "Returns the second item in a sequence"
    [lst]

    (echo lst | cdr | car)
)

;--------------------------------------------------------------------------
;
(defn caddr
    "Returns the third item in a sequence"
    [lst]

    (echo lst | cdr | cdr | car)
)

;--------------------------------------------------------------------------
;
(defn third
    "Returns the third item in a sequence"
    [lst]

    (echo lst | cdr | cdr | car)
)

;--------------------------------------------------------------------------
;
(defn cddr
"
Returns the cdr of the cdr of the sequence.

Examples:
    (cddr '(1 2 3 4)    ; returns (3 4)
    (cddr [1 2 3 4])    ; returns [3 4] (as a Slice)
    (cddr nil)          ; returns nil
    (cddr [])           ; returns nil
"
    [lst]

    (echo lst | cdr | cdr)
)

;--------------------------------------------------------------------------
;
(defn mapcat
"
For each argument collection, map a function onto the elements of the collection
then concatenate the results into a single flat collection.

Examples:
    (mapcat ++ [1 2] [3 4] [5 6])   ; returns [2 3 4 5 6 7]

See also: map concat
"
    [f &colls]

    (forall -flatten c colls (map c f))
)

;--------------------------------------------------------------------------
;
(defn subseq
"
Return a subsequence of a Seq. The sequence starts at 'start'. If 'end' is not specified,
the rest of the sequence is returned. If 'end' is provided, the sequence that is returned
includes the item at the 'end' position.
"
    [lst start (^int end -1)]

    (let index 0)
    (if (== end -1)
        (forall it lst
            (incr index)
            (if (<= start index) it)
        )

        (forall it lst
            (incr index)
            (if (> index end)
                (break)
            )
            (if (<= start index end) it)
        )
    )
)

;--------------------------------------------------------------------------
;
(defn debug/pwatch
"""
The 'debug/pwatch' (pipeline watch) function is a debugging utility that can be
inserted into a pipeline to see what's passing through the pipeline. The
output display will prefixed with the user specified tag to help correlate
the output. An optional filter may be specified to reduce the ammount of output.

Examples:
    (ls | pwatch "files" #".cs$" | map .length)
"""
    [input (^string tag) (outputFilter null)]

    (if outputFilter
        (str "pwatch(" tag "): " (input | filter outputFilter) | info)
        (str tag ": " input | info)
    )

    input
)

;--------------------------------------------------------------------------
;
(defn contains?
"
Returns true if the argument list contains the specified value or
matches the lambda. Does a shallow search.
"
    | (^BraidLang.RangeList rangeList) value -> (.contains rangelist value)

    | (^IDictionary dict) (^callable value) ->
        (foreach e (.keys dict) (if (value e) (return true)))
        (return false)

    | (^IDictionary dict) value ->
        (.containskey dict value)

    | (^HashSet hashset) (^callable value) ->
        (foreach e hashset (if (value e) (return true)))
        (return false)

    | (^HashSet hashset) value ->
        (.contains hashset value)

    | (^string str) (^callable value) ->
        (foreach e (chars str | tostring-all)
            (if (value e) (return true)))

    | (^string str) value ->
        ; BUGBUGBUG this needs to be case insensative but ^string doesn't support it
        (.contains (.tolower str) (.tolower (tostring value)))

    | (^IEnumerable lst) (^callable value) ->
        (foreach e lst (if (value e) (return true)))
        (return false)

    | (^IEnumerable lst) value ->
        (foreach e lst (if (== value e) (return true)))
        (return false)
    
    | -> (throw "Invalid arguments to 'contains?' expected (in? <val> <collection>).")
)

;--------------------------------------------------------------------------
;
(defn in?
"
Returns true if the argument list contains the specified value or
matches the lambda. Does a shallow search. The in? function is the
same as the contains? function except the arguments are reversed.

Examples:
    (in? :a [:a :b :c])     ; returns true
    (in? :d [:a :b :c])     ; returns false
    (3 | in? [1 2 3 4 5])   ; returns true
    (in? 5 (range 10))      ; returns true

See also: contains?
"
    | lst ->
        ; auto-curry
        (partial in? lst)

    | value (^BraidLang.RangeList rangeList) -> (.contains rangelist value)

    | (^callable value) (^IDictionary dict)  ->
        (foreach e (.keys dict) (if (value e) (return true)))
        (return false)

    | value (^IDictionary dict) ->
        (.containskey dict value)

    |  (^callable value) (^HashSet hashset) ->
        (foreach e hashset (if (value e) (return true)))
        (return false)

    | value (^HashSet hashset) ->
        (.contains hashset value)

    |  (^callable value) (^string str) ->
        (foreach e (chars str | tostring-all)
            (if (value e) (return true)))

    | value (^string str) ->
        ; BUGBUGBUG this needs to be case insensative but ^string doesn't support it
        (.contains (.tolower str) (.tolower (tostring value)))

    | (^Callable value) (^IEnumerable lst) ->
        (foreach e lst (if (value e) (return true)))
        (return false)

    | value (^IEnumerable lst) ->
        (foreach e lst (if (== value e) (return true)))
        (return false)
    
    | -> (throw "Invalid arguments to 'in?' expected (in? <val> <collection>).")
)

;--------------------------------------------------------------------------
;
(defn contains-scalar
"
Checks the argument tree to see if it contains specified scalar value
Does a deep (recursive) search.
"
    [(^ISeq lst) value]

    (foreach item lst
        (cond
            (pair? item)
                (if (contains-scalar item value)
                    (return true)
                )
            (== item value)
                (return true)
        )
    )
    false
)

;--------------------------------------------------------------------------
;
(defn scalarize
"If the argument is a collection of 1 element, extract it and return it as a scalar"
    | (^iseq lst) ->
        (if (== (count lst) 1)
            (car lst)
            lst
        )
    | lst -> lst
    | null -> null
)

;--------------------------------------------------------------------------
;
(defn contains-key
"
Recursively searches a structure to see if there are dictionary entries
matching the specified key and optional value. A vector of all matching
dictionaries are returned.

Examples:
    (let data {:a 1 :b {:aa 1 :bb 2} :c 3}
    (contains-key data :aa)     ; returns [ {:aa 1 :bb 2} ]
    (contains-key data :aa 5)   ; returns nothing because of value mismatch

"
    [structure key (valueOrFunc null)]

    (let func
        (if (some? valueOrFunc)
            (if (function? valueOrFunc)
                valueOrFunc
                (fn it -> (== it valueOrFunc))
            )
            null
        )
    )

    (matchp structure
        | (^ISeq vec) ->
            (forall v vec (contains-key v key func) | flatten)

        | (^IDictionary dict) ->
            (if (.containskey dict key)
                (if (some? func)
                    (if (func (dict key))
                        dict
                        null
                    )
                    ; otherwise
                    dict
                )
                ; otherwise
                (forall v (.values dict) (contains-key v key func) | flatten)
            )

        | ->  ; ignore everything else
    )
)

;--------------------------------------------------------------------------
;
(defn last-node
"
Returns the last node in a list. Not to be confused with the 'last'
function which returns the last *value* in a list. In otherwords,
'last-node' returns the 'cdr' of the last nde, instead of the last car.

Examples:
    (last-node '(1 2 3)) ; returns (3)
    (last '(1 2 3))      ; returns 3

See also: flatmap flatten
"
    [(^ISeq lst)]

    (while (!= (cdr lst) nil)
        (let lst (cdr lst))
    )
    lst
)

;--------------------------------------------------------------------------
;
; BUGBUGBUG - remove hard dependency on .console/windowwidth
;
(defn list/wrapprint [(^ISeq lst) (^Callable? printFn null) :sort]
"
Print or return a string containing the list elements stringified then
padded to column width and finally wrapped at console width. If '-sort'
is specified, the elements are returned/displayed in sorted order.

NOTE: This function has a hard dependency on there being a console. Should
fix that.

Examples:
    (ls | list/wrapprint)      ; returns a string
    (ls | list/wrapprint inf)  ; prints using the 'info' function, returns null.
"

    (if (none? lst)
        (return null)
    )

    (const slist
        (if sort
            (tostring-all lst | sort)
            (tostring-all lst)))

    ; get longest string length
    (const width (map slist .length | reduce max))

    ; get number of columns
    (const cols (try (.console/windowwidth | div (++ width) | --) -catch: 80))

    (if (some? printFn)

        ; if a print function was specified, iuse it to print 1 row at a time
        (list/partition slist cols | each (\ row ->
            (map row (\ e -> (.padright (^string? e) width)) | join | printFn)))

        ; otherwise return a single string
        (list/partition slist cols
        | map (\ lst -> (map lst (\ e -> (.padright (^string? e) width)) | join))
        | join "\n")
    )
)

;--------------------------------------------------------------------------
;
(defn list/all
"
Applies the argument function to each element of the list. If the
function evaluates to true for all elements, then this function returns
true.

Examples:
    (all [1 2 3 4] (\ x  -> x (> x 0))) ; returns true

See also: any
"
    [lst func]
    (foreach n lst
        (if-not (func n) (return false))
    )
    true
)

;--------------------------------------------------------------------------
;
(defn list/any
"
Applies the argument function to each element of the list. If the
function evaluates to true for any of the elements, then this
function returns true.

Examples:
    (all [0 9 1 0] (\ x  -> x (> x 0))) ; returns true

See also: any
"
    [lst func]

    (foreach n lst
        (if (func n) (return true))
    )
    false
)

;--------------------------------------------------------------------------
;
(defn get-prop
"
Get the named property from each of the elements in the argument list.
For exampple:
    (ls '*.tl | get-prop 'length)
which returns a list of the values of the 'length' field.

(Note: probably don't need this since (... | map .prop | ...) works i.e.
the member accessors can be used with map to get the same effect.
"
    [lst (^string property)]

    (forall item lst
        (. item property)
    )
)

;--------------------------------------------------------------------------
;
(defn list/monotonic
"
Returns true if the members of the argument collection increase monotonically in size, If
the '-descending' flag is specified, it will return true if the list is decreasing monotonically
in size. The expression (list/monotonic [1 2 3]) is effectively equivalent to (<= 1 2 3).

Examples:
    (list/monotonic [1 2 3 4])              ; returns true
    (list/monotonic [2 1 3])                ; returns false
    (list/monotonic [3 2 1])                ; returns false
    (list/monotonic -descending [3 2 1])    ; returns true

See also: <= >= list/any list/all
"
    [lst :descending]

    (if descending
        (apply >= lst)
        (apply <= lst)
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; I/O Utilities
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;--------------------------------------------------------------------------
;
(defn read-text
"
This function reads all of the text in a file and returns it as a single string.

Examples:
    (read-text foo.txt)

See also: read-file write-text write-data write-lines
"
    [(^string? path)]

    (.IO.File/ReadAllText (resolve-path path | .path))
)

;--------------------------------------------------------------------------
;
(defn write-text
"""
Write an object to a text file. If the object is a string, just write
it as is.

Examples:
    (write-file "Hello." 'file.txt)           ; write 'Hello.' to file.txt
    (read-text 'foo.txt | write-text 'bar.txt)  ; copies the contents from foo.txt to bar.txt.

See also: read-text read-data write-data read-file write-lines write-source
"""
    [text (^string? path)]

    (if (not (is? text ^string))
        (let text (tostring text)))

    (.System.IO.File/WriteAllText path (tostring text))
)

;--------------------------------------------------------------------------
;
(defn write-source
"
Write an object formatted as Braid/JSON source to a text file. This means
embedded escapable characters in strings will be turned back into escapes.

If the object is already a string, no changes are made.

See also: read-text read-data write-data read-file write-lines
"
    [text (^string path)]

    (if (not (is? text ^string))
        (.BraidLang.utils/tostringstring text))

    (.System.IO.File/WriteAllText path text)
)

;--------------------------------------------------------------------------
;
(defn read-data
    "Read binary data from a file."
    [(^string path)]

    (.IO.File/ReadAllBytes (resolve-path path | .path))
)

;--------------------------------------------------------------------------
;
(defn write-data
    "Write binary data to a file."
    [data (^string path)]

    (.IO.File/WriteAllBytes path  data)
)

;--------------------------------------------------------------------------
;
(defn write-lines
    "write an array of strings to a file."
    [(^string[]? text) (^string? path)]

    (.IO.File/WriteAlllines path text)
)

;--------------------------------------------------------------------------
;
(defn file/dirname
    "Gets the directory part of a file name"
    | ^Io.File  -> (.directoryName %0)
    | path      -> (.io.path/GetDirectoryName (tostring path))
)

;--------------------------------------------------------------------------
;
(defn file/filename
    "Gets the directory part of a file name"
    | ^Io.File  -> (.name %0)
    | path      -> (.io.path/GetFileName (tostring path))
)

;--------------------------------------------------------------------------
;
(defn file/basename
    "Gets the basename part of a file name"
    | ^Io.File  -> (.io.path/GetFileNameWithoutExtension (.name %0))
    | path      -> (.io.path/GetFileNameWithoutExtension (tostring path))
)

;--------------------------------------------------------------------------
;
(defn file/extension
    "Gets or sets the extension on a file name"
    | ^Io.File ->
        (.GetExtension ^IO.Path (.name %0))

    | (^string path) ->
        (.io.path/GetExtension path)

    | ^Io.File (^string newExtension) ->
        (str (.fullname %0 | re/replace #"\.[^.]+$") "." (.trimstart newExtension "."))  

    | ^string (^string newExtension) ->
        (str (tostring %0 | re/replace #"\.[^.]+$") "." (.trimstart newExtension "."))

    | ->
        (throw (join [
                    "The 'file/extension' takes 1 or 2 arguments."
                    "The file must be an ^IO.File or a path string."
                    "The second optional argument is a new extension for the file."
                    ]))
)

;--------------------------------------------------------------------------
;
(defn file/tempFileName
"
Gets the name of a temporary file, optionally specifying the file extension.
When specifying the extension, the leading dot may be omitted.

Examples:
    (file/tempfilename)         ; returns a temp file name with '.tmp' extension
    (file/tempfilename 'json)   ; returns a temp file name with '.json' extension
    (file/tempfilename '.tl)    ; returns a temp file name with '.tl' extension

See also: file/extension file/basename file/dirname file/filename
"
    [(^string extension null)]

    (const tfn (.io.path/GetTempFileName))
    (if (some? extension)
        (.io.path/ChangeExtension tfn (tostring extension))
        tfn
    )
)

;--------------------------------------------------------------------------
;
(defn file/exists
    "Test to see if a file exists"
    [(^string path)]

    (.io.file/exists path)
)

;--------------------------------------------------------------------------
;
(defn file/dir-exists
    "Test to see if a directory exists"
    [(^string path)]

    (.io.directory/exists path)
)

;--------------------------------------------------------------------------
;
(defn file/isRooted
    "Test to see if a pathname is absolute"
    [(^string path)]

    (.io.path/IsPathRooted path)
)

;--------------------------------------------------------------------------
;
(defn file/setWriteTime
"
Sets the last write time on the file specified to the targetTime. If
no time is specified, then the current time is used. (Similar to
the 'touch' utility.
"
    [(^string pathToSet) (targetTime (.datetime/now))]

    (.io.file/SetLastWriteTime pathToSet targetTime)
)

;--------------------------------------------------------------------------
;
(defn file/join-path
"Join path components into a single string using the system appropriate path separator."
    [&args]

    (if (length args | < 5)
        (.io.path/combine @args)
        (do
            (let base:args args)
            (foreach p args (let base (.io.path/combine base p)))
            base
        )
   )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;   Vector utilities
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;--------------------------------------------------------------------------
;
(defn copy-vector
"
Copy the argument collection into a new vector. It's always copied even if the
argument was already a vector. Non-sequence types get wrapped into a single-element vector.

See also: new-vector to-vector
"
    | nil   -> (Vector)
    | lst   -> (new ^Vector (.BraidLang.Braid/GetNonGenericEnumerableFrom lst))
    | -> (throw "Too many arguments to 'copy-vector'. This function takes 1 argument: the vector to copy.")
)

;--------------------------------------------------------------------------
;
(defn slice
"""
The 'slice' function returns a ^Slice of an indexable collection (e.g a ^Vector or ^Array).
A ^Slice object is essentially a "window" into the underlying collection. Slice takes two
arguments - the offset into the collection to index from and the length of the collection.
Note that slices are immutable which means that you can't change the underlying collection
using the slice object. On the other hand, changes to the underlying collection will be
reflected in the slice.

Examples:
    (range 10 | slice 2 3)          ; returns [3 4 5]

See also: to-vector vector asarray
"""
    
    [(^IEnumerable vec) (^int Start 0) (^int Length (length vec | - start))]

    (new ^Slice vec start Length)
)

;--------------------------------------------------------------------------
;
; Cache of anonymous types generated by project.
;
(if (not (bound? '*anonymous-types*))
    (const *anonymous-types* {})
)

(defn project
"""
This function "projects" a subset of the properties on an object (or elements of a dictionary)
onto a new anonymously-typed object. The anonymous types are generated on an on-demand basis.

If the first object is a Dictionary, rather than enumerating the object,
a new anonymously-typed object is returned where the object properties
correspond to the dictionary keys.

Note: Anonymous types are unified based on the type's property names (but not types). A dictionary
of the currently defined anonymous types is available in the variable *anonymous-types*. So they're not
really anonymous.

Examples:
    (project {:a 1 :b 2 :c 3})                       ; turns the dictionary into an anonymously typed object.
    (gps | project :name :id :ws)                    ; returns object with properties name,id and ws.
    ([{:a 1 :b 2} {:a 2 :b 4 :c 5}] | project :a :b) ; return objects with only props a & b
    ([{:a 1 :b 2} {:a 2 :b 4 :c 5}] | project)       ; return different kinds of objects with all props

See also: deftype defobject
"""
    [data &args]

    (if (not args)
        (do
            (matchp data
            ; turn a dictionary into an object
            | ^IDictionary ->
                ; get the property names
                (const propNames (.keys data))

                ; find or build an appropriate anonymous type
                (const tkey (sort propnames | join ","))
                (unless (let ptype (!! *anonymous-types* tkey))
                    (let ptype (deftype "_projected_${(random 1 1 100_000)}" @(map propNames tostring)))
                    (.add *anonymous-types* tkey ptype)
                )

                ; finally construct and populate the instance
                (let obj (new ptype))
                (foreach pname propNames
                    (let val (!! data pname))
                    ; recurse on nested dictionaries and vectors so it's object all the way down.
                    (let val
                        (matchp val
                        | ^IDictionary -> (project val)
                        | ^System.Collections.IList -> (map val project)
                        | -> val
                        )
                    )
                    (. obj pname val)
                )

                obj

            | ^ISeq ->
                ; project each member of the sequence
                (forall e data (project e))

            | ->
                ; non-dictionaries pass unchanged
                data
            )
            

        )
        ; otherwise
        (do
            ; project new objects with specific keys
            (const propNames args)

            ; find or build the type
            (const tkey (sort propnames | join ","))
            (unless (let ptype (!! *anonymous-types* tkey))
                (let ptype (deftype "_projected_${(random 1 1 100_000)}" @(map propNames tostring)))
                (.add *anonymous-types* tkey ptype)
            )

            (forall e data
                (let nobj (new ptype))
                (if (is? e ^IDictionary)
                    ; handle turning dictionaries into objects
                    (foreach pname propNames
                        (try (. nobj pname (!! e pname)))
                    )

                    ; handle copying properties to a the new
                    (foreach pname propNames
                        (try (. nobj pname (. e pname)))
                    )
                )
                nobj
            )
        )
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; .Net-specific functions


;--------------------------------------------------------------------------
;
(defn new-stopwatch
"
The 'new-stopwatch' function returns a .NET ^System.Diagnostics.Stopwatch object
which can be used to time operations. The returned object has members .start,
.stop, .elapsed, .reset.

Examples:
    (let sw (new-stopwatch))            ; create the mobject
    (.start sw)                         ; start timing
    (.stop sw)                          ; stop timing
    (.elapsed sw | totalmilliseconds)   ; get elapsed time.
    (.reset sw)                         ; reset the stopwatch.

See also: time
"
    []
    (new ^System.Diagnostics.Stopwatch)
)

; set up an ambient stopwatch
(if (not (bound? '*sw*))
    (const *sw* (new-stopwatch))
)

;--------------------------------------------------------------------------
;
(defn asEventHandler
"
Make an ^EventHandler delegate out of a Braid lambda. The lambda must take
two parameters: the object invoking the event and the eventArgs object.

Examples:
    (.Add_Shown MainForm (asEventHandler (\ o e -> (.Activate MainForm))))

See also: CreateDelegate
"
    [callback]

    (^EventHandler? callback)
)

;--------------------------------------------------------------------------
;
(defn members-of
"""
By default, the 'members-of' function displays all of the public members on a type.
This function has one optional positional parameter: you can specify a regular
expression used to filter the members. If 'members-of' is applied to an instance
rather than a type, it will get the type of the argument object and use that for
the type to examine.

Switches:

-raw
By default 'members-of' returns the memberinfo as string 'signatures' however
if '-raw' is specified, the raw MemberInfo object will be returned.

-private
If -private is specified, then all members, both public and private will be
returned.

-all
Normally the getter/setter methods for properties are filtered out however
if -all is specified, no filtering is done.

Examples:
    (members-of ^string)             ; get all of the members on ^string
    (members-of ^string #"sub")    ; get the members matching the pattern argument
    (members-of "hi")              ; gets the type of the argument and returns that type's members
    (members ^string -all -private)  ; gets all members, public & private, will be returned,
    (members ^int -raw)              ; returns MemberInfo objects instead of strings.

See also: type-of base-of
"""
    [
        obj (^string? pattern ".")
        :raw
        :private
        :all
    ]

    (if (not obj)
        (return nil)
    )

    (let attrString
        (if private
            "Public,Static,Instance,NonPublic" 
            "Public,Static,Instance"))

    (let type (if (is? obj ^type) obj (.GetType obj)))
    (let members (. type :GetMembers attrString))

    ; build a dictionary from name to memberinfo for checking static properties
    ; PropertyInfo objects don't have .IsStatic so we have to check the associated
    ; get_ method. This dictionary must be created before filtering the get/sets.
    (let memberDict (group members .name first))

    (if (not all)
        (let members (filter members -not  #"(get|set)_"))  ; filter out the getters and setters
    )

    ; Function to figure out if a member is static with special handling for properties.
    (defn isStatic [m]
        (if (.membertype m | == .System.Reflection.MemberTypes/Property)
            ; if its a property get IsStatic from the getter method
            (!! memberDict (str "get_" (.name m)) | .?IsStatic)
            ; otherwise get it from the member directly.
            (.?IsStatic m)
        )
    )

    (defn formatMember [m]
        (try
            (matchp m
            | {isprivate true} :where (IsStatic m) -> (str "PS " m)
            | {isprivate true}                     -> (str "P  " m)
            | _ :where (IsStatic m)                -> (str " S " m)
            |                                      -> (str "   " m)
            )
             -catch: (str "   " m)
        )
    )

    [
        @( members
        | re/match-all pattern
        | map (fn m ->
                (if raw
                    m
                    (formatMember m)
                )
            )
        )

        ; add any Braid pseudo-extension methods
        @(if (not raw) (.braidLang.BraidTypeBuilder/GetExtensionMethods type))
    ]
)

(defn base-of
"
The 'base-of' function returns the base type of its type argument.

Examples:
    (base-of ^System.Reflection.MemberFilter)  ; returns System.MulticastDelegate

See also: members-of type-of
"
    [obj]

    (let type
        (if (is? obj ^type)
            obj
            (.gettype obj)))
            
    (.basetype type)
)

(defn all-members
"""
The 'all-members' function is used by the 'completer' function to do method completion.
It returns a Vector of all of the members defined on the types that are currently 'in use'
i.e. there is an instance of that type stored in a Braid variable. These members are considered
to be the 'interesting' ones for the interactive user.

Examples:
    (all-members #"sub")

See also: completer
"""
    [(^regex? pattern ".")]

    (.BraidLang.Braid/callstack
    | .GetSnapshot
    | .vars
    | map .value
    | map .value
    | filter some?
    | map type-of
    | distinct
    | flatmap (\ type ->
        (.GetMembers type (bor
            .system.reflection.bindingflags/Public
            .system.reflection.bindingflags/Static
            .system.reflection.bindingflags/Instance
            .system.reflection.bindingflags/FlattenHierarchy
            )
        | filter -not #"(get|set)_" ; filter out the getters and setters
        | map .?name
        )
    )
    | filter pattern
    | distinct
    | sort
    | map (\ n -> (str "." n))
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PowerShell-specific functions
;

; This is a macro so the PowerShell script gets compiled
; and therefore syntax-checked at parse-time.
;
(defmacro create-scriptblock
"""
Create a PowerShell ScriptBlock object. This object can be used as a braid
function simply by assigning it to a variable then invoking it like any other
function.

Exmples:
    (let sb (create-scriptblock "param ($x) $x*2")) ; create the scriptblock and assign it to 'sb'
    (sb 10)                                           ; returns 20

"""
    [(^string bodyText)]

    (.System.Management.Automation.Scriptblock/Create bodyText)
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Run the helpsource.tl to load the help info for built-in functions
; into the association table.  This must be done after all of the
; functions referenced in the help file have been defined. Since
; the file only covers the C# compiled built-ins, this isn't a problem
; for the core built-inss but there might be an issue for external binary
; modules.

(try -catch: (\ e ->  (throw "Error processing help: ${(.message e)}" e))
    ((file/join-path braidhome "helpsource.tl"))
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; REPL Command Completer Function
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Get the list of System.* types which will be used by the completer
; when completing "^in<tab>". We don't need to do this for casts/conversions
; because we use PowerShell's converter which already does this.
;
;--------------------------------------------------------------------------
;
(defn Select-Type
    "Look for types based on a regular expression."
    [(^regex? pattern #".")]

    (.AppDomain/CurrentDomain | .GetAssemblies | flatmap .?GetTypes
        ; enable for debugging
        ; | map (\ t -> (println t) t)
        | filter -not "\<Private"
        | filter .?isPublic | filter -not #"__anonymous"
            | filter pattern)
)

(if (not (bound? '__system_types))
    (const __system_types  (select-type "^system\.[^.]*$" | re/replace-all "^system\."))
)

;
; The completer pattern function.
;
(defn completer
"""
The tab-completion implementation for Braid. This
function needs to be bound to the completer callback to
work (see the function definition for how this is done.)

Examples:
    (completer <prefixString> <beforeString> <suffixString>)
    (completer "" "(list/" ":foo")
"""

    ; completions for specific commands
    | prefix #"^.*[|(] *(map|filter|where|map|each|lazy-map|lazy-filter) +([^ ]*)$" after ->
        ["(\ x -> x)"]

    ; completions for reduce,foldl and foldr
    | prefix #"^.*[|(] *(reduce|foldl|foldr) +([^ ]*)$" after ->
        ["(\ x y -> (+ x y))"]

    ; git command completions
    | prefix #"^.*[|(] *(git) +([^ ]*)$" after ->
        (re/match-all [
            ":add @(modified))"
            ":pull)"
            ":push)"
            ":commit -m: \"\""
            ":branch \"\")" ":status)"
            ":diff)"
            ":checkout \"\")"
            ] (!! matches 2))

    ; completions for 'cd' only completes directories.
    | prefix #"^.*[|(] *(cd) +([^ ]*)$" after ->
        (Get-Childitem -ea: :ignore -Directory "${prefix}*" | map .Name | map (\ f ->  (str "'" f)))

    ; handle named command parameters e.g. get-childitem -rec<tab>
    | prefix #"^.*[(|] *([a-z][^ ]*).* +(-[a-z]*)$" after ->
        (let name (!! matches 1))
        (let sw (!! matches 2))
        (let func (getFunc name))
        (if func
            (matchp func
                | ^lambda ->
                    (.keywords func
                    | map (\ obj ->
                        (let k (.key obj))
                        (let trailing (if (.value obj | .RequiresArgument) ": " " "))
                        (str "-" k trailing))
                    | filter (\ w -> (str/startswith w sw))
                    )

                | ^System.Management.Automation.AliasInfo | ^System.Management.Automation.CmdletInfo ->
                    ; resolve aliases
                    (if (is? func ^System.Management.Automation.AliasInfo)
                        (let func (.ResolvedCommand func))
                    )

                    ; if the alias resolved to a cmdlet, return the parameter completions.
                    (forall pair (.?parameters func)
                        (str "-" (.key pair) (if (.SwitchParameter (.value pair)) "" ":"))
                            | filter (\ w -> (str/startswith w sw)))

                | -> []
            )
        )

    ; BUGBUGBUG - this works in the api but not actually on the cmd line - check c# code to see how before and after are built.
    ; object member completions of the form '(.p<tab> val)'
    | prefix (#"[|(]? *(\.[a-z]*)" member) (#" *([a-z]+)" var) ->
        (let var (!! var 1))
        (let member (!! member 1))

        (if (bound? var)
            (do
                (let var (get var))
                (If var
                    (do
                        (.getmembers (type-of var)
                        | map (\ x -> (str "." (.name x) " "))
                        | sort
                        | distinct
                        | filter (\ y -> (str/startswith y member))
                        )
                   )
               )
           )
       )

    ; handle looking up static methods e.g. .console/w<tab>
    | #"^(\(?)\\.([a-z0-9.]+)/([a-z0-9]*)$" before after ->
        (let typename (matches 2))
        (let type (^type? typename))
        (let membername (^Regex? (str "^" (matches 3))))

        (if type
            (. type :getmembers
                | filter -not ^System.Reflection.PropertyInfo
                | filter .?IsStatic
                | map .name
                | re/replace-all "^[gs]et_"
                | distinct
                | re/match-all membername
                | map #(str (!! matches 1) "." typename "/" %0)
            )
            ; otherwise
            []
        )

    ; deal with type names e.g. (^func or ^func.
    | #"^(\(?)\^([^ \t]+)" before after ->
         (let startStr (!! matches 2))
         (let candidates [
                @__system_types
                @((.GetTypes *callstack*) | .keys)
                @(.BraidLang.Braid/callstack | .vars | .values | map .value
                    | filter some? | map (\ e -> (. (.gettype e) :name)))
             ]
         )

         (distinct candidates
            | filter (\ candidate -> (str/startswith candidate startStr))
                | map (\ s -> (str (!! matches 1) "^" s)))

         ; BUGBUGBUG currently unused - returning all of the types is too much
         ;(.AppDomain/CurrentDomain | .GetAssemblies | flatmap .gettypes | filter -not #"__anonymous" | map tostring)

    ; deal with looking up member names .conso<tab> .sub<tab>
    | #"^(\(?)\.([a-z0-9]+$)" before after ->
        ; search all of the types used in bound variables
        (all-members (^regex? (str "^" (!! matches 2)))
            | map (\ n -> (str (!! matches 1) n)))

    ; match quoted words against the file system
    | #"^\(?'([^ \t]+$)" before after ->
        (let pattern (str (!! matches 1) "*"))
        (get-childitem -ea: :ignore pattern | to-vector | map #(str "'" (.name %0)))

    ; match :keyword arguments against the dictionary keys and the file system
    | #"^(\(?):([^ \t]+$)" before after ->
        (let pattern (str (!! matches 2) "*"))
        (let ^regex? keypattern (str "^" (!! matches 2)))

        ; try matching dictionary keys from all variables
        (let results (.BraidLang.Braid/callstack | .GetSnapshot | .vars | map .value | map .value
            | where ^IDictionary | flatmap .keys | re/match-all keypattern))

        ; add in the file system matches
        (let results [@results @(get-childitem -ea: :ignore pattern | map .name)])

        ; filter, format and return the matches
        (results | where some? | map #(str (matches 1) ":" %0))

    ; match "(cmd..."
    | #"^\( *([^ \t]+$)" before after ->
        (let ^regex? func-pattern (str "^" (!! matches 1)))
        (let ^string script-pattern (str (!! matches 1) "*.tl"))
        (let ^string cmdlet-pattern (str (!! matches 1) "*"))

        (concat
            ; try matching functions
            (functions | map .Key | map .value | re/match-all func-pattern)
            ; try matching files
            (Get-Childitem -File -ea: :ignore script-pattern | map .Name)
            (try (get-command -ea: :ignore cmdlet-pattern | map .name) -catch: [])
        | distinct
        | map (\ s -> (str "(" s))
        )

    ; match unquoted words against functions and the current file system directory
    | prefix before after ->
        (concat
            ; try matching functions...
            (get-symbols | where bound? | map .Value | re/match-all "^${prefix}")
            ; try matching files...
            (Get-Childitem -File -ea: :ignore "${prefix}*" | map .Name | map (\ f ->  (str "'" f)))
        | distinct
        | sort -descending
        )
)

; Bind the completer callback. You can't currently create a delegate from
; a pattern matcher so we use a lambda wrapper as a workaround for now.

(.BraidLang.LineEditor/BraidCompleter
    (^Func[string,string,string,object]?
        (fn prefix before after  -> (try -catch: null (completer prefix before after)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; End completer
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Functions that should be moved to a profile. These are "user-assistance"
; functions that aren't generally used in programs.
;

;--------------------------------------------------------------------------
;
(defspecial edit
    "Launch gvim on the argument file."
    [file]

    (if (list? file)
        (let file (tostring (eval file)))
    )

    (Start-Process -NoNewWindow -FilePath: (whence "gvim") -ArgumentList: file)
)

;--------------------------------------------------------------------------
;
(defn files
    "Prints out the '*.tl' files in columns."
    [:new (^regex? pattern #".") (^Callable printFn println)]

    ; Get the list of files; newest first if -new specified
    (const allfiles
        (if new
            (get-childitem '*.tl | sort -descending .LastWriteTime)
            (get-childitem '*.tl | sort .name)
        )
    )

    ; get the filtered list of names
    (list/wrapprint (allfiles | map .name | filter pattern) printFn)
)

;--------------------------------------------------------------------------
;
(defn fixit
    "Resets the screen colors to white on black."
    []

    (.consolecolor/black | .console/backgroundcolor)
    (.consolecolor/white | .console/foregroundcolor)
    (.console/cursorvisible true)
    (cls)
)

;--------------------------------------------------------------------------
;
;
; Define the prompt string
;
(def prompt "=> ")

;--------------------------------------------------------------------------
;
(defn fgrep
"
Utility to recursively find files containing the specified regular expression. By default
only '*.tl' files are scanned.
"
    [:rec &args]

    (matchp @args
    | pattern ->
        (get-childitem -recurse: (^bool? rec) -file -filter: "*.tl"
        | map .fullname
        | filter (\ f -> (read-file f (^regex? pattern)))
        )
    | pattern filePath ->
        (get-childitem -recurse: (^bool? rec) -file -filter: filePath
        | map .fullname
        | filter (\ f -> (read-file f (^regex? pattern)))
        )
    )
)

;--------------------------------------------------------------------------
;
; Utility to compute the mb5 hash of a file as a string
;
(defn Get-FileHash
"
The 'Get-FileHash' function computes the MD5 hash for the specified file and
then returns a vector of the form:
    [ <fileToHash> <md5-hash> ]

Examples:
    (get-filehash 'autoload.tl)
"
    [fileToHash]

    (try
        [
            fileToHash

            ( .create ^System.Security.Cryptography.MD5
            | .computeHash (.io.file/openread fileToHash)
            | map #(hex -noprefix %0)
            | join ""
            )
        ]
        -finally: #(.close fs)
    )
)

;--------------------------------------------------------------------------
;
; Wrapper to make git a little more friendly inside braid.

;(defn git
;"
;The 'git' function is a Braid wrapper around 'git.exe' that makes
;it a bit easier to use git from the Braid repl.
;
;Examples:
;    (git :add @(modified))          ; all the the modified files
;    (git :commit -m: \"msg...\")    ; creates a commit with the message \"msg\"
;"
;    [(^string? subcmd) :m: :norun &args]
;
;    (defn stringify
;        | (^string e) -> " \"${e}\""
;        | (^ISeq   o) -> (join o " ")
;        | other       -> (+ " " other)
;    )
;
;    (let fixedargs
;        (str
;            (.tolower subcmd)
;            " "
;            (if m "-m \"${m}\" "  " ")
;            @(args | stringify)
;        )
;    )
;
;    (if norun
;        (info "git.exe" fixedargs)
;        (start -workingdirectory: (pwd) -wait -nonewwindow "git.exe" fixedargs)
;    )
;)

;--------------------------------------------------------------------------
;
; function to list just the names of the git modified files to add.

(defn modified
"
The 'modified' function returns a list of the nanes of the modified
files in the current Git workspace.

Examples:
    (git :add @(modified))
"
    []

    (git.exe :status | filter #"deleted:|modified:" | map (\ n -> (re/split n | second)))
)

;--------------------------------------------------------------------------
;
(defn lc
"Count the lines in the argument files."
    [:totalOnly &args]

    (let total 0)
    (foreach f args
        (let cnt (read-file f | count))
        (if (not totalOnly)
            (info f cnt)
        )
        (incr total cnt)
    )

    (if totalOnly
        total
        (alert "Total lines" total)
    )
)

;--------------------------------------------------------------------------
;
(defn out-list
"
A function to format the argument object using PowerShell's Format-List. It
returns a list of strings.

Examples:
    (get-childitem | out-list)                  ; format the output of get-childitem 
    (out-list (get-childitem))
    ({:a 1 :b 2 :c 3} | out-list)               ; format a dictionary
"
    [obj]

    (echo obj | Format-List -Force "*" | Out-String -Stream)
)

;--------------------------------------------------------------------------
;
(defn sls
"
A function to print directory lstings in columns
"
    [(path '*.tl)]

    (ls path
    | map .name
    | list/partition  4
    | each (\ it ->
                (echo it
                | map #(fmt "{0,-25}" %0)
                | join ""
                | println)
                )
    )
)

