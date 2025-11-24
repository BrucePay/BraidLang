;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; helpsource.tl
;
; This file contains documentation for Braid's built-in
; functions. The script is loaded by the interpreter at startup
; time and must be present in the distribution.
; On load, content is stored in memory using 'Set-Assoc'
; which sets up weak references to the doc content for each
; function under the ":helptext" key. This means that
; the documentation can be accessed using:
;       '(get-assoc <funcObject> :helptext)'
; (though 'doc' and 'help' provide a better user experience.)
; The 'bindhelp' function simplifies this process. To attach help
; content to a function you do
;       '(bindhelp myCommand helpText)'
; 'helptext' should be a string formatted as shown below.
; This script is idempotent so you can reload it at any time
; to see changes in the text for a command.
;
; See also: doc help set-assoc get-assoc
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;
; First validate the contents of the file:
; - every call to 'bindhelp' should correspond to a built-in function
; - user-defined functions should not appear in this file.
;

(let helpnames {})

(foreach e (file/parse (file/join-path braidhome "helpsource.tl"))
    (when (== 'bindhelp (car e))
        (let entries (second e))
        (while (is? entries ^VectorLiteral)
           (let entries (.Value entries))
        )
        (let entries (car entries))

        (foreach fname entries
            (if (contains? helpnames fname)
                (do
                    (warn "Loading helpfile: duplicate topic name found:" fname)
                    (!! helpnames fname true)
                )
                (do
                    (def funcToCheck (try (get fname)))
                    (cond
                        (is? funcToCheck ^Exception)
                            (alert "helpsource.tl:  no function named '${fname}' was found:\n${funcToCheck}")
                        ;(lambda? funcToCheck)
                        ;   (alert "helpsource.tl:  user function ${fname} - should not be in this file")
                        ;true (println fname)
                    )
                )
            )
        )
    )
)

;
; Function to associate help text with the function. The 'bindhelp' function
; allows multiple functions to be bound to a single topic which is how "command aliases"
; work.
;
(defn bindhelp
    "Creates a :helptext association between one or more functions and their help text"
    [funcs text]

    (if (and funcs text)
        (foreach f funcs
            ; bind the help to each function.
            (set-assoc f :helptext (re/replace text "@fn@" f))
        )
        ; otherwise
        (throw "bindhelp: requires that you specify at least one function and the help text.")
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp !!  """
Syntax: (!! indexible index [valueToSet])

This function is used for accessing or setting elements in indexable
data structures like lists, vectors and dictionaries. The first two
arguments specify the indexible collection and the index to access.
If a third argument is provided, this argument is used as the value to
set the indexed item to. (Note that strings are a special case - they
are indexible but not mutable and which means the three argument syntax
doesn't work).

Examples:
    (!! [0 1 2 3] 2)         ; result is 2
    (!! [0 1 2 3] 2 20)      ; sets the third element to 20.
    (!! {:a 1 :b 2 :c 3} :b) ; returns 2
    (!! "hello" 3)           ; returns 'l'.
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp ==  """
Syntax: (== arg1 arg2 ... argN1 argN2)

This is the polymorphic comparison function (==) which works on any types that
support comparisons (IComparable). Arguments must be specified in pairs. If more
than one pair of values is provided, they will all be compared pairwise.

Examples:
    (== 5 5)            ; returns true
    (== 5 6)            ; returns false
    (== 1 2 3 4)        ; returns false
    (== 1 1 2 2)        ; returns true
    (== :a :a 3 3.0)    ; returns true
    (== "ab" "ab" 2 2)  ; returns true
    (== "ab" "a" 2 2)   ; returns false
    (== [1 2] [1 2])    ; returns true
    (== [1] [1 2])      ; returns false
    (== [1 2] [1 3])    ; returns false

See also: != === !==
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp !=  """
Syntax: (!= arg1 arg2)

The '!=' function compares two objects to see if they are not equal.

Examples:
    (!= 3 4)    ; returns true as the values are not equal
    (!= 3 3)    ; returns false as the values are equal.

See also: == === !==
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp %  """
Syntax: (% arg1 arg2)

The mod function '%' computes the modulus of the its argument values.
The function is only defined for numeric values.

Examples:
    (% 9 4)                     ; returns 1
    (range 10 | filter (% 2))   ; return all the odd numbers

See also: + - * / -- ++ incr decr
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp *  """
Syntax: (* arg1 arg2 arg3 ... argN)

The '*' multiplication function computes the product of
it's arguments if the arguments are numeric. If the first argument
is a string or sequence, that sequence will be replicated the specified
number of times. If only one argument is passed, then a curried function
is returned

You can compute factorials using multiply, splatting and the range function as

Examples:
    (* 1 2 3)              ; Compute the product of the argument values
    (* "hi" 10)            ; Repeat the string argument 10 times
    (* [1 2 3] 10)         : Repeat the sequence argument 10 times
    (range 10 | map (* 2)) ; return the numbers from 1-10 multiplied by 2
    (* @(range 10))        ; compute factorial of 10
    (apply * (range 10))   ; compute factorial of 10

See also: + - / % -- ++ incr decr
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp .  """
Syntax: (. object 'member [args...])

The '.' function is the member accessor operation allowing you to get
and set properties and fields and call instance (by specifying an object
instance) and static (by specifying a type) methods. In the case of a property
or field, if only the member name is specified, the operation will be a get.
If an additional argument is provided, the operation will be a set.

Examples:
    (. "hello" :length)         ; gets the 'length' property from the string
    (. ^math :pi)               ; gets the value of the static member 'pi
    (. "hello" :substring 1 2)  ; Applies the method 'substring with 2 arguments
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp /  """
Syntax (/ arg1 arg2)

The division function (/) divides its first operand by it's second.
If the division is not perfect, the result will be returned as a ^double

Examples:
    (/ 6 2) ; returns 3
    (/ 5 2) ; returns 2.5

See also: + - * % -- ++ incr decr
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp +  """
Syntax: (+ arg1 arg2 arg3 ... argN)

The addition function (+) sums all of its arguments together. It
works on numbers, strings and datetime objects. The type of the first
argument (number, string or datetime) will determine the type of the
overall operation.

Examples:
    (+ 1 2 3)          ; Compute the sum of the argument values
    (+ 10 "23")         ; Conver "24" into a number and add it to give 33
    (+ "ab" "cd")      ; Add 'ab' and 'cd' to get 'abcd'
    (+ "ab" "cd" 123)  ; 123 is turned into a string and appended

See also: - * / % -- ++ incr decr
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp -  """
Syntax: (- arg1 arg2 ... argN)

The subtraction function (-) allows you to subtract numbers, DateTimes,
TimeSpans and string objects. For numeric subtraction, all .NET
numeric formats are supported. Timespans and DateTime objects can subtract
integer and TimeSpan values. Subtracting from a string removes the characters
that match the remaining string, character and Regex arguments.
If only a single argument is passed, a curried function is returned. If more than
one additional argument is provided, those additional arguments are also subtracted
in order.

Examples:
    (- 10 5)                                    ; returns 5
    (- 10 5 1)                                  ; returns 4
    (- "Hello" "lo")                            ; removes all 'l' and 'o' characters.
    (- "Hello" #"^Hel")                         ; Regex subtraction, returns "lo"
    (- (.DateTime/Now) (.timespan/TicksPerDay)) ; subtract one day from now
    (range 10 | map (- 2))                      ; Subtract 2 from each member of the collection
    (ls | map .name | map (- #"\.[a-z]+$"))     ; strip the extension from each file name

See also: + * / % -- ++ incr decr
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp ++  "
Syntax: (++ arg1)

The '++' function takes a single numeric argument value and returns
that value incremented by one. In contrast, the 'incr' function
takes a symbol argument and increments the value the named variable.

Examples:
    (++ 10)              ; returns 11
    (let x 5) (++ x)     ; returns 6, the value in x is unchanged
    (++ (/ 25 5))        ; returnsn 6
See also: -- + - incr pincr decr
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp --  "
Syntax: (-- arg1)

The '--' function takes a single numeric argument value and returns
that value decremented by one. In contrast, the 'decr' function
takes a symbol argument and increments the value the named variable.
Examples:
    (-- 10)              ; returns 9
    (let x 5) (-- x)     ; returns 4, the value in x is unchanged
    (++ (/ 25 5))        ; returnsn 46
See also: ++ + - incr pincr decr
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp <  """
Syntax: (< arg1 arg2 ... argN)

This is the polymorphic less than function (<) which works on any types
that support ordered comparisons. If more than 2 objects are
provided as arguments, the function will return true if all of the
arguments are in order.

Examples:
    (< 1 5)               ; returns true
    (< "abc" "ab")    ; returns false

See also: <= > >= == != === !==
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp <=  "
Syntax: (<= arg1 arg2 ... argN)

This is the polymorphic less than or equals function which works on
any types that support ordered comparisons. If more than 2 objects are
provided as arguments, the function will return true if all of the
arguments are in order.

Examples:
    (<= 5 5)    ; returns true
    (<= 4 5 6)  ; returns true
    (<= 7 4 5)  ; returns true

See also: < > >= == != === !==
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp ===  """
Syntax: (=== arg1 arg2 ... argN)

This is the reference equals function (===). If the arguments provided refer to the
same object, the function will return true. If more than one pair of values is provided,
they will all be compared pairwise.

Examples:
    (=== 5 5)                   ; returns true
    (=== 5 6)                   ; returns false
    (=== 1 2 3 4)               ; returns false
    (=== 3 3.0)                 ; returns false
    (=== "foo" "foo")           ; returns false (different references)
    (let x "foo") (=== x x)     ; returns true (same reference)

See also: !== == !=
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp !==  """
Syntax: (!== arg1 arg2 ... argN)

This is the negative reference equals function (!==). If the arguments provided refer to the
same object, the function will return false. If more than one pair of values is provided,
they will all be compared pairwise.

Examples:
    (!== 5 5)                   ; returns false
    (!== 5 6)                   ; returns true
    (!== 1 2 3 4)               ; returns true
    (!== 3 3.0)                 ; returns true
    (!== "foo" "foo")           ; returns true (different references)
    (let x "foo") (=== x x)     ; returns false (same reference)

See also: === == !=
""")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp >  "
Syntax: (> arg1 arg2 ... argN)

With two arguments, the '>' function returns true if arg1
is greater than arg2. If more than two arguments are specified,
'>' returns true if the arguments are in monotonically decreasing
order. This function works for all comparable types.

Examples:
    (> 3 2)                                 ; returns true
    (> 2 3)                                 ; returns fakse
    (> 3 2 1)                               ; returns true
    (> 4 2 3)                               ; returns false (non-monotonic)
    (range 10 | filter (fn n -> (> 8 n 3))) ; returns [4 5 6 7]
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp >=  "
Syntax: (>= arg1 arg2 ... argn)

Returns true if all of its arguments are monotonically greater than
or equal to the previous argument.

Examples:
    (>= 2 1)        ; returns true
    (>= 1 2)        ; returns false
    (>= 2 2)        ; returns true
    (>= 3 2 2 1)    ; returns true
    (>= 3 4 2 1)    ; returns false
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp alert  """
Syntax: (alert arg1 arg2 arg3 ... argn)

This function prints a string to the console with emphasis.

Examples:
    (alert "This is an alert")
    (alert 'this 'is 'an 'alert 'in 'pieces.)
    (alert "The value of 2+2 is" (+ 2 2))

See also: info warn error println
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp and  """
Syntax: (and arg1 arg2 arg3 ... argn)
The 'and' function returns the last argument if all of its other arguments
evaluate to true. Lazy evaluation is used so the first argument that doesn't
resolve to true terminates execution and false is returned.

Examples:
    (and true true true)    ; returns true
    (and true false true)   ; returns false
    (and 1 2)               ; returns 2
    (and 0 2)               ; returns false

See also: or not
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp append  """
Syntax: (append arg1 arg2 arg3 ... argn)

The 'append' function appends it's arguments together to produce a new list.
If an argument is a list, it is stiched into the result list rather than
being added as a single member.
    (append 1 '(2 3) 4)     ; results in a new list '(1 2 3 4)
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp concat "
Syntax: (concat arg1 arg2 arg3 ... argn)

The 'concat' function appends it's arguments together to produce a new vector
(see also the 'append' function with produces a list instead of a vector.)
If an argument is a sequence, it is stiched into the result list rather than
being added as a single member. Any null arguments are simply skipped.

Examples:
    (concat 1 '(2 3) 4)         ; results in a new vector [1 2 3 4]
    (concat [1 2] null 3 [4])   ; returns [1 2 3 4]

See also: nconc vcons append
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp nconc "
Syntax: (nconc <value> <vector>)

The 'nconc' function adds its first argument to the end of the vector
provided in the second argument then returns the modified vector.
If the first argument is also a vector, it is added as a single element
to the end of the second argument. If the second argument is null, then
a new empty vector will be created first then the first argument will
be added to that new vector.

Examples:
    (nconc 4 [1 2 3])       ; returns [1 2 3 4]
    (nconc [4 5] [1 2 3]]   ; returns [1 2 3 [4 5]]
    (nconc 1 null)          ; returns [1]
    (nconc [1 2 3] null)    ; returns [[1 2 3]]

See also: vcons concat
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp apply  """
Syntax: (apply functionToApply collection)

The apply takes a function and a collection and applies the function using the
collection as the arguments to that function. It is similar to splatting in that
(apply + coll) returns the same result as (+ @coll).

Examples:
    (apply + [1 2 3])                           ; returns 6
    (apply * '(2 4 6))                          ; returns 48
    (apply (fn &args -> (length args)) [1 2 3]) ; returns 3

See also: call
""")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp as  """
Syntax: (as objectToConvert targetType)

As converts it's first argument into the type specified by the second
argument either returning an object of that type or null if the conversion
was not successful.
    (as "123" ^int)   ; returns the integer value 123
    (as "abc" ^int)   ; returns null
""")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp asarray  "
Syntax: (asarray enumerableToConvert [arrayType])

The 'asarray' function returns its argument wrapped in an instance of ^object[].
If the argument is already ^object[], it is simply returned. If the argument is
an ^IEnumerable, an array of equivalent size is allocated and the elements copied
in to this new array. It the argument is a scalar, it will be wrapped in a
one-element array. An optional array type can be specified in which case the returned
array will be of that type and the objects in the source enumerable will be converted
to the target type

Examples:
    (asarray '(1 2 3))          ; returns an array 1,2,3.
    (asarray 13)                ; returns a 1 element array.
    (asarray [1 2 3] ^string)   ; returns an array of the specified type containing 3 strings

See Also: new-array
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp aslist  "
Syntax: (aslist enumerableToConvert)

The 'aslist' function converts its argument enumerable into a Braid list.

Examples:
    (aslist [1 2 3]) ; returns (1 2 3)

See also: asarray
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp atom?  """
Syntax: (atom? object)

The 'atom?' function returns true if its argument is not an
enumerable type.

Examples:
    (atom? 123)         ; returns true
    (atom? "abc")       ; returns true
    (atom? [1 2 3])     ; false
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp band  "
Syntax: (band arg1 arg2 ...)

The 'band' function performs a binary 'and' on its arguments.

Examples:
    (band 0xF 0x5)      ; returns 5
    (band 0xF 0x5 0x4)  ; returns 4

See also: shiftl shiftr bnot bor bxor
")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp bnot  "
Syntax: (bnot arg)

The 'bnot' function computes the bitwise complement of its argumen.

See also: shiftl shiftr band bor bxor
")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp baseobject  "
Syntax: (baseobject object)

If the argument object is a PowerShell PSObject, the 'baseobject' function
will return the base object from the PSObject. If the argument is not a
PSObject, then it will just return the original object.
")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp bind  "
Syntax: (bind lambda [environment])

(Re)Bind a lambda to either the current environment or a optional
passed argument.

See also: environment
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp environment  "
Syntax: (environment arg1 arg2)

Returns the active lexical environment.

See also: bind
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp bor  "
Syntax: (bor arg1 arg2 ...)

The 'bor' function performs a binary 'or' on its arguments.

Examples:
    (bor 0x4 0x1)           ; returns 5
    (bor 0x1 0x2 0x4 0x8)   ; returns 15 (0xF)

See also: shiftl shiftr band bxor
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp bound?  "
Syntax: (bound? symbol)

returns true if the symbol has a binding (an associated value or function.)

Examples:
    (bound? 'x)              ; returns true
    (bound? 'nosuchvar)      ; returns false

See also: symbol?
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp break  """
Syntax: (break [<value>])

The 'break' function allows you to break out of a loop as shown in the
examples An optional value can be specified in which case the value
becomes the result (or part of the result) of the loop. It works for
'conventional' loops like 'while' and 'foreach' as well as functions
like 'map', 'filter' and 'zip'.

Examples:
    ; executes the println function once then stops
    (while true
        (println "I'm done.")
        (break)
    )
    ; break can be called from zip function lambda to stop iterating early.
    ; the following returns [2 4 6]
    (zip (range 10) (range 10) (fn x y ->
        (let r (+ x y))
        (if (> r 6) (break))
        r)
    )
    ; break out of the 'map' pipeline returning "hello"
    (range 10 | map (fn x -> (if (== x 5) (break "hello") x))

See also: foreach forall for while continue recur return map filter zip 
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp continue  "
Syntax: (continue)

Continues to the next iteration in a loop (while, foreach, forall) or
in higher-order functions like map or filter.  

Examples:
    ; print numbers skipping the odd ones
    (foreach n [1 2 3 4] (if (% n 2) (continue)) (println n))
    ; same thing using 'map'
    (range 10 | map (fn n -> (if (% n 2) (continue) n)))

See also: foreach forall for while break recur return map filter zip 
")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp bxor  "
Syntax: (bxor arg1 arg2)

The 'bxor' function performs a binary 'xor' on its two arguments.

Examples:
    (bxor 0x1 0x4)          ; returns 0x5
    (bxor 0xF 0b1001)       ; returns 6

See also: shiftl shiftr band bor
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [car head]  """
Syntax: (@fn@ listOfObjects)

The '@fn@' function returns the first item from a sequence, or the
item itself if it's an atom.  (head is an alias for car.) If the argument
is a string, the first 'word' is returned i.e. all of the text up to
the first whitespace character.

Examples:
    (@fn@ '(1 2 3))       ; returns 1
    (@fn@ [4 5 6])        ; returns 4
    (@fn@ "abc")          ; returns "abc"
    (@fn@ "abc def ghi")  ; returns the first word "abc"

See also: cdr tail first last
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp first  """
Syntax: (first <collection> [<num>])

The 'first' function returns the first <num> items from the argument
collection. If <num> is not specified, it defaults to 1. If the collection
is a string, 'first' returns the first <num> characters. If the argument
is not a collection, then it is simply returned.

Examples:
    (first '(1 2 3))  ; returns 1
    (first [4 5 6])   ; returns 4
    (first "abc")     ; returns "a"
    (first 1)         ; returbs 1

See also: car cdr tail last
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [cdr tail rest]  """
Syntax: (@fn@ listOfObjects)

The '@fn@' function skips the first item in a sequence and returns the rest,
or it returns the item itself if it's an atom. Note that for sequences, cdr
always returns an s_Expr regardless of the original type of the sequence. This
is for performance reasons. Getting the cdr of a Vector is slow. Getting the
cdr of an s_Expr, is very fast. (Commands tail and rest are aliases for cdr.)

Examples:
    (car '(1 2 3))  ; returns '(2 3)
    (car [4 5 6])   ; returns [5 6[
    (car "abc")     ; returns "abc"

See also: car head first tail rest
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp char  """
Syntax: (char stringValue)

Returns the ^char of the first character in a 1-element string.

Examples:
    (char "a")    ; returns the char value 'a'.
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp chars  """
Syntax: (chars stringValue)

The 'chars' function converts is string argument to an array
of characters.

Examples:
    (chars "hello")   ; returns [ \h \e \l \l \o]

See also: char str join
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp cls  "
Syntax: cls

Clears the console screen.
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp collection?  """
Syntax: (collection? obj)

Returns true if its argument is any of the sequence types
(List, Vector, IEnumerable, ISeq etc.).

Examples:
    (collection? [1 2 3]        ; returns true
    (collection? 5)             ; returns false
    (collection? "hi")        ; returns false
    (collection? {:a 1})        ; returns true
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp cond  "
Syntax: (cond condExpr1 action1 ... condExprN actionN)

The 'cond' function evaluates each conditional expression and if
it evaluates to true, execute the associated action. To specify
the default action, make the condition 'true' as shown in the example.

Examples:
    (cond
        (< 1 x) 'less
        (> 1 x) 'greater
        true 'equals
    )

See also: if case matchp
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [cons :] "
Syntax: (@fn@ arg list)

The '@fn@' function constructs a new list. It adds the arg value to the list,
returning a new list.

Examples:
    (@fn@ 1 '(2 3))         ; returns '(1 2 3)
    (@fn@ 1 [2 3])          ; returns a new vector [1 2 3]
    (@fn@ 1 2)              ; returns a dotted pair (1 . 2)

See also: vcons >cons
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [>cons >:] "
Syntax: (>cons list arg)

This function is identical to 'cons' except the arguments are reversed
allowing it to be used in a pipeline. Like 'cons', it adds the arg value
to the start of the list, returning a new list.

Examples:
    (list 2 3 | @fn@ 1)    ; returns '(1 2 3)

See also: cons vcons
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp lambda "
Syntax: (lambda [args..] body...)

This function returns an anonymous function with the specified
args and body elements.

Examples:
    (lambda [x y] (+ x y))  ; returns an anonymous function to add 2 values

See also: defn
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp compare "
Syntax: (compare value1 value2)

The 'compare' function compares two value and returns -1 if the
first value is smaller than the second, 0 if the values are the same
and 1 if thesecond value is larger than the fitst value.

Examples:
    (compare 1 2)   ; returns -1
    (compare 5 5)   ; returns 0
    (compare 5 2)   ; returns 1

See also: == === < >
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp new-array "
Syntax: (new-array <type> <size> members...)

The 'new-array' function returns an initialized array with the specified
type and size.

Examples:
    (new-array ^int 5)      ; returns a new integer array with 5 elements
    (new-array ^int 3)      ; returns an integer array containing [1 2 3]

See also: new
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp console/backcolor  "
Syntax: (console/backcolor color)

Sets the console background color.

Examples:
    (console/backcolor 'black)

See also: cls console/cls console/forecolor
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [console/clear cls] "
Syntax: (@fn@)

Clears the console screen.

Examples:
    (@fn@)          ; clears the screen

See also:
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp console/forecolor  """
Syntax: (console/forecolor color)

Sets the console foreground color.

Examples:
    (console/forecolor "green") ; sets foreground color to green.
    ; using the ^ConsoleColor enum
    (console/forecolor .ConsoleColor/Yellow)
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp console/writeat  """
Syntax: (console/writeat [-foreground: color] [-background: color] xPos yPos "Message")

The console/writeat function writes a message at a specified location on
the console. You can optionally specify the fore- and background colors to
use when writing the text.

Examples:
    (console/writeat -foreground: "red" -background: "green" 40 40 "This is a message")
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp console/writeline  "
Syntax: (console/writeline arg1 arg2 arg3 ... argN)

Print a string made out of the tostring's of each of the argument
to the console adding a newline at the end. (This function is an alias
for 'println'.)

See also: print println alert info erro
")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp const  "
Syntax: (const symbol value)

The 'const' function reates a constant binding in the variable table at
the current scope. Trying to set the value of a constant will result in an
error. Constants can be removed with the 'undef' function.

See also: let def undef
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [count length]  """
Syntax: (count object)

Returns the @fn@ of a collection. If the argument is a scalar, then
it returns 1. If it's null, then the function returns 0.

Examples:
    (@fn@ '(1 2 3 4))      ; returns 4
    (@fn@ "hello")         ; returns 5
    (@fn@ [1 2 3 4 5 6])   ; returns 6
    (@fn@ {:a 1 :b 2})     ; returns 2
    (@fn@ (range 10))      ; returns 10
""")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp CreateDelegate  "
Syntax: (CreateDelegate <type> <lambda>)

Creates a delegate of the specified type out of a lambda.

Examples:
    ; create a delegate that takes one object argument and returns an object
    (createdelegate ^Func[object,object] (fn obj -> (+ obj 1)))

See also: AsEventHandler
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp decr  "
Syntax: (decr variableToDecrement)

This function decrements the value in the named variable, returning
the new value. The value in the variable must be of an integral type.

Examples:
    (let a 5) (decr a) ; returns 4 and the value of 'a' is now 4.
")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp pdecr  "
Syntax: (pdecr variableToDecrement)

This function decrements the value in the named variable, returning
the original value. The value in the variable must be of an integral
type.

Examples:
    (let a 5)
    (pdecr a) ; returns 4 and the value of 'a' is now 4.

See also: decr incr pincr
")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [def setq] "
Syntax: (@fn@ name value)

Set the value of the named variable if a variable with that name already
exists or create a new variable in the current scope if it doesn't.

Note: If the name takes the form 'v1:v2:v3' then destructuring will
be done and the parts of the argument collection will be assigned
to the variables.

Examples:
    (@fn@ foo 123)
    (@fn@ x:y:z [1 2 3 4 5])

See also: let defn >def def setq
")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp >def  "
Syntax: (>def value name)

Like 'def', this function sets the value of a variable if that
variable already exists or create a new variable in the current
scope if it doesn't. The difference is that the order of the
arguments is reversed. This allows '>def' to be used in the pipeline.

Note: If the name takes the form of v1:v2:v3 then destructuring will
be done and the parts assigned.

Examples:
    (123 | >def foo)            ; assign 123 to 'foo'.
    ([1 2 3 4] | >def foo)      ; assign the array to 'foo'
    ([1 2 3 4 5] | >def x:y:z)  ; assign 1 to 'x', 2 to 'y' and the rest to 'z'.

See also: let defn >def
")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp def-dynamic  "
Establish a binding in the dynamic scope of the calling function.

See also: Get-Dynamic
")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp defmacro  "
Syntax: (defmacro name body)

Define a new macro to be processed at compile time. The defined macro will
receive its arguments unevaluated and should return a new S-Expression to
replace the original structure.
")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp defn  """
Syntax: (defn funcName [ "doc string" ] [ ^returnType ] ( [args] functionBody | patternBody)

The 'defn' function allows you to define custom functions. The body of the function
being defined can either be a 'conventional' function or a pattern function. A literal
string specified after the function name but before the argument vector or first pattern
is treated as the  documentation string for that function. You can also specify the return
type for the function by placing a type literal after the doc string but before the start
of the function body.

Arguments to a conventional function are enclosed in a vector literal and can take several
forms: a simple name such as 'num', a type-constrained argument such as (^int num), an
initialized name such as '(num 0)' and finally as an initialized type-constrained
name: '(^int num 0)'. Uninitialized names are manadatory (must be specified). Initialized names
are optional arguments. If they are passed an explicit value, that value is used. If there is no
formal argument corresponding to the name then the initializer value is used.

BUGBUGBUG -add stuff about named parameters.

Examples:
    (defn sqr "compute the square root." [x] (* x x))
    (defn fact "compute factorial" [n] (if (n < 1) 1 (* n (fact (- n 1)))))
    (defn fact ^int [(^int n)]
        (if (n < 1)
            1 (* n (fact (- n 1)))
        )
    )
    (defn fib "compute fib number"
        | 0 -> 1
        | 1 -> 1
        | (+ (fib (- n 1)) (fib (- n 2)))
    )

See also: defmacro defspecial deftype
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp defobject  "
Syntax: (defobject val1 name2 val2 name3 val3 ... nameN valN)

Create a PowerShell PSCustomObject.

Examples:
    (defobject :a 1 :b 2) ; returns a PSCustomObject with a=1 and b=2.

See also: deftype definterface project
")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp defspecial  """
Syntax: (defspecial name [args] body

Defines a 'special form'. Special forms are functions that will receive their
arguments unevaluated. Braid has many built-in special forms such as
'if', 'while', 'let' and so on. Using 'defspecial', you can define your own
control structures, as shown in the examples. Typically, defspecial functions
also use the 'upvar' and 'upDo' functions to implement these control structures.

Examples:
    ; Define a 'forall' variant that uses two variables - item and count
    (defspecial forall-with-count
        "A forall loop with item and count variables."
        [(^symbol itemVar) (^symbol countVar) lst &args]
        ; bind the loop variables in the caller's context
        (upvar itemVar  'iv)
        (upvar countVar 'cv)
        ; wrap the body in a do expression
        (let body (cons 'do args))
        ; initilize the count variable
        (let cv 0)
        ; Now execute the loop
        (forall iv (upDo lst)
            (incr cv)
            (upDo body)
        )
    )
    ; try it out
    (forall-with-count i c [:a :b :c]
        [i c]
    )

See also: defn defmacro deftype

""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp dict?  "
Syntax: (dict? <expression>)

Returns true if the argument expression resolves to a dictionary.

Examples:
    (dict? {:a 1 :b 2}      ; returns true
    (dict? 1)               ; returns false

See also: new-dict
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp distinct  "
Syntax: (distinct <collection> [<accessorFunction>])

Returns only the distinct items in the argument collection. The result
is returned as a vector. An optional accessor function can be supplied
which extracts the property to compare.

Examples:
    (distinct [1 2 2 3 4 4])    ; returns [1 2 3 4]
    (random 100 | distinct)     ; remove duplicates in the collection returned by 'random'

See also: except unique union intersect
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp do  "
Syntax: (do <expr1> <expr2> <expr3> ... <exprn>)

Executes a series of expressions, one at a time and in order returning the
result of the last expression as the final value of the expression.
Do is commonly used with the 'if' function when you want to have
multiple expressions in the 'if' or 'else' parts of the statemant. The 'when'
and 'unless' macros use 'do' for this purpose.

Examples:
    (do 1 2 3 4)                            ; returns 4
    (if true (do (println 1) (println 2)))  ; prints 1 and then 2.

See also: if while when unless
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp dump-error  "
Syntax: (dump-error)

Dump the contents of the last PowerShell/.NET exception that occurred. This will give you
the .NET stack trace for the error instead of the Braid stack trace.
This is implemented using the PowerShell $error[0] variable.

See also: show-callstack
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp eq?  "
Syntax: (eq? arg1 arg2)

This is the polymorphic equality comparison function (eq?) which works on
any types that support comparisons (IComparable). (Note: eq? is
actually an  alias for the '==' function.) Value semantics are used for the
core braid types of vectors, dictionaries and lists.

Examples:
    (eq? 5 5)           ; returns true
    (eq? 5 6)           ; returns false
    (== [1 2] [1 2])    ; returns true
    (== [1 2] [1])      ; returns false
    (== {:a 1} {:a 1})  ; returns true

See also: == !=
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp error  """
Syntax: (error arg1 arg2 arg3 ... argn)

This function prints an error string to the console in red.

Examples:
    (error "This is an information message.")
    (error 'this 'is 'a 'message 'in 'pieces.)
    (error "The value of 2+2 is" (+ 2 2))

See also: println info warn
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp eval  "
Syntax: (eval <exprList>)

Evaluate an s-expression as a function in the current scope.

Examples:
    (eval '(+ 2 3))                                  ; returns 5
    (eval (list 'forall 'n [1 2 3] 'n))              ; returns [1 2 3]
    (eval (cons + (cons (list * 2 3) (cons 4 nil)))) ; returns 10
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp eval-string  """
Syntax: (eval-string <stringToEval>)

Parses a string into an s-expression then evaluate it using 'eval'.

Examples:
    (eval "(+ 2 3)")   ; returns 5

See also: eval
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp except "
Syntax: (except <coll1> <coll2>)

Computes the difference between two collections. All of the items in
collection 1 that aren't in collection 2 are returned.
BUGBUGBUG - the dictionary and set semantics aren't right - they
should return dictionaries and sets respectively.

Examples:
    (except [1 2 3 4] [2 4])      ; 2 lists returns [1 3]
    (except {:a 1 :b 2} {:a 1})   ; 2 dictionaries returns [ {:b 2} ]
    (except #{:a 1 :b 2} #{:a 1}) ; 2 sets returns [ :b, 2 ]

See also: union intersect distinct
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp edit-distance """
Syntax: (edit-distance <string1> <string2>)

The 'edit-distance' function computes the "edit distance" between the two
argument strings using the Damerau-Levenshtein algorithm - a metric of similarity
based on inserts, removes and replacements.

Examples:
    (edit-distance "foo" "boo")     ; returns an edit distance of 1 ('f' -> 'b')
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [lazy-filter filter where]  """
Syntax: (@fn@ [-not] <list> <predicate>)

Filters the input collection based on the results of evaluating the predicate
function on each item. The predicate can be a lambda literal, a named function,
a member accessor, a type literal, a regular expression or a dictionary literal.
If a dictionary literal is provided, '@fn@' will use property pattern matching as
the filter criteria. The sense of the comparison can be changed with the '-not' flag.
The 'lazy-' variant returns an enumerable instead of a collection. Individual values
can then be pulled from the enumerable as needed thus only evaluating as much as is
necessary.  Either of the forms can use 'break' in the predicate function to terminate
the search at the current item. You can also use 'continue' to skip over the current
item in the list and keep searching.

Examples:
    (range 10 | @fn@ (\ n -> (== (% n 2) 0)))  ; returns [2 4 6 8 10]
    (range 10 | @fn@ even?)                    ; returns [2 4 6 8 10]
    (range 10 | @fn@ -not even?)               ; returns [1 3 5 7 9]
    (range 20 | @fn@ #"2")                     ; returns [2 12 20]
    (get-process | @fn@ .cpu)                  ; returns all procs that have used CPU
    ; use property patterns to find Error entries whose message matches the regex #"timeout"
    (get-eventlog -log: "system" -newest: 1000 | @fn@ {entrytype "error" message #"timeout"})
    ; find element '99' in the input collection, stopping the search when it's found
    (range 100000 | @fn@ (\ n -> (if (== n 99) (break))))

See also: filter lazy-filter map lazy-map each 
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [flatmap lazy-flatmap] """
Syntax: (@fn@ list function)

The '@fn@' function is usually used in pipelines to process items in
the pipeline. It takes a list of values and a function to apply to each value
as is showen in the examples. Functions can either be predefined functions,
property functions or lambdas. As opposed to the map function, '@fn@' flattens
its result so if the function returns a list, then that list will be stiched
into the result list rather than appearing as a discrete list. The distinction
between 'flatmap' and 'lazy-flatmap' is that 'flatmap' returns the entire result
collection whereas 'lazy-flatmap' returns an enumerable immediately and the values
can be pulled out 1 at a time, as needed.

Examples:
    (range 10 | @fn@ sqr)                  ; maps 'sqr' onto each number from the range
    (ls '*.cs | @fn@ .length)              ; gets the property .length from each file object
                                           ; through the pipeline
    (range 10 | @fn@ (fn x -> [x x]))      ; returns [1 1 2 2 3 3 ...]

See also: map filter flatten
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp flatten """
Syntax: (flatten args...)

The 'flatten' function recursively flattens all of its arguments into a single collection.

Example:
    (flatten '(1 (2 3) 4 ((5))))    ; returns '(1 2 3 4 5)
    (flatten '(1 2 3) [4 [5 6]] 7)  ; returns '(1 2 3 4 5 6 7)

See also: flatmap
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp lazy-flatten """
Syntax: (lazy-flatten arg1 arg2 ... argN)

The 'lazy-flatten' function lazily flattens all of its arguments into a single collection.
On execution, it returns an ^IEnumerable immediately. Individual values can then be read
from that enumerable as needed.

Example:
    (lazy-flatten '(1 (2 3) 4 ((5))))    ; returns '(1 2 3 4 5)
    (lazy-flatten '(1 2 3) [4 [5 6]] 7)  ; returns '(1 2 3 4 5 6 7)

See also: flatmap
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [id echo]  """
Syntax: (@fn@ args...)

The '@fn@' is the 'identity function' and simply returns it's arguments unmodified. If multiple
arguments are specified then a collection is returned. If only a single value is provided, then
it will be returned as scalar.

Examples:
    (@fn@ 123)              ; returns 123
    (@fn@ 1 2 3 4)          ; returns [1 2 3 4]

See also: id echo
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp forall """
Syntax: (forall var <list> <expr1> <expr2> ... <exprn>)

The 'forall' function iterates over the argument list, binding
each value to the supplied variable and then executes all of the
body expressions. The 'forall' function returns the value of evaluating
the last body expression for all iterations.

Examples:
    (let x (forall i (range 5) (* i i))) ; x is set to [ 1, 4, 9, 16, 25 ] 

See also: foreach map lazy-map filter lazy-filter each
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp foreach  """
Syntax: (foreach var <list> <expr1> <expr2> ... <exprn>)

The 'foreach' function iterates over the argument list, binding
each value to the supplied variable and then executes all of the
body expressions.  The 'var' specification can be a simple variable
e.g. 'foo' or a pattern 'a:b:c' in which case destructuring is performed
on each item or finally, it can be a literal vector of variables in which
case multiple items will be pulled from the list. Lite the pipeline 'each'
function, the standalone 'foreach' function returns no value (null).

Examples:
    (foreach i (range 1) (println i))              ; print numbers from 1 to 10
    (foreach x:y: [[1 2] [3 4]] (println (+ x y))) ; print sum of pairs
    (foreach [a b] [1 2 3 4] (println (+ a b)))    ; traverse two elements at a time
    (foreach [a:b: c:d:] [[1 2] [3 4]] (println [(+ a b) (+ c d)])) ; pattern matching

See also: forall map lazy-map filter lazy-filter each
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp function?  """
Syntax: (function? <expression>)

Returns true if the argument expression resolves to a executable object..

Examples:
    (function? sqr )     ; returns true
    (function? 123 )     ; returns false
    (function? [1] )     ; returns true - indexables can be used as functions
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp functions  """
Syntax: (functions [<filter-regex>])

Return a list of all symbols bound to functions, special forms and macros. An optional
regex can be used to filter the names that are returned. Functions are returned
as key/value pairs where the .key is the function name and the .value is the
function definition.
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp gen-symbol  "
Syntax: (get-symbol)

Generates and returns a new unique symbol. This is used in macros
to create unique symbols for the generated code.
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp get """
Syntax: (get <expression>)

Retrieves the value of the symbol identified by the argument expression.

See also: global globalq
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp get-args """
Syntax: (get-args)

Retrieves a vector containing the arguments to the current function. This
is typically used when creating error messages in pattern defaults.

Examples:
    (matchp 1 2 3 | -> (get-args))      ; returns [1 2 3]
    ; the following throws an exception whose string contains the actual args:
    ;    Expected one integer argument, not <<1 2 3>> 
    (matchp 1 2 3
    | (^int x) -> (+ x 2)
    | -> (throw "Expected one integer argument, not <<${(join (get-args))}>>")
    )
"""
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp get-assoc  """
Syntax: (get-assoc object [key])

This function allows you to retrieve tagged data from an
arbitrary object. For example, if you tagged the number 1 with
a message as follows:
    (set-assoc 1 :message "Hi there")
you could then retrieve it with
    (get-assoc 1 :message)

See also: set-assoc
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp if  """
Syntax: (if condExpr ifExpr [ elseExpr ])

The 'if' function does branching, taking one (if clause) or
une (if clause) or
two (if and else) clauses.

Examples:
    (if cond if-clause)
    (if cond if-clause else-clause)
    (let word (if (% x 2) "odd" "true"))    ; 'if' returns a value
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp getvar  """
Syntax: (getvar <varname>)

Get the variable object corresponding to the argument symbol.

Examples:
    (getvar 'braidhome)

See also: get
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp incr  """
Syntax: (incr variable [increment])

Post-increment a variable by the desired amount and returns the result. If no increment
is specified, then 1 is used. This function can be used for variables containing
integral values (e.g. ^int or ^long), strings or collections. In the case of strings
and collections, the "increment" will be appended to the end of the current value.

Examples:
    (let a 0)
    (println (incr a))  ; prints 0 on the screen
    (println a)         ; prints 1 on the screen
    (for (let i 0) (< i 10) (incr i) (println i))
    (let a [1 2 3])
    (incr a 4)          ; a now contains [1 2 3 4]
    (incr a)            ; a now contains [1 2 3 4 1]
    (let a "abc")
    (incr a "ef")       ; a now contains "abcdef

See also: pincr decr pdecr ++ --
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp pincr  """
Syntax: (pincr variable [increment])

Pre-increment a variable by the desired amount, returning the original un-incremented
value. If no increment is specified, then 1 is used. This function can be used for variables
containing integral values (e.g. ^int or ^long), strings or collections. In the case of strings
and collections, the "increment" will be appended to the end of the current value. Note that
in the collection case, because the collection is actually mutated, calling pincr returns the
updated value.

Examples:
    (let a 0)
    (println (pincr a)) ; prints 1 on the screen
    (println a)         ; prints 1 on the screen (a is 1)
    (let i 0) (while (pincr i | < 10) (println i))

See also: incr decr pdecr ++ --
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp info  """
Syntax: (info arg1 arg2 arg3 ... argn)

This function prints an informational message to the console in yellow.
All of the arguments are turned into strings then joined with a single
space between each string.

Examples:
    (info "This is an information message.")
    (info 'this 'is 'a 'message 'in 'pieces.)
    (info "The value of 2+2 is" (+ 2 2))

See also: warn error println
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp intersect """
Syntax: (intersect <collection1> <collection2>)

Computes the intersection of two collections and returns the result
as a vector.

Examples:
    (intersect [1 2 3] [2 3 4]; returns [2 3]

See also: distinct union except
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp is?  """
Syntax: (is? <object> <type>)

Checks to see if the argument object is of the specified type or
matches a specified property pattern. If only a single argument is
specified, a new "curried" function is returned.

Examples:
    (is? 123 ^int)                          ; returns true
    (is? 123 ^string)                       ; returns false
    (is? "abc" ^string)                     ; returns true
    (get-date | is? {:dayofweek "Tuesday"})
    (filter coll1 (is? ^int))               ; returns the integers in 'coll1'

See also: isnot?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp isnot?  """
Syntax: (isnot? <object> <type>)

Checks to see if the argument object is not of the specified type. If only
a single argument is specified, a new "curried" function is returned.

Examples:
    (isnot? 123 ^int)               ; returns false
    (isnot? 123 ^string)            ; returns true
    (filter coll1 (isnot? ^int))    ; returns the non-integers from 'coll1'

See also: is?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp lambda  """
Syntax: (lambda [args...] body...) or (lambda | pattern -> action | ...)

Lambda is not a function pe se. If 'lambda' is the first token in a list,
then that list is marked as a 'lambda function' or 'closure'. Lambda can be used
to specify both conventional and pattern functions. Lambda is rarely used
directly in Braid code. You usually use '\' as in (\ a b -> (+ a b)) or
the 'defn' macro to define a function.


Examples:
    (range 10 | map (lambda [x] (* x x)))                ; squares the number from 1 to 10
    (range 3  | map (lambda | 1 -> "one" | -> "not one") ; prints matching string
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp lambda?  "
Syntax: (lambda? <object>)

A predicate function that returns true if the argument object is a lambda function.

Examples:
    (lambda? (fn -> 1))     ; returns true
    (lambda? (lambda[] 1))  ; returns true
    (lambda? 1)             ; returns false

See also: lambda fn function?
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp last  """
Syntax: (last <list> [<number>])

The 'last' function returns a number of items from the end of a list or
vector. The number of items specified is optional and, if not specified,
defaults to 1. If more items are request than are available in the collecion,
as many items as available are returned. If the argument is not an enumerable
(i.e. not a scalar), then 'last' will simply return the item as is.
If a single item is to be returned, it is returned as a scalar rather
than as a vector of 1 element.

Examples:
    (range 10 | last)               ; returns 10
    (range 10 | last 1)             ; returns 10, not [ 10 ]
    (range 10 | last 3)             ; returns [8 9 10]
    (range 5  | last 10)            ; returns [1 2 3 4 5]

See also: first take !! slice
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp str  """
Syntax: (str args...)

The 'str' function converts its arguments to strings the concatenates the
individual strings with no intervening spaces. This function is similar to
join but is varargs and doesn't allow a seperator.

Examples:
    (str 1 2 3)         ; returns "123"

See also: join
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [length count] """
Syntax: (@fn@ object)

Returns the @fn@ of a collection. If the argument is a scalar, then
it returns 1. If it's null, then the function returns 0. This is an alias
for the 'count' function.

Examples:
    (@fn@ "abcdef")     ; returns 5
    (@fn@ [1 2 3])        ; returns 3
    (@fn@ '(2 4 6 8)      ; returns 4
    (@fn@ 13              ; returns 1
    (@fn@ null)           ; returns 0

See also: count
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp let  "
Syntax: (let name value)

Sets the value of a variable in the current scope if a variable
with that name exists or creates a new variable in the current scope
if it doesn't. If the name takes the form of v1:v2:v3 then destructuring
will be done and the parts assigned. If the assignment target is a Vector
or Dictionary literal, then pattern matching is done.

Examples:
    (let foo 123)               ; returns 123
    (let x:y:z [1 2 3 4 5])     ; x is bound to 1, y to 2 and z to [3 4 5]
    (let [x y z] [1 2 3])       ; returns true
    (let [x y z] [1 2 3 4 5]    ; returns false - too many values
    (let [x y &z] [1 2 3 4 5]   ; x is bound to 1, y to 2 and z to [3 4 5]
    (let [x 2 z] [1 2 3])       ; x is bound to 2, z to 3 and true is returned

See also: vlet def setq defn const
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp vlet """
Syntax: (vlet name value)

Sets the value of a variable in the current scope if a variable
with that name exists or creates a new variable in the current scope
if it doesn't. If the name takes the form of v1:v2:v3 then destructuring will
be done and the parts assigned. The only difference between 'let' and 'vlet' is
that 'vlet' always returns null instead of the assigned value. This function
is primarily intebder fot interactive use.

Examples:
    (let foo 123)
    (let x:y:z [1 2 3 4 5])

See also: let def setq
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp let? """
Syntax: (let? name value)

Returns true if a destructuring assignment was successful, false otherwise.

Examples:
    (vlet xs [1 2 3]) (while (let? x:xs xs) (println x)) ; print a list

See also: let vlet def setq defn
""")
;)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp list """
Syntax: (list arg1 arg2 arg3 ... argN)

Returns a list composed of its evaluated arguments.

Examples:
    (list 1 (+ 2 3) 4) ; returns (1 5 4)

See also: list? append
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp list?  """
Syntax: (list? <object>)

Returns true if the argument object is a list.

Examples:
    (list? '(1 2 3))        ; returns true
    (list? (list 1 2 3))    ; returns true
    (list? [1 2 3])         ; returns false
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp load  """
Syntax: (load <fileName>)

Loads a braid file into the current scope (like PowerShell's
'dot sourcing'.)

Examples:
    (load 'foo.tl)      ; load the file 'foo.tl'
    (load "foo.tl")     ; load the file 'foo.tl'
    (let fileToLoad "foo.tl")
    (load fileToLoad)   ; load the file 'foo.tl'

See also: using-module using-assembly
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp map  """
Syntax: (map <collection> <function>)

The 'map' function is usually used in pipelines to process items in the
pipeline. It takes a collection of values and a function to apply to each value
as in: (map <collection> <function>) or: (<list> | map <function>)
Functions can either be predefined functions, property functions or lambdas.
The function is applied to each inbound element, returning the new element to
the output vector.

Examples:
    (range 10 | map sqr)                ; maps 'sqr' onto each number in the range
    (ls '*.cs | map .length)            ; gets the property .length from each file object
                                        ; through the pipeline
    (range 10 | map (fn x -> (* x x)))  ; maps the lambda function onto each value
    (range 10 | map (fn x -> (* x x)))  ; same thing but using function literal notation.

See also: map-parallel lazy-map each filter where lazy-filter
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp lazy-map  """
Syntax: (lazy-map list function)

The 'lazy-map' function is usually used in pipelines to lazily process items in the
pipeline. It takes a collection of values plus a transformation function to apply to
each value in the input collection e.g.
    (lazy-map <collection> <function>) or (<collection> | lazy-map <function>)
and returns a lazy enumerable which will compute result items one at a time (lazy
evaluation).
Transformation functions can either be predefined functions, member accessors or lambdas.

Examples:
    (range 10 | lazy-map sqr)                ; maps 'sqr' onto each number in the range
    (ls '*.cs | lazy-map .length)            ; gets the property .length from each file object
                                             ; through the pipeline
    (range 10 | lazy-map (fn x -> (* x x)))  ; maps the lambda function onto each value
    (range 10 | lazy-map (fn x -> (* x x)))  ; same thing but using function literal notation.

See also: map map-parallel each filter where lazy-filter
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp each  """
Syntax: (each list function)

Like 'map', the 'each' function is usually used in pipelines to process items from
the input sequence. It takes a list of values and a function to apply to each value
    (map <list> <function>) or (<list> | map <function>)
Functions can either be predefined functions, property functions or lambdas.
However, unlike 'map', the 'each' function always returns a singke null so its primary
use case is in side effects.

Examples:
    (range 10 | each println)   ; maps the 'println' onto each number in the range
                                ; then returns null.

See also: map flatmap lazy-map filter reduce
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp map-parallel  "
Syntax: (map-parallel list function)

The 'map-parallel' function is used in pipelines like 'map' to the
process items in the pipeline.  It takes a list of values and a function to
apply to each value
    (map-parallel <list> <function>) or (<list> | map-parallel <function>)
Functions can either be predefined functions, property functions or lambdas.
The difference betweenthis function and regular 'map' is that this function
runs it's lambda as a Task. In otherwords,the work for all pipeline items is
done concurrently (subject to processor limitations). As a consequence, the
lambda is executed in an isolated space that starts with a snapshot of the
caller's space but, because it's just a copy, changes the function makes are not
reflected in the caller's environment. Using this function over 'map' can make
your program run faster but be aware that the operation of creating a task is
fairly expensive so if your lambda is trivial, 'map-parallel' is probably not
the best choice.

Examples:
    (range 10 | map-parallel sqr)                  ; maps the function 'sqr' onto each number from the range
    (ls '*.cs | map-parallel .length)              ; gets the property .length from each pipeline object
    (range 10 | map-parallel (lambda [x] (* x x))) ; maps the lambda function onto each value
    (range 10 | map-parallel (fn x -> (* x x)))    ; same thing but using function literal notation.

See also: map flatmap each
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp new  """
Syntax: (new <type> [args...] [-properties: <dictionary>])

Create a new instance of a class passing arguments as appropriate. If
'-properties:' is specified along with a dictionary argument,
the properties corresponding to each pair in the dictionary
will be set to the dictionary value.

Examples:
    (new ^foo)          ; returns a new instance of ^foo with default values.
    (new ^foo 1 2 3)    ; returns an instance using a constructor with arguments.
    (new ^foo -properties: {:a 1 :b 2} ; sets the properties 'a' and 'b'.

See also: defmethod definterface
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp new-dict  """
Syntax: (new-dict <keytype> <valueType> key1 value1 key2 value2 ... keyN valueN)

Create a new generic dictionary with the keys and values constrained to
the specified types. The type can be followed by an optional list of keys and
values that will be used to populate the dictionary.

Examples:
    (new-dict ^string ^int "one" 1 "two" 2) ; creates Dictionary<string,int> with 2 pairs.

See also: dict?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp symbol  """
Syntax: (symbol <symname>)

Gets or creates the named symbol. If the symbol exists, it
is simply returned otherwise a new symbol is created atomically.

See also: symbol get-symbol gen-symbol show-symbols
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp keyword  """
Syntax: (keyword <name>)

Gets or creates a keyword object using the name string. If the keyword already
exists, the existing object is returned otherwise a new keyword is created atomically.

See also: symbol 
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [null? nil?]  """
Syntax: (@fn@ <object>)

Returns true if the argument object is null. 'null?' and 'nil?' are
aliases.

See also: nil? null? nil null notnull? notnil?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [notnull? notnil?]  "
Syntax: (@fn@ <object>)

Returns true if the argument object is not null. 'notnull?' and 'notnil?' are
aliases.

See also: nil? null? nil null
")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp not """
Syntax: (not <object>)

Is the boolean complement function. If the argument object
is interpreted as true, then the function returns false and
vise versa. Since all objects have a boolean interpretation
this function can be applied to anything.
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp number? """
Syntax: (number? <object>)

Returns true if the argument object is any of the numeric types.

Examples:
    (number? 1)     ; returns true
    (number? 1.0)   ; returns true
    (number? "1")   ; returns false
    (number? :abc)  ; returns false
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp or """
Syntax: (or arg1 arg2 arg3 ... argn)

The 'or' function returns a true value if any of its arguments
evaluate to a true value. Lazy evaluation is used so the first
argument that evaluates to true halts execution and that value
is returned.

Examples:
    (or true true true)    ; returns true
    (or true false true)   ; returns true
    (or 1 2)               ; returns 1
    (or 0 2)               ; returns 2

See also: and not xor
AutoCurry: true
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp xor """
Syntax: (xor arg1 arg2)
The 'xor' function, which takes exactly 2 arguments, converts it's arguments
into boolean values then computes the boolean xor of those values.

Examples:
    (xor false false)   ; returns false
    (xor true false)    ; returns true
    (xor false true)    ; returns true
    (xor true true)     ; returns false
See Also: or not and
AutoCurry: true
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp pair?  """
Syntax: (pair? <object>)

Returns true if the argument is a list (dotted-pair).

See also: list? atom?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp ilist?  """
Syntax: (ilist? <object>)

Returns true if the argument is of type ^System.Collections.IList.

See also: list? atom? pair?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [pipe ->>] """
Syntax: (@fn@ <value> (expr1) (expr2) ... (exprN))

This function implements the logic for the form (a | b | c) which
is translated at compile time into (@fn@ a (b) (c))
There's not a lot of reason to use this function directly.

Examples:
    (@fn@ (range 10) (where (% 2)) (sum))   ; same as  (range 10 | where (% 2) | sum)
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp add-watch """
Syntax: (add-watch <filename>)

This function sets up a file watcher that will cause a script module to be reloaded
if it has changed since the last repl command was issued.

Examples:
    (add-watch 'my-module.tl)

See also: get-watch remove-watch
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp get-watch """
Syntax: (get-watch)

Returns a list of all of the watched scripts that were set up with 'add-watch'.

Examples:
    (get-watch)

See also: add-watch remove-watch
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp remove-watch """
Syntax: (remove-watch)

Removes a script watch that was set up with 'add-watch'.

Examples:
    (get-watch)

See also: add-watch get-watch
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp pos? """
Syntax: (pos? <number>)

Returns true if the argument number is positive.

Examples:
    (pos? 1)                ; returns true
    (pos? -1)               ; returns false
    (numbers | filter pos?) ; returns only the positive numbers from 'numbers'
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp neg? """
Syntax: (neg? <number>)

Returns true if the argument number is negative.

Examples:
    (neg? 1)                ; returns false
    (neg? -1)               ; returns true
    (numbers | filter neg?) ; returns only the negative numbers from 'numbers'
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp neg """
Syntax: (neg <number>)

Inverts the sign on a number.

Examples:
    (neg 2)     ; returns -2
    (neg -3)    ; returns 3
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp print """
Syntax: (print arg1 arg2 arg3 ... argN)

Print a string made out of the tostring's of each of the argument
to the console without adding a newline at the end.

See also: println alert info error
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp printat  """
Syntax: (printat [-foreground: color] [-background: color] x y msg)

Print a string at the specified location, optionally specifying the
foreground and background colors.

Examples:
    (printat 40 40 "A message")
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp println  """
Syntax: (println arg1 arg2 arg3 ... argN)

Print a string made out of the tostring's of each of the argument
to the console adding a newline at the end.

See also: print alert info error
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp println-color  """
Syntax: (println-color <foreground> <background> arg3 arg4 ... argn)

The first two arguments are treated as the colors to uese and the remaining
arguments are contcatenated into a string to be displayed. Spaces are placed
between each value in the resulting string. Cooersion on the color arguments
is used so they can be specified as strings rather than ^System.ConsoleColor
values.

Examples:
    (println-color "red" "black" "2+2 = "  (+ 2 2) 'so there!)
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp quit """
Syntax: (quit)

Quits the current braid session. If in a nested (debug) session, this will
return you to the parent session.

Examples:
    (quit)      ; exit the braid session
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp range  """
Syntax: (range collection) (range upper) (range lower upper) (range lower upper increment)

The 'range' function returns an enumerator over a range of numbers. If only one
argument is provided and that argument is a string or collection, the enumerator
will span the length of that collection. If there is only one argument and it is an
integer the range will be from 1 to that number. If two numbers are provided, they
represent the upper and lower bounds for the range. If the first number is larger
than the second, the range will be counted from largest to smallest.
You can also specify a third argument  the increment, which sets
the step count.  Note - stepping is always done so the larger number will converge
with the smaller.

Examples:
    (range 10)      ; returns 1-10.
    (range 10 1)    ; returns 10-1
    (range 0 10 2)  ; returns [0 2 4 6 8 10]
    (range "hello") ; returns 0-4
    (range [1 2 3]) ; returns 0-2
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp smaller """
Syntax: (smaller args...)

This function returns the smallest member of its argument list.

Examples:
    (smaller 3 1 4 2)   ; returns 1
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp bigger """
Syntax: (bigger args...)

This function returns the largest member of its argument list.

Examples:
    (bigger 3 1 4 2)   ; returns 4
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [read-file read-lines file/read-lines]  """
Syntax: (@fn@ <fileNames> [<regex>] [lambda])

This function reads files line by line, returning a vector of lines. If a regular expression
is specified then only lines matching that regular expression will be returned. You
can also specify a lambda which will be invoked on each matched item and the result
of the invocation will be returned. If the lambda returns null, then nothing will be added
to the output collection, allowing for more sophisticated filtering of the file.
If you specify a standard lambda, it  will receive 1-4 arguments which are, in order:
- the text of the matching line
- an array of the regex submatches in the line if a regex was specified
- the number of the matching line
- the name of the current file
Pattern lambdas, on the other hand, receive only a single argument - the current line being
processed.
The '@fn@' function also takes two named parameters: '-not' which changes the regex processing
from 'match' to 'not match' and '-annotate' which will result in the output lines being prefixed with
the current file name and line number.

Examples:
    (@fn@ 'foo.txt)                 ; returns a vector of the lines in the file
    (@fn@ 'foo.txt #"bar")          ; only returns the lines matching the regex
    ; Return the names of braid functions defined in a file i.e. ' ... defn <name> ...'
    (@fn@ 'autoload.tl  #"defn +([^ ]+)" (fn l m -> (!! m 1)))a
    ; Read all of the *.tl files and return strings of the form "fileName:lineno functionName".
    (@fn@ (ls '*.tl) #"defn +([^ ]+)" (fn l m n f -> (str f ': n " " (m 1))))
    ; use a pattern lambda to find all braid functions in the current file tree
    (@fn@ (ls -recurse '*.tl) (fn | (#"defn ([^ ]+)" _:m:_ -> m | -> null)))
    ; as the previous function but prefiltering with a regex which is faster
    (@fn@ (ls -recurse '*.tl) #"defn " (fn | (#"defn ([^ ]+)" m -> (!! m 1) | -> null)))

See also: read-text read-data
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [reduce foldl] """
Syntax: (@fn@ <list> <function> [seed])

This function iterates through a list applying the function
to each of the items and accumulating a result. An optional seed
value can be provided.

Examples:
    (range 10 | @fn@ (fn x y -> (+ x y)))               ; sum the numbers from 1 to 10 using a lambda
    (range 10 | @fn@ (fn x y -> (* x y)))               ; computer 10 factorial
    (range 10 | @fn@ +)                                 ; sums the numbers 1-10 using the '+' function.
    (ls '*.tl | @fn@ (fn x y -> (+ x (.length y))) 0)   ; sums the length of the *.tl files

See also: reduce foldl foldr unfold
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp foldr """
Syntax: (foldr <list> <function> [seed])

This function iterates through a list applying the function
to each pair of the items and accumulating a result. An optional seed
value can be provided. Unlike reduce/foldl, which folds from left to
right whereas 'foldr' folds right-to-left. 

Examples:
    (range 10 | foldr (fn x y -> (+ x y)))              ; sum the numbers from 1 to 10 using a lambda
    (range 10 | foldr (fn x y -> (* x y)))              ; computer 10 factorial
    (range 10 | foldr +)                                ; sums the numbers 1-10 using the '+' function.
    (range 10 | foldr (fn x y -> (- x y)))              ; returns -5

See also: reduce foldl foldr unfold
""")

(;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [iterator unfold] """
Syntax: (@fn@ <function> <initialValue> [<max>]

The @fn@ function is a way to produce a (possibly) infinite sequence
of values. Each new value in the sequence is computed by taking the
current value and passing it to the argument <function>. The result of evaluating
that function becomes the new current value. Instead of an array or list,
invoking @fn@ returns a .Net ^IEnumerable. Consumers can then get the enumerator
and iterate over that enumerator. If no 'max' is provided, the enumerator will
produce new values forever on until the consumer stops requesting values.
If 'max' is specified, values will be produced until 'max' is reached.

Examples:
    (unfold ++ 1 | take 100)        ; get integers from 1-100.
    (unfold (+ 2) 2 10)             ; even numbers from 2-10 inclusive.
    ; the following computes (fib 10)
    (unfold (fn x:y: -> [y (+ x y)]) [1 1] | take 10 | last | last)

See also: reduce foldl roldr
""")
;)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp reduce-with-seed """
Syntax: (reduce-with-seed <list> <function> <seedValue>)

This function iterates through a list applying the function
to each of the items and accumulating a result. The accumulator is
initialized with the seed value.

Examples:
    ; compute the total size of the '*.tl files in the current directory
   (ls '*.tl | reduce-with-seed (fn x y -> (+ x (.length y))) 0)

See also: reduce foldl foldr unfold
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp repeat """
Syntax: (repeat <number> clause1 clause2 clause3 ... clauseN)

Evaluates each of the clause arguments in sequence, repeating the
evaluation the specified number of times. This function always returns null.

Examples:
    (repeat 10 (println 'Hi)) ; print hi 10 times

See also: repeat-all do
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp repeat-all """
Syntax: (repeat-all <number> clause1 clause2 clause3 ... clauseN)

Evaluates each of the clause arguments in sequence, repeating the
evaluation the specified number of times. This function a vector
of the results of evaluating the last clause from each iteration.

Examples:
    (repeat-all 10 (.datetime/now)) ; get the date 10 times, returning 10 values

See also: repeat-all do
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [await resolve] """
Syntax: (@fn@ <listOfTasks>)

The @fn@ function waits for all argument tasks to complete and
then returns a collection containing the values returned by the tasks.
Note that even in the simple case of a single task,
the result will still be returned as a collection of one
element. 'resolve' is an alias for 'await'.

See also: async task map-parallel
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp return  """
Syntax: (return [value])

Returns immediately from a function returning a value.
Null is returned if the value is not specified.

Examples:
    (defn foo [] (return "foo")

See also: break continue
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp reverse  """
Syntax: (reverse list)

Reverses a list or vector, returning a new reversed list.

Examples:
    (reverse [1 2 3])   ; returns [3 2 1]
    (reverse '(1 2 3))  ; returns [3 2 1]
    (chars "hello" | reverse | join "") ; returns 'olleh'
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindHelp [get-dynamic gdv] """
Syntax: (@fn@ <symbol>)

This function retrieves the ^BraidVariable object associated with the argument symbol
looking up the dynamic (runtime) callstack. This is particularly useful in the
debugger.

See also: get def let
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp seq? """
Syntax: (seq? object)

The 'seq?' function returns true if it's argument is a sequence type (list or vector).

Examples:
    (seq? '(1 2 3)) ; returns true
    (seq? [1 2 3])  ; returns true
    (seq? 123)      ; returns false
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp set """
Syntax: (set <varNameExpr> <value>)

Sets the value of the variable named by the result of evaluating <varNameExpression>.
This allows you to do indirect sets of variables.

Examples:
    (def n 'x) (set n 123)  ; sets the variable 'x' to 123
    (set 'foo 123)          ; equivalent to (setq foo 123)

See also: setq def let get defn
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp set-assoc  """
Syntax: (set-assoc object key value)

This function allows you to associate tagged data with an
arbitrary object. For example, you could tag the number 1 with
a message as follows:
    (set-assoc 1 :message "Hi there")
and then retrieve it with
    (get-assoc 1 :message)

See also: get-assoc
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp show-callstack """
Syntax: (@fn@)

This function dumps all of the current bindings in the variable
table across all of the dynamic scopes. It takes no arguments and
any provided arguments will be ignored. 'scs' is an alias for
show-callstack.

Examples:
    (@fn@)
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp show-symbols """
Syntax: (show-symbols)

This function returns all of the symbols currently in the symbol table.
It takes no arguments and any provided arguments will be ignored.
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp skip """
Syntax: (skip <coll> <number)

This function skips the first <number> items in collection <coll>. If the
collection is too short, then an empty collection will be returned.
If <coll> is an ^IList, skip will return an immutable ^Slice addressing
the remainder of <coll>. If <coll> is an ^IEnumerable, skip will return
a lazy enumerable for the rest of <coll>.

Examples:
    (skip [1 2 3 4 5] 3) ; returns (4 5)

See also: skip-while
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp skip-while """
Syntax: (skip-while <list> <predicate>)

The 'skip-while' function skips items in a list while the provided predicate
evaluates to true. For example '(range 100 | skip-while (fn n -> (< n 90)))'
will skip the numbers 1-89 returning 90-100.

Examples:
    (range 10 | skip-while (< 8))   ; returns [8 9 10]

See also: skip
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [sort lazy-sort] """
Syntax: @fn@ [-Descending] listToSort [keyFunction])

This function sorts a sequence of values. By default, it sorts in ascending order
but the '-descending' flag changes this to descending order. You can also specify
a 'keyFunction' that will be used to select the value to sort on. You can use the
'lazy-sort' varient to pull values as needed.

Examples:
    (random 10 | sort)                      ; sorts 10 random numbers in ascending order
    (random 10 | sort -descending)          ; sorts 10 random numbers in descending order
    (ls -file | sort .length)               ; sort files by length
    (ls '* | sort (fn e -> (.extension e))) ; sort files by extensions
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp thenSort """
Syntax: (thenSort <output-of-sort> [<accessor>])

This function performs a secondary sort on the enumerator returned by 'sort'. It can
be applied multiple times to perform very complex sortings. Note that this is a lazy
function and returns an IEnumerable.

Examples:
    (sort [[2 :a] [1 :a] [2 :b]] car | thenSort second) ; returns [[1 :a] [2 :a] [2 :b]]

See also: sort
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp splice """
Syntax: (splice <list1> <list2>)

Splices two lists together so that list2 becomes the 'cdr' of list1, mutating list 1.

Examples:
    (splice '(1 2 3) '(4 5 6)) ; returns (1 2 3 4 5 6)
    (do (let a '(1 2 3)) (splice a '(4 5 6)) a) ; returns (1 2 3 4 5 6)
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp string?  """
Syntax: (string? <obj>)

The 'string?' function returns true if it's argument is a string.

Examples:
    (string? "hi")    ; returns true
    (string? 123)       ; returns false
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp swap """
Syntax: (swap var1 var2 [function]) or (swap var1 index1 var2 index2 [function])

This function swaps the values in variables or alternately, the values of
vectors stored in variables. In both cases, a comparer function can be provided.
This function is evaluated with the two values and the result is true, the values
are swapped.

Examples:
    (swap a b)        ; swaps the values in 'a' and 'b'.
    (swap a b >)      ; swap if 'a' is greater than 'b'
    (swap a 0 a 1)    ; swaps the first and second elements in the vector stored in 'a'.
    (swap a 0 a 1 > ) ; swaps if the first element is greated that the second element
    (swap a b (fn x y -> (> x y))) ; swap with user function
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp symbol? """
Syntax: (symbol? <object>)

Returns true if the argument object is a symbol.

Examples:
    (symbol? 'foo)  ; returns true.
    (symbol? 123)   ; returns false.
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp take  """
Syntax: (take <list> <count>)

Takes <count> objects from the front of the argument list. If the
count specified is larger than the number of items in the list, the
entire list is returned. Negative indexing is also supported. For example
'(take lst -1)' returns all but the last element from 'lst'. (Note: while
negative indexing will work on an ^IEnumerable, it can be slow as it must
count the number of elements to determine how many to take.) If an ^IList
is passed, an immutable ^Slice of that ^IList will be returned.

Examples:
    (take [1 2 3 4] 2) ; returns [1 2]
    (take [1 2 3] 10)  ; returns [1 2 3]
    (take [1 2 3] -1)  ; returns [1 2]

See also: take-after take-until skip
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp take-after """
Syntax: (take-after <list> <item>) or (take-after <list> <function>)

Takes items from a list after the specified item is found or the specified
function returns true.

Examples:
    (range 5 | take-after 3) ; returns [4 5]
    (range 4 | take-after (fn n -> (== (% n 2) 0))))  ; returns [3 4]

See also: take take-until skip
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp take-until """
Syntax: (take-until <list> <item>) or (take-until <list> <function>)

Takes items from a list untils the specified item is found or the specified
function returns true.

Examples:
    (range 5 | take-until 3) ; returns [1 2]
    (range 4 | take-until (fn n -> (== (% n 2) 0))))  ; returns [1]

See also: take take-after skip
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp [task async] """
Syntax: (@fn@ <lambda> [<argToLambda>])

Starts a new background task using the .NET Task Parallel Library with the lambda
as the ^Task procedure. An optional argument may be passed in though most things will
be passed through the closure. Tasks can be composed with the subsequent task receiving
the result of the previous task.

Examples:
    (await (@fn@ (fn -> (println 'hello))))           ; starts and then waits for a task that prints 'hello'.
    (@fn@ (fn -> 123) | await)                        ; returns [123]
    (@fn@ (fn -> 2) | @fn@ (fn n -> (* n 2)) | await) ; returns [4]

See also: resolve map-parallel await
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp throw  """
Syntax: (throw <messageString>)

Throws a generic exception with a custom message.

Examples:
    (throw "An error notification")

See also: try error
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp time """
Syntax: (time [<count>] <expression>)

Times the duration of the execution of an expression. If the optional count is
specified then the expression will be executed that number of times, then printing both
the total and average times for all runs.

Examples:
    (time (fib 25))     ; times how long it takes to compute the factorial of 25
    (time 100 (range 100 | !! 50))  ; times indexing into a range 100 times

""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp tostring  """
Syntax: (tostring <object>)

Converts its argument into a string.

Examples:
    (tostring 3.14)     ; returns "3.14"
    (toostring "hi")    ; just returns the string

ee also: str
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp trace """
Syntax: (trace true/false) or (trace [-Exceptions] <expression>)

Trace the execution of the interpreter. Tracing can be enabled globaly with (trace true)
disable with (trace false). You can also trace the evaluation of an expression. If the
'-exceptions' flag is specified, then runtime exceptions will trop you into a nested
listener level (repl) where you can example and mutate the state of the system with
functions like 'show-callstack' and 'get-dynamic'.

Examples:
    (trace true) (+ 2 3) (trace false)  ; try global tracing
    (trace -exceptions (+ 2 3))         ; trace a specific expression.
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp try  """
Syntax: (try [-catch: <catchExpr>] [-finally: <finallyExpr>] <bodyExpressions...>)

This function implements try/catch semantics. It executes all of the body
expressions in order. If any of thoese expressions raises an exception,
transfer is made to the -catch: expression where the exception is available
as %0. Finally, before leaving the control of the function, if there
was a -catch: expressions specified, it will be executed.

Examples:
    (try -catch: (echo "caught it")  (nosuchcommand))  ; returns "caught it"
    (try (/ 1 0))                                      ; returns an exception
    (matchp (/ 1 0) | ^exception -> "bad" | -> "good") ; pattern match on the exception

See also: throw
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp tuple  """
Syntax: (tuple <arg1> <arg2> ... <arg5>)

Create and return an immutable tuple using the values of the arguments.
A maximum of 5 arguments is supported.

Examples:
    (let tup (tuple 1 2 "Hello" (.datetime/now))    ; returns a tuple (1 2 "hello" <datetime>)
    (.item1 tup)                                    ; returns 1
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp type-alias """
Syntax: (type-alias <alias> [<type>])

If no arguments are provided, returns the current list of type aliases.
If just the alias is provided the existing alias binding will be deleted.
If both an alias and type are provided then the type alias will be created or
updated if it already exists.

Examples:
    (type-alias)            ; list all existing type aliases
    (type-alias :foo)       ; delete the type alias for :foo
    (type-alias :foo ^int)  ; establish that ^foo is a type alias for ^int

See also: deftype
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp type-of """
Syntax: (type-of <object>)
Returns the type of the argument object.

Examples:
    (type-of 123) ; returns ^int

See also: members-of
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp undef """
Syntax: (undef symbolToUnbind)
Removes the binding to the specified symbol from the variable table.

Examples:
    (undef foo)

See also: let def global
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp union """
Syntax: (union <list1> <list2>)
Computes the union of the two argument sets.

Examples:
    (union [1 2 3] [2 3 4]) ; returns [1 2 3 4]

See also: except intersect
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp unless """
Syntax: (unless <cond> <expr1> <expr2> ... <exprn>)

A control structure that evaluates all of the body exprs if the cond expr
evaluates to false. This is a macro that is implemented in terms of the
'if' and 'do' functions.

See also: when if do
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp vcons """
Syntax: (vcons <object> <vector>)

Inserts the first argument at the start of the second argument vector
and returns the updated vector. This is similar to 'cons' but 'cons'
returns a new list and 'vcons' returns a mutated vector. Note - if the
second argument is null, then a new vector will be created that contains
the first argument.

Examples:
    (vcons 1 [2 3 4])       ; returns [1 2 3 4]
    (vcons [1 2 3] [4 5])   ; returns [[1 2 3] 4 5]
    (vcons 3 null)          ; returns [3]
    (vcons [1 2 3] null)    ; returns [[1 2 3]]

See also: concat nconc
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp vector? """
Syntax: (vector? <object>)

Returns true if the argument object is a vector.

Examples:
    (vector? [1 2 3])   ; returns true
    (vector? '(1 2 3))  ; returns false becuase a list is not a vector

See also: vector to-vector
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp vector  """
Syntax: (vector [<args>...])

The 'vector' function constructs new vector objects. If no arguments are
provided, an empty vector wil be constructed. If arguments are
provided, they will be added to the new vector.

Examples:
    (vector)                      ; construct a new empty vector
    (vector 1 "two")            ; construct a 2 elenent vector
    (apply vector (list 1 2 3 4)) ; applies the vector to a list
                                  ; returning a new vector

See also: to-vector vector?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp new-vector  """
Syntax: (new-vector [<args>...])

The 'new-vector' function constructs new vector objects. If no arguments are
provided, an empty vector wil be constructed. If arguments are
provided, they will be added to the new vector.

Examples:
    (new-vector)            ; construct a new empty vector
    (new-vector 1 "two")  ; construct a 2 element vector
    (apply new-vector (list 1 2 3 4))

See also: to-vector vector? vector
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp to-vector """
Syntax: (to-vector <IEnumerable>)

The 'to-vector' function takes an enumerable value as an argument.
If the argument is already a vector, it will be returned unchainged.
All other types will be copied into a new vector.

Examples:
    (list 1 2 3 4 | to-vector)

See also: vector vector? ^vector
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp void """
Syntax: (void <object> ...)

This function ignores its arguments and simply returns null. Casting
to ^void has a similar effect.

Examples:
    (range 10 | map (fn x -> (* x x)) | void) ; returns null

See also: drain
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp drain """
Syntax: (drain <enumerable> ...)

This function ignores any non-enumerable arguments and returns null.
Any enumerable arguments are run to completion i.e. they are drained.
This is particularly important with lazy functions like range or lazy-map
which must be specifically enumerated to have any effect. In contrast,
if you used 'void' instead of 'drain', the enumerables will not be run.

Examples:
    ; the following will print each value then return null.
    (range 10 | lazy-map (fn x -> (info x) (* x x)) | drain)
    ; in contrast, the same expression but with void will print nothing
    (range 10 | lazy-map (fn x -> (info x) (* x x)) | void)

See also: void lazy-map lazy-filter to-vector
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp warn  """
Syntax: (warn arg1 arg2 arg3 ... argn)

This function prints a warning string to the console in magenta. All of the
arguments are converted to strings then joined to a single string seperated
by spaces then printed.

Examples:
    (warn "This is an warning message.")
    (warn 'this 'is 'a 'message 'in 'pieces.)
    (warn "The value of 2+2 is" (+ 2 2))

See also: alert info error println
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp when """
Syntax: (when <cond> <expr1> <expr2> ... <exprn>)

A control structure that evaluates all of the body exprs if the cond expr
evaluates to true. This is a macro that is implemented in terms of the
'if' and 'do' functions.

See also: unless if do
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp while """
Syntax: (while condExpr bodyExprs...)

The basic while loop. It loops evaluating the bodyExprs in sequence until the
condExpre evaluates to false following Braid's truthiness rules.

Examples:
    ; print number from 1 to 10
    (let n 1)
    (while (<= n 10)
        (println n) (incr n)
    )
    ; print a vector
    (let l [1 2 3 4])
    (while (let? x:xs l)
        (print x)
    )

See also: foreach forall map each
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp zip """
Syntax (zip <list1> <list2> [<zipFunction>])

This function zips two lists together so
    (zip [1 2 3] [10 20 30])
returns
    [[1 10] [2 20] [3 30]]
An optional function can be used to compute the 'zip' results.
The examples section shows code that sums the zip'ed elements using
a lambda.

Note: the 'break' and 'continue' functions can be used
in the lambda passed to 'zip' to, for example, early terminate
the 'zip' process.

Examples:
    (zip [1 2 3] [10 20 30] (fn x y -> (+ y x))) ; returns [11 22 33]
    (zip [1 2 3] [10 20 30] +)                   ; simpler but still returns [11 22 33]
    (defn dotprod [l1 l2] (zip l1 l2 * | sum))   ; function to compute the dot
                                                 ; product of 2 lists.

See also: map filter break
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp defmethod """
Syntax: (defmethod <targetType> <methodName> <lambda>)

Add a method to an existing type definition. Methods require
at least one parameter: the 'this' pointer. This must be
specified even if it is not used in the method body. Note
that the method name must be a raw symbol, not a keyword i.e. it
must be "foo" not ":foo".

Examples:
    ; add a method to ^int
    (defmethod ^int hi (fn this name -> (println 'Hi name 'its this)))
    (.hi 123 'bob)

See also: deftype definterface
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp random """
Syntax: (random <number>) or (random <min> <max>) or (random <number> <min> <max>)

This function generates a sequence of random numbers. If a single argument
is specified, that argument is used as the number of numbers to generate, ranging from
0 to the number. If two arguments are specified, they represent the min and max of the
range and the difference (max-min) is the number of numbers to generate. Finally
if three numbers are specified, the first is the number of numbers to generate and the
second and third represent the range into which the numbers should be generated.

Examples:
    (random 10)      ; generates 10 random numbers
    (random 5 10)    ; generates 5 random numbers between 5 and 10
    (random 5 10 20) ; generates 5 numbers between 10 and 20
    (random 100 | qsort) ; generates 100 numbers then sorts them

See also: range
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp get-symbol """
Syntax: (get-symbol <string>)

Gets the symbol associated with the argument string. This function is
most useful in macros.

See also: gen-symbol show-symbols
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp get-symbols """
Syntax: (get-symbols)

Returns all of the symbols in the symbol table.

See also: gen-symbol show-symbols get-symbol
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp global """
Syntax: (global <expression> <value>)

Binds the variable identified by expression to the specified value in the global
scope. Because the function takes an expression to evaluate rather than a symbol
to look up, it can be used to do indirect lookups in the global variable table.

Examples:
    (global (get-symbol "foo") 123) ; set the variable 'foo' to 13

See also: let def globalq
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp getfunc """
Syntax: (getfunc <object> [-caller])

The 'getfunc' function will return a function object corresponding to the object
passed in. This includes returning function objects for regular expressions,
dictionaries and vectors. If the optional '-caller' switch is specified, the function
will be resolved in the caller's dynamic scope rather than the current scope.

Examples:
    (getfunc '+)            ; return the function associated with '+'
    (getfunc {:a 1 :b 2}    ; return a function to look up items in the dictionary.

See also: compose partial compliment
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp globalq """
Syntax: (globalq <symbol> <value>)

Binds the variable identified by the symbol to the specified value in the global
scope.

See also: let def global
""")

(; is now a computed variable   BUGBUGBUG
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp h "
Syntax: (h) or (h <number>) or (h <pattern>)

Displays the history of commands executed in the REPL. With
no arguments, it will display the last 100 commands executed.
If a number is specified, then that number of commands will be
displayed (the absolute max is 1000.) If a pattern (string)
is specified, then that it will return the commands matching
that string.
")
;)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp shiftl """
Syntax: (shiftl value numberOfBitsToShift)

Shifts a value the specified number of bits to the left.

See also: shiftr band bor bxor
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp shiftr """
Syntax: (shiftr value numberOfBitsToShift)

Shifts a value the specified number of bits to the right.

See also: shiftl band bor bxor
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp recur """
Syntax: (recur arglist...)

The 'recur' function allows you to write tail-recursive programs in braid.
When invoked, it transfers control to the nearest function or loop context.
You can pass arguments to 'recur' which must match the arity of the
enclosing function.

Examples:
    (loop [x 10] (if x (do (println x) (recur (-- x))) 'done))
    (defn sum | x:xs -> (println x) (recur xs) | -> 'done)
See also: loop recur-to defn fn lambda
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp recur-to """
Syntax: (recur-to targetFunc arglist...)

The 'recur-to' function allows you to write tail-recursive programs in Braid
when you need to recur to a specific function. When invoked, it transfers
control to the identified function context. You must pass arguments to 'recur-to'
with the same arity of the target function. Note: the target function is identified
by the functions value, not its name.

Examples:
    (defn outer [x y] (if (== x 1) (recur-to outer 0 10) y)     ; (outer 1 0) returns 10
    (defn outer [x y] ((fn -> (if (== x 1) (recur-to outer 0 10) y)))) ; recur to outer function

See also: loop recur defn fn lambda \
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp dict/accessor """
Syntax: (dict/accessor dictKey)

The 'dict/accessor' function takes a dictionary key (typically a string) and generates
a custom dictionary accessor function. This function can then be used to retrieve
the value for that key from an arbitrary dictionary. If the key is not present, an
error is thrown.  If the function is applied against an ^IEnumerable, then the
designated member from each element in the collection is aggregated into a result vector.
Note that in the enumerable case, if the element is not a dictionary, it is simply
skipped.  Using a dictionary accessor for commonly retrieved keys can produce some
signifinant performance improvements.

Examples:
    (let afunc (dict/accessor :foo))
    (afunc {:foo 1 :bar 2})             ; returns 1
    (afunc [{:foo 1} {:foo 2}])         ; returns [1 2]

See also: !!
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp shell """
Syntax: (shell cmds...)

The 'shell' function concatenates its arguments and then runs the resulting
string as a PowerShell script.

Examples:
    (shell "Get-ChildItem" "-File")
    (shell "foreach ($i in 1..10) {$i}")

See also: psvar
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp quote? """
Syntax: (quote? argument)

The 'quote?' function returns true if its argument is quoted.

Examples:

See also: quote
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp zero? """
Syntax: (zero? argument)

The 'zero?' function returns true if its argument is zero.

Examples:
    (zero? 0)                                      ; returns true
    (zero? 1)                                      ; returns false
    (defn f [n] (if (zero? n) 1 (* n (f (-- n)))))

See also: none? some? number? null?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp even? """
Syntax: (even? argument)

The 'even?' function returns true if its argument is an even number.

Examples:
    (even? 4)                       ; returns true
    (even? 5)                       ; returns false

See also: none? some? number? number? odd?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp odd? """
Syntax: (odd? argument)

The 'odd?' function returns true if its argument is an odd number.

Examples:
    (odd? 4)                       ; returns false
    (odd? 5)                       ; returns true

See also: none? some? number? number? even?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp keyword? """
Syntax: (keyword? argument)

The 'keyword?' function returns true if its argument is a keyword literal.

Examples:
    (keyword? :foo)              ; returns true
    (keyword? "hi")              ; returns true

See also: none? some? number? number? even?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp some? """
Syntax: (some? argument)

The 'some?' function returns true if its argument has a value i.e. it
is not null, "" or [].

Examples:
    (some? 1)                ; returns true
    (some? 0)                ; returns true
    (some? null)             ; returns false
    (some? "")             ; returns false
    (some? [])               ; returns false
    (some? [ null ])         ; returns true

See also: some? null?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp none? """
Syntax: (none? argument)

The 'none?' function returns true if its argument has a value i.e. it
is not null, "" or [].

Examples:
    (none? 1)                ; returns false
    (none? 0)                ; returns false
    (none? null)             ; returns true
    (none? "")             ; returns true
    (none? [])               ; returns true
    (none? [ null ])         ; returns false

See also: some? null?
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp deftype """
Syntax: (deftype ^typeToDefine [^type] <memberVar> ... [ :defm <methodName> (fn this <vars..> -> <actions...) ]

The 'deftype' function allows you to define types in Braid. Data members can be specified
by simply including their names. An optional type may also be specified for a data member.
The ':defm' keyword is used to define a method. The method body is specified as a lambda
where the first parameter must be 'this'. 'this' contains a reference to the current
instance so to access a member variable 'a', you must write '(.a this)'. Methods can also be
defined independently of the type using the 'defmethod' function. Re-executing a 'deftype'
call will redefine existing any existing types with the same name.

Examples:
    (deftype ^foo a b c)            ; defines a type ^foo with 3 typeless data members
    (deftype ^bar ^int x ^int y)    ; defines a type ^foo with 2 int-typed data members
    ; define a type with 2 data members + 1 method.
    (deftype ^bax x y :defm sum (fn this -> (+ (.this x) (.this y))))

See also: defmethod defobject definterface
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp undeftype """
Syntax: (undeftype ^typeToUndefine)

The 'undeftype' removes a typename from the type lookup table.

Examples:
    (undeftype ^sometype)  ; returns true if the type was undefined, if the type didn't exist.
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp definterface """
Syntax: (definterface ^interfaceToDefine [[^type] <memberVar> ...]* [ :defm <methodName> (fn this <vars..> -> <actions...) ]*

The 'definterface' function allows you to define .NET interfaces in Braid. Data members can be specified
by simply including their names. An optional type may also be specified for a data member.
The ':defm' keyword is used to define method prototypes. The method body is specified as a lambda
where the first parameter must be 'this'. Any code in the member body is ignore as interfaces do not
provide implementation.

Examples:
    (definterface ^foo a b c)            ; defines a type ^foo with 3 typeless data members
    (definterface ^bar ^int x ^int y)    ; defines a type ^foo with 2 int-typed data members
    ; define an interface with 2 data members + 1 method.
    (definterface ^bax x y :defm sum (fn this ->))
    ; create a concrete type implementing that class.
    (deftype ^concretebax -implementsbax x y :defm sum (fn this -> (+ (.this x) (.this y))))

See also: defmethod defobject definterface
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp join """
Syntax: (join <seq> [<separator])

The 'join' function stringizes the elements of the argument collection
then joins them into a single string separated by an optional separator
string. If no separator string is provided, 'join' will use a single space.

Examples:
    (join [1 2 3])      ; results in "1 2 3"
    (join [1 2 3] "+")  ; results in "1+2+3"
    (join [1 2 3] ", ") ; results in "1, 2, 3"

See also: str tostring
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp defenum """
Syntax: (defenum <typeToCreate> <names...>)

A function for defining Braid enum types with a base type of integer. The enum
members can be specified either as a simple list of names or using a single dictionary.
If simple names are specified, they are automatically assigned values starting at 0,
increasing by 1 for each member. If a dictionary is passed, member names names are taken
from the keys and the dictionary values become the member values.

Examples:
    (defenum ^foo red blue green)               ; define an enum with 3 members with values 0, 1 and 2.
    (defenum ^foo {:red 10 :blue 20 :green 30}) ; define enum with values 10, 20 and 30.
    (defenum :foo a b c)                        ; use keyword for the typename instead of a type literal
    (defenum "foo" a b c)                       ; use a string for the typename instead of a type literal.
    (defenum "${tn}" a b c)                     ; use an expandable string for the typename instead of a type literal.

See also: deftype undeftype
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp slice """
The 'slice' function returns a ^Slice of an indexable collection (e.g a ^Vector or ^Array).
A ^Slice object is essentially a "window" into the underlying collection. Slice takes two
arguments - the offset into the collection to index from and the length of the collection.
Note that slices are immutable which means that you can't change the underlying collection
using the slice object. On the other hand, changes to the underlying collection will be
reflected in the slice.

Examples:
    (range 10 | slice 2 3)          ; returns [3 4 5]

See also: to-vector vector asarray
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp list/split """
Syntax: (list/split <list> <value or predicate>)

The 'list/split' function splits a list into two pieces based on a either a provided
value or a predicate function. If a value is specified the list is split at the first
occurance of that item in the list. Note that the value to split on is not included in
either result list and subsequent instances are not treated specially. Also note that if
the item is not found an empty second list is returned.

If a predicate function is specified, elements for which the function is true
are placed in the first result list and the rest are placed in the second result
list.

Examples:
    (list/split [1 2 3 4 5] odd?)   ; returns [[1 3 5] [2 4]]
    (list/split [1 2 3 4 5] (< 4))  ; returns [[1 2 3] [4 5]]
    (list/split [1 2 3 4 5] 3)      ; returns [[1 2] [4 5]]
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp breadth-search """
Syntax: (breadth-search <start> <goalValue|goalFn> <moveGeneratorFunction>)

This function will perform a breadth-first search through a set of
data. The first parameter is the starting data item. The second parameter
is either the target data item on a function of one argument returning
a boolean value if it's argument is the target item. The final argument
is the move generator function. This function is passed the current item
and returns a list of 'next' items to search.

Examples:
    ; searching a binary tree
    (breadth-search
        tree
        (fn x -> (.val x | == 15)) ; goal is 15
        (fn n -> (filter [(.?left n) (.?right n)] some?)))
    ; Starting at 5, search for the number 35 using the next move fn.
    (breadth-search 5 35
        (fn x -> [(+ x 3) (* x 2) (- x 7)]))
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp upvar """
Syntax: (upvar <parentSymbol> <localSymbol>)

The 'upvar' function allows you to bind a variable from the caller's
scope onto a variable in the current (local) scope i.e. it binds a variable 'up'
one level. Once this binding is established, setting the local variable actually
sets the variable in the caller's scope. When the binding is being established,
if there is no variable corresponding to <parentSymbol> in the caller's context,
a new variable will be created in the caller's context. This function is usually used
in special forms defined with 'defspecial'.

Examples:
    ; Define a function like 'incr' that increments the named variable by 2
    (defspecial incr-by-2 [(^symbol varToIncrement)]
        (upvar varToIncrement 'localVar)
        (incr localvar 2)
    )
    ; try it out
    (incr-by-2 foo)
    foo                 ; returns 2

See also: defspecial upDo
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp upDo """
Syntax: (upDo <expression>)

The 'upDo' function is similar to the 'eval' function except it evaluates
its argument in the caller's (parent) context. This function is typically used
in special forms created with defspecial.

Examples:
    ; function to set x to 1 in the caller's context.
    (defn set-x-to-1 [] (upDo '(let x 1)))
    (let x 10)      ; set x to 10
    (set-x-to-1)
    x               ; returns 1

See also: defspecial upvar upDo
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp group """
Syntax: (group <collection> <byFunction> <processGroupFn>)

The 'group' function groups members of a collection together in a dictionary by
the value returned by the <byFunction>. Once the groups have been created, the
<processGroupFn> is applied to each group. This function can be used to do things
like rrplace the group with the count of group elements or compute the sum of
a property on an element.

Examples:
    (ls -file | group .extension count)   ; counts the number of files per extension
    ; get the total length of each type of file
    (ls -file | group .extension (fn files -> (sum files .length)))
    ; count the number of times a word appears in a file
    (read-data words.txt | re/split | group echo count)
""")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(bindhelp loop """
Syntax: (loop [ sym1 expr1 sym2 expr2 ... ] (println \"hello\") (+ sym1 sym2))

This function allows a loop to be executed with 'recur'. The 'loop'
function creates a new scope, binds the symbols sym1, sym2, etc. to the results
of evaluating expr1, expr2, etc. Once that is done, the remaining statements (the
'loop body') are executed one after the other with the result of the last statement
being returned. If there is a call to 'recur' in the body with the same number of
values as in the initialization vector, control will be passed back to the top of
the loop, the listed symbols will be rebound to the new values and execution will
proceed from the top of the loop.

Examples:
    (loop [])                    ; executes but returns nil
    (loop [a 1 b 2] (+ a b))     ; returns 4
    (loop [n 10] (println n) (if n (recur (- n 1)))) ; uses recur to loop, prints 10 thru 0
    ; as above but a new const 'cn' created and set each time
    (loop [n 10]
        (const cn n)
        (println cn)
        (if n
            (recur (- cn 1))
        )
    )
    ; calculate the Fibonacci number for 10 using loop/recur
    (loop [n 10 r1 0 r2 1]
        (if n
            (recur (- n 1) r2 (+ r1 r2))
        )
        r2
    )
""")

;-------------------------------------------------------------------------------
;
; Test to make sure all the help is available through the 'doc' function.
;
(foreach name (.keys helpnames)
    (if (null? (doc name))
        (error "No help was found for" name)
    )
)

