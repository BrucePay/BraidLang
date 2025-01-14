;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Unit Test suite for Braid.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

lambda [
    :verbose ; if specified, will execute showing the names of each test as executed
    (^regex? tests-to-run #"") ; pattern to match against test names to see what to run.
]

;--------------------------------------------------------

(let run-in-verbose-mode verbose)

(alert "\nStarting test run at ${(.datetime/now)}")
(alert "============================================")

(let total-test-time-stopwatch (new ^System.Diagnostics.Stopwatch))
(.start total-test-time-stopwatch)
(let test-time-stopwatch (new ^System.Diagnostics.Stopwatch))

(let _counttests 0)
(let _failures   [])
(let _passed     0)
(let test-names  #{}) ; hashset for all the test names
(let test-durations {})

; delete any 'foo' binding that might otherwise causes test failures.
(undef foo)

;--------------------------------------------------------
;
; The test driver function.
;
(defn test/exec
    "Test driver function"
    [test-name lambda-to-run _expectedResult]

    ; only run tests that match the script argument pattern
    (when (re/match test-name tests-to-run)

        ; check to see if this test name was already used.
        (when (.contains test-names test-name)
            (warn "Duplicate test name '${test-name}")
        )

        (.add test-names test-name)

        (let _actualResult null)
        (.reset test-time-stopwatch)
        (.start test-time-stopwatch)
        (let _actualResult (try (lambda-to-run)))
        (.stop test-time-stopwatch)
        (!! test-durations test-name (.elapsed test-time-stopwatch | .TotalMilliseconds))

        (matchp _actualResult
        | (^Exception e) ->
            (error (fmt "{0,4}| test: '{1}' failed with exception:\n{2}" _counttests test-name (.message e)))
            (.add _failures test-name)

        | _ :where (== _expectedResult _actualResult) ->
            (if run-in-verbose-mode
                (info (fmt "{0,4}| test {1,-30} passed." _counttests test-name))
                (print ".")
            )
            (incr _passed)

        | ->
            (try
                (let error-msg
                    (fmt "{0,4}| test '{1}' FAILED!\nExpected: '{2}' ({3})\nActual: '{4}' ({5}).\n====================================="
                        _counttests test-name (toSourceString _expectedResult) (type-of _expectedResult)
                        (toSourceString _actualResult) (type-of _actualResult)))
                (error error-msg)
                (.add _failures error-msg)
            -catch: (fn e -> (e | fl -force '* | out-string | error))
            )
        )
        (incr _counttests)
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Tests start here.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;-------------------------------------------------------
; testing type literals
(test/exec :typetest1
    (fn -> ^int)
    ^int
)
(test/exec :typetest2
    (fn -> (. ^int :fullname))
    "System.Int32"
)
(test/exec :typetest3
    (fn -> (^int? "123"))
    123
)
(test/exec :typetest3a
    (fn -> (try (^int "123") | is? ^Exception))
    true
)
(test/exec :typetest4
    (fn -> (try (^int? "abc") | is? ^exception))
    true
)
(test/exec :typetest4a
    (fn -> (try (^int "abc") | is? ^exception))
    true
)
(test/exec :typetest5
    (fn -> (is? {:a 1 :b 2} ^Idictionary))
    true
)
(test/exec :typetest6
    (fn -> (is? {} ^Idictionary))
    true
)
(test/exec :typetest7
    (fn -> (is? [1 2 3 4]  ^Idictionary))
    false
)
(test/exec :typetest8
    (fn -> (is? [1 2 3 4] ^vector))
    true
)
(test/exec :typetest9
    (fn -> (is? [] ^vector))
    true
)
(test/exec :typetest10
    (fn -> (is? {} ^vector))
    false
)
(test/exec :typetest11
    (fn -> (is? '(1 2 3) ^List))
    true
)
(test/exec :typeetest12
    (fn -> (is? [1 2 3] ^List))
    false
)
(test/exec :typetest13
    (fn -> (== '() null))
    true
)
(test/exec :typetest14
    (fn -> (is? ^int ^type))
    true
)
(test/exec :typetest15
    (fn -> (is? {} ^System.Collections.IDictionary))
    true
)
(test/exec :typetest16
    (fn -> (is? {} ^System.Collections.Generic.Dictionary[object,object]))
    true
)
(test/exec :typetest17
    (fn -> (is? [] ^System.Collections.Generic.Dictionary[object,object]))
    false
)
(test/exec :typetest18
    (fn -> (== ^list ^BraidLang.s_Expr))
    true
)

;-------------------------------------------------------
; the "tostring" function
(test/exec :tostring1
    (fn ->
        (tostring '(1 2 (3 4) 5))
    )
    "(1 2 (3 4) 5)"
)
(test/exec :tostring2
    (fn ->
        (tostring [1 2 3] | re/replace #"\s+" "")
    )
    "[1,2,3]"
)
(test/exec :tostring3
    (fn ->
        (tostring {"a" 1 "b" 2} | re/replace #"\s+" "")
    )
    "{\"a\":1,\"b\":2}"
)
(test/exec :tostring4
    (fn ->
        (tostring '(1 2 (3 4) [5 6]))
    )
    "(1 2 (3 4) [5 6])"
)
(test/exec :tostring5
    (fn ->
        (tostring [1 2 '(5 6 7) 4] | re/replace #"[\n ]+" "")
    )
    "[1,2,(567),4]"
)

;-------------------------------------------------------
; the "tostring-all" function
(test/exec :tostring-all1
    (fn ->
        (let data (* [.datetime/now] 10))
        (data | tostring-all | == (data | map tostring))
    )
    true
)
(test/exec :tostring-all2
    (fn ->
        (let data (ls))
        (data | tostring-all | == (data | map tostring))
    )
    true
)

;-------------------------------------------------------
; the "str/truncate" function
(test/exec :str/truncate1
    (fn ->
        ; truncates the file text to a single line (i.e. no new lines
        (str/truncate (read-text (file/join-path braidhome "autoload.tl")) | #"\n" | ^bool?)
    )
    false
)

;-------------------------------------------------------
(test/exec :str/startswith1
    (fn ->
        (str/startsWith "abcde" "ab")
    )
    true
)
(test/exec :str/startswith1a
    (fn ->
        (str/startsWith "abcde" "xyz")
    )
    false
)
(test/exec :str/startswith2
    (fn ->
        (str/startsWith "abcde" "a")
    )
    true
)
(test/exec :str/startswith2a
    (fn ->
        (str/startsWith "abcde" "x")
    )
    false
)
(test/exec :str/startswith3
    (fn ->
        (str/startsWith "abcde" "")
    )
    true
)
(test/exec :str/startswith3a
    (fn ->
        (str/startsWith "abcde" nil)
    )
    true
)
(test/exec :str/startswith4
    (fn ->
        (str/startsWith "abcde" \a)
    )
    true
)

;-------------------------------------------------------
; the "fmt" function
(test/exec :fmt1
    (fn ->
        (fmt "{0}-{1}-{2}" :a :bb :ccc)
    )
    "a-bb-ccc"
)
(test/exec :fmt2
    (fn ->
        (fmt "{0:x} {1:x}" 0xdead 0xbeef)
    )
    "dead beef"
)
(test/exec :fmt3
    (fn ->
        (fmt "{0,10}|" "foo")
    )
    "       foo|"
)
(test/exec :fmt4
    (fn ->
        (fmt "{0,-10}|" "foo")
    )
    "foo       |"
)
(test/exec :fmt5
    (fn ->
        (let wordz [0xdead 0xbeef])
        (fmt "{0:x} {1:x}" @wordz)  ; use splattting
    )
    "dead beef"
)
(test/exec :fmt6
    (fn ->
        (let wordz [0xdead 0xbeef])
        (fmt "{1:x} {0:x}" @wordz)  ; use splattting
    )
    "beef dead"
)

;-------------------------------------------------------
; the 'call' function
(test/exec :call1
    (fn ->
        (defn foo [x y] (+ x y))
        (call foo 2 3)
    )
    5
)
(test/exec :call2
    (fn ->
        (defn foo [x y] (+ x y))
        (let table {:cmd foo})
        (call (table :cmd) 4 3)
    )
    7
)
(test/exec :call3
    (fn ->
        ; iterate over a list of functions and call each one
        ([+ - * / %] | map (fn op -> (call op 10 15)))
    )
    [25 -5 150 0 10]
)
(test/exec :call4
    (fn ->
        ; do the same thing but don't use call (so why have call?)
        ([+ - * / %] | map (fn op -> (op 10 15)))
    )
    [25 -5 150 0 10]
)

;-------------------------------------------------------
; The apply function.
(test/exec :apply1 #(apply + [1 2 3 4])     10)
(test/exec :apply2 #(apply * [1 2 3 4])     24)
(test/exec :apply3 #(apply + (range 1 100))  5050)
(test/exec :apply4 #(apply (fn &args -> (sum args)) (range 100)) 5050)
(test/exec :apply5 #(apply + (range 100))  (+ @(range 100)))
(test/exec :apply6
    (fn ->
        (apply (* 10) 5)
    )
    50
)
(test/exec :apply7
    (fn ->
        (==
            ; apply and call are basically the same...
            (apply + [1 2 3 4])
            (call  + 1 2 3 4)
        )
    )
    true
)

;-------------------------------------------------------
; the addition (+) function
(test/exec :+1 #(+ 1 2)          3)
(test/exec :+2 #(+ 1 2 4)        7)
; string addition
(test/exec :+3 #(+ "abc" "def")  "abcdef")
; polymorphic - string plus number gives string
(test/exec :+4 #(+ "abc" 123)    "abc123")
; polymorphic number + numeric string gives number
(test/exec :+5 #(+ 10 "2")       12)
; number plus bad string should raise an exception
(test/exec :+6
    (fn -> (is? (try (+ 10 "2abc")) ^Exception))
    true
)
(test/exec :+7
    (fn ->
        (+ 0.5 1 | type-of)
    )
    ^double
)
(test/exec :+8
    (fn ->
        ; uses the widest type
        (+ 3 0.5 1 | type-of)
    )
    ^double
)
(; BUGBUGBUG fails "with + cannot be applied to bigint and double"
(test/exec :+9
    (fn ->
        ; should widen to ^bigint
        (+ 0.5 1i 123 | type-of)
    )
    ^bigint
)
;)
(test/exec :+10
    (fn ->
        ; should roll up to long
        (+ .int/maxvalue 1 | type-of)
    )
    ^long
)
(test/exec :+11
    (fn ->
        ; should roll up to double
        (+ .long/maxvalue 1 | type-of)
    )
    ^double
)
(; BUGBUGBUG - doesn't widen properly when 0.5 is a string.
(test/exec :+12
    (fn ->
        ; should widen to ^double after converting string to number
        (let val (+ 1 "0.5" 123))
        [val (val | type-of)]
    )
    [124.5 ^double ] ; BUGBUGBUG - space needed between ^double and ] - make tokenizer more picky?
)
;)

;-------------------------------------------------------
; the number? function
(test/exec :number?1 #(number? (^byte? 123))  true) ; byte
(test/exec :number?2 #(number? 123)          true) ; int32
(test/exec :number?3 #(number? 123.00)       true) ; double
(test/exec :number?4 #(number? 123i)         true) ; bignum
(test/exec :number?5 #(number? (^uint32? 5))  true) ; uint32
(test/exec :number?6 #(number? (^uint64? 5))  true) ; uint64
(test/exec :number?7 #(number? (^sbyte? 5))   true) ; uint64
(test/exec :number?8 #(number? "abc")        false)
(test/exec :number?9 #(number? "123")        false)
(test/exec :number?10 #(number? {})          false)
(test/exec :number?11 #(number? [1 2 3 4])   false)
(test/exec :number?12 #(number? 0)           true)
(test/exec :number?13 #(number? nil)         false)
(test/exec :number?14 #(number? 15)          true)
(test/exec :number?15 #(number? -15)         true)
(test/exec :number?16 #(number? 10.784)      true)
(test/exec :number?17 #(number? -10.784)     true)
(test/exec :number?18 #(number? 10i)         true)
(test/exec :number?19 #(number? 0xdeadbeef)  true)
(test/exec :number?19a #(number? 0x10010110) true)
(test/exec :number?21 #(number? "")          false)
(test/exec :number?22 #(number? [1 2 3])     false)
(test/exec :number?23 #(number? {:a 1 :b 2}) false)
(test/exec :number?24 #(number? 123)         true)
(test/exec :number?25 #(number? 0x123)       true)
(test/exec :number?25a #(number? 0b100100)   true)
(test/exec :number?27 #(number? 123.00)      true)
(test/exec :number?28 #(number? 56i)         true)
(test/exec :number?29 #(number? nil)         false)
(test/exec :number?30 #(number? {})          false)
(test/exec :number?31 #(number? [1 2])      false)


;-------------------------------------------------------
; The sum function.
(test/exec :sum1  (fn -> (sum 5))        5)
(test/exec :sum2  (fn -> (sum [6]))      6)
(test/exec :sum3  (fn -> (sum []))       0)
(test/exec :sum3a (fn -> (sum nil))      0)
(test/exec :sum4  (fn -> (12 | sum))     12)
(test/exec :sum5  (fn -> ([13] | sum))   13)
(test/exec :sum6  (fn -> ([14] | sum))   14)
(test/exec :sum7  #(sum [1 2 3 4])       10)
(test/exec :sum8  #(sum ["a" "b" "c"])   "abc")
(test/exec :sum9  #(sum '(1 2 3))        6)
(test/exec :sum10 #(sum [1 "2" 3 "4"])  10)
(test/exec :sum11 #(sum '("a" 1 "b" 2)) "a1b2")
(test/exec :sum12 #(sum [1 2 0.5 4])    7.5) ; widening
(test/exec :sum13 #(sum [1 2 3i 4] | type-of)   ^bigint) ; widening to bigint
(test/exec :sum14
    (fn ->
        (deftype ^foo a b c)
        ; test default constructor that populates all the variables.
        (let objs (range 10 | map (fn n -> (new ^foo n n n))))
        ; test summing a property.
        (objs | sum .b)
    )
    55
)
(test/exec :sum15
    (fn ->
        (deftype ^foo a b c)
        (let objs (range 10 | map (fn n -> (new ^foo n n n))))
        ; test summing a property.
        (objs | sum (fn o -> (.b o)))
    )
    55
)
(test/exec :sum16
    (fn ->
        ([ {:a 1} {:a 2} {:a 3}] | sum (fn h -> (:a h)))
    )
    6
)

;-------------------------------------------------------
; The prod function.
(test/exec :prod1  (fn -> (prod 1)) 1)
(test/exec :prod2  (fn -> (prod [])) 0)
(test/exec :prod2a (fn -> (prod nil)) 0)
(test/exec :prod3  (fn -> (prod [1])) 1)
(test/exec :prod4  (fn -> ([1] | prod )) 1)
(test/exec :prod5  (fn -> (1 | prod )) 1)
(test/exec :prod6  (fn -> ([] | prod)) 0)
(test/exec :prod7  (fn -> (prod (range 10))) 3628800)
(test/exec :prod8  (fn -> (range 10 | prod)) 3628800)
(test/exec :prod9  (fn -> ([10 0.5] | prod)) 5)
(test/exec :prod10 (fn -> (range 100 | prod | type-of)) ^bigint)

;-------------------------------------------------------
; The average function.
(test/exec :average1  (fn -> (average 1))             1)
(test/exec :average2  (fn -> (average 5))             5)
(test/exec :average2a (fn -> (average nil))           0)
(test/exec :average2b (fn -> (average []))            0)
(test/exec :average3  (fn -> (average (range 10)))    5.5)
(test/exec :average4  (fn -> (range 100 | average))   50.5)
(test/exec :average5  (fn -> (average [3 6.5]))       4.75)
(test/exec :average6  (fn -> (range 1000 | average))  500.5)
(test/exec :average7  (fn -> (range 10000 | average)) 5000.5)
(test/exec :average8  (fn -> (average [1 2.0 3] | type-of)) ^double)
(test/exec :average9  (fn -> (average 1 echo))             1)
(test/exec :average10 (fn -> (average 5 echo))             5)
(test/exec :average11 (fn -> (average (range 10) echo))    5.5)
(test/exec :average12 (fn -> (range 100 | average echo))   50.5)
(test/exec :average13 (fn -> (average [3 6.5] echo))       4.75)
(test/exec :average14 (fn -> (range 1000 | average echo))  500.5)
(test/exec :average15 (fn -> (range 10000 | average echo)) 5000.5)
(test/exec :average16 (fn -> (average nil echo))           0)
(test/exec :average17 (fn -> (average [] echo))            0)
(test/exec :average18 (fn -> (ls | average .?length | > 0)) true)

;-------------------------------------------------------
; The median function.
(test/exec :median1  (fn -> (median 5))          5)
(test/exec :median2  (fn -> (median [5]))        5)
(test/exec :median3  (fn -> (median (range 10))) 5.5)
(test/exec :median4  (fn -> (range 10 | median)) 5.5)
(test/exec :median5  (fn -> (median nil))        0)
(test/exec :median6  (fn -> (median []))         0)
(test/exec :median7  (fn -> (median 5 echo))     5)
(test/exec :median8  (fn -> (median [5] echo))   5)
(test/exec :median9  (fn -> (median (range 10) echo)) 5.5)
(test/exec :median10 (fn -> (range 10 | median echo)) 5.5)
(test/exec :median11 (fn -> (median nil echo))   0)
(test/exec :median12 (fn -> (median [] echo))    0)
(test/exec :median13 (fn -> (ls -file | median .?length | > 0)) true)
(test/exec :median14 (fn -> (median (ls -file) .?length | > 0)) true)

;-------------------------------------------------------
; The max function
(test/exec :max1  (fn -> (max 5 6)) 6)
(test/exec :max2  (fn -> (max 10 6)) 10)
(test/exec :max2a (fn -> (max 6.5 6)) 6.5)
(test/exec :max2b (fn -> (max "hello" "world")) "world")
(test/exec :max2c (fn -> (max "aaa" "a")) "aaa")
(test/exec :max2d (fn -> (max 4 "123")) "123") ; left-hand rule for types
(test/exec :max2e (fn -> (max "123" 4)) 4)
(test/exec :max2f (fn -> (max "abc" 4)) "abc")
(test/exec :max2g (fn -> (try (max 4 "abc") | is? ^Exception)) true)
; max with 1 argument returns a curried function
(test/exec :max3 (fn -> (range 4 | map (max 3))) [3 3 3 4])
(test/exec :max4  (fn -> (is? (try (max)) ^Exception)) true) ;max with no arguments is an error
(test/exec :max5  (fn -> (max {:a 1} {:a 2} (fn x -> (:a x)))) {:a 2})
(test/exec :max5a (fn -> (max {:a 1} {:a 2} :a)) {:a 2})
(test/exec :max10 (fn -> (max 5 6 echo)) 6)
(test/exec :max11 (fn -> (max 10 6 echo)) 10)
(test/exec :max12 (fn -> (max 6.5 6 echo)) 6.5)
(test/exec :max13 (fn -> (max "hello" "world" echo)) "world")
(test/exec :max14 (fn -> (max "aaa" "a")) "aaa")
(test/exec :max15 (fn -> (max 4 "123" echo)) "123") ; left-hand rule for types
(test/exec :max16 (fn -> (max "123" 4 echo)) 4)
(test/exec :max17 (fn -> (max "abc" 4 echo)) "abc")

;-------------------------------------------------------
; the smaller and bigger functions
(test/exec :smaller1 #(smaller 1 2) 1)
(test/exec :smaller2 #(smaller 3 10 2) 2)
(test/exec :smaller3 #(smaller 3 10 2 4) 2)
(test/exec :smaller4 #(smaller 3 10 0.5 2 4) 0.5)
(test/exec :smaller5 #(smaller 3 -10 0.5 2 4) -10)
(test/exec :smaller6 #(smaller "hello" "world") "hello")
(test/exec :smaller7 #(smaller "hello" "world" 2) 2)
; curried function
(test/exec :smaller8 (fn -> (range 6 | map (smaller 3))) [1 2 3 3 3 3])

(test/exec :bigger1 #(bigger 1 2) 2)
(test/exec :bigger2 #(bigger 3 10 2) 10)
(test/exec :bigger3 #(bigger 3 10 2 4) 10)
(test/exec :bigger4 #(bigger 3 10 10.6 0.5 2 4) 10.6)
(test/exec :bigger5 #(bigger 3 -10 0.5 2 4) 4)
(test/exec :bigger6 #(bigger "hello" "world") "world")
(test/exec :bigger7 #(bigger "hello" "world" 2) "world")
; curried function
(test/exec :bigger8 (fn -> (range 6 | map (bigger 3))) [3 3 3 4 5 6])


;-------------------------------------------------------
; The max-list function
(test/exec :max-list1  (fn -> (max-list [1 3 5 2 4])) 5)
(test/exec :max-list1a (fn -> (max-list [1 3])) 3)
(test/exec :max-list1b (fn -> (max-list '(1 3 5 2 4))) 5)
(test/exec :max-list2  (fn -> (max-list 5)) 5) ; scalar argument
(test/exec :max-list3  (fn -> (max-list [])) nil)
(test/exec :max-list3a (fn -> (max-list nil)) nil)
(test/exec :max-list4  (fn -> (is? (try (max-list)) ^Exception)) true)
(test/exec :max-list5  (fn -> ([1 3 5 2 4] | max-list)) 5)
(test/exec :max-list6  (fn -> (range 1000 | max-list)) 1000)
(test/exec :max-list7  (fn -> ([1 3 5 2 4] | max-list (fn x -> (neg x)))) 1)
(test/exec :max-list8  (fn -> (range 1000 | max-list (fn x -> (neg x)))) 1)
(test/exec :max-list9
    (fn ->
        ; test with object properties
        (let data ([{:a 0 :b 0} {:a 3 :b 1} {:a 1 :b 2} {:a 2 :b 3}] | project :a :b))
        (data | max-list .a)
    )
    (project {:a 3 :b 1})
)
(test/exec :max-list10
    (fn ->
        ; test with object properties
        (let data ([{:a 0 :b 0} {:a 3 :b 1} {:a 1 :b 2} {:a 2 :b 3}] | project))
        (data | max-list .a)
    )
    (project {:a 3 :b 1})
)
(test/exec :max-list11
    (fn ->
        ; test with object properties
        (let data ([{:a 0 :b 0} {:a 3 :b 1} {:a 1 :b 2} {:a 2 :b 3}] | project))
        (data | max-list .a | .b)
    )
    1
)
(test/exec :max-list14
    (fn ->
        ; function to find the difference between adjacent pairs
        (defn nd 
            | x: i -> 
            | x:xs (i 0) ->
                (cons {:d (abs (- x (car xs))) :x x :y (car xs) :i i}
                    (nd xs (++ i)))
         )
         (let data [1 5 0 4 6 5 0 4])
         ; find the first index of the pair with the largest difference
         (nd data | max-list (fn d -> (:d d)))
    )
    {
        :d : 5,
        :x : 5,
        :y : 0,
        :i : 1
    }
)


;-------------------------------------------------------
; The min function
(test/exec :min1  (fn -> (min 5 6)) 5)
(test/exec :min2  (fn -> (min 10 6)) 6)
(test/exec :min2a (fn -> (min 6.5 6)) 6)
(test/exec :min2b (fn -> (min "hello" "world")) "hello")
(test/exec :min2c (fn -> (min "aaa" "a")) "a")
(test/exec :min2d (fn -> (min 40 "5")) "5") ; left-hand rule for types, compares not converts
(test/exec :min2e (fn -> (min "123" 4)) "123")
(test/exec :min2f (fn -> (min "abc" 4)) 4)
(test/exec :min2g (fn -> (try (min 4 "abc") | is? ^Exception)) true)
; curried  min function
(test/exec :min3 (fn -> ([1 2 3 4] | map (min 2))) [1 2 2 2])
(test/exec :min4 (fn -> (is? (try (min)) ^Exception)) true)
(test/exec :min5 (fn -> (min {:a 1} {:a 2} (fn x -> (:a x)))) {:a 1})

;-------------------------------------------------------
; The min-list function
(test/exec :min-list1  (fn -> (min-list [7 1 3 5 2 4])) 1)
(test/exec :min-list2  (fn -> (min-list 5)) 5)
(test/exec :min-list3  (fn -> (min-list [])) null)
(test/exec :min-list4  (fn -> (is? (try (min-list)) ^Exception)) true)
(test/exec :min-list5  (fn -> ([7 1 3 5 2 4] | min-list)) 1)
(test/exec :min-list6  (fn -> (range 1000 | min-list)) 1)
(test/exec :min-list7  (fn -> (min-list [7 1 3 5 2 4] echo)) 1)
(test/exec :min-list8  (fn -> (min-list 5 echo)) 5)
(test/exec :min-list9  (fn -> (min-list [] echo)) null)
(test/exec :min-list10 (fn -> ([7 1 3 5 2 4] | min-list echo)) 1)
(test/exec :min-list11 (fn -> (range 1000 | min-list echo)) 1)
(test/exec :min-list12
    (fn ->
        ; test with object properties
        (let data ([ {:a 3 :b 1} {:a 0 :b 100} {:a 1 :b 2} {:a 2 :b 3}] | project :a :b))
        (data | min-list .a)
    )
    (project {:a 0 :b 100})
)
(test/exec :min-list13
    (fn ->
         (min-list [3 2 6 7 5 4 1 9] neg)
    )
    9
)
(test/exec :min-list14
    (fn ->
        ; function to find the difference between adjacent pairs
        (defn nd 
            | x: i -> 
            | x:xs (i 0) ->
                (cons {:d (abs (- x (car xs))) :x x :y (car xs) :i i}
                    (nd xs (++ i)))
         )
         (let data [1 5 5 4 6 8 8 9])
         ; find the first index of the pair with the smallest difference
         (nd data | min-list (fn d -> (:d d)))
    )
    {
        :d : 0,
        :x : 5,
        :y : 5,
        :i : 1
    }
)

;-------------------------------------------------------
; Test the factorial functions
(test/exec :fact1
    (fn ->
        (fact 20)
    )
    2432902008176640000
)
(test/exec :fact2
    (fn ->
        (fact 10)
    )
    3628800
)
(test/exec :fact3
    (fn -> (fact 100))
    93326215443944152681699238856266700490715968264381621468592963895217599993229915608941463976156518286253697920827223758251185210916864000000000000000000000000
)
(test/exec :rfact1
    (fn ->
        (rfact 20)
    )
    2432902008176640000
)

;-------------------------------------------------------
; Test the 'isPrime' function.
(test/exec :isprime1    (fn -> (isprime 8))     false)
(test/exec :isprime2    (fn -> (isprime 9))     false)
(test/exec :isprime3    (fn -> (isprime 19))    true)
(test/exec :isprime4    (fn -> (isprime 101))   true)
(test/exec :isprime5    (fn -> (isprime 1998))  false)
(test/exec :isprime6    (fn -> (isprime 1999))  true)
(test/exec :isprime7    (fn -> (isprime 9973))  true)
(test/exec :isprime8    (fn -> (isprime 9974))  false)
(test/exec :isprime9    (fn -> (isprime 49999)) true)
(test/exec :isprime10   (fn -> (isprime 50000)) false)
(test/exec :isprime11
    (fn ->
        ; get all the primes between 1-100.
        (range 100 | filter isprime | join)
    )
    (join [3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71 73 79 83 89 97])
)

;-------------------------------------------------------
; Test the 'hex' function
(test/exec :hex1
    (fn ->
        (hex 1234)
    )
    "0x04d2"
)
(test/exec :hex2
    (fn ->
        (hex 0)
    )
    "0x0000"
)
(test/exec :hex3
    (fn ->
        (hex -1)
    )
    "0xffffffff"
)
(test/exec :hex4
    (fn ->
        (hex -noprefix 123)
    )
    "007b"
)
(test/exec :hex5
    (fn ->
        (hex 0xdeadbeef)
    )
    "0xdeadbeef"
)
(test/exec :hex6
    (fn ->
        (hex -noprefix 0xDEADBEEF)
    )
    "deadbeef"
)
(test/exec :hex7
    (fn ->
        ; should get an error on non-intergral types
        (is? (try (hex 3.14)) ^Exception)
    )
    true
)
(test/exec :hex8
    (fn ->
        (hex (^int? 3.14))
    )
    "0x0003"
)

(;BUGBUGBUG String.Format does not throw an exception on non-numeric data
(test/exec :hex9
    (fn ->
        ; should get an error on non-integral types
        (is? (try (hex "3.14")) ^Exception)
    )
    true
)
(test/exec :hex10
    (fn ->
        ; should get an error on non-numeric types
        (is? (try (hex "xyz")) ^Exception)
    )
    true
)
(test/exec :hex11
    (fn ->
        ; should get an error on non-intergral types
        (is? (try (hex [1 2 3])) ^Exception)
    )
    true
)
;)

(test/exec :hex12
    (fn ->
        (hex (^int? "1234"))
    )
    "0x04d2"
)

;-------------------------------------------------------
; Test binary literals and the 'binary' function
(test/exec :binary1
    #(binary 0b1)
    "0b1"
)
(test/exec :binary2
    #(binary 0b_1001_0110)
    "0b10010110"
)

;-------------------------------------------------------
; Tail-recursive "Sieve of Erathosenes" implementation.
(test/exec :tailsieve1
    (fn ->
        (defn sieve2
            | xs -> (recur xs nil)
            | x:xs r ->  (recur (filter xs (% x)) (append r x))
            | nul r -> r
        )

        ; the input sequence must start on a prime and increase by 2
        (range 3 100 2 | sieve2)
   )
   [3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71 73 79 83 89 97]
)
(test/exec :tailsieve2
    (fn ->
        (defn sieve2
            | xs -> (recur xs nil)
            | x:xs r ->  (recur (filter xs (% x)) (append r x))
            | nul r -> r
        )

        ; the input sequence must start on a prime and increase by 2
        (sieve2 (range 3 100 2))
   )
   [3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71 73 79 83 89 97]
)

;
;-------------------------------------------------------
; The minus (-) function
(test/exec :-1 #(- 1 2) -1)
; subtracting strings should be an error
(test/exec :-2
    #(is? (try (- "abc" "a")) ^exception)
    true
)
; more than two arguments should be an error
(test/exec :-3
    #(is? (try (- 5 4 3)) ^Exception)
    true
)
; test result type
(test/exec :-4 #(type-of (- 6 3)) ^int)
(test/exec :-5 #(type-of (- 6 3.0)) ^double)
(test/exec :-6 #(type-of (- 6.0 3)) ^double)
(test/exec :-7 #(type-of (- 6i 3)) ^bigint)
(test/exec :-8 #(is? (- 2) ^Lambda) true)

;-------------------------------------------------------
; Test times (*) function
(test/exec :*1 #(* 2 3) 6)
(test/exec :*2 #(* 2 3 4) 24)
; multiplying a string
(test/exec :*3 #(* "a" 5) "aaaaa")
; multiplying vectors
(test/exec :*4 #(* [1 2] 2) [1 2 1 2])
; multiplying lists
(test/exec :*5 #(* '(1 2) 2) '(1 2 1 2))
; invalid multiply
(test/exec :*6 #(is? (try (* 2 "abc")) ^Exception) true)
;BUGBUGBUG times with string coercion in the second argument raises an exception
(test/exec :*7 #(is? (try (* 2 "4")) ^Exception) true)
(test/exec :*8 #(is? (* 2) ^Lambda) true)

;-------------------------------------------------------
; Test division (/) function
(test/exec :/1 #(/ 10 5) 2)
(test/exec :/2 #(is? (try (/ "a" 5)) ^Exception) true)
(test/exec :/3 #(is? (try (/ 5 4 3)) ^Exception) true)
(test/exec :/4 #(/ 9 4) 2) ; integer division; truncates
(test/exec :/5 #(/ 9.0 4) 2.25) ; double division
(test/exec :/6 #(/ 9 4.0) 2.25) ; double division
(test/exec :/7 #(/ 9 4.0 | type-of) ^double) ; double division
(test/exec :/8 #(/ 123i 5) 24)
(test/exec :/9 #(/ 123i 5 | type-of) ^bigint)
(test/exec :/10 #(is? (/ 2) ^Lambda) true)

;-------------------------------------------------------
; Test modulus (%) function
(test/exec :%1 #(% 9 2)           1)
(test/exec :%2 #(% 9.5678 6)     3.5678)
(test/exec :%3 #(range 10 | filter (% 2)) [1 3 5 7 9])
(test/exec :%4 #(is? (% 2) ^Lambda) true)

;-------------------------------------------------------
; Test the div function
(test/exec :div1 #(div 9 2)                 4)
(test/exec :div2 #(div 8.793 4)             2)
(test/exec :div3 #(div 8.793 4 | is? ^int)  true)
(test/exec :div4 #(is? (div 2) ^Lambda)     true)

;-------------------------------------------------------
; Test the exponentiation (**) function
(test/exec :**1 #(** 3 2)   9)
(test/exec :**2 #(** 4 3)   64)
(test/exec :**3 #(** 2 10)  1024)
(test/exec :**4 #(** 0.5 3) 0.125)

;-------------------------------------------------------
; Equals (==) function ; does value comparisons
(test/exec :==1 #(== 2 2) true)
(test/exec :eq?1 #(eq? 2 2) true)
(test/exec :!=1 #(!= 2 2) false)
(test/exec :==2 #(== 2 3) false)
(test/exec :eq?2 #(eq? 2 3) false)
(test/exec :!=2 #(!= 2 3) true)
(test/exec :==3 #(== "abc" "abc") true)
(test/exec :!=3 #(!= "abc" "abc") false)
(test/exec :==4 #(== "abc" "abcd") false)
(test/exec :!=4 #(!= "abc" "abcd") true)
(test/exec :==5 #(== 1 "1") false)
(test/exec :!=5 #(!= 1 "1") true)
(test/exec :==6 #(== 1 (^int? "1")) true)
(test/exec :!=6 #(!= 1 (^int? "1")) false)
(test/exec :==7 #(== [1 2 3] [1 2 3]) true)
(test/exec :!=7 #(!= [1 2 3] [1 2 3]) false)
(test/exec :==8 #(== [1 3 3] [1 2 3]) false)
(test/exec :!=8 #(!= [1 3 3] [1 2 3]) true)
(test/exec :==9 #(== [1 2 3] [1 "2" 3]) false)
(test/exec :!=9 #(!= [1 2 3] [1 "2" 3]) true)
(test/exec :==10 #(== {:a 1 :b 2} {:a 1 :b 2}) true)
(test/exec :!=10 #(!= {:a 1 :b 2} {:a 1 :b 2}) false)
(test/exec :==11 #(== {:a 1 :b 2} {:a 2 :b 2}) false)
(test/exec :!=11 #(!= {:a 1 :b 2} {:a 2 :b 2}) true)
(test/exec :==12 #(== {:a 1 :b [1 2 3]} {:a 1 :b [1 2 3]}) true)
(test/exec :!=12 #(!= {:a 1 :b [1 2 3]} {:a 1 :b [1 2 3]}) false)
(test/exec :==13 #(== {:a 1 :b [1 2 3]} {:a 1 :b [1 3 3]}) false)
(test/exec :!=13 #(!= {:a 1 :b [1 2 3]} {:a 1 :b [1 3 3]}) true)
; test == on complex polymorphic structures
(test/exec :==14
    #(==
        {:a 1 :b [1 2 3] :c {:d 10 :e 30}}
        {:a 1 :b [1 3 3] :c {:d 10 :e 20}}
    )
    false
)
(test/exec :!=14
    #(!=
        {:a 1 :b [1 2 3] :c {:d 10 :e 30}}
        {:a 1 :b [1 3 3] :c {:d 10 :e 20}}
    )
    true
)
(test/exec :==15
    #(==
        {:a 1 :b [1 2 3] :c {:d 10 :e 30}}
        {:a 1 :b [1 3 3] :c {:d 10 :e 30}}
    )
    false
)
(test/exec :!=15
    #(!=
        {:a 1 :b [1 2 3] :c {:d 10 :e 30}}
        {:a 1 :b [1 3 3] :c {:d 10 :e 30}}
    )
    true
)
(test/exec :==16
    #(==
        {:a 1 :b [1 2 3] :c {:d 10 :e [:a :b :c]}}
        {:a 1 :b [1 2 3] :c {:d 10 :e [:a :b :c]}}
    )
    true
)
(test/exec :!=16
    #(!=
        {:a 1 :b [1 2 3] :c {:d 10 :e [:a :b :c]}}
        {:a 1 :b [1 2 3] :c {:d 10 :e [:a :b :c]}}
    )
    false
)
(test/exec :==17
    #(==
        {:a 1 :b [1 2 3] :c {:d 10 :e [:a :b :c]}}
        {:a 1 :b [1 3 3] :c {:d 10 :e [:a 10 :c]}}
    )
    false
)
(test/exec :!=17
    #(!=
        {:a 1 :b [1 2 3] :c {:d 10 :e [:a :b :c]}}
        {:a 1 :b [1 3 3] :c {:d 10 :e [:a 10 :c]}}
    )
    true
)
(test/exec :==18
    (fn ->
        ([1 2 1 2 1 3 2] | filter (== 2))
    )
    [2 2 2]
)
(test/exec :!=18
    (fn ->
        ([1 2 1 2 1 3 2] | filter (!= 2))
    )
    [1 1 1 3]
)

;-------------------------------------------------------
; Test the reference equals/nt equals function
(test/exec :===1 (fn -> (=== 1 1)) true)
(test/exec :!==1 (fn -> (!== 1 1)) false)
(test/exec :===2 (fn -> (=== "abc" "abc")) false)
(test/exec :!==2 (fn -> (!== "abc" "abc")) true)
(test/exec :===3 (fn -> (let x "abc") (=== x x)) true)
(test/exec :!==3 (fn -> (let x "abc") (!== x x)) false)
(test/exec :===4 (fn -> (=== 'abc 'abc)) true)
(test/exec :!==4 (fn -> (!== 'abc 'abc)) false)
(test/exec :===5 (fn -> (=== :abc :abc)) true)
(test/exec :!==5 (fn -> (!== :abc :abc)) false)
(test/exec :===6 (fn -> (=== 1 1 :abc :abc 'foo 'foo)) true)
(test/exec :!==6 (fn -> (!== 1 1 :abc :abc 'foo 'foo)) false)
(test/exec :===7 (fn -> (=== 1 1 :abc :abc "foo" "foo")) false)
(test/exec :!==7 (fn -> (!== 1 1 :abc :abc "foo" "foo")) true)

;-------------------------------------------------------
; Test the comparison function
(test/exec :>1 (fn -> (> 2 3)) false)
(test/exec :>2 (fn -> (> 2 3 4)) false)
(test/exec :>3 (fn -> (> 3 2)) true)
(test/exec :>4 (fn -> (> 4 3 2)) true)
(test/exec :>5 (fn -> (> :a :b)) false)
(test/exec :>6 (fn -> (> :c :b)) true)
(test/exec :>7 (fn -> (> :c :b :a)) true)
(test/exec :>=1 (fn -> (>= 2 3)) false)
(test/exec :>=2 (fn -> (>= 2 3 4)) false)
(test/exec :>=3 (fn -> (>= 3 2)) true)
(test/exec :>=4 (fn -> (>= 4 3 2)) true)
(test/exec :>=5 (fn -> (>= 3 3)) true)
(test/exec :>=6 (fn -> (>= 4 3 3)) true)
(test/exec :>=7 (fn -> (>= :a :b)) false)
(test/exec :>=8 (fn -> (>= 2 3 4)) false)
(test/exec :>=9 (fn -> (>= :b :a)) true)
(test/exec :>=10 (fn -> (>= :c :b :a)) true)
(test/exec :>=11 (fn -> (>= :a :a)) true)
(test/exec :>=12 (fn -> (>= :b :a :a)) true)

(test/exec :<1 (fn -> (< 2 3)) true)
(test/exec :<2 (fn -> (< 4 3 2)) false)
(test/exec :<3 (fn -> (< 4 3)) false)
(test/exec :<4 (fn -> (< 2 3 4)) true)
(test/exec :<5 (fn -> (< :a :b)) true)
(test/exec :<6 (fn -> (< :c :b :a)) false)
(test/exec :<7 (fn -> (< :c :b)) false)
(test/exec :<8 (fn -> (< :a :b :c)) true)
(test/exec :<=1 (fn -> (<= 2 3)) true)
(test/exec :<=2 (fn -> (<= 2 3 4)) true)
(test/exec :<=3 (fn -> (<= 3 2)) false)
(test/exec :<=4 (fn -> (<= 4 3 2)) false)
(test/exec :<=5 (fn -> (<= 3 3)) true)
(test/exec :<=6 (fn -> (<= 2 3 3)) true)
(test/exec :<=7 (fn -> (<= :a :b)) true)
(test/exec :<=8 (fn -> (<= :a :b :c)) true)
(test/exec :<=9 (fn -> (<= :b :a)) false)
(test/exec :<=10 (fn -> (<= :c :b :a)) false)
(test/exec :<=11 (fn -> (<= :b :b)) true)
(test/exec :<=12 (fn -> (<= :a :b :b)) true)

(test/exec :ge100
    (fn ->
        ; use comparisons in a slightly larger example
        (defn size
            | #(<= 1 %0 4)  -> :big
            | #(<= 5 %0 8)  -> :medium
            | #(<= 8 %0 10) -> :small
            |               -> :other
        )
        (range 1 10 | map size)
    )
    [:big :big :big :big :medium :medium :medium :medium :small :small]
)

; use comparison function with collections directly
(test/exec :comparison101 (fn -> (< @(range 1000))) true)
(test/exec :comparison102 (fn -> (<= @(range 1000))) true)
(test/exec :comparison103 (fn -> (> @(range 1000 1))) true)
(test/exec :comparison104 (fn -> (>= @(range 1000 1))) true)

(test/exec :comparison105 (fn -> (apply < (range 1000))) true)
(test/exec :comparison106 (fn -> (apply <= (range 1000))) true)
(test/exec :comparison107 (fn -> (apply > (range 1000 1))) true)
(test/exec :comparison108 (fn -> (apply >= (range 1000 1))) true)

; random can produce duplicates so use the <op>= variants.
(test/exec :comparison209 (fn -> (<= @(random 100 | sort))) true)
(test/exec :comparison210 (fn -> (<= @(random 100 | sort -descending))) false)
(test/exec :comparison211 (fn -> (>= @(random 100 | sort -descending))) true)
(test/exec :comparison212 (fn -> (apply >= (random 100 | sort -descending))) true)

; fix the random dups problem by using distinct.
(test/exec :comparison213 (fn -> (< @(random 100 | sort | distinct))) true)
(test/exec :comparison214 (fn -> (> @(random 100 | sort -descending | distinct))) true)
(test/exec :comparison215 (fn -> (apply < (random 100 | sort | distinct))) true)
(test/exec :comparison216 (fn -> (apply > (random 100 | sort -descending | distinct))) true)

;-------------------------------------------------------
; Test the list/monotonic function (which use < and >
(test/exec :monotonic1
    (fn ->
        (list/monotonic [1 2 3 4 5])
    )
    true
)
(test/exec :monotonic2
    (fn ->
        (list/monotonic [1 2 3 3 2 4 5])
    )
    false
)
(test/exec :monotonic3
    (fn ->
        (list/monotonic -descending [50 20 13 7 5 1])
    )
    true
)
(test/exec :monotonic4
    (fn ->
        (list/monotonic -descending [50 20 13 14 7 5 1])
    )
    false
)

;-------------------------------------------------------
; Test the let function
(test/exec :let1   (fn -> (let x 1) x)       1)
(test/exec :setq1  (fn -> (setq x 1) x)       1)
(test/exec :let2   (fn -> (let x "abc") x)   "abc")
(test/exec :setq2  (fn -> (setq x "abc") x)   "abc")
(test/exec :let3
    (fn ->
        (let ^int a 0)
        (is? (try (let a "abc")) ^Exception)
    )
    true
)
(test/exec :let4
    (fn ->
        (let ^string? a "")
        (let a 3.13)
        a
    )
    "3.13"
)
(test/exec :let4a
    (fn ->
        (let ^string a "")
        (try (let a 3.13) | is? ^Exception)
    )
    true
)
(test/exec :let4b
    (fn ->
        (let ^string a "")
        (let a (^string? 3.13))
        a
    )
    "3.13"
)
(test/exec :setq4
    (fn ->
        (setq a "")
        (setq a 3.13)
        a
    )
    "3.13"
)
; test destructuring
(test/exec :let5
    (fn ->
        (let x:y:z [1 2 3 4 5])
        (and (== x 1) (== y 2) (== z [3 4 5]))
    )
    true
)
; test using with to establish a new binding context
(test/exec :with1
    (fn ->
        (with
            [ a 1 b 2 c 3]
            
            (+ a b c)
        )
    )
    6
)
(test/exec :with2
    (fn ->
        (let c 3)
        (with [ a 1 b 2 ]
            (+ a b c)
        )
    )
    6
)
(test/exec :with3
    (fn ->
        ; test clojure style let
        (let a 10)
        (let b 20)
        (let c 30)
        (with [ a 1 b 2 c 3 ]
            (+ a b c)
        )
    )
    6
)
(test/exec :with4
    (fn ->
        ; test multiple assignent with let
        (with [a:b [1 2 3]  c:d [4 5 6]]
            [d c b a]
        )
    )
    ['(5 6) 4 '(2 3) 1]
)
(test/exec :with5
    (fn ->
        (defn lzip [xs ys (pairs [])]
            (if (and xs ys)
                (with [x:xs xs y:ys ys]
                    (.add pairs [x y])
                    (recur xs ys pairs)
                )
                (aslist pairs)
            )
        )
        (lzip [1 2 3] [4 5 6])
    )
    [[1 4] [2 5] [3 6]]
)
(test/exec :with6
    (fn ->
        ; nested lets + verify values are completed before binding
        (with [a 1 b 2 c 3]
            (with [a (+ a 1) b a c b]
                [a b c]
            )
       )
   )
   [2 1 2]
)
; test pattern matching in let/local
(test/exec :let12
    #(let {a _  b _ c _} {"a" 1 "b" 2 "c" 3})
    true
)
(test/exec :let12a
    #(let {a _  b _ c _} {"a" 1 "b" 2})
    false
)
(test/exec :let12b
    #(let {a _  b ^int c _} {"a" 1 "b" 2 "c" 3})
    true
)
(test/exec :let12c
    #(let {a _  b ^int c _} {"a" 1 "b" "abc" "c" 3})
    false
)
(test/exec :let12d
    #(let {a _  b ^int? c _} {"a" 1 "b" "123" "c" 3})
    true
)
(test/exec :let13
    (fn ->
        (let {a _  b _ c _} {"a" 1 "b" 2 "c" 3})
        [a b c]
    )
    [1 2 3]
)
(test/exec :let13a
    (fn ->
        (let {c _  a _ b _} {"a" 1 "b" 2 "c" 3}) ; switch pattern order; expect same results
        [a b c]
    )
    [1 2 3]
)
(test/exec :let14
    (fn ->
        ; test with object instead of dictionary
        (let {a _  b _ c _} (project {"a" 1 "b" 2 "c" 3}))
        [a b c]
    )
    [1 2 3]
)
(test/exec :let14a
    (fn ->
        (let {c _  a _ b _} (project {"a" 1 "b" 2 "c" 3}))
        [a b c]
    )
    [1 2 3]
)
(test/exec :with8
    (fn ->
        ; test clojure style 'let' with strict type constraints and correct arguments.
        (with [^int a 1 ^int b 2 ^int c 3]
            (+ a b c)
        )
    )
    6
)
(test/exec :with9
    (fn ->
        ; test clojure style 'let' with strict type constraints and incorrect arguments.
        (try
            (with [^int a 1 ^int b "2" ^int c 3]
                (+ a b c)
            )
        | is? ^exception
        )
    )
    true
)
(test/exec :with10
    (fn ->
        ; test clojure style 'let' with varying strict type constraints
        (with [^int a 1 ^double b 2.0 ^string c "3"]
            (and
                (is? a ^int)
                (is? b ^double)
                (is? c ^string)))
    )
    true
)
(test/exec :with11
    (fn ->
        ; test clojure style 'let' with varying coersive type constraints
        (with [^int? a "1" ^double? b 2 ^string? c 3]
            (and
                (is? a ^int)
                (is? b ^double)
                (is? c ^string)))
    )
    true
)
(test/exec :let17
    (fn ->
        (let ^regex? pat "a")
        (["a" "A" "a"] | filter pat)
    )
    ["a" "A" "a"]
)
(test/exec :let18
    (fn ->
        (let ^int? x null)
        x
    )
    0
)
(test/exec :let19
    (fn ->
        (let ^int? x null)
    )
    0
)
(test/exec :let20
    (fn ->
        (let ^string? x null)
        x
    )
    ""
)
(test/exec :let22
    (fn ->
        (let ^vector? x null)
        x
    )
    null
)
(test/exec :let23
    (fn ->
        (let ^vector? x null)
    )
    null
)
(test/exec :let24
    (fn ->
        ; test implicit coercion of symbols to strings even in strict mode
        (let ^string? foo null)
        (let foo 'abc)
        [(type-of foo) foo]
    )
    [^string "abc"]
)
(test/exec :let25
    (fn ->
        ; test implicit coercion of keywords to strings even in strict mode
        (let ^string? foo null)
        (let foo :abcd)
        [(type-of foo) foo]
    )
    [^string "abcd"]
)
(test/exec :let26
    (fn ->
        ; test implicit coercion of member literals to strings even in strict mode
        (let ^string? foo null)
        (let foo '.abcde)
        [(type-of foo) foo]
    )
    [^string ".abcde"]
)
;-------------------------------------------------------
; test "reverse let"
; BUGBUGBUG - need more tests, >let doesn't implement pattern matching
(test/exec :>let1
    (fn ->
        (15 | + 19 | >let __zork)
        __zork
    )
    (+ 15 19)
)
(test/exec :>let2
    (fn ->
        (range 10 | where (% 3) | >let __foo)
        __foo
    )
    [1 2 4 5 7 8 10]
)
(test/exec :>let3
    (fn ->
        ([1 2 3] | map (* 2) | >let a:b:c:)
        [a b c]
    )
    [2 4 6]
)

;-------------------------------------------------------
; test the 'def' function.
;
(test/exec :def1
    (fn ->
        (undef 'zorkzorkzork)
        ((fn ->
            ; create variable in lexical parent
            (def zorkzorkzork 123)
        ))
        zorkzorkzork
    )
    123
)
(test/exec :def2
    (fn ->
        (undef 'zorkzorkzork)
        ((fn ->
            ; create variable in lexical parent
            (def zorkzorkzork 123)
        ))
        ; test in lexical child
        ((fn -> zorkzorkzork))
    )
    123
)
(test/exec :def3
    (fn ->
        (undef 'zorkzorkzork)
        ((fn ->
            ; set variable in lexical parent
            (def zorkzorkzork 123)
            ; and also in the local scope
            (let zorkzorkzork 10)
        ))
        ; verify that the parent scope was unmodified
        zorkzorkzork
    )
    123
)
(test/exec :def4
    (fn ->
        (undef 'zorkzorkzork)
        ((fn ->
            ; set variable in lexical parent
            (def zorkzorkzork 123)
            ; and also in the local scope
            (let zorkzorkzork 10)
        ))
        ; test in child scope
        ((fn -> zorkzorkzork))
    )
    123
)
(test/exec :def5
    (fn ->
        (let zorkzorkzork 55)
        ; test with let
        (with [zorkzorkzork 10]
            ; sets variable in local scope since it already exists
            (def zorkzorkzork 123)
        )
        zorkzorkzork
    )
    55
)
(test/exec :def6
    (fn ->
        (let zorkzorkzork 55)
        ; test with let
        (with []
            ; sets variable in local scope since it already exists
            (def zorkzorkzork 123)
        )
        ; test in child scope
        (with []
            zorkzorkzork
        )
    )
    123
)
(test/exec :def7
    (fn ->
        (undef 'zorkzorkzork)
        (with []
            ; set variable in lexical parent
            (def zorkzorkzork 123)
        )
        ; test in child scope
        (with []
            zorkzorkzork
        )
    )
    123
)

;-------------------------------------------------------
; test let?
;
(test/exec :let?1
    (fn ->
        (let? foo 123)
    )
    true
)
(test/exec :let?2
    (fn ->
        (and (let? a:b:c: [1 2 3]) (== a 1 b 2 c 3))
    )
    true
)
(test/exec :let?3
    (fn ->
        (let? a:b:c: [1 2 3 4])
    )
    false
)

;-------------------------------------------------------
; test vlet
;
(test/exec :vlet1
    (fn ->
        (vlet x:xs [1 2 3 4])
    )
    null
)
(test/exec :vlet2
    (fn ->
        (vlet x:xs [1 2 3 4])
        [x xs]
    )
    [1 [2 3 4]]
)

;-------------------------------------------------------
; test constants
;
(test/exec :const1
    (fn ->
        ; test constant variable
        (and
            (is? (try (def pi 3)) ^exception)
            (== pi .math/PI)
        )
    )
    true
)
(test/exec :const2
    (fn ->
        ; test constant function binding
        (and
            (is? (try (def if "foo")) ^exception)
            (!= if "foo")
        )
    )
    true
)
(test/exec :const3
    (fn ->
        ; create a constant then try to set it.
        (const foo 13)
        (if (is? (try (let foo 22)) ^Exception)
            foo
            "*error*"
        )
     )
     13
)
(test/exec :const4
    (fn ->
        ; create a constant then try to set it using def instead of let
        (const foo 13)
        (if (is? (try (let foo 22)) ^Exception)
            foo
            "*error"
        )
     )
     13
)
(test/exec :const5
    (fn ->
        ; create a constant then try to override it with the const function
        (const foo 13)
        (if (is? (try (const foo 22)) ^Exception)
            foo
            "*error"
        )
     )
     13
)
(test/exec :const6
    (fn ->
        ; create a constant then try to override it in a child scope
        (const foo 13)
        (with [foo 14]
            (== foo 14)
        )
    )
    true
)

;-------------------------------------------------------
; The 'vars' function.
(test/exec :vars1
    (Fn ->
        (with [a-strange-variable 1]
            (vars | contains? "a-strange-variable")
        )
    )
    true
)
(test/exec :vars2
    (Fn ->
        (undef a-strange-variable)
        (vars | contains? "a-strange-variable")
    )
    false
)

;-------------------------------------------------------
; test getvar function
(test/exec :getvar1
    (fn ->
        (getvar 'getvar | .value | == getvar)
    )
    true
)
(test/exec :getvar2
    (fn ->
        (getvar 'getvar | .name | == 'getvar)
    )
    true
)
(test/exec :getvar3
    (fn ->
        (getvar "no such var")
    )
    null
)

;-------------------------------------------------------
; test undef function
(test/exec :undef1
    (fn ->
        (let foo 1)
        (undef foo)
    )
    true
)
(test/exec :undef2
    (fn ->
        (let foo 1)
        (undef foo)
        (bound? 'foo)
    )
    false
)
(test/exec :undef3
    (fn ->
        (global 'foo 1)
        (undef foo)
    )
    true
)
(test/exec :undef4
    (fn ->
        (global 'foo 1)
        (undef foo)
        (bound? 'foo)
    )
    false
)
(test/exec :undef5
    (fn ->
        (undef zork)
        (try zork | is? ^exception)
    )
    true
)
(test/exec :undef6
    (fn ->
        (undef zork)
        (try (* zork 2) | is? ^exception)
    )
    true
)
(test/exec :undef7
    (fn ->
        (undef zork)
        (defn doit [x] (+ zork x))
        (try (doit 2) | is? ^exception)
    )
    true
)

;-------------------------------------------------------
; predicates

; zero?
(test/exec :zero?1  #(zero? 0)          true)
(test/exec :zero?2  #(zero? 0.0)        true)
(test/exec :zero?3  #(zero? 1)          false)
(test/exec :zero?4  #(zero? 1.0)        false)
(test/exec :zero?5  #(zero? 0.00000001) false)
(test/exec :zero?6  #(zero? "abc")      false)
(test/exec :zero?7  #(zero? "")         false)
(test/exec :zero?8  #(zero? [1 2 3])    false)
(test/exec :zero?9  #(zero? [])         false)
(test/exec :zero?10 #(zero? {:a 1 :b 2}) false)
(test/exec :zero?11 #(zero? {})         false)
(test/exec :zero?12 #(zero? nil)        false)

; pair?
(test/exec :pair?1  #(pair? '(1 2 3))   true)
(test/exec :pair?2  #(pair? '())       false)
(test/exec :pair?3  #(pair? [1 2 3])    false)
(test/exec :pair?4  #(pair? {:a 1 :b 2}) false)

; vector?
(test/exec :vector?1  #(vector? [1 2 3]) true)
(test/exec :vector?2  #(vector? [])     true)
(test/exec :vector?3  #(vector? '(1 2 3)) false)
(test/exec :vector?4  #(vector? {:a 1 :b 2}) false)
(test/exec :vector?5  #(vector? 123)    false)
(test/exec :vector?6  #(vector? "abc")  false)
(test/exec :vector?7  #(vector? (new ^system.collections.generic.list[int])) false)

; list?
(test/exec :ilist?1  #(ilist? [1 2 3]) true)
(test/exec :ilist?2  #(ilist? [])     true)
(test/exec :ilist?3  #(ilist? '(1 2 3)) false)
(test/exec :ilist?4  #(ilist? {:a 1 :b 2}) false)
(test/exec :ilist?5  #(ilist? 123)    false)
(test/exec :ilist?6  #(ilist? "abc")  false)
(test/exec :ilist?7  #(ilist? (new ^system.collections.generic.list[int])) true)

; collection?
(test/exec :collection?1  #(collection? [1 2 3]) true)
(test/exec :collection?2  #(collection? [])     true)
(test/exec :collection?3  #(collection? '(1 2 3)) true)
(test/exec :collection?4  #(collection? {:a 1 :b 2}) true)
(test/exec :collection?5  #(collection? 123)    false)
(test/exec :collection?6  #(collection? "abc")  false)
(test/exec :collection?7  #(collection? (new ^system.collections.generic.list[int])) true)
(test/exec :collection?8  #(collection? (asarray '(1 2 3))) true)

; atom?
(test/exec :atom?1  #(atom? 1)          true)
(test/exec :atom?2  #(atom? "abc")      true)
(test/exec :atom?3  #(atom? 'abc)       true)
(test/exec :atom?4  #(atom? '(1 2 3))   false)
(test/exec :atom?6  #(atom? [1 2 3])    false)
(test/exec :atom?7  #(atom? {:a 1 :b 2}) false)

; dict?
(test/exec :dict?1  #(dict? {})   true)
(test/exec :dict?2  #(dict? 123)  false)
(test/exec :dict?3  #(dict? null) false)

; even?
(test/exec :even?1  #(even? 4)   true)
(test/exec :even?2  #(even? 3)   false)
(test/exec :even?3  #(range 10 | filter even?) [2 4 6 8 10])

; odd?
(test/exec :odd?1  #(odd? 4)   false)
(test/exec :odd?2  #(odd? 3)   true)
(test/exec :odd?3  #(range 10 | filter odd?) [1 3 5 7 9])

; function?
(test/exec :function?1 #(function? +)           true)
(test/exec :function?2 #(function? (fn -> 13))  true)
(test/exec :function?3 #(function? (get-command "get-command")) true)
(test/exec :function?4 #(function? (list 1 2 3)) false)
(test/exec :function?5 #(function? [1 2 3])     true)
; Slow because it eventually calls PowerShell Get-Command.
(test/exec :function?6 #(function? "abcd")      false)
(test/exec :function?7 #(function? 3.14)        false)

; ilist?
;----------------------------------------------------
; Test the 'is?' function
(test/exec :is?1   #(is? 1 ^int)           true)
(test/exec :is?1a  #(is? "1" ^int)         false)
(test/exec :is?1b  #(is? "1" ^int?)        true)
(test/exec :is?2   #(is? "abc" ^string)    true)
(test/exec :is?3   #(is? 1.23 ^double)     true)
(test/exec :is?4   #(is? '(1 2 3) ^List)   true)
(test/exec :is?5   #(is? '() ^List)        true)
(test/exec :is?5a  #(is? null ^List)       true)
(test/exec :is?6   #(is? 1.23 ^int)        false)
(test/exec :is?7   #(is? 123 ^double)      false)
(test/exec :is?8   #(is? {:a 1 :b 2} ^IDictionary) true)
(test/exec :is?10  #(is? [1 2 3] ^Vector)  true)
(test/exec :is?11  #(is? [1 2 3] ^IList)   true)
(test/exec :is?11a #(is? [1 2 3] ^ISeq)    true)
(test/exec :is?11b #(is? [1 2 3] ^IEnumerable) true)
(test/exec :is?12  #(is? [1 2 3] ^Array)   false)
(test/exec :is?13  #(is? (asarray [1 2 3]) ^Array) true)
(test/exec :is?14  #(is? (+ 2 3.5) ^double) true)
; tests is? as a curried function
(test/exec :is?15  #(range 5 | filter (is? ^int)) [1 2 3 4 5])
(test/exec :is?15a #([1 "2" 3 "4" 5] | filter (is? ^int)) [1 3 5])
(test/exec :is?15b #([1 "2" 3 "4" 5] | filter (is? ^int?)) [1 "2" 3 "4" 5])
(test/exec :is?16
    (fn ->
        ; test with custom type
        (deftype ^a_type)
        (let v (new ^a_type))
        (is? v ^a_type)
    )
    true
)
(test/exec :is?17
    (fn ->
        ; test with enum type
        (defenum ^an_enum a b c)
        (let v (new ^an_enum))
        (is? v ^an_enum)
    )
    true
)
(test/exec :is?18 #(is? null null) true)

;----------------------------------------------------
; Test the 'notis?' function
(test/exec :isnot?1   #(isnot? 1 ^int)           false)
(test/exec :isnot?2   #(isnot? "abc" ^string)    false)
(test/exec :isnot?3   #(isnot? 1.23 ^double)     false)
(test/exec :isnot?4   #(isnot? '(1 2 3) ^List)   false)
(test/exec :isnot?5   #(isnot? '() ^List)        false)
(test/exec :isnot?5a  #(isnot? null ^List)       false)
(test/exec :isnot?6   #(isnot? 1.23 ^int)        true)
(test/exec :isnot?7   #(isnot? 123 ^double)      true)
(test/exec :isnot?8   #(isnot? {:a 1 :b 2} ^IDictionary) false)
(test/exec :isnot?10  #(isnot? [1 2 3] ^Vector)  false)
(test/exec :isnot?11  #(isnot? [1 2 3] ^IList)   false)
(test/exec :isnot?12  #(isnot? [1 2 3] ^Array)   true)
(test/exec :isnot?13  #(isnot? (asarray [1 2 3]) ^Array) false)
(test/exec :isnot?14  #(isnot? (+ 2 3.5) ^double) false)

;----------------------------------------------------
; Test the 'as' function
(test/exec :as1 #(type-of (as 123 ^int))        ^int)
(test/exec :as2 #(type-of (as 123 ^double?))     ^double)
(test/exec :as3 #(type-of (as 123.456 ^int?))     ^int)
(test/exec :as4 #(as 123.456 ^int?)              123)
(test/exec :as5 #(type-of (as "123" ^int?))      ^int)
(test/exec :as6 #(type-of (as "123" ^double?))   ^double)
(test/exec :as7 #(as [1 2 3] ^string?)           "1 2 3")
(test/exec :as8 #(as "abc" ^int?)                null)
(test/exec :as9 #(as "abc" ^vector?)             [(char "a") (char "b") (char "c")])
; tests curried function
(test/exec :as10 #(range 5 | map (as ^string?) | !! 0) "1")

;----------------------------------------------------
; Test the keyword? function
(test/exec :keyword?1
    (fn ->
        (defspecial testkeyword [x] (keyword? x))
        (testkeyword :foo)
    )
    true
)

;----------------------------------------------------
; Test the defspecial function
(test/exec :defspecial1
    (fn ->
        (defspecial special [x y]
            (and
                (== x '(+ 1 2))
                (== y '(vars))))

        (special (+ 1 2) (vars))
    )
    true
)
(test/exec :defspecial2
    (fn ->
        ; define a custom 'foreach' loop in Braid using 'upvar' and 'upDo'
        (defspecial myforeach [(^symbol varToSet) lst &args]
            (upvar varToSet 'proxy)
            (foreach o (upDo lst)
                (let proxy o)
                (foreach a args
                    (upDo a)
                )
            )
        )

        (let result 0)
        (myforeach zzz [1 2 3 4] (let result (+ zzz result)))
        result
    )
    10
)
(test/exec :defspecial3
    (fn ->
        ; call-by-name function to count a list and bind the count in the caller's scope.
        (defspecial count-it [name lst]
            (upvar name "lcl")
            (let lcl 0)
            (foreach o (upDo lst)
                (incr lcl)
            )
        )

        (count-it the-count (range 100))
        the-count
    )
    100
)

;----------------------------------------------------
; Test the defmacro function
; BUGBUGBUG - need more tests here
(test/exec :defmacro1
    (fn ->
        ; check that macros are visible as variables
        (.ftype fn | tostring | == "Macro")
    )
    true
)

;----------------------------------------------------
; Test the upvar function
(test/exec :upvar1
    (fn ->
        (let xyz 0)
        (with []
            (upvar 'xyz 'lcl)
            (let lcl 123)
        )
        xyz
    )
    123
)
(test/exec :upvar1a
    (fn ->
        ; upvar should create the variable in this context
        (with []
            (upvar 'xyz 'lcl)
            (let lcl 123)
        )
        xyz
    )
    123
)
(test/exec :upvar2
    (fn ->
        (let xyz 0)
        (with []
            (upvar "xyz" "lcl")
            (let lcl 123)
        )
        xyz
    )
    123
)
(test/exec :upvar3
    (fn ->
        (let xyz 0)
        (let name "xyz")
        (with []
            (upvar name "lcl")
            (let lcl 123)
        )
        xyz
    )
    123
)
(test/exec :upvar4
    (fn ->
        (defn f []
            (fn ->
                (upvar 'xyz 'lcl)
                (let lcl 123)
            )
        )

        (with [xyz 0 f (f)]
            (f)
            xyz
        )
    )
    123
)

;----------------------------------------------------
; Test the upDo function
(test/exec :upDo1
    (fn ->
        (let x 1)
        (with []
            (let x 2)
            ; get 'x' in the parent scope and the current scope
            [ (upDo 'x) x ]
        )
    )
    [1 2]
)
(test/exec :upDo2
    (fn ->
        (let x 1)
        (with []
            ; change the value of 'x' in the parent scope.
            (upDo '(let x 123))
        )
        x
    )
    123
)
(test/exec :upDo3
    (fn ->
        ;
        ; Define a 'forall' variant that uses two variables - item and count
        ;
        (defspecial forall-with-count
            "A forall loop with item and count variables"
            [(^symbol itemVar) (^symbol countVar) lst &body]

            ; bind the loop variables in the caller's context
            (upvar itemVar  'iv)
            (upvar countVar 'cv)

            ; wrap the body in a do expression
            (let body (cons 'do body))

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
    )
    [[:a 1] [:b 2] [:c 3]]
)

;----------------------------------------------------
; Test the 'getdynamic' function
(test/exec :get-dynamic1
    (fn ->
        (undef x)
        (let x 123)
        (with [x 456]
            ; returns the variable object
            [(get-dynamic x | .value) x]
        )
    )
    [123 456]
)
(test/exec :get-dynamic2
    (fn ->
        (undef x)
        (with [x 456]
            ; returns the variable object
            [(get-dynamic x | .?value) x]
        )
    )
    [null 456]
)


;----------------------------------------------------
; Test the 'lambda?' function
(test/exec :lambda?1 #(lambda? (lambda [] 123))     true)
(test/exec :lambda?1a #(lambda? (fn | -> 123))     true)
(test/exec :lambda?2 #(lambda? (lambda | -> 123))   true)
(test/exec :lambda?3 #(lambda? (list [] 123))       false)
(test/exec :lambda?4 #(lambda? [lambda [] 123])     false)
(test/exec :lambda?5 #(lambda? 123)                 false)
(test/exec :lambda?6 #(lambda? "abc")               false)
(test/exec :lambda?7 #(lambda? null)                false)
(test/exec :lambda?8
    #(do
       (defn zork [] "zork")
       (lambda? zork)
    )
    true
)
(test/exec :lambda?9
    #(do
       (defn zork | -> "zork")
       (lambda? zork)
    )
    true
)
(test/exec :lambda?10
    (fn ->
        (lambda? (fn x y -> (+ x y)))
    )
    true
)
(test/exec :lambda?11
    (fn ->
        (lambda? #(+ 2 2))
    )
    true
)
(test/exec :lambda?12
    (fn ->
        (lambda? (+ 2 2))
    )
    false
)


;----------------------------------------------------
; leap-year?
(test/exec :leap-year?1
    (fn ->
        (range 2000 2020 | filter leap-year?)
    )
    [ 2000 2004 2008 2012 2016 2020 ]
)

;----------------------------------------------------
; list?
(test/exec :list?1  #(list? '(1 2 3))    true)
(test/exec :list?2  #(list? [1 2 3])     false)
(test/exec :list?3  #(list? {:a 1 :b 2}) false)
(test/exec :list?4  #(list? 1)           false)
(test/exec :list?5  #(list? "abc")       false)
(test/exec :list?6  (fn -> (list? '()))  false)
(test/exec :list?7  (fn -> (list? null))  false)

;----------------------------------------------------
; Test the 'nil?' function.
(test/exec :nil?1  #(nil? nil)     true)
(test/exec :nil?2  #(nil? '())     true)
(test/exec :nil?3  #(nil? 123)     false)
(test/exec :nil?4  #(nil? "abc")   false)
(test/exec :nil?5  #(nil? "")      false)
(test/exec :nil?6  #(nil? [])      false)
(test/exec :nil?7  #(nil? {})      false)

;----------------------------------------------------
; Test the 'null?' function.
(test/exec :null?1  #(null? null)   true)
(test/exec :null?2  #(null? '())    true)
(test/exec :null?3  #(null? 123)    false)
(test/exec :null?4  #(null? "abc")  false)
(test/exec :null?5  #(null? "")     false)
(test/exec :null?6  #(null? [])     false)
(test/exec :null?7  #(null? {})     false)
(test/exec :null?8  #([1 null 2 null 3 null] | filter null?) [null null null])

;-------------------------------------------------------
; Tests the 'notnil?' function
(test/exec :notnil?1 #(notnil? 1)   true)
(test/exec :notnil?2 #(notnil? nil) false)

;-------------------------------------------------------
; Tests the 'notnull?' function
(test/exec :notnull?1  #(notnull? null)   false) 
(test/exec :notnull?1a #(notnull? nil)    false) 
(test/exec :notnull?2  #(notnull? 1)      true)
(test/exec :notnull?3  #(notnull? "abc")  true)
(test/exec :notnull?4  #(notnull? "")     true)
(test/exec :notnull?5  #(notnull? [])     true)
(test/exec :notnull?6  #(notnull? {})     true)
(test/exec :notnull?7  #([1 null 2 null 3 null] | filter notnull?) [1 2 3])

;----------------------------------------------------
; Test the 'some?' function.
(test/exec :some?1  #(some? null)      false)
(test/exec :some?2  #(some? '())       false)
(test/exec :some?3  #(some? 123)       true)
(test/exec :some?4  #(some? "abc")     true)
(test/exec :some?5  #(some? "")        false)
(test/exec :some?6  #(some? [])        false)
(test/exec :some?7  #(some? {})        false)


;----------------------------------------------------
; Test the 'none?' function.
(test/exec :none?1  #(none? null)      true)
(test/exec :none?2  #(none? '())       true)
(test/exec :none?3  #(none? 123)       false)
(test/exec :none?4  #(none? "abc")     false)
(test/exec :none?5  #(none? "")        true)
(test/exec :none?6  #(none? [])        true)
(test/exec :none?7  #(none? {})        true)

;----------------------------------------------------
; Test the 'pos?' predicate
(test/exec :pos?1  #(pos? 123)         true)
(test/exec :pos?2  #(pos? -123)        false)
(test/exec :pos?3  #(pos? 0)           true)
(test/exec :pos?4  #(pos? 123.456)     true)
(test/exec :pos?5  #(pos? -123.456)    false)
; not a number so false
(test/exec :pos?6  #(pos? "123")       false)

;----------------------------------------------------
; Test the 'neg?' predicate
(test/exec :neg?1  #(neg? 123)         false)
(test/exec :neg?2  #(neg? -123)        true)
(test/exec :neg?3  #(neg? 0)           false)
(test/exec :neg?4  #(neg? 123.456)     false)
(test/exec :neg?5  #(neg? -123.456)    true)
; not a number so false
(test/exec :neg?6  #(neg? "123")       false)

;----------------------------------------------------
; Test the 'neg' function
(test/exec :neg1  #(neg 1)       -1)
(test/exec :neg2  #(neg -1)      1)
(test/exec :neg3  #(neg -2.13)   2.13)
(test/exec :neg4  #(neg 2.13)   -2.13)
; BUGBUGBUG - parses -1i as a symbol instead of a number (test/exec :neg5 #(neg 1i)       -1i)
; BUGBUGBUG (test/exec :neg6 #(neg -1i)      1i)
(test/exec :neg7  #(neg (fib 10)) -89)
(test/exec :neg8  #(neg? (neg 1234)) true)
(test/exec :neg9  #(neg? (neg -1234)) false)
(test/exec :neg10 #(try (neg null) | is? ^exception) true)
(test/exec :neg11 #(neg 0) 0)
(test/exec :neg12 #(try (neg "123") | is? ^exception) true)
(test/exec :neg13 #(try (neg [1 2 3]) | is? ^exception) true)
(test/exec :neg14 #(try (neg []) | is? ^exception) true)
(test/exec :neg15 #(try (neg '(1 2 3)) | is? ^exception) true)
(test/exec :neg16 #(try (neg {}) | is? ^exception) true)

;----------------------------------------------------
; quote?
(test/exec :quote?1
    (fn ->
        (defspecial islist [obj] (list? obj))
        (islist 'abc)
    )
    true
)
(test/exec :quote?2
    (fn ->
        (symbol? 'abc)
    )
    true
)
; create a dotted pair i.e. (quote . abc).
(test/exec :quote?3
    (fn ->
        (symbol? (quote 'abc | car | cdr))
    )
    true
)
(test/exec :quote?4
    (fn ->
        (quote 'abc | car | tostring)
    )
    "(quote . abc)"
)

;----------------------------------------------------
; Test the 'seq?' predicate
(test/exec :seq?1  #(seq? [1 2 3])      true)
(test/exec :seq?2  #(seq? '(1 2 3))     true)
(test/exec :seq?3  #(seq? '())          false)
(test/exec :seq?4  #(seq? "abc")        false)
(test/exec :seq?5  #(seq? 123)          false)
(test/exec :seq?6  #(seq? null)         false) ; BUGBUGBUG - maybe this should be true if null is the empty list?

;----------------------------------------------------
; Test the 'string?' predicate
(test/exec :string?1  #(string? "abcd") true)
(test/exec :string?2  #(string? "")     true)
(test/exec :string?3  #(string? nil)    false)
(test/exec :string?4  #(string? :abcd)  false)
(test/exec :string?5  #(string? 'a)     false)
(test/exec :string?6  #(string? [])     false)
(test/exec :string?7  #(string? {})     false)

;----------------------------------------------------
; Test the 'symbol?' predicate
(test/exec :symbol?1  #(symbol? 'a)     true)
(test/exec :symbol?2  #(symbol? "abc")  false)
(test/exec :symbol?3  #(symbol? [])     false)
(test/exec :symbol?4  #(symbol? {})     false)
(test/exec :symbol?5  #(symbol? null)   false)
(test/exec :symbol?6  #(symbol? (gen-symbol)) true)
(test/exec :symbol?7  #(symbol? (get-symbol "abc")) true)
(test/exec :symbol?8
    (fn ->
        ; verify that symbols passed as arguments remain as symbols
        (defn foo [a b c] [a b c])
        (let result (foo 'a 'b 'c))
        (and
            (!! result 0 | symbol?)
            (!! result 1 | symbol?)
            (!! result 2 | symbol?)
        )
    )
    true
)

;----------------------------------------------------
; Test the 'list/all' function
(test/exec :list/all1 (fn -> ([1 2 3 4] | list/all even?)) false)
(test/exec :list/all2 (fn -> ([2 4 6 8] | list/all even?)) true)
(test/exec :list/all3 (fn -> ([2 4 6 8] | list/all (fn n -> (band n 0x01)))) false)
(test/exec :list/all4 (fn -> ([1 3 5 7 9 13] | list/all (fn n -> (band n 0x01)))) true)
(test/exec :list/all5
    (fn ->
        ;see if all characters are lowercase
        ("hello" | chars | list/all .char/islower)
    )
    true
)
(test/exec :list/all5a
    (fn ->
        ("Hello" | chars | list/all .char/islower)
    )
    false
)

;----------------------------------------------------
; Test the 'list/any' function
(test/exec :list/any1 (fn -> ([1 2 3 4] | list/any even?)) true)
(test/exec :list/any2 (fn -> ([3 5 7 9] | list/any even?)) false)
(test/exec :list/any3 (fn -> ([1 2 3 4 5] | list/all (fn n -> (band n 0x01)))) false)
(test/exec :list/any4
    (fn ->
        ;see if any char is uppercase
        ("hello world" | chars | list/any .char/isupper)
    )
    false
)
(test/exec :list/any4a
    (fn ->
        ("Hello world" | chars | list/any .char/isupper)
    )
    true
)

;----------------------------------------------------
; Test the 'list/monotonic' function - each element in the sequence must be strictly larger
(test/exec :list/monotonic1 (fn -> ([1 2 3 4] | list/monotonic)) true)
(test/exec :list/monotonic2 (fn -> ([1 5 3 4] | list/monotonic)) false)
(test/exec :list/monotonic3 (fn -> ([-10 -5 0 1 20 30 31 40] | list/monotonic)) true)
(test/exec :list/monotonic4 (fn -> (random 2000 | sort | list/monotonic)) true)
(test/exec :list/monotonic5 (fn -> (random 2000 | list/monotonic)) false)

;-------------------------------------------------------
; Test the 'random' function
(test/exec :random1
    (fn ->
        (random 5 | length)
    )
    5
)
(test/exec :random2
    (fn ->
        (random 5 | type-of)
    )
    ^vector
)
(test/exec :random4
    (fn ->
        (random 1 | type-of)
    )
    ^int
)
(test/exec :random5
    (fn ->
        (random 1 50 | <= 50)
    )
    true
)
(test/exec :random6
    (fn ->
        (random 100 1 50 | max-list | <= 50)
    )
    true
)

;-------------------------------------------------------
; Test the 'foreach' function (loop)
(test/exec :foreach1
    (fn ->
        (let s 0)
        (foreach e (range 10)
            (let s (+ e s))
        )
        s
    )
    55
)
(test/exec :foreach2
    (fn ->
        (let abc null)
        (foreach n (range 5) (let abc n) (break))
        abc
    )
    1
)
(test/exec :foreach3
    (fn ->
        (let abc 10)
        (foreach n (range 5) (continue) (let abc n))
        abc
    )
    10
)
(test/exec :foreach4
    (fn ->
        ; foreach returns null
        (foreach n (range 5) (* 5 5))
    )
    nil
)
(test/exec :foreach5
    (fn ->
        (let result [])
        ; test nested foreach loops
        (foreach x (range 5)
            (foreach y (range 5)
                (.add result (+ x y))
            )
        )
        result
    )
    [2 3 4 5 6 3 4 5 6 7 4 5 6 7 8 5 6 7 8 9 6 7 8 9 10]
)
(test/exec :foreach6
    (fn ->
        (let result [])
        ; test destructuring
        (foreach a:b: [[1 2] [3 4] [5 6]]
            (.add result (+ a b))
        )
        result
    )
    [3 7 11]
)
(test/exec :foreach6a
    (fn ->
        (let result [])
        ; test destructuring
        (foreach [a b] [1 2 3 4 5 6]
            (.add result (+ a b))
        )
        result
    )
    [3 7 11]
)
(test/exec :foreach6b
    (fn ->
        (let result [])
        ; test destructuring inside destructuring 
        (foreach [a:b: c:d:] [[1 2] [3 4] [5 6] [7 8]]
            (.add result (str (+ a b) \: (+ c d)))
        )
        result
    )
    ["3:7" "11:15"]
)
(test/exec :foreach7
    (fn ->
        (let result [])
        ; test pulling multiple items at a time from the input
        (foreach [a b c] (range 10) (.add result [a b c]))
        result
    )
    [[1 2 3] [4 5 6] [7 8 9] [10 null null]]
)
(test/exec :foreach8
    (fn ->
        (let result [])
        ; multiple items with destructuring
        (foreach [a:b: c:d:] [[1 2] [3 4] [5 6] [7 8]] (.add result [(+ a b) (+ c d)]))
        result
    )
    [[3 7] [11 15]]
)
(test/exec :foreach9
    (fn ->
        ; test parameter validation.
        (let e (try (foreach 1 [1 2 3] "foo")))
        (is? e ^Exception | and (#"foreach" (.message e)) | ^bool?)
    )
    true
)

;-------------------------------------------------------
; Test the 'forall' function
(test/exec :forall1
    (fn -> (forall n '(1 2 3 4) (* n n)))
    [1 4 9 16]
)
(test/exec :forall2
    (fn ->
        (forall n (range 5) (break) n)
    )
    []
)
(test/exec :forall3
    (fn ->
        (let abc 10)
        (forall n (range 5) (continue) (let abc n))
        abc
    )
    10
)
(test/exec :forall4
    (fn ->
        ; nested forall calls returning collections
        (forall x (range 3)
            (forall y (range 3)
                [x y]
            )
        )
    )
    [
        [[1 1] [1 2] [1 3]]
        [[2 1] [2 2] [2 3]]
        [[3 1] [3 2] [3 3]]
    ]
)
(test/exec :forall5
    (fn ->
        ; test destructuring
        (forall a:b: [[1 2] [3 4] [5 6]] (+ a b))
    )
    [3 7 11]
)
(test/exec :forall6
    (fn ->
         (forall [a b c] (range 10) (+ a b c))
    )
    [6 15 24 10]
)
(test/exec :forall8
    (fn ->
        (forall [a:b: c:d:] [[1 2] [3 4] [5 6] [7 8]] [(+ a b) (+ c d)])
    )
    [[3 7] [11 15]]
)
(test/exec :forall9
    (fn ->
        ; test parameter validation.
        (let e (try (forall 1 [1 2 3] "foo")))
        (is? e ^Exception | and (#"forall" (.message e)) | ^bool?)
    )
    true
)
(test/exec :forall10
    (fn ->
        ; test flattening (used internally by the 'from' macro)
        (forall -flatten val [[1 1] [2 2] [3 3]] val)
    )
    [1 1 2 2 3 3]
)
(test/exec :forall11
    (fn ->
        ; test flattening (used internally by the 'from' macro)
        (forall -flatten a:b: [[1 2] [3 4] [5 6]] [a b])
    )
    [1 2 3 4 5 6]
)
(test/exec :forall12
    (fn ->
        ; test flattening (used internally by the 'from' macro)
        (forall -flatten a:b: [[1 2] [3 4] [5 6]] [b a])
    )
    [2 1 4 3 6 5]
)
(test/exec :forall13
    (fn ->
        (forall -flatten [a b c] [1 2 3 4 5 6] [c b a])
    )
    [3 2 1 6 5 4]
)
(test/exec :forall14
    (fn ->
        ; too few nuls which should be padded by null but the
        ; null should be stripped on output
        (forall -flatten [a b c] [1 2 3 4 5] [c b a])
    )
    [3 2 1 5 4]
)
(test/exec :forall15
    (fn ->
        ; function to count the numbers of each char in a string.
        (defn count-chars [(^char[]? xs)]
            (let result {})
            (forall x xs
                (result x (+ (result x) 1))
            )
            result
       )
       (count-chars "Hello world, how are you?")
   )
   { \H 1 \e 2 \l 3 \o 4 \space 4 \w 2 \r 2 \d 1 \, 1 \h 1 \a 1 \y 1 \u 1 \? 1 }
)

;-------------------------------------------------------
; Test the 'while' function
(test/exec :while1
    (fn ->
        (let s 0)
        (while (< s 10)
            (incr s)
        )
        s
    )
    10
)
(test/exec :while2
    (fn ->
        (let s 0)
        ; while returns the value of the last evaluated expression
        (while (< s 10)
            (incr s)
        )
    )
    10
)
(test/exec :while3
    (fn ->
        (let s 0)
        (let t 0)
        (while (< s 10)
            (incr s)
            (incr t 2)
        )
        [s t]
    )
    [10 20]
)
(test/exec :while4
    (fn ->
        (let s 0)
        (while (< (incr s) 10)
            ; null body
        )
        ; but the conditional part increments the variable
        s
    )
    10
)
(test/exec :while5
    (fn ->
        ; nested while statements
        (let ^int s 0)
        (let ^int u 0)
        (while (incr s | <= 10)
            (let t 0)
            (while (incr t | <= s)
                (let u (+ s t))
            )
       )
       u
   )
   20
)
(test/exec :while6
    (fn ->
        (let xs [1 2 3 4 5])
        ; returns the last element of the list
        (while (let? x:xs xs) x)
    )
    5
)
(test/exec :while7
    (fn ->
        ; A function to reverse a list that uses while.
        (defn while-rev [xs (result null)]
            (while (let? x:xs xs) (let result (cons x result))) 
        )

        (while-rev [1 2 3 4 5])
    )
    (list 5 4 3 2 1)
)
(test/exec :while8
    (fn ->
        ; function to count the numbers of each char in a string.
        (defn count-chars [(^string s)]
            (let result {})
            (let xs (chars s))
            (while (let? x:xs xs)
                (result x (+ (result x) 1))
            )
            result
       )
       (count-chars "Hello world, how are you?")
   )
   { \H 1 \e 2 \l 3 \o 4 \space 4 \w 2 \r 2 \d 1 \, 1 \h 1 \a 1 \y 1 \u 1 \? 1 }
)

;-------------------------------------------------------
; Test the 'break' function
(test/exec :break1
    (fn ->
        (let i 0)
        (while (< i 10)
            (incr i)
            (if (> i 5)
                (break)
                i
            )
        )
    )
    6
)
(test/exec :break2
    (fn ->
        (let i 0)
        (while (< i 10)
            (incr i)
            (break 20)
        )
    )
    20
)
(test/exec :break3
    (fn ->
        (for (let i 0) (< i 10) (incr i)
            (if (== i 5)
                (break)
                i
            )
        )
    )
    5
)
(test/exec :break4
    (fn ->
        (for (let i 0) (< i 10) (incr i)
            (if (== i 5)
                (break false)
                i
            )
        )
    )
    false
)
(test/exec :break5
    (fn -> (range 10 | map (fn x -> (if (== x 5) (break) x))))
    [1 2 3 4]
)
(test/exec :break5a
    (fn -> (range 10 | lazy-map (fn x -> (if (== x 5) (break) x)) | to-vector))
    [1 2 3 4]
)
(test/exec :break6
    (fn -> (range 10 | map (fn x -> (if (== x 5) (break "hello") x))))
    "hello"
)
(test/exec :break6a
    (fn -> (range 10 | lazy-map (fn x -> (if (== x 5) (break "hello") x)) | to-vector))
    [1 2 3 4 "hello"]  ; with lazy ops, you can'r replace emitted values
)
(test/exec :break7
    (fn -> (range 10 | filter (fn x -> (if (== x 5) (break) true))))
    [1 2 3 4 5]
)
(test/exec :break7a
    (fn -> (range 10 | lazy-filter (fn x -> (if (== x 5) (break) true))))
    [1 2 3 4 5]
)
(test/exec :break8
    (fn -> (range 10 | filter (fn x -> (if (== x 5) (break 'zork) true))))
    'zork
)
(test/exec :break8a
    (fn -> (range 10 | lazy-filter (fn x -> (if (== x 5) (break 'zork) true)) | to-vector))
    [1 2 3 4 'zork] ; with lazy ops, you can'r replace emitted values
)
(test/exec :break9
    (fn -> (forall i (range 10) (if (== i 5) (break) i)))
    [1 2 3 4]
)
(test/exec :break9a
    (fn -> (forall i (range 10) (if (== i 5) (break "zap") i)))
    "zap"
)

;-------------------------------------------------------
; Test the 'continue' function
(test/exec :continue1
    (fn ->
        (let x 0)
        (let i 0)
        (while (< i 5)
            (incr i)
            (continue)
            (incr x)
        )
        [x i]
    )
    [0 5]
)
(test/exec :continue2
    (fn -> (forall i (range 10) (if (% i 2) (continue) i)))
    [2 4 6 8 10]
)
(test/exec :continue3
    ; skips odd numbers
    (fn -> (range 10 | map (fn x -> (if (% x 2) (continue) x))))
    [2 4 6 8 10]
)

;-------------------------------------------------------
; test the 'for' macro.
(test/exec :for1
    (fn ->
        (let s 0)
        (for (let i 0) (< i 10) (incr i) (incr s))
        [s i]
    )
    [10 10]
)
(test/exec :for2
    (fn ->
        ; last value is returned
        (for (let i 0) (< i 5) (incr i))
    )
    5
)
(test/exec :for3
    (fn ->
        (defn pal
            "Iterative function to determine if the argument string is a palindrome"
            [(^string str)]

            (let len (length str))
            (let r (- len 1))
            (for (let i 0) (= i < len/2) (incr i)
                (if (!! str i | == (!! str r))
                    (return true)
                )
            )
            false
        )

        (and
            (pal "abcdeebcda")
            (pal "abcba")
            (not (pal "abcde"))
        )
    )
    true
)


;-------------------------------------------------------
; Test the 'reverse' function
(test/exec :reverse1
    #(reverse [1 2 3 4 5])
    [5 4 3 2 1]
)
(test/exec :reverse2
    (fn ->
        (is? (reverse '(1 2 3 4 5)) ^Vector)
    )
    true
)
(test/exec :reverse3
    (fn ->
        (defn pal [arr] (== arr (reverse arr)))
        (and
            (pal [1 2 3 2 1])
            (not (pal [1 2 3 4 5]))
        )
    )
    true
)
(test/exec :reverse4
    (fn ->
        ; verify that 'reverse' doesn't mutate the original vector
        (let vec [1 2 3 4 5])
        (reverse vec)
        vec
    )
    [1 2 3 4 5]
)
(test/exec :reverse5
    (fn ->
        (reverse null)
    )
    []
)
(test/exec :reverse6
    (fn ->
        (reverse [])
    )
    []
)
(test/exec :reverse7
    (fn ->
        (reverse "abcd")
    )
    "dcba"
)
(test/exec :reverse7a
    (fn ->
        (reverse "")
    )
    ""
)

;-------------------------------------------------------
(test/exec :str/reverse1
    (fn ->
        (str/reverse "abcd")
    )
    "dcba"
)
(test/exec :str/reverse2
    (fn ->
        (str/reverse "")
    )
    ""
)
(test/exec :str/reverse3
    (fn ->
        (str/reverse null)
    )
    ""
)

;-------------------------------------------------------
; Test the 'if' function
(test/exec :if1
    #(do
        (let r 0)
        (if true (let r 3.14))
        r
    )
    3.14
)
(test/exec :if2
    #(do
        (let r 0)
        (if false (let r 3.14))
        r
    )
    0
)
(test/exec :if3
    #(do
        (let r 0)
        (if true (let r 3.14) (let r 20))
        r
    )
    3.14
)
(test/exec :if4
    #(do
        (let r 0)
        (if false (let r 3.14) (let r 20))
        r
    )
    20
)
(test/exec :if5  #(if true 10 20) 10)
(test/exec :if6  #(if true 10) 10)
(test/exec :if7  #(if false 10 20) 20)
(test/exec :if8  #(if false 10) nil)
; test > with monotonic sequences of numbers.
(test/exec :if10a #(if (> 5 6) "t_r_u_e" "f_a_l_s_e") "f_a_l_s_e")
(test/exec :if10b #(if (< 5 6) "t_r_u_e" "f_a_l_s_e") "t_r_u_e")
(test/exec :if10c #(if (< 5 6 7) "t_r_u_e" "f_a_l_s_e") "t_r_u_e")
(test/exec :if10d #(if (< 5 6 7 8) "t_r_u_e" "f_a_l_s_e") "t_r_u_e")
(test/exec :if10e #(if (< 5 4 7 8) "t_r_u_e" "f_a_l_s_e") "f_a_l_s_e")
(test/exec :if11a #(if (<= 5 6) "t_r_u_e" "f_a_l_s_e") "t_r_u_e")
(test/exec :if11b #(if (<= 5 6 7) "t_r_u_e" "f_a_l_s_e") "t_r_u_e")
(test/exec :if11c #(if (<= 5 5 6 7) "t_r_u_e" "f_a_l_s_e") "t_r_u_e")
(test/exec :if11d #(if (<= 5 6 7 8) "t_r_u_e" "f_a_l_s_e") "t_r_u_e")
(test/exec :if11e #(if (<= 5 4 7 8) "t_r_u_e" "f_a_l_s_e") "f_a_l_s_e")
(test/exec :if11f #(if (<= 5 6 7 6) "t_r_u_e" "f_a_l_s_e") "f_a_l_s_e")
; test piping into an if
(test/exec :if12 #(true | if 1 2) 1)
(test/exec :if13 #(123 | if 1 2) 1)
(test/exec :if14 #(0 | if 1 2) 2)
(test/exec :if15 #("hello" | if 1 2) 1)
(test/exec :if16 #("" | if 1 2) 2)
(test/exec :if17 #(true | if false true | if true false | if false true) true)

;-------------------------------------------------------
(test/exec :unless1 #(unless true 123) nil)
(test/exec :unless2 #(unless false 123) 123)
(test/exec :unless3 #(unless false 123 456 789) 789)

;-------------------------------------------------------
(test/exec :when1 #(when true 123) 123)
(test/exec :when2 #(when true 123 456 789) 789)
(test/exec :when3 #(when false 123) nil)

;-------------------------------------------------------
; Test the 'if-not' function
(test/exec :if-not1
    (fn ->
        (if-not true 1 2)
    )
    2
)
(test/exec :if-not2
    (fn ->
        (if-not false 1 2)
    )
    1
)
(test/exec :if-not3
    (fn ->
        (if-not true 1)
    )
    null
)
(test/exec :if-not4
    (fn ->
        (if-not false 1)
    )
    1
)

;-------------------------------------------------------
; The 're/split' function
(test/exec :re/split1 #(re/split "a b c") ["a" "b" "c"])
(test/exec :re/split2 #(re/split "a,b,c,d" ",") ["a" "b" "c" "d"])
(test/exec :re/split3 #(re/split "a,,,b::c,d" #"[,:]+") ["a" "b" "c" "d"])
(test/exec :re/split4 #(re/split "a+b+c" '+) ["a" "b" "c"])  ; test with symbol
(test/exec :re/split5 #(re/split "a+b+c" "+") ["a" "b" "c"]) ; test with string
(test/exec :re/split6 #(re/split "a+b+c" \+) ["a" "b" "c"])  ; test with char literal

;-------------------------------------------------------
; The 're/split-all' function
(test/exec :re/split-all1
    #(re/split-all ["a b c" "d e f"])
    ["a" "b" "c" "d" "e" "f"]
)
(test/exec :re/split-all1a
    #(re/split-all -dontflatten ["a b c" "d e f"])
    [["a" "b" "c"] ["d" "e" "f"]]
)
(test/exec :re/split-all2
    #(re/split-all ["a a,b,c" "d,e,,,f"] #",+") ; split with specified pattern
    ["a a" "b" "c" "d" "e" "f"]
)
(test/exec :re/split-all2a
    #(re/split-all -dontflatten ["a a,b,c" "d,e,,,f"] #",+") ; split with specified pattern
    [["a a" "b" "c"] ["d" "e" "f"]]
)
(test/exec :re/split-all3
    #(re/split-all "a b c")
    ["a" "b" "c"]
)
(test/exec :re/split-all4
    #(re/split-all ["a b c"])
    ["a" "b" "c"]
)
(test/exec :re/split-all5
    #(re/split-all [])
    []
)

;-------------------------------------------------------
; Test the 'list/split' function.
(test/exec :list/split1
    (fn ->
        ([1 2 3 4] | list/split (< 3))
    )
    [[1 2][3 4]]
)
(test/exec :list/split2
    (fn ->
        ([1 2 3 4] | list/split (% 2))
    )
    [[1 3][2 4]]
)
(test/exec :list/split3
    (fn ->
        ([] | list/split (% 2))
    )
    [[][]]
)
(test/exec :list/split4
    (fn ->
        (1 | list/split (% 2))
    )
    [[1][]]
)
(test/exec :list/split5
    (fn ->
        ([1] | list/split (% 2))
    )
    [[1][]]
)

;-------------------------------------------------------
; test the 'try' and 'throw' functions
(test/exec :try1
    (fn ->
        (try
            1
        -catch:
            2
        )
    )
    1
)
(test/exec :try2
    (fn ->
        (try
            (/ 1 0)
        -catch:
            2
        )
    )
    2
)
(test/exec :try3
    (fn ->
        (let fval 0)
        (try
            (/ 1 0)
        -catch:
            2
        -finally:
            (let fval 3.14)
        )
        fval
    )
    3.14
)
(test/exec :throw1
    (fn ->
        (try
            (throw "Boom")
        -catch:
            ; if the arg to catch is a lambda, call it with the exception
            (fn e ->
                (.message e | re/match "boom"))
        )
    )
    true
)
(test/exec :throw2
    (fn ->
        (let fval "")
        (let val
            (try
                (throw "Boom")
            -catch:
                #(.message %0 | re/match "boom")
            -finally:
                (let fval "mooB")
            )
        )
        "${val} ${fval}"
    )
    "true mooB"
)
(test/exec :try6
    (fn ->
        (let val (try 3.14))
        val
    )
    3.14
)
(test/exec :throw3
    (fn ->
        (let val (try (throw "Boom")))
        (is? val ^Exception)
    )
    true
)
(test/exec :try7
    (fn ->
        ; this is slow since it goes through PowerShell command lookup.
        (let val (try (nosuchfunction)))
        (is? val ^Exception)
    )
    true
)

;-------------------------------------------------------
; Test the 'cons' function.
(test/exec :cons1  #(cons 1 '(2 3)) '(1 2 3))
(test/exec :cons2  #(cons 1 (cons 2 (cons 3 null))) '(1 2 3))
(test/exec :cons3  #(is? (cons 1 (cons 2 (cons 3 null))) ^List) true)
(test/exec :cons4  #(cons 1 2 | == '(1 . 2)) true)
(test/exec :cons5  #(car (cons 1 2) | == 1) true)
(test/exec :cons6  #(cdr (cons 1 2) | == 2) true)
(test/exec :cons7  #(cons 1 2) '(1 . 2))
(test/exec :cons8  #(cons 1 [2 3] | cdr) [2 3])
(test/exec :cons9  #(cons 1 [2 3] | cdr | type-of) ^BraidLang.Vector)
; test the ':' alias for 'cons'
(test/exec ::4  #(: 1 '(2 3)) '(1 2 3))
(test/exec ::5  #(: 1 (: 2 (: 3 null))) '(1 2 3))
(test/exec ::6  #(is? (: 1 (: 2 (: 3 null))) ^List) true)

;-------------------------------------------------------
; Test the '>cons' function.
(test/exec :>cons1
    (fn ->
        (list 2 3 4 | >cons 1)
    )
    '(1 2 3 4)
)
(test/exec :>cons2
    (fn ->
        (list 2 3 4 | >cons 1 | >cons 0)
    )
    '(0 1 2 3 4)
)


;-------------------------------------------------------
; Test the '>:' function.
(test/exec :>:1
    (fn ->
        (list 2 3 4 | >: 1)
    )
    '(1 2 3 4)
)
(test/exec :>:2
    (fn ->
        (list 2 3 4 | >: 1 | >: 0)
    )
    '(0 1 2 3 4)
)

;-------------------------------------------------------
; Test the 'vcons' function.
(test/exec :vcons1  #(vcons 1 [2 3]) [1 2 3])
(test/exec :vcons2  #(vcons 3 null)  [3])
(test/exec :vcons3  #(is? (vcons 1 (vcons 2 (vcons 3 null))) ^Vector) true)
(test/exec :vcons4
    (fn ->
        (let x [1 2 3])
        (vcons 0 x)
        x
    )
    [0 1 2 3]
)
(test/exec :vcons5
    (fn ->
        ; vcons mutates the argument vector
        (let x [1 2 3])
        (vcons -1 (vcons 0 x))
        x
    )
    [-1 0 1 2 3]
)
(test/exec :vcons6
    (fn ->
        (let x [1 2 3])
        (nconc 4 (vcons 0 x))
        x
    )
    [0 1 2 3 4]
)
(test/exec :vcons7
    (fn ->
        (let x [1 2 3])
        (vcons 4 (nconc 0 x))
        x
    )
    [4 1 2 3 0]
)
(test/exec :vcons8
    (fn ->
        ; tail-recursive function to reverse a vector
        (defn rev | x:xs (r []) -> (recur xs (vcons x r)) | %none? (r []) -> r)
        (rev [1 2 3 4 5])
    )
    [5 4 3 2 1]
)

;-------------------------------------------------------
; Test the 'car' function.
(test/exec :car1  #(car (list 1 2 3)) 1)
(test/exec :car2  #(car '())          nil)
(test/exec :car2a #(car nil)          nil)
(test/exec :car3  #(car 1)            1)      ; car of an atom/scalar object is itself.
(test/exec :car4  #(car "abc")        "abc")
(test/exec :car5  #(car "abc def ghi") "abc") ; takes the "car" of a string
(test/exec :car6  #([10 20 30] | car) 10)     ; takes the car of a vector
(test/exec :car7  #(car null) null)
(test/exec :car8  #(car (unfold ++ 1)) 1)     ; test IEnumerable
(test/exec :car9  #(car (slice [1 2 3 4])) 1) ; test car of a slice

;-------------------------------------------------------
; Test the 'head' function.
(test/exec :head1  #(head (list 1 2 3)) 1)
(test/exec :head2  #(head '())          nil)
(test/exec :head3  #(head 1)            1)      ; head of a non-sequence/scalar object is itself.
(test/exec :head4  #(head "abc")        "abc")
(test/exec :head5  #(head "abc def ghi") "abc") ; takes the "head" of a string
(test/exec :head6  #([10 20 30] | head) 10)     ; takes the head of a vector
(test/exec :head7  #(head null) null)

;-------------------------------------------------------
; The 'cdr' function on lists, vectors, arrays and ienumerables
(test/exec :cdr1  #(cdr (list 1 2 3))    '(2 3))
(test/exec :cdr2  #(cdr "abc")           nil)
(test/exec :cdr3  #(cdr "a b c")         (list "b" "c")) ; cdr of a string is a list of everything after the first set of spaces
(test/exec :cdr4  #(cdr [1 2 3])         [2 3])
(test/exec :cdr5  #(cdr 1)               nil)
(test/exec :cdr6  #([1 2 3] | cdr)       [2 3])
(test/exec :cdr7  #([1 2 3] | cdr | cdr) [3])
(test/exec :cdr8  #([1 2 3] | cdr | cdr | cdr) null)
(test/exec :cdr9  #([1 2 3] | cdr | cdr | car) 3)
(test/exec :cdr10 #(cdr null) null)
(test/exec :cdr11 #(cdr (unfold ++ 1 5)) [2 3 4 5])     ; test cdr of an IEnumerable
(test/exec :cdr12 #(cdr (unfold ++ 1 5) | type-of) ^Slice)
(test/exec :cdr13 #(cdr (chars "abcd")) ["b" "c" "d"])
(test/exec :cdr14 #(cdr (chars "abcd") | type-of) ^slice)
(test/exec :cdr15 #(cdr (slice [1 2 3 4])) [2 3 4])
(test/exec :cdr16 #(cdr (slice [1 2 3 4]) | type-of) ^Slice)

;-------------------------------------------------------
; The 'tail' function (just an alias for 'cdr')
(test/exec :tail1  #(tail (list 1 2 3))    '(2 3))
(test/exec :tail2  #(tail "abc")           nil)
(test/exec :tail3  #(tail "a b c")         (list "b" "c")) ; tail of a string is eerything after the first set of spaces, returned as a list
(test/exec :tail4  #(tail [1 2 3])         [2 3])
(test/exec :tail5  #(tail 1)               nil)
(test/exec :tail6  #([1 2 3] | tail)       [2 3])
(test/exec :tail7  #([1 2 3] | tail | tail) [3])
(test/exec :tail8  #([1 2 3] | tail | tail | tail) null)
(test/exec :tail9  #([1 2 3] | tail | tail | car) 3)
(test/exec :tail10  #(tail null) null)

;-------------------------------------------------------
; The 'cadr' function
(test/exec :cadr1  #(cadr '(1 2 3 4)) 2)
(test/exec :cadr2  #(cadr [1 2 3 4]) 2)
(test/exec :cadr3  #(cadr '()) nil)

;-------------------------------------------------------
; The 'cadr' function
(test/exec :cddr1  #(cddr '(1 2 3 4)) '(3 4))
(test/exec :cddr2  #(cddr [1 2 3 4]) [3 4])
(test/exec :cddr3  #(cddr '()) nil)

;-------------------------------------------------------
; The 'second' function
(test/exec :second1  #(second '(1 2 3 4)) 2)
(test/exec :second2  #(second [1 2 3 4]) 2)
(test/exec :second3  #(second '()) nil)

;-------------------------------------------------------
; The 'caddr' function
(test/exec :caddr1  #(caddr '(1 2 3 4)) 3)
(test/exec :caddr2  #(caddr '()) nil)

;-------------------------------------------------------
; The 'third' function
(test/exec :third1  #(third '(1 2 3 4)) 3)
(test/exec :third2  #(third '(1 2)) nil)
(test/exec :third3  #(third '()) nil)

;-------------------------------------------------------
; The 'contains?' function
(test/exec :contains?1  (fn -> (contains? [1 2 3 4 5] 3)) true)
; test non-ISeq IEnumerable type
(test/exec :contains?1a (fn -> (contains? (asarray [1 2 3 4 5]) 3)) true)
(test/exec :contains?2  (fn -> (contains? [1 2 3 4 5] 10)) false)
(test/exec :contains?2a (fn -> (contains? (asarray [1 2 3 4 5]) 10)) false)
(test/exec :contains?3  (fn -> (contains? [] 10)) false)
(test/exec :contains?4  (fn -> (contains? '(1 2 3 4 5) 3)) true)
(test/exec :contains?5  (fn -> (contains? '(1 2 3 4 5) 10)) false)
(test/exec :contains?6  (fn -> (contains? [1 2 3 4 5] (fn n -> (== 4 n)))) true)
(test/exec :contains?7  (fn -> (contains? [1 2 3 4 5] (fn n -> (== 10 n)))) false)
(test/exec :contains?8  (fn -> (contains?  #{1 2 3 4} 2)) true)
(test/exec :contains?9  (fn -> (contains?  #{1 2 3 4} 7)) false)
(test/exec :contains?10 (fn -> (contains?  #{1 2 3 4} (fn n -> (== n 4)))) true)
(test/exec :contains?11 (fn -> (contains?  #{1 2 3 4} (fn n -> (== n 7)))) false)
(test/exec :contains?12 (fn -> (contains? {:a 1 :b 2 :c 3 :d 4} :b)) true)
(test/exec :contains?13 (fn -> (contains? {:a 1 :b 2 :c 3 :d 4} :z)) false)
(test/exec :contains?14 (fn -> (contains? {:a 1 :b 2 :c 3 :d 4} (fn n -> (== n :b)))) true)
(test/exec :contains?15 (fn -> (contains? {:a 1 :b 2 :c 3 :d 4} (fn n -> (== n 10)))) false)
(test/exec :contains?16 (fn -> (contains? "abcdefghij" "d")) true)
(test/exec :contains?17 (fn -> (contains? "abcdefghij" "z")) false)
(test/exec :contains?18 (fn -> (contains? "abcdefghij" \d)) true)
(test/exec :contains?19 (fn -> (contains? "abcdefghij" \z)) false)
; test with rangelist
(test/exec :contains?20 (fn -> (contains? (range 4 12 3) 6)) true)
(test/exec :contains?21 (fn -> (contains? (range 4 12 3) 7)) false)
(test/exec :contains?22 (fn -> (contains? (range \a \m) \l)) true)
(test/exec :contains?23 (fn -> (contains? (range \a \m) \z)) false)

;-------------------------------------------------------
; The 'in?' function - same as contains but the args are reversed
(test/exec :in?1  (fn -> (in? 3 [1 2 3 4 5])) true)
; test non-ISeq IEnumerable type
(test/exec :in?1a (fn -> (in? 3 (asarray [1 2 3 4 5]))) true)
(test/exec :in?2  (fn -> (in? 10 [1 2 3 4 5])) false)
(test/exec :in?2a (fn -> (in? 10 (asarray [1 2 3 4 5]))) false)
(test/exec :in?3  (fn -> (in? 10 [])) false)
(test/exec :in?4  (fn -> (in? 3 '(1 2 3 4 5))) true)
(test/exec :in?5  (fn -> (in? 10 '(1 2 3 4 5))) false)
(test/exec :in?6  (fn -> (in? (fn n -> (== 4 n)) [1 2 3 4 5])) true)
(test/exec :in?7  (fn -> (in? (fn n -> (== 10 n)) [1 2 3 4 5])) false)
(test/exec :in?8  (fn -> (in? 2  #{1 2 3 4})) true)
(test/exec :in?9  (fn -> (in? 7  #{1 2 3 4})) false)
(test/exec :in?10 (fn -> (in? (fn n -> (== n 4))  #{1 2 3 4})) true)
(test/exec :in?11 (fn -> (in? (fn n -> (== n 7))  #{1 2 3 4})) false)
(test/exec :in?12 (fn -> (in? :b {:a 1 :b 2 :c 3 :d 4})) true)
(test/exec :in?13 (fn -> (in? :z {:a 1 :b 2 :c 3 :d 4})) false)
(test/exec :in?14 (fn -> (in? (fn n -> (== n :b)) {:a 1 :b 2 :c 3 :d 4})) true)
(test/exec :in?15 (fn -> (in? (fn n -> (== n 10)) {:a 1 :b 2 :c 3 :d 4})) false)
(test/exec :in?16 (fn -> (in? "d" "abcdefghij")) true)
(test/exec :in?17 (fn -> (in? "z" "abcdefghij")) false)
(test/exec :in?18 (fn -> (in? \d "abcdefghij")) true)
(test/exec :in?19 (fn -> (in? \z "abcdefghij")) false)
; test with rangelist
(test/exec :in?20 (fn -> (range 20 | filter (in? (range 4 12 3)))) [6 9 12])
(test/exec :in?21 (fn -> (in? \l (range \a \m))) true)
(test/exec :in?22 (fn -> (in? \z (range \a \m))) false)

;-------------------------------------------------------
; Test the 'first' function (first <list> [<number>])
(test/exec :first1  #(first [1 2 3])       1)
(test/exec :rest1   #(rest  [1 2 3 4])     '(2 3 4))
(test/exec :first2  #(first '(1 2 3))      1)
(test/exec :rest2   #(rest  '(1 2 3))      '(2 3))
(test/exec :first3  #(first [1 2 3] 1)     1)
(test/exec :first4  #(first '(1 2 3) 1)    1)
(test/exec :first5  #(first [1 2 3] 2)     [1 2])
(test/exec :first6  #(first '(1 2 3) 2)    '(1 2))
(test/exec :first7  #(first "abcd")        "a")
(test/exec :first8  #(first "abcd" 1)      "a")
(test/exec :first9  #(first "abcd" 2)      "ab")
(test/exec :first10 #(first "abcd" 3)      "abc")
(test/exec :first11 #(first "abcd" 4)      "abcd")
(test/exec :first12 #(first "abcd" 5)      "abcd")
(test/exec :first13 #(first "abcd" 100)    "abcd")
(test/exec :first14 #(first (first "abcd")) "a")
(test/exec :first15 #(first "abcd" | first) "a")
(test/exec :first16 #(first "abcd" 2 | first 2) "ab")
(test/exec :first17 #(first ["abc" "def"] | first) "a")
(test/exec :first18 #(last ["abc" "def"] | first) "d")
(test/exec :first19 #(chars "abcd" | first 3) [\a \b \c])

;-------------------------------------------------------
; Test the 'last' function (last <list> [<number>]]
(test/exec  :last1   #(last '(1 2 3))           3) ; works on lists
(test/exec  :last2   #(last [1 2 3])            3) ; works on vectors
(test/exec  :last3   #(last '(1 2 3 4) 2)       [3 4]) ; always returns multiple items in a ^Vector
(test/exec  :last4   #(last [1 2 3 4] 2)        [3 4])
(test/exec  :last5   #(last 1 1)                1) ; scalar
; test with strings - always returns a string
(test/exec  :last6   #(last "")                 "")
(test/exec  :last7   #(last "abcde")            "e")
(test/exec  :last8   #(last "abcde" 1)          "e")
(test/exec  :last9   #(last "abcde" 2)          "de")
(test/exec  :last10  #(last "abcde" 100)        "abcde")
(test/exec  :last11  #(last null)               null)
(test/exec  :last12  #(last null 10)            null)
(test/exec  :last13  #(last ["abc" "def"] | last) "f")
(test/exec  :last14  #(first ["abc" "def"] | last) "c")
(test/exec  :last15  #(last [1 2 3] | last) 3)

;-------------------------------------------------------
; Test the 'list' function (list args...)
(test/exec  :list1   #(list 1 2 3)              '(1 2 3))
(test/exec  :list2   #(list 1 (+ 2 3) 3)        '(1 5 3))
(test/exec  :list3   #(list 1 '(+ 2 3) 3)       '(1 (+ 2 3) 3))
                                                ; need to cons up the result because Vector != VectorLiteral
(test/exec  :list4   #(list 1 ["a" "b" "c"] 3)  (cons 1 (cons ["a" "b" "c"] (cons 3 nil))))
(test/exec  :list5   #(list 1 ["a" (+ 10 30) "c"] 3)  (cons 1 (cons ["a" 40 "c"] (cons 3 nil))))
(test/exec  :list6   #(list 1 (list 1 2 3) 3)   '(1 (1 2 3) 3))

;-------------------------------------------------------
; The 'append' function - always returns a List
(test/exec :append1  #(append '(1 2 3) '(4 5 6))     '(1 2 3 4 5 6))
(test/exec :append2  #(append '(1 2) 3 '(4 5 6) 7)   '(1 2 3 4 5 6 7))
(test/exec :append3  #(append [1 2 3] 4 '(5 6) [7])  '(1 2 3 4 5 6 7))
(test/exec :append4  #(append [1 2 3] 4 '(5 6) [7] | is? ^List) true)
(test/exec :append5  #(append 1 2 3 4)               '(1 2 3 4))
(test/exec :append6  #(append 1 null 2 nil 3)        '(1 2 3)) ; nulls are discarded
(test/exec :append7  #(append 1 '() 2 '() 3)         '(1 2 3))
(test/exec :append8  #(append 1 [] 2 [] 3)           '(1 2 3))
(test/exec :append9  #(append 1 [[2]] 3)             (list 1 [2] 3))

;-------------------------------------------------------
; the concat function - always returns a Vector
(test/exec :concat1  #(concat [1 2 3] [4 5] [6])     [1 2 3 4 5 6])
(test/exec :concat2  #(concat '(1 2) 3 '(4 5 6) 7)   [1 2 3 4 5 6 7])
(test/exec :concat3  #(concat [1 2 3] 4 '(5 6) [7])  [1 2 3 4 5 6 7])
(test/exec :concat4  #(concat [1 2 3] 4 '(5 6) [7] | is? ^Vector) true)
(test/exec :concat5  #(concat 1 2 3 4)               [1 2 3 4])
(test/exec :concat6  #(concat 1 null 2 nil 3)        [1 2 3]) ; nulls are discarded
(test/exec :concat7  #(concat 1 '() 2 '() 3)         [1 2 3])
(test/exec :concat8  #(concat 1 [] 2 [] 3)           [1 2 3])
(test/exec :concat9  #(concat 1 [[2]] 3)             [1 [2] 3])
; hash tables should be preserved
(test/exec :concat10 #(concat [1 2 3] {:a 1 :b 2})  [1 2 3 {:a 1 :b 2}])
; but not with splatting
(test/exec :concat11 #(concat [1 2 3] @{:a 1 :b 2})  [1 2 3 :a 1 :b 2])

;-------------------------------------------------------
; Test 'nconc' function
(test/exec :nconc1
    (fn ->
        (nconc 1 [2 3])
    )
    [2 3 1]
)
(test/exec :nconc2
    (fn ->
        (nconc 1 [])
    )
    [1]
)
(test/exec :nconc3
    (fn ->
        (nconc 1 null)
    )
    [1]
)
(test/exec :nconc4
    (fn ->
        ; verify that nconc mutates the collection
        (let res [])
        (nconc 2 (nconc 1 res))
        res
    )
    [1 2]
)
(test/exec :nconc5
    (fn ->
        (try (nconc 1 '(2 3 4)) -catch: "exception")
    )
    "exception"
)
(test/exec :nconc6
    (fn ->
        (nconc [4 5] [1 2 3])
    )
    [1 2 3 [4 5]]
)
(test/exec :nconc7
    (fn ->
        (nconc [1 2 3] null)
    )
    [[1 2 3]]
)

;-------------------------------------------------------
; test the add function
(test/exec :add1
    (fn ->
        (add [2 3] 1)
    )
    [2 3 1]
)
(test/exec :add2
    (fn ->
        (add [] 1)
    )
    [1]
)
(test/exec :add3
    (fn ->
        (try (add null 1) -catch: "exception")
    )
    "exception"
)
(test/exec :add4
    (fn ->
        ; verify that add mutates the collection
        (let res [])
        (add res 1 | add 2)
        res
    )
    [1 2]
)
(test/exec :add5
    (fn ->
        (try (add '(2 3 4) 1) -catch: "exception")
    )
    "exception"
)
(test/exec :add6
    (fn ->
        (add [1 2 3] [4 5])
    )
    [1 2 3 [4 5]]
)

;-------------------------------------------------------
; Test vector indexing
(test/exec :vector-indexing1
    (fn ->
        ; the result of an assignment should be
        ; the updated vector not the new value
        ([1 2 3 4 5] | !! 1 20 | !! 3 40)
    )
    [1 20 3 40 5]
)

;-------------------------------------------------------
; The 'flatten' function
(test/exec :flatten1
    (fn ->
        (flatten 3.14)
    )
    [3.14]
)
(test/exec :flatten2
    (fn ->
        (flatten [1 2 3])
    )
    [1 2 3]
)
(test/exec :flatten3
    (fn ->
        (flatten [1 [2 3] 4 [5 6]])
    )
    [1 2 3 4 5 6]
)
(test/exec :flatten4
    (fn ->
        (flatten (list 1 2 3))
    )
    [1 2 3]
)
(test/exec :flatten5
    (fn ->
        (flatten [1 '(2 3) 4 '(5 6)])
    )
    [1 2 3 4 5 6]
)
(test/exec :flatten6
    (fn ->
        ; dictionaries don't get flattened.
        (flatten [1 {:a 2} 3])
    )
    [1 {:a 2} 3]
)

;-------------------------------------------------------
; The 'lazy-flatten' function
(test/exec :lazy-flatten1
    (fn ->
        (lazy-flatten 3.14)
    )
    [3.14]
)
(test/exec :lazy-flatten2
    (fn ->
        (lazy-flatten [1 2 3])
    )
    [1 2 3]
)
(test/exec :lazy-flatten3
    (fn ->
        (lazy-flatten [1 [2 3] 4 [5 6]])
    )
    [1 2 3 4 5 6]
)
(test/exec :lazy-flatten4
    (fn ->
        (lazy-flatten (list 1 2 3))
    )
    [1 2 3]
)
(test/exec :lazy-flatten5
    (fn ->
        (lazy-flatten [1 '(2 3) 4 '(5 6)])
    )
    [1 2 3 4 5 6]
)
(test/exec :lazy-flatten6
    (fn ->
        ; dictionaries don't get flattened.
        (lazy-flatten [1 {:a 2} 3])
    )
    [1 {:a 2} 3]
)

;-------------------------------------------------------
; The 'take' function
(test/exec :take1a  #(take [1 2 3 4 5 6] 3)   [1 2 3])
(test/exec :take1b  #(take [1 2 3 4 5 6] 0)   [])
(test/exec :take1c  #(take [1 2 3 4 5 6] 1)   [1])
(test/exec :take3  #([] | take 0)            [])
(test/exec :take3a  #([] | take 5)            [])
(test/exec :take5   #(null | take 5)          [])
(test/exec :take5a  #(null | take 0)          [])
(test/exec :take7   #(12 | take 1)            [12])
(test/exec :take8   #(12 | take 5)            [12])
(test/exec :take9   #([1 2 3] | take 20)      [1 2 3])
(test/exec :take10  #(take [1 2 3 4 5] -1)    [1 2 3 4]) ; test negative indexing
(test/exec :take11  #(take [1 2 3 4 5] -2)    [1 2 3])
(test/exec :take12  #(take [1 2 3 4 5] -3)    [1 2])
(test/exec :take13  #(take [1 2 3 4 5] -4)    [1])
(test/exec :take14  #(take [1 2 3 4 5] -5)    [])
(test/exec :take15  #(take [1 2 3 4 5] -6)    [])
(test/exec :take16  #(take '(1 2 3 4 5) -1)   [1 2 3 4])
(test/exec :take17  #(take '(1 2 3 4 5) -2)   [1 2 3])
(test/exec :take18  #(take '(1 2 3 4 5) -3)   [1 2])
(test/exec :take19  #(take '(1 2 3 4 5) -4)   [1])
(test/exec :take20  #(take '(1 2 3 4 5) -5)   [])
(test/exec :take21  #(take '(1 2 3 4 5) -6)   [])
(test/exec :take22  #([1 2 3 4 5] | take  -1) [1 2 3 4])
(test/exec :take23  #(list 1 2 3 4 5 | take -1) [1 2 3 4])
(test/exec :take24  #(range 5 | take 3)       [1 2 3])
(test/exec :take25  #(range 5 | take -3)      [1 2])
(test/exec :take26  #(range 5 1 | take -3)    [5 4])

;-------------------------------------------------------
; the 'take-after' function
(test/exec :take-after1
    (fn ->
        ; test with value
        (range 10 | take-after 5)
    )
    [6 7 8 9 10]
)
(test/exec :take-after2
    (fn ->
        ; test with lambda
        (range 10 | take-after  #(== %0 6))
    )
    [7 8 9 10]
)

;-------------------------------------------------------
; the 'take-until' function
(test/exec :take-until1
    (fn ->
        ; test with value
        (range 10 | take-until 5)
    )
    [1 2 3 4]
)
(test/exec :take-until2
    (fn ->
        ; test with lambda
        (range 10 | take-until  #(== %0 5))
    )
    [1 2 3 4]
)

;-------------------------------------------------------
; the 'skip' function
(test/exec :skip1a
    (fn ->
        (skip [] 0)
    )
    []
)
(test/exec :skip1b
    (fn ->
        (skip [] 1)
    )
    []
)
(test/exec :skip1c
    (fn ->
        (skip [1 2 3 4 5] 0)
    )
    [1 2 3 4 5]
)
(test/exec :skip1d
    (fn ->
        (skip [1 2 3 4 5] 1)
    )
    [2 3 4 5]
)
(test/exec :skip1e
    (fn ->
        (skip [1 2 3 4 5] 2)
    )
    [3 4 5]
)
(test/exec :skip2
    (fn ->
        ([1 2 3 4 5] | skip 2)
    )
    [3 4 5]
)
(test/exec :skip3
    (fn ->
        (skip '(1 2 3 4 5) 3)
    )
    [4 5]
)
(test/exec :skip4
    (fn ->
        (skip '(1 2 3 4 5) 4)
    )
    [5]
)
(test/exec :skip5
    (fn ->
        (skip '(1 2 3 4 5) 5)
    )
    []
)
(test/exec :skip6
    (fn ->
        (skip '(1 2 3 4 5) 6)
    )
    []
)
(test/exec :skip7
    (fn ->
        (skip '(1 2 3 4 5) 2 | is? ^IEnumerable)
    )
    true
)
(test/exec :skip7a
    (fn ->
        (skip [1 2 3 4 5] 2 | is? ^Slice)
    )
    true
)
(test/exec :skip8
    (fn ->
        ; skip the whole vector should return []
        (skip [1 2 3 4 5 6 7 8] 8)
    )
    []
)
(test/exec :skip8a
    (fn ->
        ([1 2 3 4 5 6 7 8] | skip 8)
    )
    []
)
(test/exec :skip9
    (fn ->
        ; skip the whole vector should return []
        (skip [1 2 3 4 5 6 7 8] 9)
    )
    []
)
(test/exec :skip9a
    (fn ->
        ([1 2 3 4 5 6 7 8] | skip 8)
    )
    []
)
(test/exec :skip10
    (fn ->
        ; skip the whole vector should return []
        (skip [1 2 3 4 5 6 7 8] 100)
    )
    []
)
(test/exec :skip10a
    (fn ->
        ([1 2 3 4 5 6 7 8] | skip 100)
    )
    []
)
(test/exec :skip11
    (fn ->
        (vlet data [1 2 3 4 5 6 7])
        (let result [])
        (while data
            (let cnt (^int (data 0)))
            (.add result (take data cnt | join))
            (let data (skip data cnt))
        )
        result
    )
    ["1", "2 3", "4 5 6 7"]
)

;-------------------------------------------------------
; the 'skip-while' function
(test/exec :skip-while1
    (fn ->
        (skip-while [1 2 3 4 5] (fn n -> (!= (% n 3) 0)))
    )
    [3 4 5]
)
(test/exec :skip-while2
    (fn ->
        (skip-while [:a :bb :ccc :dd :e] (fn s -> (< (.length (tostring s)) 3)))
    )
    [:ccc :dd :e]
)
(test/exec :skip-while3
    (fn ->
        ; use implicit curry of <
        (skip-while [1 2 3 4 5 6] (< 4))
    )
    [4 5 6]
)

;-------------------------------------------------------
; the 'swap' function
(test/exec :swap1
    (fn ->
        ; swap variables
        (let a 1)
        (let b 2)
        (swap a b)
        [a b]
    )
    [2 1]
)
(test/exec :swap1a
    (fn ->
        ; swap variables with a comparison function
        (let a 1)
        (let b 2)
        (swap a b <)
        [a b]
    )
    [2 1]
)
(test/exec :swap1b
    (fn ->
        ; swap variables
        (let a 1)
        (let b 2)
        (swap a b >)
        [a b]
    )
    [1 2]
)
(test/exec :swap1c
    (fn ->
        ; swap variables
        (let a 1)
        (let b 2)
        (swap a b (fn x y -> (< x y)))
        [a b]
    )
    [2 1]
)
(test/exec :swap2
    (fn ->
        ; swap vector elements
        (let x [10 20])
        (swap x 0 x 1)
        x
    )
    [20 10]
)
(test/exec :swap2a
    (fn ->
        ; swap vector elements
        (let x [10 20])
        (swap x 0 x 1 <)
        x
    )
    [20 10]
)
(test/exec :swap2b
    (fn ->
        ; swap vector elements
        (let x [10 20])
        (swap x 0 x 1 >)
        x
    )
    [10 20]
)
(test/exec :swap2c
    (fn ->
        ; swap vector elements
        (let x [10 20])
        (swap x 0 x 1  #(< %0 %1))
        x
    )
    [20 10]
)
(test/exec :swap3
    (fn ->
        ; itterative in-place list reverse
        (defn irev [lst]
            (let sp 0)
            (let ep (- (count lst) 1))
            (while (!= sp ep)
                (swap lst sp lst ep)
                (incr sp)
                (decr ep)
            )
            lst
        )
        (irev [1 2 3 4 5])
    )
    [5 4 3 2 1]
)
(test/exec :swap4
    (fn ->
        ; bubble sort function
        (defn bub
            "Sort a vector of elements in-place (mutates the argument vector.)"
            [(^vector? data)]

            (foreach cnt (range (length data) 2)
                (foreach it (range 0 (- cnt 2))
                    (swap data it data (++ it) >)
                )
            )

            data
        )
        (bub [6 9 8 1 3 5 2 4 7])
    )
    [1 2 3 4 5 6 7 8 9]
)

;-------------------------------------------------------
; the str function
(test/exec :str1
    (fn ->
        (str "a" "b" "c")
    )
    "abc"
)
(test/exec :str2
    (fn ->
        (str 1 2 3)
    )
    "123"
)
(test/exec :str3
    (fn ->
        (str "a" 1 "b" 2)
    )
    "a1b2"
)


;-------------------------------------------------------
; the chars function
(test/exec :chars1
    (fn ->
        (str @("hello" | chars | reverse))
    )
    "olleh"
)
(test/exec :chars2
    (fn ->
        (chars "hello" | type-of)
    )
    ^vector
)


;-------------------------------------------------------
; the sort function
(test/exec :sort1
    (fn ->
        (sort [2 4 1 6 5 8 7 9 3])
    )
    [1 2 3 4 5 6 7 8 9]
)
(test/exec :sort2
    (fn ->
        (sort -descending [2 4 1 6 5 8 7 9 3])
    )
    [9 8 7 6 5 4 3 2 1]
)
; test with a predicate: '-' (subtraction) forces a descending sort
(test/exec :sort3
    (fn ->
        ([2 4 1 6 5 8 7 9 3] | sort (fn n -> (- 0 n)))
    )
    [9 8 7 6 5 4 3 2 1]
)
(test/exec :sort4
    (fn ->
        (sort [2 4 1 6 5 8 7 9 3] neg)
    )
    [9 8 7 6 5 4 3 2 1]
)
(test/exec :sort5
    (fn ->
        ([2 4 1 6 3 5 8 7 9] | sort (% 2)) ; sort into even and odd with curried '%'
    )
    [2 4 6 8 1 3 5 7 9]
)
; sort by property - can't check the actual value against anything known
; so we just make sure there wasn't an exception.
(test/exec :sort6
    (fn ->
        (try (get-process | sort .ws) | map echo | isnot? ^exception)
    )
    true
)

;-------------------------------------------------------
; the thenSort function
(test/exec :thenSort1
    (fn ->
        ([[2 "c"] [3 "b"] [3 "a"] [1 "a"] [2 "b"] [2 "a"]] | sort ($ (!! 0)) | thenSort ($ (!! 1)))
    )
    [
      [1 "a"]
      [2 "a"]
      [2 "b"]
      [2 "c"]
      [3 "a"]
      [3 "b"]
    ]
)
(test/exec :thenSort2
    (fn ->
        ([[2 "c"] [3 "b"] [3 "a"] [1 "a"] [2 "b"] [2 "a"]] | sort ($ (!! 0)) | thenSort -descending ($ (!! 1)))
    )
    [
      [1 "a"]
      [2 "c"]
      [2 "b"]
      [2 "a"]
      [3 "b"]
      [3 "a"]
    ]
)
(test/exec :thenSort3
    (fn ->
        ([[2 "c"] [3 "b"] [3 "a"] [1 "a"] [2 "b"] [2 "a"]] | sort -descending ($ (!! 0)) | thenSort ($ (!! 1)))
    )
    [
      [3 "a"]
      [3 "b"]
      [2 "a"]
      [2 "b"]
      [2 "c"]
      [1 "a"]
    ]
)
(test/exec :thenSort4
    (fn ->
        ([[2 "c"] [3 "b"] [3 "a"] [1 "a"] [2 "b"] [2 "a"]] | sort -descending ($ (!! 0)) | thenSort -descending ($ (!! 1)))
    )
    [
      [3 "b"]
      [3 "a"]
      [2 "c"]
      [2 "b"]
      [2 "a"]
      [1 "a"]
    ]
)

;-------------------------------------------------------
; the lazy sort function
(test/exec :lazy-sort1
    (fn ->
        (lazy-sort [2 4 1 6 5 8 7 9 3])
    )
    [1 2 3 4 5 6 7 8 9]
)
(test/exec :lazy-sort2
    (fn ->
        (lazy-sort [2 4 1 6 5 8 7 9 3] | is? ^System.Linq.IOrderedEnumerable[System.Object])
    )
    true
)
(test/exec :lazy-sort3
    (fn ->
        (let result 0)
        ; call lazy-sort with a lambda that increments result as a side effect.
        (let e (range 10 | lazy-sort (fn n -> (incr result) n)))
        ; result should still be zero since the enumeration has not been run yet.
        (let x1 result)
        ; run the enumeration
        (drain e)
        [x1 result]
    )
    [0 10]
)
(test/exec :lazy-sort4
    (fn ->
        (let numitems 0)
        ; call lazy-sort with a lambda that increments result as a side effect.
        ; combined with other lazy functions.
        (let e (range 10 | lazy-sort (fn n -> (incr numitems) n) | lazy-filter (% 2) | lazy-map ++))
        ; result should still be zero since the enumeration has not been run yet.
        (let x1 numitems)
        ; run the enumeration
        (let result (to-vector e))
        [x1 numitems result]
    )
    [0 10 [2 4 6 8 10]]
)
(test/exec :lazy-sort5
    (fn ->
        (lazy-sort -descending [2 4 1 6 5 8 7 9 3])
    )
    [9 8 7 6 5 4 3 2 1]
)
; test with a predicate: '-' (subtraction) forces a descending sort
(test/exec :lazy-sort6
    (fn ->
        ([2 4 1 6 5 8 7 9 3] | lazy-sort (fn n -> (- 0 n)))
    )
    [9 8 7 6 5 4 3 2 1]
)
(test/exec :lazy-sort7
    (fn ->
        (lazy-sort [2 4 1 6 5 8 7 9 3] neg)
    )
    [9 8 7 6 5 4 3 2 1]
)
(test/exec :lazy-sort8
    (fn ->
        ([2 4 1 6 3 5 8 7 9] | lazy-sort (% 2)) ; sort into even and odd with curried '%'
    )
    [2 4 6 8 1 3 5 7 9]
)
; sort by property - can't check the actual value against anything known
; so we just make sure there wasn't an exception.
(test/exec :lazy-sort9
    (fn ->
        (try (get-process | lazy-sort .ws) | map echo | is? ^exception)
    )
    false
)

;-------------------------------------------------------
; the end-user "qsort" function defined in autoload.tl
(test/exec :qsort1
    (fn ->
        (qsort [2 4 1 6 5 8 7 9 3])
    )
    [1 2 3 4 5 6 7 8 9]
)
(test/exec :qsort2
    (fn ->
        ; piped version
        ([2 4 1 6 5 8 7 9 3] | qsort)
    )
    [1 2 3 4 5 6 7 8 9]
)
(test/exec :qsort3
    (fn ->
        (let data (random 100))
        (== (qsort data) (sort data))
    )
    true
)
(test/exec :qsort4
    (fn ->
        (qsort [])
    )
    nil
)
(test/exec :qsort5
    (fn ->
        ([] | qsort)
    )
    nil
)
(test/exec :qsort6
    (fn ->
        (qsort nil)
    )
    nil
)
(test/exec :qsort7
    (fn ->
        (nil | qsort)
    )
    nil
)
(test/exec :qsort8
    (fn ->
        ; sort the chars in a string
        ("Hello world" | chars | qsort | join "")
    )
    " Hdellloorw"
)

;-----------------------------------------------------
; test the 'tokenize-file' function
(test/exec :tokenize-file1
    (fn ->
        ; Count the number of comments in the 'autoload.tl' file.
        ; There should be more than 100.
        ( tokenize-file (file/join-path braidhome "autoload.tl")
        | where (fn t -> (== (.type t) .BraidLang.TokenType/Comment))
        | count | > 100
        )
    )
    true
)

;-----------------------------------------------------
; test 'gen-symbol' function - always generates a distinct symbol
(test/exec :gen-symbol1
    (fn ->
        (symbol? (gen-symbol))
    )
    true
)
(test/exec :gen-symbol2
    (fn ->
        (!= (gen-symbol) (gen-symbol))
    )
    true
)
(test/exec :gen-symbol3
    (fn ->
        (gen-symbol | is? ^symbol)
    )
    true
)

;-------------------------------------------------------
; test the 'symbol' function - gets existing symbol or creates a new one.
(test/exec :symbol1
    (fn ->
        (symbol "_foo_bar_baz_" | is? ^symbol)
    )
    true
)
(test/exec :symbol2
    (fn ->
        (==
            (symbol "_foo_bar_baz_")
            (symbol "_foo_bar_baz_"))
    )
    true
)

;--------------------------------------------------------
; Test the 'get-symbol' function which retrieves existing symbols but doesn't create new ones
(test/exec :get-symbol1
    (fn -> (get-symbol "get-symbol" | some?))
    true
)
(test/exec :get-symbol2
    ; test a symbol that doesn't exist - very small chance of collision here...
    (fn -> (get-symbol (str "sym-" (random 1 1_000_000 2_000_000)) | none?))
    true
)

;-------------------------------------------------------
; test the 'keyword' function - gets existing keyword or creates a new one.
(test/exec :keyword1
    (fn ->
        (keyword "_foo_bar_baz_" | is? ^Keyword)
    )
    true
)
(test/exec :keyword2
    (fn ->
        (==
            (keyword "_foo_bar_baz_")
            (keyword "_foo_bar_baz_"))
    )
    true
)

;-------------------------------------------------------
; test the 'do' function
(test/exec :do1 #(do 1 2 3) 3)
(test/exec :do2 #(do 1 2 [3 4]) [3 4])
(test/exec :do3
    (fn ->
        (let x 1)
        (let y 2)
        (let z 3)
        (let zz (do (def x 10) (def y 20) (def z 30) [1 2 3]))
        [x y z zz]
    )
    [10 20 30 [1 2 3]]
)

;-------------------------------------------------------
; test the 'distinct' function
(test/exec :distinct1  #([1 1 2 2 3 3 4 4] | distinct) [1 2 3 4])
(test/exec :distinct2  #(["a" "a" "b" "c" "c" "b"] | distinct) ["a" "b" "c"])
(test/exec :distinct3  #(["a" 2  "a"  "c" 2 "c" 2] | distinct) ["a" 2 "c"])
; distinct doesn't sort so test out-of-order characters
(test/exec :distinct4  #([2 2 1 2 3 1 1 2 4 2 4 3 4 3 4] | distinct | sort) [1 2 3 4])
(test/exec :distinct5
    (fn ->
        ; test using a predicate compare function
        (let data [{:a 1 :b 1} {:a 2 :b 2} {:a 2 :b 3}])
        (distinct data (fn h -> (:a h)))
    )
    [{:a 1 :b 1} {:a 2 :b 2}]
)

;-------------------------------------------------------
; Test the union function
(test/exec :union1  #([1 3 5 6] | union [2 4 6] | sort) [1 2 3 4 5 6])
(test/exec :union2  #([] | union [2 4 6] | sort) [2 4 6])
(test/exec :union3  #([1 3 5 6] | union [] | sort) [1 3 5 6])
(test/exec :union4  #([1 3] | union [ 4 6] | sort) [1 3 4 6])

;-------------------------------------------------------
; Test the intersection function
(test/exec :intersect1  #([1 2 3 4] | intersect [3 4 5]) [3 4])
(test/exec :intersect2  #([1 2 3] | intersect [4 5 6]) [])

;-------------------------------------------------------
; Test the except function
(test/exec :except1  #([1 2 3 4 5 6] | except [3 4 5]) [1 2 6])
(test/exec :except2  #([1 2 3] | except [4 5 6]) [1 2 3])
(test/exec :except3  #([1 2 3 4 5 6 7 8] | except [2 4 6]) [1 3 5 7 8])
(test/exec :except4  #(range 10 | except (range 2 9)) [1 10])

;-------------------------------------------------------
; Tests the range function
(test/exec :range1  #(range 5)                   [1 2 3 4 5])
(test/exec :range2  #(range 2 5)                 [2 3 4 5])
(test/exec :range3  #(range 0 5 2 | to-vector)   [0 2 4])
(test/exec :range4  #(range 5 0   | to-vector)   [5 4 3 2 1 0])
(test/exec :range5  #(range 5 0 2 | to-vector)   [5 3 1])
(test/exec :range6  #(range -5 -1)               [-5 -4 -3 -2 -1])
(test/exec :range7  #(range -3 3)                [-3 -2 -1 0 1 2 3])
(test/exec :range8  #(range (^int? \a) (^int? \z) | map ^char? | join "") "abcdefghijklmnopqrstuvwxyz")

;-------------------------------------------------------
; basic test of the filter function - get even numbers
(test/exec :filter1  #(range 10 | filter (fn it -> (== (% it 2) 0))) [2 4 6 8 10])
(test/exec :where1   #(range 10 | where  (fn it -> (== (% it 2) 0))) [2 4 6 8 10])
(test/exec :filter2  #(range 10 | filter -not (fn it -> (== (% it 2) 0))) [1 3 5 7 9])
(test/exec :where2   #(range 10 | where  -not (fn it -> (== (% it 2) 0))) [1 3 5 7 9])
; even numbers using the builtin predicate
(test/exec :filter3  #(range 10 | filter even?) [2 4 6 8 10])
(test/exec :filter4  #(range 10 | filter -not even?) [1 3 5 7 9])
; filtering by type
(test/exec :filter5  #([1 "two" 3 "four"] | filter ^int) [1 3])
(test/exec :filter6  #([1 "two" 3 "four"] | filter -not ^int) ["two" "four"])
(test/exec :filter7  #([1 "two" 3 "four"] | filter ^string) ["two" "four"])
(test/exec :filter8  #([1 "two" 3 "four"] | filter -not ^string) [1 3])
; filtering by regex
(test/exec :filter9  #(range 20 | filter #"2") [2 12 20])
(test/exec :filter10  #(range 5 | filter -not #"2") [1 3 4 5])
; filter with a property
(test/exec :filter11  #(["" "a" "" "b"] | filter .length) ["a" "b"])
(test/exec :filter12  #(["" "a" "" "b"] | filter -not .length) ["" ""])
; filter with keyword property names on dictionaries
(test/exec :filter13
    (fn ->
        ([{:a 1 :b 2} {:a 0 :b 3} {:a 1 :b 4} {:a 0 :b 5}] | filter :a)
    )
    [{:a 1 :b 2} {:a 1 :b 4}]
)
(test/exec :filter14
    (fn ->
        ([{:a 1 :b 2} {:a 0 :b 3} {:a 1 :b 4} {:a 0 :b 5}] | filter -not :a)
    )
    [{:a 0 :b 3} {:a 0 :b 5}]
)
; filter with user function
(test/exec :filter15
    (fn ->
        (defn mod3 | n -> (% n 3))
        (range 10 | filter mod3)
    )
    [1, 2, 4, 5, 7, 8, 10]
)
(test/exec :filter16
    (fn ->
        (defn mod3 | n -> (% n 3))
        (range 10 | filter -not mod3)
    )
    [3 6 9]
)
; filter with curried functions
(test/exec :filter17
    (fn ->
        (range 10 | filter (% 3))
    )
    [1, 2, 4, 5, 7, 8, 10]
)
(test/exec :filter18
    (fn ->
        (range 10 | filter -not (% 3))
    )
    [3 6 9]
)
; filtering by type but not using a type literal
(test/exec :filter19
    (fn ->
        (let iv ^int)
        ([1 "two" 3 "four"] | filter iv)
    )
    [1 3]
)
(test/exec :filter20
    (fn ->
        (let iv ^int)
        ([1 "two" 3 "four"] | filter -not iv)
    )
    ["two" "four"]
)
; filtering by predicate but not using a lambda literal
(test/exec :filter21
    (fn ->
        (def p (fn v -> (is? v ^int)))
        ([1 "two" 3 "four"] | filter p)
    )
    [1 3]
)
(test/exec :filter22
    (fn ->
        (def p (fn v -> (is? v ^int)))
        ([1 "two" 3 "four"] | filter -not p)
    )
    ["two" "four"]
)
; filter with regex stored in a variable.
(test/exec :filter23
    (fn ->
        (let r  #"2")
        (range 20 | filter r)
    )
    [2 12 20]
)
(test/exec :filter24
    (fn ->
        (let r  #"2")
        (range 5 | filter -not r)
    )
    [1 3 4 5]
)
(test/exec :filter25
    (fn ->
        ; test filtering with literals - in this case, for anagrams
        (==
            (chars "parliament" | sort)
            (chars "partial men" | filter -not \space  | sort)
        )
    )
    true
)
(test/exec :filter26
    (fn ->
        ([1 2 3 2 3 4 3 4 5] | filter 3)
    )
    [3 3 3]
)
(test/exec :filter27
    (fn ->
        (re/split "one two three" | filter "two")
    )
    [ "two" ]
)
(test/exec :filter28
    (fn ->
        (null | filter 3)
    )
    null
)
(test/exec :filter30
    (fn ->
        ([1 null 2 null 3 null 4]  | filter null)
    )
    [null null null]
)
(test/exec :filter31
    (fn ->
        (["a" null "b" "" "" "c"] | filter -not .string/isNullOrEmpty)
    )
    ["a" "b" "c"]
)
(test/exec :filter32
    (fn ->
        ; test use of break in filter - stops at (and returns) 5.
        (range 10 | filter -not (fn n -> (if (== n 5) (break)) (% n 2)))
    )
    [2 4 5]
)
(test/exec :filter33
    (fn ->
        ; test use of break in filter - stops at (and returns) 6.
        (range 10 | filter -not (fn n -> (if (== n 6) (break)) (% n 2)))
    )
    [2 4 6]
)
(test/exec :filter34
    (fn ->
        ; test continue in filter - skips 
        (range 10 | filter -not (fn n -> (if (== n 6) (continue)) (% n 2)))
    )
    [2 4 8 10]
)
(test/exec :filter35
    (fn ->
        (range 1000 | filter (fn n -> (if (== n 99) (break))) | first)
    )
    99
)

;-------------------------------------------------------
; basic test of the lazy-filter function - get even numbers
(test/exec :lazy-filter1  #(range 10 | lazy-filter (fn it -> (== (% it 2) 0))) [2 4 6 8 10])
(test/exec :lazy-filter2  #(range 10 | lazy-filter -not (fn it -> (== (% it 2) 0))) [1 3 5 7 9])
; even numbers using the builtin predicate
(test/exec :lazy-filter3  #(range 10 | lazy-filter even?) [2 4 6 8 10])
(test/exec :lazy-filter4  #(range 10 | lazy-filter -not even?) [1 3 5 7 9])
; lazy-filtering by type
(test/exec :lazy-filter5  #([1 "two" 3 "four"] | lazy-filter ^int) [1 3])
(test/exec :lazy-filter6  #([1 "two" 3 "four"] | lazy-filter -not ^int) ["two" "four"])
(test/exec :lazy-filter7  #([1 "two" 3 "four"] | lazy-filter ^string) ["two" "four"])
(test/exec :lazy-filter8  #([1 "two" 3 "four"] | lazy-filter -not ^string) [1 3])
; lazy-filtering by regex
(test/exec :lazy-filter9  #(range 20 | lazy-filter #"2") [2 12 20])
(test/exec :lazy-filter10  #(range 5 | lazy-filter -not #"2") [1 3 4 5])
; lazy-filter with a property
(test/exec :lazy-filter11  #(["" "a" "" "b"] | lazy-filter .length) ["a" "b"])
(test/exec :lazy-filter12  #(["" "a" "" "b"] | lazy-filter -not .length) ["" ""])
; lazy-filter with keyword property names on dictionaries
(test/exec :lazy-filter13
    (fn ->
        ([{:a 1 :b 2} {:a 0 :b 3} {:a 1 :b 4} {:a 0 :b 5}] | lazy-filter :a)
    )
    [{:a 1 :b 2} {:a 1 :b 4}]
)
(test/exec :lazy-filter14
    (fn ->
        ([{:a 1 :b 2} {:a 0 :b 3} {:a 1 :b 4} {:a 0 :b 5}] | lazy-filter -not :a)
    )
    [{:a 0 :b 3} {:a 0 :b 5}]
)
; lazy-filter with user function
(test/exec :lazy-filter15
    (fn ->
        (defn mod3 | n -> (% n 3))
        (range 10 | lazy-filter mod3)
    )
    [1, 2, 4, 5, 7, 8, 10]
)
(test/exec :lazy-filter16
    (fn ->
        (defn mod3 | n -> (% n 3))
        (range 10 | lazy-filter -not mod3)
    )
    [3 6 9]
)
; lazy-filter with partial functions
(test/exec :lazy-filter17
    (fn ->
        (range 10 | lazy-filter (% 3))
    )
    [1, 2, 4, 5, 7, 8, 10]
)
(test/exec :lazy-filter18
    (fn ->
        (range 10 | lazy-filter -not (% 3))
    )
    [3 6 9]
)
; lazy-filtering by type but not using a type literal
(test/exec :lazy-filter19
    (fn ->
        (let iv ^int)
        ([1 "two" 3 "four"] | lazy-filter iv)
    )
    [1 3]
)
(test/exec :lazy-filter20
    (fn ->
        (let iv ^int)
        ([1 "two" 3 "four"] | lazy-filter -not iv)
    )
    ["two" "four"]
)
; lazy-filtering by predicate but not using a lambda literal
(test/exec :lazy-filter21
    (fn ->
        (def p (fn v -> (is? v ^int)))
        ([1 "two" 3 "four"] | lazy-filter p)
    )
    [1 3]
)
(test/exec :lazy-filter22
    (fn ->
        (def p (fn v -> (is? v ^int)))
        ([1 "two" 3 "four"] | lazy-filter -not p)
    )
    ["two" "four"]
)
; lazy-filter with regex stored in a variable.
(test/exec :lazy-filter23
    (fn ->
        (let r  #"2")
        (range 20 | lazy-filter r)
    )
    [2 12 20]
)
(test/exec :lazy-filter24
    (fn ->
        (let r  #"2")
        (range 5 | lazy-filter -not r)
    )
    [1 3 4 5]
)
(test/exec :lazy-filter25
    (fn ->
        (["a" null "b" "" "" "c"] | lazy-filter -not .string/isNullOrEmpty)
    )
    ["a" "b" "c"]
)
(test/exec :lazy-filter30
    (fn ->
        ; test use of break in filter - stops at (and returns) 6.
        (range 10 | lazy-filter -not (fn n -> (if (== n 6) (break)) (% n 2)) | to-vector)
    )
    [2 4 6]
)
(test/exec :lazy-filter30a
    (fn ->
        ; test use of break in filter - stops at (and returns) 6.
        (range 10 | lazy-filter -not (fn n -> (if (== n 5) (break)) (% n 2)) | to-vector)
    )
    [2 4 5]
)
(test/exec :lazy-filter31
    (fn ->
        ; test continue in filter - skips 
        (range 10 | lazy-filter -not (fn n -> (if (== n 6) (continue)) (% n 2)) | to-vector)
    )
    [2 4 8 10]
)
(test/exec :lazy-filter32
    (fn ->
        (range 1000 | lazy-filter (fn n -> (if (== n 99) (break))) | first)
    )
    99
)

;-------------------------------------------------------
; test the map function
(test/exec :map1
    #(range 6 | map (fn it -> (* it 2)))
    [2 4 6 8 10 12]
)
(test/exec :map1a
    #(range 6 | lazy-map (fn it -> (* it 2)))
    [2 4 6 8 10 12]
)
(test/exec :->>1
    #(->> (range 6) (map (fn it -> (* it 2))))
    [2 4 6 8 10 12]
)
(test/exec :pipe1
    #(pipe (range 6) (map (fn it -> (* it 2))))
    [2 4 6 8 10 12]
)
(test/exec :map2a  #([1 2] | map ^string?) ["1" "2"])
(test/exec :map2b  #(map [1 2] ^string?) ["1" "2"])
(test/exec :map2c
    (fn ->
        (let r (["123" 1i 3.14] | map ^int?))
        (and
            (== r [123 1 3])
            (is? (r 0) ^int)
            (is? (r 1) ^int)
            (is? (r 2) ^int)
        )
    )
    true
)

(test/exec :map3  #(["a" "aa" "aaa"] | map .length) [1 2 3])

(test/exec :map4
    (fn ->
        ([{:a 1 :b 2} {:a 10 :b 20} {:a 100 :b 200}] | map :a)
    )
    [1 10 100]
)
(test/exec :map5
    (fn ->
        (map [{:a 1 :b 2} {:a 10 :b 20} {:a 100 :b 200}] :a)
    )
    [1 10 100]
)
(test/exec :map6
    (fn ->
        ([{:a 1 :b 2} {:a 10 :b 20} {:a 100 :b 200}] | map :b)
    )
    [2 20 200]
)
(test/exec :map7
    (fn ->
        (map [{:a 1 :b 2} {:a 10 :b 20} {:a 100 :b 200}] :b)
    )
    [2 20 200]
)
(test/exec :map8
    (fn ->
        ([{:a 1 :b 2} {:b 20} {:a 100 :b 200}] | map :a)
    )
    [1 nil 100]
)
(test/exec :map9
    (fn ->
        (map [{:a 1 :b 2} {:b 20} {:a 100 :b 200}] :a)
    )
    [1 nil 100]
)
(test/exec :map10
    (fn ->
        ([{:a 1 :b 2} {:b 20} {:a 100 :b 200}] | map :b)
    )
    [2 20 200]
)
(test/exec :map11
    (fn ->
        ([{:a 1 :b 2} {:b 20} {:a 100 :b 200}] | map :c)
    )
    [nil nil nil]
)
(test/exec :map12
    (fn ->
        ([] | map :b)
    )
    null
)
(test/exec :pipe13
    ; make pipeline data is not double-evaluated
    ; because map is a special form
    (fn -> (['(+ 2 3) '(+ 4 5) '(- 10)] | map (fn x -> x)))
    ['(+ 2 3) '(+ 4 5) '(- 10)]
)
; regex as a function - converts the args to matches
(test/exec :map15
    (fn ->
        ([:a :b :ab :bb :c :ca :ac] | map  #"a")
    )
    ["a" nil "ab" nil nil "ca" "ac"]
)
(test/exec :map16
    (fn ->
        (map [:a :b :ab :bb :c :ca :ac]  #"a")
    )
    ["a" nil "ab" nil nil "ca" "ac"]
)

(test/exec :map20
    (fn ->
        (defn foo [n] (* n 2))
        (range 5 | map foo)
    )
    [2 4 6 8 10]
)
(test/exec :map21
    (fn ->
        (defn foo [n] (* n 2))
        ; call function named by a string
        (range 5 | map "foo")
    )
    [2 4 6 8 10]
)
(test/exec :map22
    (fn ->
        ; destructuring key/value pairs
        ({:a 1 :b 2 :c 3}
        | map (fn key:value: ->
                "key: ${key} value: ${value}"
            )
        )
    )
    [
        "key: a value: 1"
        "key: b value: 2"
        "key: c value: 3"
    ]
)
(test/exec :map23
    (fn ->
        ; verify assignment returns the collection not the member value
        ({} | !! :a 1 | !! :b 2 | !! :c 3)
    )
    {:a 1 :b 2 :c 3}
)
(test/exec :map24
    (fn ->
        ; test patterns using the 'fn' macro.
        (range 10 | map (fn | (% 2) -> "odd" | -> "even"))
    )
    ["odd" "even" "odd" "even" "odd" "even" "odd" "even" "odd" "even"]
)
(test/exec :map24a
    (fn ->
        ; test patterns using 'lambda'.
        (range 10 | map (lambda | (% 2) -> "odd" | -> "even"))
    )
    ["odd" "even" "odd" "even" "odd" "even" "odd" "even" "odd" "even"]
)
(test/exec :map24b
    (fn ->
        ; test patterns using an s-expression
        (range 10 | map (fn | (% %0 2) -> "odd" | -> "even"))
    )
    ["odd" "even" "odd" "even" "odd" "even" "odd" "even" "odd" "even"]
)
(test/exec :map24c
    (fn ->
        ; test patterns using  #(...) dispatch expression
        (range 10 | map (fn |  #(% %0 2) -> "odd" | -> "even"))
    )
    ["odd" "even" "odd" "even" "odd" "even" "odd" "even" "odd" "even"]
)
(test/exec :map25
    (fn ->
        ; use a dictionary as a mapping function
        ([1 2 3] | map {1 :a 2 :b 3 :c})
    )
    ["a" "b" "c"]
)
(test/exec :map25a
    (fn ->
        ; try different order
        ([3 1] | map {1 :a 2 :b 3 :c})
    )
    ["c" "a"]
)
(test/exec :map25b
    (fn ->
        ; misses return null
        ([30 1] | map {1 :a 2 :b 3 :c})
    )
    [null "a"]
)
(test/exec :map26
    (fn ->
        ; use a vector as a mapping function
        ([0 2] | map ["one" "two" "three" "four"])
    )
    ["one" "three"]
)
(test/exec :map26a
    (fn ->
        ; use a vector as a mapping function
        ([3 1] | map ["one" "two" "three" "four"])
    )
    ["four" "two"]
)
(test/exec :map27
    (fn ->
        ; test continue in map lambda - doesn't add on continue
         (range 10 | map (fn n -> (if (% n 2) (continue) n)))
    )
    [2 4 6 8 10]
)
(test/exec :map27a
    (fn ->
        ; test without continue in map lambda - adds nil as default.
         (range 10 | map (fn n -> (if (% n 2) n)))
    )
    [1 nil 3 nil 5 nil 7 nil 9 nil]
)

;-------------------------------------------------------
; test the lazy map (lazy-map) function
(test/exec :lazy-map1
(range 6 | lazy-map (fn it -> (* it 2)))
    [2 4 6 8 10 12]
)
(test/exec :lazy-map1a
(range 6 | lazy-map (fn it -> (* it 2)))
    [2 4 6 8 10 12]
)
(test/exec :lazy-map2a  #([1 2] | lazy-map ^string?) ["1" "2"])
(test/exec :lazy-map2b  #(lazy-map [1 2] ^string?) ["1" "2"])
(test/exec :lazy-map2c
    (fn ->
        (let r (["123" 1i 3.14] | lazy-map ^int?))
        (and
            (== r [123 1 3])
            (is? (r 0) ^int)
            (is? (r 1) ^int)
            (is? (r 2) ^int)
        )
    )
    true
)
(test/exec :lazy-map3  #(["a" "aa" "aaa"] | lazy-map .length) [1 2 3])
(test/exec :lazy-map4
    (fn ->
        ([{:a 1 :b 2} {:a 10 :b 20} {:a 100 :b 200}] | lazy-map :a)
    )
    [1 10 100]
)
(test/exec :lazy-map5
    (fn ->
        (lazy-map [{:a 1 :b 2} {:a 10 :b 20} {:a 100 :b 200}] :a)
    )
    [1 10 100]
)
(test/exec :lazy-map6
    (fn ->
        ([{:a 1 :b 2} {:a 10 :b 20} {:a 100 :b 200}] | lazy-map :b)
    )
    [2 20 200]
)
(test/exec :lazy-map7
    (fn ->
        (lazy-map [{:a 1 :b 2} {:a 10 :b 20} {:a 100 :b 200}] :b)
    )
    [2 20 200]
)
(test/exec :lazy-map8
    (fn ->
        ([{:a 1 :b 2} {:b 20} {:a 100 :b 200}] | lazy-map :a)
    )
    [1 nil 100]
)
(test/exec :lazy-map9
    (fn ->
        (lazy-map [{:a 1 :b 2} {:b 20} {:a 100 :b 200}] :a)
    )
    [1 nil 100]
)
(test/exec :lazy-map10
    (fn ->
        ; use a keyword as an indexing function
        ([{:a 1 :b 2} {:b 20} {:a 100 :b 200}] | lazy-map :b)
    )
    [2 20 200]
)
(test/exec :lazy-map11
    (fn ->
        ([{:a 1 :b 2} {:b 20} {:a 100 :b 200}] | lazy-map :c)
    )
    [nil nil nil]
)
(test/exec :lazy-map12
    (fn ->
        ([] | lazy-map :b)
    )
    []
)
(test/exec :lazy-map13
    ; make pipeline data is not double-evaluated
    ; because lazy-map is a special form
    (fn ->
        (['(+ 2 3) '(+ 4 5) '(- 10 5)] | lazy-map (fn x -> x) | to-vector)
    )
    ['(+ 2 3) '(+ 4 5) '(- 10 5)]
)
; regex as a function
(test/exec :lazy-map15
    (fn ->
        ([:a :b :ab :bb :c :ca :ac] | lazy-map  #"a")
    )
    ["a" nil "ab" nil nil "ca" "ac"]
)
(test/exec :lazy-map16
    (fn ->
        (lazy-map [:a :b :ab :bb :c :ca :ac]  #"a")
    )
    ["a" nil "ab" nil nil "ca" "ac"]
)

(test/exec :lazy-map20
    (fn ->
        (defn foo [n] (* n 2))
        (range 5 | lazy-map foo)
    )
    [2 4 6 8 10]
)
(test/exec :lazy-map21
    (fn ->
        (defn foo [n] (* n 2))
        ; call function named by a string
        (range 5 | lazy-map "foo")
    )
    [2 4 6 8 10]
)
(test/exec :lazy-map22
    (fn ->
        ; destructuring key/value pairs
        ({:a 1 :b 2 :c 3}
        | lazy-map (fn key:value: ->
                "key: ${key} value: ${value}"
            )
        )
    )
    [
        "key: a value: 1"
        "key: b value: 2"
        "key: c value: 3"
    ]
)
(test/exec :lazy-map23
    (fn ->
        ; verify that assignment returns the collection not the member value
        ({} | !! :a 1 | !! :b 2 | !! :c 3)
    )
    {:a 1 :b 2 :c 3}
)
(test/exec :lazy-map24
    (fn ->
        (["a" "" "b" null "c"] | lazy-map .string/isnullorempty)
    )
    [false true false true false]
)

;-------------------------------------------------------
; Test the 'mapcat' function
(test/exec :mapcat1
    (fn ->
        (mapcat ++ [1 2] [3 4] [5 6])
    )
    [2 3 4 5 6 7]
)
(test/exec :mapcat2
    (fn ->
        (mapcat (* 2) [1 2] [3 4] [5 6])
    )
    [2 4 6 8 10 12]
)
(test/exec :mapcat3
    (fn ->
        (mapcat sqr [1 2] [3 4] [5 6])
    )
    [1 4 9 16 25 36]
)
;-------------------------------------------------------
; Test the 'ifmap' function
(test/exec :ifmap1
    (fn ->
        (ifmap (range 10) (% it 2) "e" "o" | join "")
    )
    "eoeoeoeoeo"
)
(test/exec :ifmap2
    (fn ->
        (ifmap (range 10) (% it 2) "e" | join "")
    )
    "eeeee"
)
(test/exec :ifmap3
    (fn ->
        (range 10 | ifmap (% it 2) "e" "o" | join "")
    )
    "eoeoeoeoeo"
)
(test/exec :ifmap4
    (fn ->
        (range 10 | ifmap (% it 2) "e" | join "")
    )
    "eeeee"
)
(test/exec :ifmap5
    (fn ->
        (ifmap 1 (% it 2) "odd" "even")
    )
    ["odd"]
)
(test/exec :ifmap6
    (fn ->
        (2 | ifmap (% it 2) "odd" "even")
    )
    ["even"]
)
(test/exec :ifmap7
    (fn ->
        (range 10 | ifmap (> it 5) it)
    )
    (range 6 10)
)

;-------------------------------------------------------
; Test 'each' function
(test/exec :each1
    (fn ->
        (range 10 | each id)
    )
    null
)
(test/exec :each2
    (fn ->
        (let s 0)
        ; each is about side-effects so we manipulate a variable defined in the parent scope.
        (range 10 | each (fn n -> (incr s n)))
        s
    )
    55
)
(test/exec :each3
    (fn ->
        (let result [])
        ; destructuring key/value pairs
        ({:a 1 :b 2 :c 3}
        | each (fn key:value: ->
                (nconc  "key: ${key} value: ${value}" result)
            )
        )
        result
    )
    [
        "key: a value: 1"
        "key: b value: 2"
        "key: c value: 3"
    ]
)
(test/exec :each4
    (fn ->
        (let res 0)
        (defn mysqr [x] (incr res (* x x)))
        (range 10 | each mysqr)
        res
    )
    385
)
(test/exec :each5
    (fn ->
        (null | each id)
    )
    null
)
(test/exec :each6
    (fn ->
        ; return in an 'each' returns only from that lambda, not everything
        (or (range 10 | each (fn n -> (return '123))) true)
    )
    true
)
(test/exec :each7
    (fn ->
        (let x 0)
        ; test break function in each
        (range 5 | each (fn n -> (if (> n 3) (break)) (def x n)))
        x
    )
    3
)
(test/exec :each8
    (fn ->
        (let x 0)
        ; test continue function in 'each'
        (range 5 | each (fn n -> (continue) (def x n)))
        x
    )
    0
)

;-------------------------------------------------------
; test regex as function
(test/exec :regex1
    (fn ->
        ; test match
        (#"abc" "1 2 3abc456")
    )
    "1 2 3abc456"
)
(test/exec :regex2
    (fn ->
        ; test unsuccessful match
        (#"abc" "1 2 356")
    )
    nil
)
(test/exec :regex3
    (fn ->
        ([:abc :dbc :eee :abf] | filter  #"^a")
    )
    [:abc :abf]
)
(test/exec :regex4
    (fn ->
        ; regex substitution
         (#"[0-9]" "a6b" "-")
    )
    "a-b"
)
(test/exec :regex5
    (fn ->
        ; regex substitution on a list
        (#"[0-9]" ["a6b" "c7d"]  "-")
    )
    ["a-b" "c-d"]
)
(test/exec :regex6
    (fn ->
        ; regex match on a list
        (#"[0-9]" ["a6b" "efg" "c7d" "hij"])
    )
    ["a6b" "c7d"]
)
(test/exec :pipe17
    (fn ->
        ; regex match on a list in a pipeline
        ; filters the input only returning matches
        (["a6b" "efg" "c7d" "hij"] |  #"[0-9]")
    )
    ["a6b" "c7d"]
)
(test/exec :pipe18
    (fn ->
        ; regex replace on a list in a pipeline
        ; all pipeline items are returned, not just the ones where substitution was done.
        ; essentially equivalent to re/match-all
        (["a6b" "efg" "c7d" "hij"] |  #"[0-9]" "+")
    )
    ["a+b" "efg" "c+d" "hij"]
)
(test/exec :pipe19
    (fn ->
        ; regex replace and filter on a list in a pipeline
        (["a6b" "efg" "c7d" "hij"] |  #"[0-9]" "+" | #"\+")
    )
    ["a+b" "c+d"]
)
(test/exec :regex8
    (fn ->
        (if (#"(a)(b)(c)" "abc")
            (matches | map .value)
        )
    )
    ["abc" "a" "b" "c"]
)
(test/exec :regex9
    (fn ->
        (and
            (#"let +([a-z]+) +([0-9]+)" "(let foo 12)")
            (matches 1 | .value | == "foo")
            (matches 2 | .value | == "12"))
    )
    true
)
(test/exec :regex10
    (fn ->
        (and
            (#"let +([a-z]+) +([0-9]+)" "(xxx foo 12)")
            (matches 1 | .value | == "foo")
            (matches 2 | .value | == "12"))
    )
    false
)
(test/exec :regex11
    (fn ->
        ; failed match sets matches to an empty vector.
        (#"abc" "def") matches
    )
    []
)
(test/exec :regex12
    (fn ->
        (#"a(bc)" "abc")
        (count matches)
    )
    2
)
(test/exec :regex13
    (fn ->
        (#"a(..)" "abc")
        (.value (matches 0))
    )
    "abc"
)
(test/exec :regex14
    (fn ->
        ; test with a lambda
        (["a" "ab" "ba" "bb" "cb"] |  #"^[ac]" (lambda [s] [s (!! matches 0)]))
    )
    [["a" "a"] ["ab" "a"] ["cb" "c"]]
)
(test/exec :regex15
    (fn ->
         (range 20 |  #"2" (fn (^int? s) -> (* s 10)))
    )
    [20 120 200]
)
;-------------------------------------------------------
; test regex as a parameter case - it should turn strings,
; however quoted into a regular expression
(test/exec :regex20
    (fn ->
        (defn toregex [(^regex? foo)] foo)
        (toregex "abc" | is? ^regex)
    )
    true
)
(test/exec :regex21
    (fn ->
        (defn toregex [(^regex? foo)] foo)
        (toregex 'abc | is? ^regex)
    )
    true
)
(test/exec :regex22
    (fn ->
        (defn toregex [(^regex? foo)] foo)
        (toregex (quote abc) | is? ^regex)
    )
    true
)
(test/exec :regex23
    (fn ->
        (defn toregex [(^regex? foo)] foo)
        (toregex :abc | is? ^regex)
    )
    true
)


;-------------------------------------------------------
; test the flatmap function
(test/exec :flatmap1
    (fn ->
        ([[1 2] [3 4] [5 6]] | flatmap (fn x -> x))
    )
    [1 2 3 4 5 6]
)
(test/exec :flatmap2
    (fn ->
        ([[1 2] [3 4] [5 6]] | flatmap (fn x -> (x | map (* 2))))
    )
    [2 4 6 8 10 12]
)

;-------------------------------------------------------
; test the lazy-flatmap function
(test/exec :lazy-flatmap1
    (fn ->
        ([[1 2] [3 4] [5 6]] | lazy-flatmap (fn x -> x))
    )
    [1 2 3 4 5 6]
)
(test/exec :lazy-flatmap2
    (fn ->
        ([[1 2] [3 4] [5 6]] | lazy-flatmap (fn x -> (x | map (* 2))))
    )
    [2 4 6 8 10 12]
)
(test/exec :lazy-flatmap3
    (fn ->
        ; this would take a long time if we were not using a lazy function 
        (range 10_000_000 | lazy-flatmap (fn x -> (* x 2)) | take 1)
    )
    [ 2 ]
)

;-------------------------------------------------------
(test/exec :reduce1  #(range 5  | reduce (fn it it2 -> (* it it2))) 120)
(test/exec :reduce-with-seed1
    (fn ->
        ; use implicit indexing.
        (range 5 | reduce-with-seed (fn hsh val -> (hsh val true) hsh) {})
    )
    {1 true 2 true 3 true 4 true 5 true}
)
(test/exec :reduce-with-seed2
    (fn ->
        ; use the !! function
        (range 5 | reduce-with-seed (fn hsh val -> (!! hsh val true) hsh) {})
    )
    {1 true 2 true 3 true 4 true 5 true}
)
(test/exec :reduce-with-seed3
    (fn ->
        (defn reduce-rev
            "Reverse a vector with reduce"
            [lst]

            (lst | reduce-with-seed (fn x y -> (cons y x)) nil)
        )
        (reduce-rev (range 100))
    )
    (reverse (range 100))
)
(test/exec :reduce5
    (fn ->
        (range 5 | reduce +)
    )
    15
)
(test/exec :reduce6
    (fn ->
        (range 5 | reduce *)
    )
    120
)
(test/exec :reduce7
    (fn ->
        (defn myfunc [x y] (+ x y))
        (range 5 | reduce myfunc)
    )
    15
)
(test/exec :reduce8  #(range 10 | reduce (fn x y -> (* x y))) 3628800)
; test if all elements < 20
(test/exec :reduce9  #(range 10 | reduce (fn x y -> (and x (< y 20)))) true)
; test if all elements are > 5; this should fail
(test/exec :reduce10 #(range 10 | reduce (fn x y -> (and x (> y 5)))) false)
(test/exec :reduce11
    (fn ->
        ; eliminate adjacent dups in a list
        ; (Note: Braid reduce is foldl, this example would be better with foldr (see below.)
        ([1 2 2 3 4 4 4 5 6 6 7] | reduce (fn i r -> (if (== (last i) r) i (append i r))))
    )
    [1 2 3 4 5 6 7]
)
(test/exec :reduce12
    (fn ->
        ; reverse a list
        (range 10 | reduce (fn x y -> (cons y x)) nil)
    )
    [10 9 8 7 6 5 4 3 2 1]
)
(test/exec :reduce12a
    (fn ->
        ; reverse a list using the 'reverse cons'
        (range 10 | reduce >cons nil)
    )
    [10 9 8 7 6 5 4 3 2 1]
)
(test/exec :foldl1
    (fn ->
        ; As above, this test eliminates adjacent duplicates in a list
        ; Redo the test using the forldl alias
        ([1 2 2 3 4 4 4 5 6 6 7] | foldl (fn i r -> (if (== (last i) r) i (append i r))))
    )
    [1 2 3 4 5 6 7]
)

(test/exec :foldr1
    (fn ->
        (foldr [1 2 3 4] +)
    )
    10
)
(test/exec :foldr2
    (fn ->
        (foldr [1 2 3 4] -)
    )
    (- 1 (- 2 (- 3 4)))
)
(test/exec :foldr3
    (fn ->
        ; eliminate adjacent duplicates in a list with foldr
        ([1 2 2 2 3 4 4 5] | foldr (fn x y -> (if (== x (car y)) y (cons x (aslist y)))))
    )
    [1 2 3 4 5]
)

;--------------------------------------------------------------------------
;
; Test a tail-recursive "reduce" function written in braid.
(test/exec :reducerecur1
    (fn ->
        (defn treduce
        | x:xs f -> (recur xs f x)
        | x:xs f r -> (recur xs f (f r x))
        | null _ r -> r
        | -> (error :bad %0)
        )

        ; try with a built-in function
        (treduce (range 100) +)
    )
    5050
)
(test/exec :reducerecur2
    (fn ->
        (defn treduce
        | x:xs f -> (recur xs f x)
        | x:xs f r -> (recur xs f (f x r))
        | null _ r -> r
        | -> (error :bad %0)
        )

        ; try with a lambda
        (treduce (range 10) (fn x y -> (* x y)))
    )
    3628800
)
(test/exec :reducerecur3
    (fn ->
        (defn treduce
        | x:xs f -> (recur xs f x)
        | x:xs f r -> (recur xs f (f r x))
        | null _ r -> r
        | -> (println :bad %0)
        )

        ; try with a pipe
        (range 10 | treduce (fn x y -> (* x y)))
    )
    3628800
)

;-------------------------------------------------------
; test the char function
; test turing a 1-element string into a char
(test/exec :char1  #(^int? (char "a"))   97)
(test/exec :char2  #(is? (char "a") ^char)   true)
; tedt turning ints into chars
(test/exec :char3  #(range 97 (+ 25 97) | map char | join "") "abcdefghijklmnopqrstuvwxyz")
(test/exec :char4  #(^int? (^char? "a"))   97)
(test/exec :char5  #(is? (^char? "a") ^char)   true)
; tedt turning ints into chars
(test/exec :char6  #(range 97 (+ 25 97) | map ^char? | join "") "abcdefghijklmnopqrstuvwxyz")

;-------------------------------------------------------
; Test the incr function
(test/exec :incr1 #(do (let s 0) (incr s) (incr s) (incr s) s) 3)
(test/exec :incr1a
    (fn ->
        (undef zzz)
        (incr zzz)
        (incr zzz)
        (incr zzz)
    )
    3
)
(test/exec :incr2 #(do (let s 0) (incr s 2) (incr s 3) (incr s 4) s) 9)
(test/exec :incr3 #(do (let s 0) (incr s 2) (incr s 3) (incr s -4) s) 1)
(test/exec :incr4
    (fn ->
        (defn tst [%0] (incr %0))
        (and
            (tst 10  | == 11)
            (tst 100 | == 101))
    )
    true
)
(test/exec :incr5
    (fn ->
        (defn tst [%0] (incr %0 5))
        (and
            (tst 10  | == 15)
            (tst 100 | == 105))
    )
    true
)
(test/exec :incr6
    (fn ->
        (defn tst [%0] (incr %0 -1))
        (and
            (tst 10  | == 9)
            (tst 100 | == 99))
    )
    true
)

;-------------------------------------------------------
; Test the pincr function
(test/exec :pincr1
    (fn ->
        (with [x 0 s 0] (while (pincr x | <= 10) (incr s x)) s)
    )
    66
)
(test/exec :pincr2
    (fn ->
        (defn tst [%0] (pincr %0))
        (let z 15)
        [(pincr z) z]
    )
    [15 16]
)
(test/exec :pincr3
    (fn ->
        (defn tst [%0] (pincr %0 -7))
        (let z 15)
        [(pincr z) z]
    )
    [15 16]
)
(test/exec :pincr4
    (fn ->
        (undef zzz)
        [(pincr zzz) zzz]
    )
    [0 1]
)
(test/exec :pincr5
    (fn ->
        (let zzz null)
        [(pincr zzz) zzz]
    )
    [0 1]
)


;-------------------------------------------------------
; Test the 'decr' function.
(test/exec :decr1
    (fn ->
        (let s 1)
        (decr s)
        s
    )
    0
)
(test/exec :decr2
    (fn ->
        (let s 1)
        (let res (decr s))
        [res s]
    )
    [0 0]
)
(test/exec :decr3
    (fn ->
        (defn tst [%0] [ (decr %0) %0])
        (let z 15)
        (tst z)
    )
    [14 14]
)
(test/exec :decr4
    (fn ->
        (defn tst [%0] [ (decr %0) %0 ])
        (let z 15)
        (tst z)
    )
    [14 14]
)
(test/exec :decr5
    (fn ->
        (undef zzz)
        [(decr zzz) zzz]
    )
    [-1 -1]
)
(test/exec :decr6
    (fn ->
        (let zzz null)
        [(decr zzz) zzz]
    )
    [-1 -1]
)


;-------------------------------------------------------
; Test the 'pdecr' function.
(test/exec :pdecr1
    (fn ->
        (let s 1)
        (let res (pdecr s))
        [res s]
    )
    [1 0]
)
(test/exec :pdecr2
    (fn ->
        (defn tst [%0] [ (pdecr %0) %0])
        (let z 15)
        (tst z)
    )
    [15 14]
)
(test/exec :pdecr3
    (fn ->
        (defn tst [%0] [ (pdecr %0) %0 ])
        (let z 15)
        (tst z)
    )
    [15 14]
)
(test/exec :pdecr4
    (fn ->
        (undef zzz)
        [(pdecr zzz) zzz]
    )
    [0 -1]
)
(test/exec :pdecr5
    (fn ->
        (let zzz null)
        [(pdecr zzz) zzz]
    )
    [0 -1]
)


;-------------------------------------------------------
; Test the '++' function
(test/exec :++1
    (fn ->
        (let x 1)
        (++ x)
    )
    2
)
(test/exec :++2
    (fn ->
        (let x 1)
        (++ x)
        x
    )
    1
)
(test/exec :++3
    (fn ->
        (++ 3)
    )
    4
)

;-------------------------------------------------------
; Test tye '--' function
(test/exec :--1
    (fn ->
        (let x 1)
        (-- x)
    )
    0
)
(test/exec :--2
    (fn ->
        (let x 1)
        (-- x)
        x
    )
    1
)
(test/exec :--3
    (fn ->
        (-- 3)
    )
    2
)

;-------------------------------------------------------
; test the "new-vector" function
(test/exec :new-vector1
    (fn ->
        (new-vector | is? ^vector)
    )
    true
)
(test/exec :new-vector2
    (fn ->
        (new-vector | length)
    )
    0
)
(test/exec :new-vector3
    (fn ->
        (new-vector 1 2 3 4 5)
    )
    [1 2 3 4 5]
)
(test/exec :new-vector4
    (fn ->
        (new-vector [1 2 (+ 1 2)] {} :a "hello"  #{1 2 3})
    )
    [[1 2 3] {} :a "hello"  #{1 2 3}]
)

;------------------------------------------------------
; test the 'new-dict' function
(test/exec :new-dict1
    (fn ->
        (new-dict ^object ^object "a" 1 "b" 2)
    )
    {"a" 1 "b" 2}
)
(test/exec :new-dict2
    (fn ->
        (new-dict ^object ^object "a" 1 "b" 2 | count)
    )
    2
)
(test/exec :new-dict3
    (fn ->
        (new-dict ^object ^object | count)
    )
    0
)
(test/exec :new-dict4
    (fn ->
        (new-dict ^string ^int "a" 1 "b" 2 | type-of)
    )
    ^System.Collections.Generic.Dictionary[string,int]
)

(test/exec :new-dict5
    (fn ->
         (let d (new-dict ^int ^int 1 2 3 4))
         (and
            (d 1 | == 2)
            (d 3 | == 4))
    )
    true
)
(test/exec :new-dict6
    (fn ->
        (let d (new-dict ^int ^int 1 2 3 4))
        (type-of d)  
    )
    ^System.Collections.Generic.Dictionary[int,int]
)

;------------------------------------------------------
; test the 'new-array' function
(test/exec :new-array1
    (fn ->
        (new-array ^int 10 | type-of)
    )
    ^int[]
)
(test/exec :new-array2
    (fn ->
        (new-array ^int 10 | count)
    )
    10
)
(test/exec :new-array3
    (fn ->
        (new-array ^int 0 | count)
    )
    0
)
(test/exec :new-array4
    (fn ->
        (let a (new-array ^int 1))
        (try (!! a 0 "hi") | is? ^Exception)
    )
    true
)
(test/exec :new-array5
    (fn ->
        (new-array ^int 5 1 2 3)
    )
    [1 2 3 0 0]
)
(test/exec :new-array6
    (fn ->
        (new-array ^object 5 :a 2 :b)
    )
    [:a 2 :b nil nil]
)

;-------------------------------------------------------
; test the "echo" function
(test/exec :echo1
    (fn ->
        (echo 2)
    )
    2
)
(test/exec :echo2
    (fn ->
        ([1 2 3 4] | map echo)
    )
    [1 2 3 4]
)

;-------------------------------------------------------
; test the "id" function
(test/exec :id1
    (fn ->
        (id 2)
    )
    2
)
(test/exec :id2
    (fn ->
        ([1 2 3 4] | map id)
    )
    [1 2 3 4]
)

;-------------------------------------------------------
; test the "subseq" function
(test/exec :subseq1
    (fn ->
        (subseq (range 10) 3 7)
    )
    [3 4 5 6 7]
)
(test/exec :subseq2
    (fn ->
        (subseq (range 10) 3)
    )
    [3 4 5 6 7 8 9 10]
)

;-------------------------------------------------------
; test the "join" function
(test/exec :join1
    (fn ->
        (join ["a" "b" "c"])
    )
    "a b c"
)
(test/exec :join2
    (fn ->
        (["a" "b" "c"] | join)
    )
    "a b c"
)
(test/exec :join3
    (fn ->
        (join ["a" "b" "c"] "/")
    )
    "a/b/c"
)
(test/exec :join4
    (fn ->
        (["a" "b" "c"] | join "/")
    )
    "a/b/c"
)
(test/exec :join5
    (fn ->
        (join ["a" "b" "c"] "")
    )
    "abc"
)
(test/exec :join6
    (fn ->
        (["a" "b" "c"] | join "")
    )
    "abc"
)
(test/exec :join7
    (fn ->
        ([1] | join | type-of)
    )
    ^string
)
(test/exec :join8
    (fn ->
        (range 5 | join)
    )
    "1 2 3 4 5"
)
(test/exec :join9
    (fn ->
        (range 5 | join "+")
    )
    "1+2+3+4+5"
)
(test/exec :join10
    (fn ->
        (range 5 | join "" | ^int?)
    )
    12345
)
(test/exec :join11
    (fn ->
        (str "+ " (range 10 | join " ") | eval-string)
    )
    (range 10 | sum)
)

;-------------------------------------------------------
; test splatting operations

; splatting arguments to functions
(test/exec :splatting1
    (fn ->
        (let x (list 1 2 3))
        (+ @x)
    )
    6
)
(test/exec :splatting1a
    (fn ->
        (let x (list 2 3))
        (+ 1 @x 4)
    )
    10
)
; splatting a variable into a vector
(test/exec :splatting2
    (fn ->
        (let x [2 3 4])
        (let y [7 8])
        [1 @x 5 6 @y 9]
    )
    [1 2 3 4 5 6 7 8 9]
)
(test/exec :splatting2a
    (fn ->
        ; splatting a literal
        [1 @[2 3 4] 5 6 @[7 8] 9]
    )
    [1 2 3 4 5 6 7 8 9]
)
(test/exec :splatting2b
    (fn ->
        ; splatting a "literal" list
        [1 @(list 2 3 4) 5 6 @(list 7 8) 9]
    )
    [1 2 3 4 5 6 7 8 9]
)
; splatting into a list
(test/exec :splatting3
    (fn ->
        (let x '(2 3 4))
        (let y '(7 8))
        (list 1 @x 5 6 @y 9)
    )
    '(1 2 3 4 5 6 7 8 9)
)
; splatting a vector into a list
(test/exec :splatting4
    (fn ->
        (let x [2 3 4])
        (let y [7 8])
        (list 1 @x 5 6 @y 9)
    )
    '(1 2 3 4 5 6 7 8 9)
)
(test/exec :splatting5
    (fn ->
        (let x {:a 1 :b 2})
        ; splatting a dictionary into an array embeds KeyValue pairs
        (list 1 2 @x 3 4)
    )
    '(1 2 "a" 1 "b" 2 3 4)
)
(test/exec :splatting6
    (fn ->
        (defn foo [] [1 2 3 4])
        (join ["http://" @(join (foo) "/") "/"] "")
    )
    "http://1/2/3/4/"
)
(test/exec :splatting7
    (fn ->
        (defn foo [num] (range num))
        (join ["http://" @(join (foo 5) "/") "/"] "")
    )
    "http://1/2/3/4/5/"
)
(test/exec :splatting8
    (fn ->
        (defn foo [num] (range num))
        (join ["http:/" "webroot" @(foo 5) "foo.htm" ] "/" )
    )
    "http://webroot/1/2/3/4/5/foo.htm"
)
(test/exec :splatting9
    (fn ->
        [1 2 3 @[4 5 6] 7 8]
    )
    [1 2 3 4 5 6 7 8]
)
(test/exec :splatting10
    (fn ->
        [1 2 3 @[4 5 6] 7 @[8 9]]
    )
    [1 2 3 4 5 6 7 8 9]
)
(test/exec :splatting10a
    (fn ->
        [1 2 3 [4 5 6] 7 @[8 9]]
    )
    [1 2 3 [4 5 6] 7 8 9]
)
(test/exec :splatting11
    (fn ->
        [1 2 @[ 3 4 @[ 5 6] 7]]
    )
    [1 2 3 4 5 6 7]
)
(test/exec :splatting12
    (fn ->
        [1 2 [3 4 @[ 5 6]] 7]
    )
    [1 2 [3 4 5 6 ] 7]
)
(test/exec :splatting12a
    (fn ->
        (let hash {:a 1 :b 2 :c 3 :d 4})
        ; if the splat comes first, it is overwritten
        {@hash :a 10 :c 30}
    )
    {:a 10 :b 2 :c 30 :d 4}
)
(test/exec :splatting13
    (fn ->
        (let hash {:a 1 :b 2 :c 3 :d 4})
        ; if the splat comes last, it overwrites
        {:a 10 :c 30 :e 50 @hash}
    )
    {:a 1 :b 2 :c 3 :d 4 :e 50}
)
(test/exec :splatting14
    (fn ->
        (let h1 {:c 3 :d 4})
        (let h2 {:a 1 :b 2})
        ; splatting in two dictionaries
        {:a 10 @h1 :c 30 :e 50 @h2}
    )
    {:a 1 :b 2 :c 30 :d 4 :e 50}
)
(test/exec :splatting15
    (fn ->
        ; layers of splatting
        (let h1 [1 2 3])
        (let h2 [:a @h1 :b])
        [10 @h2 20]
    )
    [10 :a 1 2 3 :b 20]
)
(test/exec :splatting16
    (fn ->
        ; nested splatting
        (let h1 [1 2])
        (let h2 [3 4])
        (let h3 [5 6])
        [10 @h1 [20 @h2 [300 @h3 40]]]
    )
    [10 1 2[20 3 4 [300 5 6 40]]]
)
(test/exec :splatting17
    (fn ->
        ; nested splatting
        (let h1 [1 2])
        (let h2 [[3 4]])
        (let h3 [5 [[6]]])
        [10 @h1 [20 @h2 [300 @h3 40]]]
    )
    [10 1 2[20 [3 4] [300 5 [[6]] 40]]]
)

(; BUGBUGBUG - Should be a syntax error "you can only splat in the key position"
(test/exec :splatting19
    (fn ->
        (let lst [1 2 3])
        {:a @lst}
    )
    ;BUGBUGBUG this is probably wrong - look at splatting a list into a dictionary
    {
        "a" : 1,
        2 : 3
    }
)
;BUGBUGBUG
;)

(test/exec :splatting20
    (fn ->
        (let lst [1 2 3])
        {:a [ @lst ]}
    )
    {:a [1 2 3]}
)
(test/exec :splatting21
    (fn ->
        {"a" 1 @(forall i (range 3) { "key${i}" i }) "b" 3}
    )
    {
        "a" : 1,
        "key1" : 1,
        "key2" : 2,
        "key3" : 3,
        "b" : 3
    }
)
; merge literal hashtables
(test/exec :splatting21a
    (fn ->
        {:a 1 @{:x 10 :y 20 @{:z 30}} :b 3}
    )
    {:a 1 :x 10 :y 20 :z 30 :b 3}
)
; merge an splatted literal array of hashtables
(test/exec :splatting22
    (fn ->
        {:a 1 @[{:x 10} {:y 20} {:z 30}]:b 3}
    )
    {:a 1 :x 10 :y 20 :z 30 :b 3}
)
; create a new dictionary based on an existing one but with updated values
(test/exec :splatting23
    (fn ->
        (let coll {:a 1 :b 2 :c 3 :d 4})
        { @(coll | map (fn e -> { (.key e) (* 10 (.value e)) })) }
    )
    {:a 10 :b 20 :c 30 :d 40}
)
; As above but using destructuring
(test/exec :splatting24
    (fn ->
        (let coll {:a 1 :b 2 :c 3 :d 4})
        { @(coll | map (fn k:v: -> { k (* 10 v) })) }
    )
    {:a 10 :b 20 :c 30 :d 40}
)
(test/exec :splatting25
    (fn ->
        (let inner [{:x 1} {:y 2} {:z 3}])
        {:a 1 @(reverse inner) :b 3}
    )
    {:a 1 :z 3 :y 2 :x 1 :b 3}
)
; splatting a null value should not add null to the collection
(test/exec :splatting26
    (fn ->
        [1 @null]
    )
    [1]
)
(test/exec :splatting27
    (fn ->
        [1 @null 2]
    )
    [1 2]
)
(test/exec :splatting28
    (fn ->
        (let foo null)
        [1 @null 2 @null @null 3 @foo 4]
    )
    [1 2 3 4]
)
(test/exec :splatting29
    (fn ->
        (let foo [3.5 3.6 3.7])
        [1 @null 2 @null @null 3 @foo 4]
    )
    [1 2 3 3.5 3.6 3.7 4]
)
(test/exec :splatting30
    (fn ->
        {:a 1 @null :b 2 @null :c 3}
    )
    {:a 1 :b 2 :c 3}
)
(test/exec :splatting31
    (fn ->
        (let foo {:d 4 :e 5})
        {:a 1 @null :b 2 @null :c 3 @null @foo @null}
    )
    {:a 1 :b 2 :c 3 :d 4 :e 5}
)

;-------------------------------------------------------
; Test the operation of pattern-bodied lambdas. (note:
; the 'matchp' macro also uses pattern lambdas in its expansion.)
(test/exec :lambda1
    (fn ->
        ([1 2 3 4] | map (lambda | 2 -> :even | 4 -> :even | -> :odd))
    )
    [:odd :even :odd :even]
)
(test/exec :lambda1a
    (fn ->
        ([1 2 3 4] | map (fn | 2 -> :even | 4 -> :even | -> :odd))
    )
    [:odd :even :odd :even]
)
(test/exec :lambda2
    (fn ->
        ([[1 2] [3 4] [5 6]] | map (fn nums ->
            ((lambda
                | 1 val -> (* val 10)
                | 3 val -> (* val 100)
                | 5 val -> (* val 1000)
                )
                @nums
            )
        ))
    )
    [ 20 400 6000 ]
)
(test/exec :lambda2a
    (fn ->
        ([[1 2] [3 4] [5 6]] | map (fn nums ->
            ((fn
                | 1 val -> (* val 10)
                | 3 val -> (* val 100)
                | 5 val -> (* val 1000)
                )
                @nums
            )
        ))
    )
    [ 20 400 6000 ]
)
(test/exec :lambda3
    (fn ->
        ([[1 2] [3 4] [5 6]] | map (fn nums ->
            ; use apply instead of splatting
            (apply
                (lambda
                | 1 val -> (* val 10)
                | 3 val -> (* val 100)
                | 5 val -> (* val 1000)
                )
                nums
            )
        ))
    )
    [ 20 400 6000 ]
)
(test/exec :lambda3a
    (fn ->
        ([[1 2] [3 4] [5 6]] | map (fn nums ->
            ; use apply instead of splatting
            (apply
                (fn
                | 1 val -> (* val 10)
                | 3 val -> (* val 100)
                | 5 val -> (* val 1000)
                )
                nums
            )
        ))
    )
    [ 20 400 6000 ]
)
(test/exec :lambda4
    (fn ->
        (lambda? (lambda [] true))
    )
    true
)
(test/exec :lambda5
    (fn ->
        ([[1 2] [3 4] [5 6]] | map (fn nums ->
            ; use apply instead of splatting
            (apply
                (fn
                | 1 val | 3 val -> (* val 10)
                | 5 val -> (* val 1000)
                )
                nums
            )
        ))
    )
    [ 20 40 6000 ]
)
(test/exec :lambda6
    (fn ->
        (let fdata '(* x x))
        (let fdata (list '[x] fdata))
        (let fdata (cons 'lambda fdata))
        (let ffn fdata)
        (ffn 8)
    )
    64
)
(test/exec :lambda7
    (fn ->

        (defn gen-func [op]
            (let fdata (list op 'x 'x))
            (let fdata (list '[x] fdata))
            (let fdata (cons 'lambda fdata))
            fdata
        )

        (let f1 (gen-func *))
        (let f2 (gen-func +))
        [(f1 3) (f2 4) ((gen-func *) 8)]
    )
    [9 8 64]
)

;-------------------------------------------------------
; Test object destructuring in patterns
(test/exec :objdestruct1
    (fn ->
        (ls braidhome
        | map (fn | (^System.IO.FileInfo name:length) -> name | ->)
        | contains? "autoload.tl")
    )
    true
)
(test/exec :objdestruct2
    (fn ->
        (ls -file braidhome
        | map (fn | (^object name:length) -> name | ->) ; force reflection
        | contains? "autoload.tl")
    )
    true
)
(test/exec :objdestruct3
    (fn ->
        (matchp (get-date) | (^DateTime dayofweek:month) -> [dayofweek month])
    )
    [ (.dayofweek (get-date)) (.month (get-date)) ]
)
(test/exec :objdestruct4
    (fn ->
        (deftype ^foo a b)
        (matchp (new ^foo 1 2) | (^foo a:b) -> [b a])
    )
    [2 1]
)
(test/exec :objdestruct5
    (fn ->
        (deftype ^foo a b)
        (let data [(new ^foo 1 10) (new ^foo 2 20) (new ^foo 3 30)])
        ; try vector of a custom type
        (data | (map (fn | (^foo a:b) :where (odd? a) -> [a b] | -> (continue) )))
    )
    [[1 10] [3 30]] 
)
(test/exec :objdestruct6
    (fn ->
        (deftype ^foo a b)
        (let data [(new ^foo 1 10) (new ^foo 2 20) (new ^foo 3 30)])
        ; try without a specifc type
        (data | (map (fn | (^any a:b) :where (odd? a) -> [a b] | -> (continue) )))
    )
    [[1 10] [3 30]] 
)
(test/exec :objdestruct7
    (fn ->
        (deftype ^foo a b)
        (let data [(new ^foo 1 10) (new ^foo 2 20) (new ^foo 3 30)])
        ; try vector of a custom type
        (defn doit
            | (^foo a:b) :where (odd? a) -> [a b]
            | (^foo a:b) :where (even? a) -> [b a]
        )
        (data | map doit)
    )
    [[1 10] [20 2] [3 30]] 
)
(test/exec :objdestruct8
    (fn ->
        ; define a binary tree datatype
        (deftype ^tree ^int v ^tree l ^tree r
            :defm new (fn this &args ->
                (matchp @args
                | v     -> (.v this v)
                | v l r -> (.v this v) (.l this l) (.r this r)
                | throw "Invalid number of arguments to ^tree constructor"
                )
            )
        )

        ; define a function to insert objects into that tree
        (defn ins
            | (^tree v:l:r) x :where (< x v)  -> (new ^tree v (ins l x) r)
            | (^tree v:l:r) x :where (> x v)  -> (new ^tree v l (ins r x))
            | (^tree v:l:r) x :where (== x v) -> %0
            | nil x -> (new ^tree x)
        )

        ; a function to retrieve the elements in the tree in order as a flat list
        (defn gt
            | (^tree v:l:r) -> [ @(gt l) v @(gt r) ]
            | ->
        )

        ; insert items at random into the tree
        (let t null)
        (let t (ins t 3))
        (let t (ins t 1))
        (let t (ins t 4))
        (let t (ins t 2))
        (let t (ins t 4)) ; duplicates will get discarded
        (let t (ins t 5))

        ; get the contents of the tree
        (gt t)
    )
    [1 2 3 4 5]
)
(test/exec :objdestruct9
    (fn ->
        (try
            ; check for a compile-time error on invalid properties when using known types
            (eval-string "(matchp \"hello\" | (^string nosuchprop:) -> true)")
            false
            -catch: true
        )
    )
    true
)


;-------------------------------------------------------
; Test 'list/partition'
(test/exec :list/partition1
    (fn ->
        ([1 2 3 4 5 6 7 8 9] | list/partition 3)
    )
    [[1 2 3] [4 5 6] [7 8 9]]
)
(test/exec :list/partition2
    (fn ->
        ([1 2 3 4 5 6 7 8 9 10] | list/partition 3)
    )
    [[1 2 3] [4 5 6] [7 8 9] [10]]
)
(test/exec :list/partition3
    (fn ->
        ([1 2 3 4 5 6 7 8 9 10] | list/partition 5)
    )
    [[1 2 3 4 5] [6 7 8 9 10]]
)
(test/exec :list/partition4
    (fn ->
        ([1 2 3 4 5 6 7 8 9 10] | list/partition 2)
    )
    [[1 2] [3 4] [5 6] [7 8] [9 10]]
)
(test/exec :list/partition5
    (fn ->
        ([1 2 3 4 5] | list/partition 1)
    )
    [[1] [2] [3] [4] [5]]
)

;-------------------------------------------------------
; The 'count' function.
(test/exec :count1  #([1 2 3 4 5] | count) 5)
(test/exec :count2  #(count "abcdef") 6)
(test/exec :count3  #(count {:a 1 :b 2 :c 3}) 3)
(test/exec :count4  #(count #{:a 1 :b 2 :c 3}) 6)
(test/exec :count5  #(count (new-array ^int 10)) 10)
(test/exec :count6  #(count 1) 1)
(test/exec :count7  #(count null) 0)
(test/exec :count8  #(count '(1 2 3 4 5 6 7)) 7)
(test/exec :count9  #(count '(1)) 1)
(test/exec :count10 #(count '(1 2)) 2)
(test/exec :count11 #(count '(1 2 3)) 3)
(test/exec :count12 #(count '()) 0)
(test/exec :count13
    (fn ->
        (let l '(1 2 3 4))
        (count l)
        (count l)
    )
    4
)
(test/exec :count14
    (fn ->
        (let l '(1 2 3 4))
        (count l)
        (let l2 (cons 0 l))
        [(count l) (count l2)]
    )
    [4 5]
)
(test/exec :count15
    (fn ->
        (let l '(1 2 3 4))
        (let c1 (count l))
        (let l2 (splice l '(5 6 7)))
        [c1 (count l2) (== l l2)]
    )
    [4 7 true]
)
(test/exec :count16
    (fn ->
        (let l '(1 2 3 4))
        (let c1 (count l))
        (let l2 (cons 0 (splice l '(5 6 7))))
        [c1 (count l2)]
    )
    [4 8]
)
(test/exec :count17
    (fn ->
        ; make sure the counts are maintainded correctly
        (let l '(1 2 3))
        (splice l '(4 5))
        [
            (count l)
            (count (cdr l))
            (count (cdr l | cdr))
            (count (cdr l | cdr | cdr))
            (count (cdr l | cdr | cdr | cdr))
            (count (cdr l | cdr | cdr | cdr | cdr))
        ]
    )
    [5 4 3 2 1 0]
)
(test/exec :count18
    (fn ->
        [
            (let l (splice '(1 2) (let m (splice '(3 4 5) (splice '(6 7) 8)))))
            (count m)
            (count l)
        ]
    )
    [
        '(1 2 3 4 5 6 7 8)
        6
        8
    ]
)

;-------------------------------------------------------
; The 'length' function (which is just an alias for 'count'.)
(test/exec :length1 #([1 2 3 4 5] | length) 5)
(test/exec :length2 #(length "abcdef") 6)
(test/exec :length3 #(length {:a 1 :b 2 :c 3}) 3)
(test/exec :length4 #(length #{:a 1 :b 2 :c 3}) 6)
(test/exec :length5 #(length (new-array ^int 10)) 10)
(test/exec :length6 #(length 1) 1)
(test/exec :length7 #(length null) 0)
(test/exec :length8 #(length '(1 2 3 4 5 6 7)) 7)

;-------------------------------------------------------
; The 'invoke-method' function.
(test/exec :invoke-method1
    (fn ->
        (invoke-method "abcde" :substring 1 2)
    )
    "bc"
)

;-------------------------------------------------------
; The 'scalarize' function.
(test/exec :scalarize1
    (fn ->
        (scalarize [1] | == 1)
    )
    true
)
(test/exec :scalarize2
    (fn ->
        (scalarize [1] | is? ^int)
    )
    true
)

;-------------------------------------------------------
; String interpolation
(test/exec :string-interpolation11
    (fn ->
        (let x 123)
        "x is ${x}"
    )
    "x is 123"
)
(test/exec :string-interpolation2
    (fn ->
        "sum is ${(+ 1 2 3)}"
    )
    "sum is 6"
)
(test/exec :string-interpolation3
    (fn ->
        (let x 2)
        (let y 3)
        "${x}+${y} is ${(+ x y)}"
    )
    "2+3 is 5"
)
(test/exec :string-interpolation4
    (fn ->
        (defn foo [v] "v is ${v}")
        (foo [1 2 3])
    )
    (+ "v is " (tostring [1 2 3]))
)
(test/exec :string-interpolation5
    (fn ->
        (defn foo [v] "v is ${v}")
        (foo {:a 1 :b 2 :c 3})
    )
    (+ "v is " (tostring  {:a 1 :b 2 :c 3}))
)
(test/exec :string-interpolation6
    (fn ->
        (re/match (.message (try "${(+ }")) "Parse error")
    )
    true
)
(test/exec :string-interpolation7
    (fn ->
        (re/match (.message (try "${(+ ")) "unclosed expansion")
    )
    true
)
(test/exec :string-interpolation8
    (fn ->
        "<${}>"
    )
    "<>"
)
(test/exec :string-interpolation9
    (fn ->
        (let v true)
        ; conditional in interpolation
        "a b ${(if v 10 20)} c d"
    )
    "a b 10 c d"
)
(test/exec :string-interpolation10
    (fn ->
        (let v false)
        "a b ${(if v 10 20)} c d"
    )
    "a b 20 c d"
)

;-------------------------------------------------------
; Methods
(test/exec :string-method1  #(.substring "abcde" 1 3) "bcd")
(test/exec :string-method1a #(. "abcde" :substring 1 3) "bcd")
(test/exec :string-method1b
    (fn ->
        ; out-of-bounds should throw an exception
        (is? (try (.substring "abcde" 1 100)) ^Exception)
    )
    true
)
(test/exec :string-method2 #(.substring "abcde" 2) "cde")
(test/exec :string-method2a
    (fn ->
        (. "abcde" :substring 2)
    )
    "cde"
)
(test/exec :string-method3  #(.contains "abcde" "bcd") true)
(test/exec :string-method3b #(. "abcde" :contains "bcd") true)
(test/exec :string-method3c #(.contains "abcde" "xyz") false)
(test/exec :string-method3d #(. "abcde" :contains "xyz") false)
; static method
(test/exec :string-method4  #(.string/format "{0}-{1}" 1 2) "1-2")
; static method
(test/exec :string-method5  #(.string/concat "abc" "def" "ghi") "abcdefghi")
(test/exec :string-property1  #(.length "abcde") 5)
(test/exec :string-property1a #(. "abcde" :length) 5)
(test/exec :string-both1    #(.substring "abcde" 1 3 | .length) 3)
(test/exec :string-both1a   #(.substring "abcde" 1 3 | . :length) 3)
(test/exec :string-both1b   #(. "abcde" :substring 1 3 | . :length) 3)
(test/exec :string-both1c
    ; chained method calls
    #(.substring "abcde" 1 | .substring 1 | .substring 1 |  .length)
    2
)
(test/exec :string-both1d
    ; chained method calls
    #(.substring "abcde" 1 | .substring 1 | .substring 1)
    "de"
)
(test/exec :string-toupper
    (fn ->
        ; convering string to uppercase then comparing it in a pipeline
        (.toupper "abcde" | .equals "ABCDE")
    )
    true
)
(test/exec :string-tolower
    (fn ->
        ; convering string to uppercase
        (.tolower "ABCDE" | .equals "abcde")
    )
    true
)
; test static string function "concat".
(test/exec :static-function-concat1
    (fn -> (.string/concat "aa" "bb" "cc" "dd"))
    "aabbccdd"
)
(test/exec :static-function-concat2
    (fn ->
        (let strs ["aa" "bb" "cc" "dd"])
        (.string/concat @strs)
    )
    "aabbccdd"
)
(test/exec :static-function-concat3
    (fn ->
        (.string/concat @(map ["aa" 10 "cc" 20] ^string?))
    )
    "aa10cc20"
)
(test/exec :static-function-concat3a
    (fn ->
        (.string/concat @(map ["aa" 10 "cc" 20] str))
    )
    "aa10cc20"
)
(test/exec :static-function-concat4
    (fn ->
        ; non-string types throws an exception
        (is? (try (.string/concat "aa" 10 "cc" 20)) ^Exception)
    )
    true
)
(test/exec :type-member-access1
    #(.ispublic ^string)
    true
)
(test/exec :type-member-access2
    #(.ispublic ^type)
    true
)
(test/exec :type-member-access3
    ; accessing properties (e.g. IsPublic) was broken; this test helps make sure it won't happen again.
    ; It expects at least 4 assembles with 25 types per assembly. It's a low count but a low count is necessary
    ; to make the test pass on all platforms.
    #(.AppDomain/CurrentDomain | .GetAssemblies | lazy-flatmap (fn a -> (.GetTypes a | take 25))
        | lazy-filter .?ispublic | take 100 | count)
    100
)
(test/exec :type-member-access4
    ; Flakey test but all version of .Net should have atleast 100 members.
    #(.getmembers ^string | count | > 100)
    true
)
(test/exec :members-as-functions1
    (fn ->
        ; testing turn a method into a function through assignment
        (let ss .substring)
        (ss "hello there" 5 5)
    )
    " ther"
)
(test/exec :members-as-functions2
    (fn ->
        ; testing turn a method into a function through assignment
        (let grange .getrange)
        (grange (range 100 | to-vector) 5 5)
    )
    [6 7 8 9 10]
)
(test/exec :members-as-functions3
    (fn ->
        ; testing turn a method into a function through assignment
        (let enumerate .getenumerator)
        ("hello" | enumerate | to-vector)
    )
    [ \h \e \l \l \o ]
)

;-------------------------------------------------------
; Test the BraidComparer class
(test/exec :braidlang-comparer1
    (fn ->
        ; test binary search on a vector
        (.binarysearch [1 2 3 4 5 6 7 8 9] 6
            (^BraidComparer? (fn x y -> (matchp x | (< y) -> -1 | (== y) -> 0 | -> 1))))
    )
    5
)
(test/exec :braidlang-comparer2
    (fn ->
        ; test a sorted dictionary with a custom comparer
        (let sortedDict
            (new
                ^System.Collections.Generic.SortedDictionary[object,object]
                (^BraidComparer?  (fn x y -> (matchp x | (< y) -> -1 | (== y) -> 0 | -> 1)))
            )
        )
        (!! sortedDict "b" 2)
        (!! sortedDict "a" 1)
        (!! sortedDict "d" 4)
        (!! sortedDict "c" 3)
        (sortedDict | map .value)
    )
    [1 2 3 4]
)

;-------------------------------------------------------
; test the '.' member access function
(test/exec :.1
    (fn ->
        (. "abcde" :length)
    )
    5
)
(test/exec :.2
    (fn ->
        (. "abcde" :substring 1)
    )
    "bcde"
)
(test/exec :.3
    (fn ->
        (. "abcde" :substring 1 3)
    )
    "bcd"
)
(test/exec :.4
    (fn ->
        ; indirect method invocation
        (let method-name "substring")
        (. "abcde" method-name 1 3)
    )
    "bcd"
)
(test/exec :.5
    (fn ->
        ; indirect method invocation
        (let method-name "add")
        (let v [1 2])
        (. v method-name 3)
        v
    )
    [1 2 3]
)
(; BUGBUGBUG - doesn't work - can't call parameterized properties (TBD .net interop)
(test/exec :.6
    (fn ->
        (let v [1 2 3])
        (. v :item 1)
    )
    2
)
;)

;-------------------------------------------------------
; test the various fibonacci functions
(test/exec :fib1
    #(fib 10)
    89
)
(test/exec :fib2
    #(fib 20)
    10946
)

; uses the iterator function
(test/exec :iterfib1
    #(iterfib 10)
    89
)
(test/exec :iterfib2
    #(iterfib 100)
    573147844013817084101
)

; test the iterative/imperative implementation
(test/exec :fastfib1
    #(fastfib 10)
    89
)
(test/exec :fastfib2
    #(fastfib 20)
    10946
)
(test/exec :fastfib3
    (fn ->
        (fastfib 200)
    )
    453973694165307953197296969697410619233826
)

;-------------------------------------------------------
; test the 'zip' function
(test/exec :zip1  #(zip [1 2 3] [4 5 6]) [[1 4] [2 5] [3 6]])
(test/exec :zip2  #(zip [1 2 3] [4 5 6 7]) [[1 4] [2 5] [3 6]])
(test/exec :zip3  #(zip [1 2 3 5] [4 5]) [[1 4] [2 5]])
(test/exec :zip4
    ; zip with lambda
    #(range 5 | zip (range 5) (fn x y -> [x y]))
    [[1 1] [2 2] [3 3] [4 4] [5 5]]
)
(test/exec :zip5
    #(range 5 | zip (range 5) (fn x y -> (+ x y)))
    [2 4 6 8 10]
)
(test/exec :zip6
    ; zip then reduce
    #(range 500
        | zip (range 500) (fn x y -> (+ x y))
        | reduce (fn x y -> (+ x y))
    )
    250500
)
(test/exec :zip7
    (fn ->
        ; multiple zips + concat to produce 3 3 item lists
        (range 3 | zip (range 3) | zip (range 3) concat)
    )
    [[1 1 1] [2 2 2] [3 3 3]]
)
(test/exec :zip8
    (fn ->
        ; multiple zips + concat to produce 3 4 item lists
        (range 3 | zip (range 3) | zip (range 3) concat | zip (range 3) concat)
    )
    [[1 1 1 1] [2 2 2 2] [3 3 3 3]]
)
(test/exec :zip9
    (fn ->
        ; implement our own "zip" function
        (defn zip2
            | _ x nil -> x
            | _ nil y -> y
            | f x:xs y:ys -> (cons (f x y) (zip2 f xs ys))
        )
        ; using built-in
        (zip2 + (range 5) (range 5))
    )
    [2 4 6 8 10]
)
(test/exec :zip10
    (fn ->
        ; implement our own "zip" function
        (defn zip2
            | _ x nil -> x
            | _ nil y -> y
            | f x:xs y:ys -> (cons (f x y) (zip2 f xs ys))
        )
        ; using user lambda
        (zip2 (fn x y -> [x y]) (range 5) (range 5))
    )
    [[1 1] [2 2] [3 3] [4 4] [5 5]]
)

;-------------------------------------------------------
; test dictionaries
(test/exec :dictionary1
    (fn ->
        (let x {:a 1 :b 2 :c 3})
        ; keyword indexing
        [(:c x) (:a x) (:b x)]
    )
    [3 1 2]
)
(test/exec :dictionary2
    (fn ->
        (let x {:a 1 :b 2 :c 3})
        [(x | .keys | .count) (x | .values | .count)]
    )
    [3 3]
)
(test/exec :dictionary3
    (fn ->
        ; test dictionary literals as functions
        ({:a 1 :b 11 :c 111} :b)
    )
    11
)
(test/exec :dictionary4
    (fn ->
        ({:a 1 :b 11 :c 111} :c)
    )
    111
)
(test/exec :dictionary5
    (fn ->
        (let dict {:a 1 :b 11 :c 111})
        ; test expressions that result in dictionaries behave like functions
        (dict :b)
    )
    11
)
(test/exec :dictionary5a
    (fn ->
        (let dict {:a 1 :b 11 :c 111})
        ; test expressions that result in dictionaries behave like functions
        (dict :d)
    )
    null
)
(test/exec :dictionary6
    (fn ->
        (let dict {:a 1 :b 11 :c 111})
        (let key :c)
        (dict key)
    )
    111
)
(test/exec :dictionary7
    (fn ->
        (let dict {:a 1 :b 11 :c 111})
        (let key :c)
        (dict key 222) ; assign to an existing key
    )
    {:a 1 :b 11 :c 222}
)
(test/exec :dictionary8
    (fn ->
        (let dict {:a 1 :b 11 :c 111})
        (let key :d)
        (dict key 222) ; add a new key
    )
    {:a 1 :b 11 :c 111 :d 222}
)

; basic value comparison of dictionaries
(test/exec :dictionary_comparison1
    #(do
        (== {:a 1 :b 2 :c 3} {:a 1 :b 2 :c 3})
    )
    true
)

; compare with keys in a different order.
(test/exec :dictionary_comparison2
    #(do
        (== {:a 1 :b 2 :c 5} {:b 2 :a 1 :c 5})
    )
    true
)

; comparison where the keys are different
(test/exec :dictionary_comparison3
    #(do
        (== {:a 1 :b 2 :c 3} {:a 1 :b 3 :c 3})
    )
    false
)

; comparison where the number of keys is different
(test/exec :dictionary_comparison4
    (fn ->
        (== {:a 1 :b 2 :c 3} {:a 1 :b 2})
    )
    false
)

; test splatting in dictionaries (see splatting tests elsewhere.)
(test/exec :dictionary_splatting1
    (fn ->
        (let x {:b 2 :c 3})
        {:a 1 @x :d 4}
    )
    {:a 1 :b 2 :c 3 :d 4}
)
(test/exec :dictionary_splatting2
    (fn ->
        (let x [1 2 3 4]) ; splat vector
        {:a 1 @x :d 4}
    )
    {:a 1 1 2 3 4 :d 4}
)
(test/exec :dictionary_splatting3
    (fn ->
        (let x (range 4)) ; splat range
        {:a 1 @x :d 4}
    )
    {:a 1 1 2 3 4 :d 4}
)
(test/exec :dictionary_splatting4
    (fn ->
        {:a 1 @(range 4) :d 4} ; splat range inline
    )
    {:a 1 1 2 3 4 :d 4}
)

; test dictionary literals as functions
(test/exec :dictionary_literal1
    (fn ->
        ({:a 1 :b 2} :b)
    )
    2
)
(test/exec :dictionary_literal2
    (fn ->
        ({:a 1 :b 2} :c)
    )
    null
)
(test/exec :dictionary_literal3
    (fn ->
        ({:a 1 :b 2} :b 3)  ; replace a value
    )
    {:a 1 :b 3}
)
(test/exec :dictionary_literal4
    (fn ->
        ({:a 1 :b 2} :c 3) ; add a value
    )
    {:a 1 :b 2 :c 3}
)

;-------------------------------------------------------
; test basic vector type
(test/exec :vector1
    (fn -> [1 2 3])
    [1 2 3]
)
(test/exec :vector1a
    (fn -> (type-of [1 2 3]))
    ^vector
)
(test/exec :vector2
    (fn ->
        [1 2 [:a :b :c] 3]
    )
    [1 2 [:a :b :c] 3]
)
(test/exec :vector3
    (fn ->
        ([1 2 [:a :b :c] 3] 2)
    )
    [:a :b :c]
)
(test/exec :vector4
    (fn ->
        ; nested implicit indexing
        (([1 2 [:a :b :c] 3] 2) 1)
    )
    :b
)
(test/exec :vector5
    (fn ->
        ; assignment returns the updated (inner) vector
        (([1 2 [:a :b :c] 3] 2) 1 "hello")
    )
    [:a "hello" :c]
)
(test/exec :vector6
    (fn ->
        (let v [1 2 [:a :b :c] 3])
        ; nested assignment
        ((v 2) 1 "hello")
        v
    )
    [1 2 [:a "hello" :c] 3]
)
; test splatting into a vector...
(test/exec :vector_splatting1
    (fn ->
        (let sp [3 4 5])
        [1 2 @sp 6]
    )
    [1 2 3 4 5 6]
)
(test/exec :vector_error1
    (fn ->
        (try ([1 2 3 4] 100) | is? ^Exception)
    )
    true
)
(test/exec :vector_error2
    (fn ->
        (try ([1 2 3 4] -100) | is? ^Exception)
    )
    true
)
(test/exec :vector7
    #([1 2 3 4] -1)
    4
)
(test/exec :vector8
    #([1 2 3 4] -2)
    3
)
(test/exec :vector9
    #([1 2 3 4] -4)
    1
)
(test/exec :vector10
    (fn ->
        (new ^vector | type-of)
    )
    ^vector
)
(test/exec :vector11
    (fn ->
        (let stk (new ^vector))
        (.push stk 1 | .push 2 | .push 3)
        (and
            (count stk | == 3)
            (.pop stk | == 3)
            (.pop stk | == 2)
            (.pop stk | == 1))
    )
    true
)
(test/exec :vector12
    (fn ->
        ; reverse function using a vector as a stack
        (defn stkrev [lst]
            (let stk (new ^vector))
            ; push all the numbers onto the stack
            (lst | each (fn e -> (.push stk e)))
            ; then retrieve them in (reversed) order.
            [ @stk ]
        )
        (stkrev [1 2 3 4])
    )
    [4 3 2 1]
)
; tests vector methods but also CreateDelegate
(test/exec :CreateDelegate1
    (fn ->
        ; member inherited from List.
        (.trueForAll [1 2 3 4 5] (Createdelegate ^System.Predicate[System.Object] (> 0)))
    )
    true
)
(test/exec :CreateDelegate2
    (fn ->
        (.trueForAll [1 3 5] (Createdelegate ^Predicate[System.Object] (% 2)))
    )
    true
)
(test/exec :CreateDelegate3
    (fn ->
        (.trueForAll [1 3 4 5] (Createdelegate ^Predicate[System.Object] (% 2)))
    )
    false
)
(test/exec :vector16   #(.count [1 2 3])   3)
(test/exec :vector17   #(do (let x [1 2]) (.add x 3) x)   [1 2 3])
(test/exec :vector18   #(.car [1 2 3])                    1)
(test/exec :vector19   #(.cdr [1 2 3])                    [2 3])
(test/exec :vector20   #(do (let x [1 2]) (.push x 0) x)  [0 1 2])
(test/exec :vector21   #(.pop [1 2 3])                    1)
(test/exec :vector22   #(do (let x [1 2 3]) (.pop x) x)   [2 3])
(test/exec :vector23   #(.dequeue [1 2 3])                3)
(test/exec :vector24   #(do (let x [1 2]) (.addrange x [3 4 5]) x) [1 2 3 4 5])
(test/exec :vector25   #(.indexof [1 2 3 4] 3)            2)
(test/exec :vector26   #(.lastindexof [1 2 3 1 2 3] 2)    4)
(test/exec :vector27
    (fn ->
        (.find [1 2 3 4 5] (createdelegate ^Predicate[object] (fn n -> (== n 3))))
    )
    3
)
(test/exec :vector28
    (fn ->
        (let v [ {:a 1 :b 0} {:a 2 :b 1} {:a 3 :b 1}])
        (.find v (createdelegate ^Predicate[object] (fn n -> (n :b))))
    )
    {:a 2 :b 1}
)
(test/exec :vecto29
    (fn ->
        (.findindex [1 2 3 4 5] (createdelegate ^Predicate[object] (fn n -> (== n 3))))
    )
    2
)
(test/exec :vecto29a
    (fn ->
        ; pattern function
        (.findindex [1 2 3 4 5] (createdelegate ^Predicate[object] (fn | n -> (== n 3))))
    )
    2
)
(test/exec :vector30
    (fn ->
        (let v [ {:a 1 :b 0} {:a 2 :b 1} {:a 3 :b 1}])
        (.findindex v (createdelegate ^Predicate[object] (fn n -> (n :b))))
    )
    1
)
(test/exec :vector31
    (fn ->
        (let v [ {:a 1 :b 0} {:a 2 :b 1} {:a 3 :b 1}])
        (.findlast v (createdelegate ^Predicate[object] (fn n -> (n :b))))
    )
    {:a 3 :b 1}
)
(test/exec :vector32
    (fn ->
        (let v [ {:a 1 :b 0} {:a 2 :b 1} {:a 3 :b 1}])
        (.findlastindex v (createdelegate ^Predicate[object] (fn n -> (n :b))))
    )
    2
)
(test/exec :vector32a
    (fn ->
        (let v [ {:a 1 :b 0} {:a 2 :b 1} {:a 3 :b 1}])
        ; pattern function
        (.findlastindex v (createdelegate ^Predicate[object] (fn | n -> (n :b))))
    )
    2
)

;------------------------------------------------------
; test implict indexing on arrays, including muli-dimensional ones
(test/exec :ImplicitArrayIndexing1
    (fn ->
        ; simple scalar indexing
        ((new-array ^int 3 1 2 3) 1)
    )
    2
)
(test/exec :ImplicitArrayIndexing2
    (fn ->
        ; index with a vector
        ((new-array ^int 3 1 2 3)[1])
    )
    2
)
(test/exec :ImplicitArrayIndexing3
    (fn ->
        ; test 2-dimensional arrays.
        (let arr (new ^int[,] 2 2))

        ; initialixe the 2d array
        (arr[0 0] 1)
        (arr[1 0] 2)
        (arr[0 1] 3)
        (arr[1 1] 4)

        ; return the values reversed
        [ (arr[1 1]) (arr[0 1]) (arr[1 0]) (arr[0 0]) ]
    )
    [4 3 2 1]
)
(test/exec :ImplicitArrayIndexing4
    (fn ->
        ; test 3-dimensional arrays.
        (let arr (new ^double[,,] 2 2 2))

        ; initialixe the 2d array
        (arr[1 1 1] PI)

        ; return the values reversed
        (arr[1 1 1])
    )
    PI
 )

;------------------------------------------------------
; Test the 'and' function - returns thd value of the last argument
; if all arguments are true.
(test/exec :and1 #(and true true) true)
(test/exec :and2 #(and true false) false)
(test/exec :and3 #(and false true) false)
(test/exec :and4 #(and true true false true) false)
(test/exec :and5 #(and true true true true) true)
(test/exec :and6 #(and 1 true "abc") "abc")
(test/exec :and7
    (fn -> (let x false) (and true (let x true)) x)
    true
)
(test/exec :and8
    (fn -> (let x false) (and false (let x true)) x)
    false
)
(test/exec :and9
    (fn ->
        (and true true 13)
    )
    13
)
(test/exec :and10
    (fn ->
        (and 0 true 13)
    )
    0
)
(test/exec :and11
    (fn ->
        (and 6 "" 13)
    )
    False
 )

;------------------------------------------------------
; Test the 'or' function.
(test/exec :or1   #(or true true)         true)
(test/exec :or2   #(or true false)        true)
(test/exec :or3   #(or true true true)    true)
(test/exec :or4   #(or false true false)  true)
(test/exec :or5   #(or false false false) false)
(test/exec :or6   #(or 1 1)               true)
(test/exec :or7   #(or 1 0)               true)
(test/exec :or8   #(or 1 1 1)             true)
(test/exec :or9   #(or 0 1 0)             true)
(test/exec :or10  #(or 0 0 0)             false)
(test/exec :or11  #(or "abc" "abc")       "abc")
(test/exec :or12  #(or "abc" "")          "abc")
(test/exec :or13  #(or "abc" "abc" "abc") "abc")
(test/exec :or14  #(or "" "abc" "")       "abc")
(test/exec :or15  #(or "" "" "")          false)
(test/exec :or16  #(do (let x 0) (or true (let x 1)) x)  0)
(test/exec :or17  #(do (let x 0) (or false (let x 1)) x)  1)
(test/exec :or18  #(or 0 36 true) 36)

;------------------------------------------------------
; Test the 'not' function
(test/exec :not10 #(not true) false)
(test/exec :not12 #(not false) true)
(test/exec :not13 #(false | not | not) false)
(test/exec :not14 #(0 | not) true)
(test/exec :not15 #(1 | not) false)
(test/exec :not16 #("" | not) true)
(test/exec :not17 #("true" | not) false)

;------------------------------------------------------
; Test the bitwise 'band' function
(test/exec :band1 #(band 0xff 0xf0) 0xf0)
(test/exec :band2 #(band 0xff 0x05) 5)
(test/exec :band3 #(band 0xff 0x00) 0)
(test/exec :band4 #(band 0xff 0x03 0b0001) 1)
(test/exec :band5
    (fn ->
        ; test curry
        (vector 0b000 0b0001 0b1010 | map (band 0x7))
    )
    [0 1 2]
)

;------------------------------------------------------
; Test the bitwise 'bor' function
(test/exec :bor1 #(bor 0x5 0xf) 0xf)
(test/exec :bor2 #(bor 0x5 0x10) 21)
(test/exec :bor3 #(bor 0b0001 0b0010 0b0100 0b1000) 0xf)
(test/exec :bor4
    (fn ->
        ; test curry
        (vector 0b000 0b0001 0b0010 | map (bor 0b1000))
    )
    [8 9 10]
)

;------------------------------------------------------
; Test the bitwise 'bnot' function
(test/exec :bnot1  #(bnot -1) 0)
(test/exec :bnot2  #(bnot 0) -1)
(test/exec :bnot3  #(bnot 1) -2)

;------------------------------------------------------
; Test the bitwise exclusive or'bxor' function
(test/exec :bxor1 #(bxor 0x5 0xf) 10)
(test/exec :bxor2 #(bxor 0x5 0x10) 21)
(test/exec :bxor3:
    ; xor twice puts you back where you started
    #(bxor 0x55 (bxor 0x11 0x55))
    0x11
)
(test/exec :bxor4:
    (fn ->
        ; swap two variables with XOR
        (let x 123)
        (let y 456)
        (let x (bxor x y))
        (let y (bxor y x))
        (let x (bxor x y))
        [x y]
    )
    [456 123]
)

;------------------------------------------------------
; Test the 'shiftr' function
(test/exec :shiftr1 #(shiftr 1 1) 0)
(test/exec :shiftr2 #(shiftr 2 1) 1)
(test/exec :shiftr3 #(shiftr 0x0f 3) 1)
(test/exec :shiftr4 #(shiftr 0xff00 8) 0xFF)
(test/exec :shiftr5 #(shiftr 0xfffffffff 1) 0x7fffffff)

;------------------------------------------------------
; Test the 'shiftl' function
(test/exec :shiftl1 #(shiftl 0 1) 0)
(test/exec :shiftl2 #(shiftl 1 1) 2)
(test/exec :shiftl3 #(shiftl 1 4) 16)
(test/exec :shiftl4 #(shiftl 0 5) 0)
(test/exec :shiftl5 #(shiftl 0xffffff 1) 0x1fffffe)
(test/exec :shiftl6 #(shiftl 0xffffff 4) 0xffffff0)

;------------------------------------------------------
; Test the 'roll' function
(test/exec :roll1
    (fn ->
        (hex (roll 0xdeadbeef 16))
    )
    "0xbeefdead"
)
(test/exec :roll2
    (fn ->
        (roll 0xdeadbeef 4)
    )
    0xeadbeefd
)
(test/exec :roll3
    (fn ->
        (roll 0xdeadbeef 8)
    )
    0xadbeefde
)
(test/exec :roll4
    (fn ->
        (roll 0xdeadbeef 16)
    )
    0xbeefdead
)
(test/exec :roll5
    (fn ->
        (roll 0 16)
    )
    0
)
(test/exec :roll6
    (fn ->
        (roll 0xffff_ffff 16)
    )
    0xffff_ffff
)

;------------------------------------------------------
; Test the 'rolr' function
(test/exec :rolr1
    (fn ->
        (hex (rolr 0xdeadbeef 16))
    )
    "0xbeefdead"
)
(test/exec :rolr2
    (fn ->
        (rolr 0xdeadbeef 4)
    )
    0xfdeadbee
)
(test/exec :rolr3
    (fn ->
        (rolr 0xdeadbeef 8)
    )
    0xefdeadbe
)
(test/exec :rolr4
    (fn ->
        (rolr 0xdeadbeef 12)
    )
    0xeefdeadb
)
(test/exec :rolr5
    (fn ->
        (rolr 0 16)
    )
    0
)
(test/exec :rolr6
    (fn ->
        (rolr 0xffff_ffff 16)
    )
    0xffff_ffff
)

;------------------------------------------------------
; Test the match function
(test/exec :re/match1
    (fn ->
        (re/match "abcd"  #"ab")
    )
    true
)
(test/exec :re/match1a
    (fn ->
        (re/match "AbCd"  #"ab")
    )
    true
)
(test/exec :re/match1b
    (fn ->
        (re/match "AbCd" "ab")
    )
    true
)
(test/exec :re/not-match1
    (fn ->
        (re/not-match "abcd"  #"xyz")
    )
    true
)
(test/exec :re/not-match1a
    (fn ->
        ; implicitly converts strings into regexes
        (re/not-match "abcd" "xyz")
    )
    true
)
(test/exec :re/not-match2
    (fn ->
        (re/not-match "abcd"  #"abc")
    )
    false
)
(test/exec :re/not-match2a
    (fn ->
        (re/not-match "ABCD"  #"abc")
    )
    false
)
(test/exec :re/not-match2b
    (fn ->
        (re/not-match "ABCD" "abc")
    )
    false
)
(test/exec :re/match2
    (fn ->
        (re/match "abcd"  #"xyz")
    )
    false
)
(test/exec :re/match3
    (fn ->
        (re/match -notmatch "abbbcd"  #"^a.*d$")
    )
    false
)
(test/exec :re/not-match3
    (fn ->
        (re/not-match "abcd"  #"ab")
    )
    false
)
(test/exec :re/match4
    (fn ->
        (re/match -notmatch "abcd"  #"xyz")
    )
    true
)
(test/exec :re/not-match4
    (fn ->
        (re/not-match "abcd"  #"xyz")
    )
    true
)
(test/exec :re/match5
    (fn ->
        (re/match "abc"  #"ab" (fn m -> (str "<<" m ">>")))
    )
    "<<abc>>"
)
(test/exec :re/match5a
    (fn ->
        (re/match -notmatch "abc"  #"ab" (fn m -> (str "<<" m ">>")))
    )
    false
)
(test/exec :re/match6
    (fn ->
        (re/match 1234  #"3")
    )
    true
)
(test/exec :re/match6a
    (fn ->
        (re/match -notmatch 1234 "3")
    )
    false
)
(test/exec :re/match6b
    (fn ->
        (re/match -notmatch 1234 "7")
    )
    true
)
(test/exec :re/match6c
    (fn ->
        ; re/match allows coercion on its arguments.
        (re/match -notmatch 1234 3)
    )
    false
)
(test/exec :re/match6d
    (fn ->
        ; re/match allows coercion on its arguments.
        (re/match -notmatch 1234 7)
    )
    true
)

;------------------------------------------------------
; Test the match-all function
(test/exec :re/match-all1
    (fn ->
        (["a", "b", "c", "d"] | re/match-all  #"[ab]")
    )
    ["a" "b"]
)
(test/exec :re/match-all2
    (fn ->
        (["a", "b", "c", "d"] | re/match-all -notmatch  #"[ab]")
    )
    ["c" "d"]
)
(test/exec :re/match-all3
    (fn ->
        (["a", "b", "c", "d"] | re/match-all "[ab]")
    )
    ["a" "b"]
)
(test/exec :re/match-all4
    (fn ->
        (["a", "b", "c", "d"] | re/match-all -notmatch "[ab]")
    )
    ["c" "d"]
)
(test/exec :re/match-all5
    (fn ->
        (["A", "B", "C", "D"] | re/match-all "[ab]")
    )
    ["a" "b"]
)
(test/exec :re/not-match-all1
    (fn ->
        (["A", "B", "C", "D"] | re/not-match-all  #"[ab]")
    )
    ["c" "d"]
)
(test/exec :re/not-match-all2
    (fn ->
        (["A", "B", "C", "D"] | re/not-match-all "[ab]")
    )
    ["c" "d"]
)

;------------------------------------------------------
; test the replace function
(test/exec :re/replace1
    (fn ->
        (re/replace "a-b-c"  #"-" )
    )
    "abc"
)
(test/exec :re/replace2
    (fn ->
        (re/replace "a-b-c"  #"-" "+")
    )
    "a+b+c"
)
(test/exec :re/replace3
    (fn ->
        ("a-b-c" | re/replace  #"-")
    )
    "abc"
)
(test/exec :re/replace4
    (fn ->
        ("a-b-c" | re/replace  #"-" "+")
    )
    "a+b+c"
)
(test/exec :re/replace5
    (fn ->
        ("a-b-c" | re/replace  #"(.)-(.)-(.)" "$3 $2 $1")
    )
    "c b a"
)
;------------------------------------------------------
; test the replace-all function
(test/exec :re/replace-all1
    (fn ->
        (["a-b", "c-d", "e-f"] | re/replace-all  #"-")
    )
    ["ab" "cd" "ef"]
)
(test/exec :re/replace-all2
    (fn ->
        (["a-b", "c-d", "e-f"] | re/replace-all  #"-" "++")
    )
    ["a++b" "c++d" "e++f"]
)
(test/exec :re/replace-all3
    (fn ->
        (["a-b", "c-d", "e-f"] | re/replace-all  #"(.)-(.)" "$2+$1")
    )
    ["b+a" "d+c" "f+e"]
)

;------------------------------------------------------
; Test the 'matchp' function
(test/exec :matchp1
    (fn ->
        ; match on types...
        (matchp 1
        | ^int      -> "int"
        | ^string   -> "string"
        | ^List     -> "list"
        | ^Vector   -> "vector"
        )
    )
    "int"
)
(test/exec :matchp2
    (fn ->
        (matchp "a string"
        | ^int      -> "int"
        | ^string   -> "string"
        | ^List     -> "list"
        | ^Vector   -> "vector"
        )
    )
    "string"
)
(test/exec :matchp3
    (fn ->
        (matchp '(1 2 3)
        | ^int      -> "int"
        | ^string   -> "string"
        | ^List     -> "list"
        | ^Vector   -> "vector"
        )
    )
    "list"
)
(test/exec :matchp4
    (fn ->
        (matchp [1 2 3]
        | ^int      -> "int"
        | ^string   -> "string"
        | ^List     -> "list"
        | ^Vector   -> "vector"
        )
    )
    "vector"
)
; test matching on arity
(test/exec :matchp5
    (fn ->
        (matchp 1
        | x y z -> [x y z]
        | x y   -> [x y]
        | x     -> x
        )
    )
    1
)
(test/exec :matchp6
    (fn ->
        (matchp 1 2
        | x y z -> [x y z]
        | x y   -> [x y]
        | x     -> x
        )
    )
    [1 2]
)
(test/exec :matchp7
    (fn ->
        (matchp 1 2 3
        | x y z -> [x y z]
        | x y   -> [x y]
        | x     -> x
        )
    )
    [1 2 3]
)
; test destructuring
(test/exec :matchp8
    (fn ->
        (matchp [1 2 3] [4 5 6]
        | x:y:z: a:b:c: -> [(+ x a) (+ y b) (+ z c)]
        )
    )
    [5 7 9]
)
; test regex matching
(test/exec :matchp9
    (fn ->
        (matchp "aaaa"
        |  #"a+" -> "a"
        |  #"bb" -> "b"
        |  #"c$" -> "c"
        )
    )
    "a"
)
(test/exec :matchp9a
    (fn ->
        (matchp "bbccdd"
        |  #"a+" -> "a"
        |  #"bb" -> %0 ; gets the value being matched
        |  #"c$" -> "c"
        )
    )
    "bbccdd"
)
(test/exec :matchp10
    (fn ->
        (matchp "_____c"
        |  #"a+" -> "a"
        |  #"bb" -> %0
        |  #"c$" -> "c"
        )
    )
    "c"
)
(test/exec :matchp10a
    (fn ->
        ; test binding multiple variables
        (matchp "a_____c"
        |  #"aa+" -> "a"
        |  #"bb" -> %0
        | (#"^(a)_*(c)$" _:one:two:) -> [two one]
        )
    )
    ["c" "a"]
)
(test/exec :matchp11
    (fn ->
        (matchp 1 20
        | 1 v   -> "1 ${v}"
        | 2 V   -> "2 ${v}"
        | 3 v   -> "3 ${v}"
        )
    )
    "1 20"
)
(test/exec :matchp12
    (fn ->
        (matchp 2 "abc"
        | 1 v   -> "1 ${v}"
        | 2 V   -> "2 ${v}"
        | 3 v   -> "3 ${v}"
        )
    )
    "2 abc"
)
(test/exec :matchp13
    (fn ->
        (matchp 3 [1 2 3 4]
        | 1 v   -> v
        | 2 V   -> v
        | 3 v   -> [@v 5]
        )
    )
    [1 2 3 4 5]
)
(test/exec :matchp14
    (fn ->
        (matchp 3
        |  #(< %0 5)  -> "less"
        |  #(== %0 5) -> "equals"
        |  #(> %0 5)  -> "more")
    )
    "less"
)
(test/exec :matchp15
    (fn ->
        (matchp 5
        |  #(< %0 5)  -> "less"
        |  #(== %0 5) -> "equals"
        |  #(> %0 5)  -> "more"
        )
    )
    "equals"
)
(test/exec :matchp16
    (fn ->
        (matchp 10
        |  #(< %0 5)  -> "less"
        |  #(== %0 5) -> "equals"
        |  #(> %0 5)  -> "more"
        )
    )
    "more"
)
(test/exec :matchp16a
    (fn ->
        (defn divisible-by [x factor] (not (% x factor)))
        (range 15 | map (fn
                |  #(divisible-by %0 15) -> "fizbuz"
                |  #(divisible-by %0 5)  -> "buz"
                |  #(divisible-by %0 3)  -> "fiz"
                | (^int n)              -> n
            )
        )
    )
    [1 2 "fiz" 4 "buz" "fiz" 7 8 "fiz" "buz" 11 "fiz" 13 14 "fizbuz"]
)
(test/exec :matchp17
    (fn ->
        (matchp 1 2 3 | 1 &xs -> xs)
    )
    [2 3]
)
(test/exec :matchp17a
    (fn ->
        (matchp 1 2 3 | 1 2 &xs -> xs)
    )
    [3]
)
(test/exec :matchp17b
    (fn ->
        (matchp 1 2 3 | 1 2 3 &xs -> xs)
    )
    null
)
(test/exec :matchp17c
    (fn ->
        (matchp | &xs -> xs)
    )
    null
)
(test/exec :matchp17d
    (fn ->
        (matchp | -> )
    )
    nil
)
(test/exec :matchp18
    (fn ->
        (matchp [1 2 3]
        | x:xs  -> [@xs x]
        )
    )
    [2 3 1]
)
(test/exec :matchp19
    (fn ->
        (matchp [1 2 3]
        | a:b:  -> "ab"
        | x:xs  -> "xs"
        )
    )
    "xs"
)
(test/exec :matchp20
    (fn ->
        (matchp 10
        | n     ->  1
        | n m   ->  2
        | n m o ->  3
        )
    )
    1
)
(test/exec :matchp21
    (fn ->
        (matchp 10 11
        | n     ->  1
        | n m   ->  2
        | n m o ->  3
        )
    )
    2
)
(test/exec :matchp22
    (fn ->
        (matchp 10 11 12
        | n     ->  1
        | n m   ->  2
        | n m o ->  3
        )
    )
    3
)
(test/exec :matchp23
    (fn ->
        (matchp @(re/split "foo | .ab")
        ; test explicit variable binding
        | (#"^[a-z]+$" v) "|" (#"^\..*$" m) ->
            [v m]
        )
    )
    ["foo" ".ab"]
)
(test/exec :matchp24
    (fn ->
        ; test null default action
        ((matchp 13 | 10 -> "text" | -> ) | == null)
    )
    true
)
(test/exec :matchp25
    (fn ->
        ; test begin action
        (let zork false)
        (let result (matchp 5 | ^ -> (let zork true) | 5 -> (* %0 5)))
        [zork result]
    )
    [true 25]
)
(test/exec :matchp26
    (fn ->
        ; test begin action
        (let zork false)
        (let result (matchp 5 | 5 -> (* %0 5) | ^ -> (let zork true)))
        [zork result]
    )
    [true 25]
)
(test/exec :matchp27
    (fn ->
        (let zork [])
        (let result
            (matchp 5
            | ^ ->  (.add zork 1)
            | 5 -> (.add zork (* %0 5))
            | $ -> (.add zork 10)
            )
        )
        zork
    )
    [1 25 10]
)
(test/exec :matchp28
    (fn ->
        ;  test empty begin, default and end clauses
        (matchp 5
        | ^ ->
        |   ->
        | $ ->
        )
    )
    null
)
(test/exec :matchp29
    (fn ->
        ;  test empty begin, default and end clauses
        (matchp 5
        | ^ ->
        | 5 ->
        | $ ->
        )
    )
    null
)
(test/exec :matchp30
    (fn ->
        ;  test empty begin,end with variable match
        (matchp 5
        | ^ ->
        | n ->
        | $ ->
        )
        ; match occurs in the current scope
        n
    )
    5
)
(test/exec :matchp31
    (fn ->
        (matchp 4
        | 0 ->
        | 4 ->  (matchp 5
                | ^ ->
                | n -> n
                | $ ->
                )
        | 5 -> 5
        | $ ->
        )
    )
    5
)
; test variable dereferencing in patterns.
(test/exec :matchp32
    (fn ->
        (let foo 13)
        (matchp 13 | %foo -> "match" | -> "not match")
    )
    "match"
)
(test/exec :matchp33
    (fn ->
        (let foo 13)
        (matchp 31 | %foo -> "match" | -> "not match")
    )
    "not match"
)
(test/exec :matchp34
    (fn ->
        ; test rebinding in a pattern
        (matchp 10 11 11 10 | x y %y %x -> "match" | -> "not match")
    )
    "match"
)
(test/exec :matchp35
    (fn ->
        ; test rebinding in a pattern
        (matchp 10 11 11 11 | x y %y %x -> "match" | -> "not match")
    )
    "not match"
)
(test/exec :matchp36
    (fn ->
        (matchp [1 2] | x:xs -> "true" | -> "false")
    )
    "true"
)
(test/exec :matchp37
    (fn ->
        (matchp [1] | x:xs -> "true" | -> "false")
    )
    "true"
)
(test/exec :matchp38
    (fn ->
        (matchp [] | x:xs -> "true" | -> "false")
    )
    "false"
)
(test/exec :matchp39
    (fn ->
         (matchp [1] | x:y:_ -> 1 | x:y -> 2)
    )
    2
)
(test/exec :matchp40
    (fn ->
         (matchp [1 2] | x:y:_ -> 1 | x:y -> 2)
    )
    1
)
(test/exec :matchp41
    (fn ->
        ; test multiple conditions per action
        (defn foo [n]
            (matchp n
                | 1 | 3         -> "odd"
                | 8             -> "eight"
                | 2 | 4 | 6     -> "even"
                | 5 | 7 | 9     -> "also odd"
            )
        )
        (range 9 | map foo)
    )
    ["odd" "even" "odd" "even" "also odd" "even" "also odd" "eight" "also odd"]
)
(test/exec :matchp42
    (fn ->
        ; test a different set of multiple conditions per action
        (defn foo [n]
            (matchp n
                | 8             -> "eight"
                | 2 | 4 | 6     -> "even"
                | 1 | 3         -> "odd"
                | 9             -> "nine"
                | 5 | 7         -> "also odd"
            )
        )
        (range 9 | map foo)
    )
    ["odd" "even" "odd" "even" "also odd" "even" "also odd" "eight" "nine"]
)
(test/exec :matchp43
    (fn ->
        (defn foo [n]
            (matchp n
                | 5 | 7 | 9     -> "also odd"
                | 2 | 4 | 6     -> "even"
                | 1 | 3         -> "odd"
                | 8             -> "eight"
            )
        )
        (range 9 | map foo)
    )
    ["odd" "even" "odd" "even" "also odd" "even" "also odd" "eight" "also odd"]
)
(test/exec :matchp44
    (fn ->
        (defn foo [n]
            (matchp n
                | 8             -> "eight"
                | 2 | 4 | 6     -> "even"
                | 1 | 3         -> "odd"
                | 5 | 7         -> "also odd"
                | 9             -> "nine"
            )
        )
        (range 9 | map foo)
    )
    ["odd" "even" "odd" "even" "also odd" "even" "also odd" "eight" "nine"]
)
; test that destructuring returns a slice, except for lists
(test/exec :matchp45
    (fn -> (matchp "abcde" | x:xs -> (type-of xs)))
    ^BraidLang.Slice
)
(test/exec :matchp45a
    (fn -> (matchp [1 2 3 4 5] | x:xs -> (type-of xs)))
    ^BraidLang.Slice
)
(; BUGBUGBUG - Pattern matching doesn't work with arrays e.g. object[] - fix this
(test/exec :matchp45b
    (fn -> (matchp (asarray [1 2 3 4 5]) | x:xs -> (type-of xs)))
    ^BraidLang.Slice
)
;) ; END BUGBUGBUG
(test/exec :matchp45c
    (fn -> (matchp '(1 2 3 4 5) | x:xs -> (type-of xs)))
    ^BraidLang.s_Expr
)

;------------------------------------------------------
; test the indexing function '!!'
(test/exec :!!1  #(!! [1 2 3 4] 0)        1)
(test/exec :!!2  #(!! [1 2 3 4] 1)        2)
(test/exec :!!3  #(!! [1 2 3 4] -1)       4)
(test/exec :!!4  #(!! [1 2 3 4] -2)       3)
(test/exec :!!5  #(!! '(1 2 3 4) 0)       1)
(test/exec :!!6  #(!! '(1 2 3 4) 1)       2)
; BUGBUGBUG - negative indexing doesn't work on lists.
;(test/exec :!!7 #(!! '(1 2 3 4) -1)      4)
;test/exec :!!8  #(!! '(1 2 3 4) -2)      3)
(test/exec :!!9  (fn -> (let x [1 2 3]) (!! x 1 20) x)   [1 20 3])

; indexing into a dictionary
(test/exec :!!10  (fn -> (let x {:a 1 :b 2}) (!! x :b 20) x)   {:a 1 :b 20})
(test/exec :!!11  (fn -> (let x {:a 1 :b 2}) (let k :b) (!! x k 20) x)  {:a 1 :b 20})

; indexing into an array instead of a vector
(test/exec :!!12  (fn -> (let x (asarray [1 2 3])) (!! x 1 20) x)   [1 20 3])
; test indexing in pipes
(test/exec :!!13  #([1 2 3 4] | !! 0)      1)
(test/exec :!!14  #([1 2 3 4] | !! 1)      2)
; test indexing into a list; this is slow so it should be used sparingly
(test/exec :!!15  #(!! '(1 2 3 4) 0)       1)
(test/exec :!!16  #(!! '(1 2 3 4) 1)       2)
(test/exec :!!17  #('(1 2 3 4) | !! 0)     1)
(test/exec :!!18  #('(1 2 3 4) | !! 1)     2)
; indexing into a range enumerable
(test/exec :!!19  #(!! (range 10) 0)       1)
(test/exec :!!20  #(!! (range 10) 5)       6)
(test/exec :!!21  (fn -> (range 0 9 | map (fn x -> (range 10 | !! x)))) [1 2 3 4 5 6 7 8 9 10])
(test/exec :!!22  (fn -> (range 0 9 | map (fn x -> (range 10 | !! x)))) '(1 2 3 4 5 6 7 8 9 10))
(test/exec :!!23 (fn ->
        ; test out-of-bounds error...
        (is? (try ([] | !! 0)) ^Exception)
    )
    true
)

;------------------------------------------------------
; Test functions and 'defn'
(test/exec :defn1
    (fn ->
        (defn foo [x y] (+ x y))
        (foo 2 3)
    )
    5
)
; destructuring in function args
(test/exec :defn2
    (fn ->
        (defn foo [x:xs] xs)
        (foo [1 2 3 4])
    )
    [2 3 4]
)
(test/exec :tuple1
    (fn ->
        (defn foo [a:b:c:d] [d c b a])
        ; destructuring on tuples
        (foo (tuple 1 2 3 4))
    )
    [4 3 2 1]
)
(test/exec :defn2b
    (fn ->
        ; test destructuring on key/value pairs
        (.getenumerator {:x 1 :y 2 :z 3} | map (fn k:v: -> (str v ":" k)))
    )
    ["1:x" "2:y" "3:z"]
)
; pattern functions
(test/exec :defn3
    (fn ->
        (defn foo
        | x:xs y:ys -> (cons (+ x y) (foo xs ys))
        | nil  nil   -> nil
        )
        (foo [1 2 3] [1 2 3])
    )
    [2 4 6]
)
(test/exec :defn4
    (fn ->
        (defn foo [x y &args] (and (== x 2) (== y 3) (== args '(4 5 6))))
        (foo 2 3 4 5 6)
    )
    true
)
(test/exec :defn4a
    (fn ->
        (defn foo [x y &xs] (and (== x 2) (== y 3) (== xs '(4 5 6))))
        (foo 2 3 4 5 6)
    )
    true
)
(test/exec :defn5
    (fn ->
        ; test initializers
        (defn foo ^int [(^int x 1) (^int y 2)] (+ x y))
        (foo)
    )
    3
)
(test/exec :defn6
    (fn ->
        (defn foo ^int [(^int x 1) (^int y 2)] (+ x y))
        (foo 3)
    )
    5
)
(test/exec :defn7
    (fn ->
        (defn foo ^int [(^int x 1) (^int y 2)] (+ x y))
        (foo 3 5)
    )
    8
)
(test/exec :defn8
    (fn ->
        (defn foo ^int [x] x)
        (and
            (is? (foo 3) ^int)
            (== (foo 3) 3)
        )
    )
    true
)
(test/exec :defn9
    (fn ->
        (defn foo ^double [x] (^double? x))
        (is? (foo "1234") ^double)
    )
    true
)
(test/exec :defn10
    (fn ->
        (defn foo
            | n -> (foo (/ n 2) (* n 3))
            | n m -> [n m]
        )
        (foo 4)
    )
    [2 12]
)
(test/exec :defn11
    (fn ->
        (defn rev
            | x:xs -> (concat (rev xs) x)
            | x -> x
        )
        (rev [1 2 3 4 5])
    )
    [5 4 3 2 1]
)
(test/exec :defn12
    (fn ->
        (defn trev
            | n       -> (trev n nil)
            | nil m    -> m
            | x:xs m  -> (trev xs (cons x m))
        )
        (trev [1 2 3 4 5])
    )
    [5 4 3 2 1]
)
(test/exec :defn13
    (fn ->
        (defn trev2
            | n       -> (recur n nil)
            | nil m    -> m
            | x:xs m  -> (recur xs (cons x m))
        )
        (trev2 [1 2 3 4 5])
    )
    [5 4 3 2 1]
)
(test/exec :defn14
    (fn ->
        ; test destructuring in function args
        (defn multi1 [x:xs] (concat xs x))
        (multi1 [1 2 3])
    )
    [2 3 1]
)
(test/exec :defn15
    (fn ->
        ; recursive list reverse using function argument destructuring
        (defn mrev [x:xs]
            (if xs
                (concat (mrev xs) x)
                x
            )
        )
        (mrev [1 2 3 4 5])
    )
    [5 4 3 2 1]
)
(test/exec :defn16
    (fn ->
        ; destructuring cmd line args
        (defn addargs
            | x       -> x
            | x &xs -> (+ x (addargs @xs))
        )
        (addargs 1 2 3 4 5)
    )
    15
)
(test/exec :defn17
    (fn ->
        ; a zip like function
        (defn make-pairs
            | x:xs y:ys   -> (cons [x y] (make-pairs xs ys))
            | nil _       -> nil
            | _ nil       -> nil
        )
        (make-pairs [1 2 3] [4 5 6 7])
    )
    [[1 4] [2 5] [3 6]]
)
(test/exec :defn18
    (fn ->
        ; test ability to define a bodyless function
        (defn foo [])
        ; calling it should return null
        (foo)
    )
    null
)
; Bodyless functions should still do parameter arity checks...
(test/exec :defn19
    (fn ->
        ; test ability to define a bodyless function with args
        (defn foo [a b c])
        ; calling it should result in an exception
        (try (foo) | is? ^Exception)
    )
    true
)
(test/exec :defn20
    (fn ->
        ; test arity
        (defn foo [x y] (+ x y))
        (.message (try (foo 1)) | re/match  "no argument")
    )
    true
)
(test/exec :defn21
    (fn ->
        ; test arity
        (defn foo [x y] (+ x y))
        (.message (try (foo 1 2 3)) | re/match  "too many arguments")
    )
    true
)
(test/exec :defn22
    (fn ->
        ; test arity
        (defn foo [x y &args] (+ x y))
        (foo 4 5 3)
    )
    9
)
(test/exec :defn22a
    (fn ->
        ; test arity
        (defn foo [x y &xs] (+ x y))
        (foo 4 5 3)
    )
    9
)
(test/exec :defn23
    (fn ->
        ; test arity
        (defn foo [x y &args] (+ x y))
        (foo 4 5)
    )
    9
)
(test/exec :defn23a
    (fn ->
        ; test arity
        (defn foo [x y &xs] (+ x y))
        (foo 4 5)
    )
    9
)
(test/exec :defn24
    (fn ->
        ; test arity
        (defn foo [x y &args] args)
        (foo 1 2 3 | type-of)
    )
    ^Slice
)
(test/exec :defn24a
    (fn ->
        ; test arity
        (defn foo [x y &xs] xs)
        (foo 1 2 3 | type-of)
    )
    ^Slice
)
(test/exec :defn25
    (fn ->
        ; test arity
        (defn foo [x y &args] args)
        (foo 1 2 3 4 5 6 | type-of)
    )
    ^Slice
)
(test/exec :defn25a
    (fn ->
        ; test arity
        (defn foo [x y &xs] xs)
        (foo 1 2 3 4 5 6 | type-of)
    )
    ^Slice
)
(test/exec :defn26
    (fn ->
        ; test arity
        (defn foo [x y &args] args)
        (foo 1 2 3 4 5 6)
    )
    ; returns a list but compares equal to vector (ISeq)
    [3 4 5 6]
)
(test/exec :defn26a
    (fn ->
        ; test arity
        (defn foo [x y &xs] xs)
        (foo 1 2 3 4 5 6)
    )
    ; returns a list but compares equal to vector (ISeq)
    [3 4 5 6]
)
(test/exec :defn27
    (fn ->
        ; test arity
        (defn foo [x y &args] args)
        (foo 1 2 3 4 5 6)
    )
    (list 3 4 5 6)
)
(test/exec :defn28
    (fn ->
        ; test arity
        (defn foo [x y &args] args)
        (foo 1 2)
    )
    null
)
(test/exec :defn28a
    (fn ->
        ; test arity
        (defn foo [x y &xs] xs)
        (foo 1 2)
    )
    null
)
(test/exec :defn29
    (fn ->
        ; mix initializers and &args
        (defn foo [x (y 3) &args] {:val (+ x y) :args args })
        (foo 1)
    )
    {:val 4 :args null}
)
(test/exec :defn29a
    (fn ->
        ; mix initializers and &args
        (defn foo [x (y 3) &xs] {:val (+ x y) :xs xs })
        (foo 1)
    )
    {:val 4 :xs null}
)
(test/exec :defn30
    (fn ->
        ; mix initializers and &args
        (defn foo [x (y 3) &args] {:val (+ x y) :args args })
        (foo 1 10)
    )
    {:val 11 :args null}
)
(test/exec :defn31
    (fn ->
        ; mix initializers and &args
        (defn foo [x (y 3) &args] {:val (+ x y) :args args })
        (foo 20 10 :x :y :z)
    )
    {:val 30 :args [:x :y :z]}
)
(test/exec :defn31a
    (fn ->
        ; mix initializers and &args
        (defn foo [x (y 3) &xs] {:val (+ x y) :xs xs })
        (foo 20 10 :x :y :z)
    )
    {:val 30 :xs [:x :y :z]}
)

; test named arguments
(test/exec :defn32
    (fn ->
        (defn foo [:namearg1 :namearg2] {:namearg1 namearg1 :namearg2 namearg2})
        (foo)
    )
    {:namearg1 nil :namearg2 nil}
)
(test/exec :defn33
    (fn ->
        (defn foo [:namearg1 :namearg2] {:namearg1 namearg1 :namearg2 namearg2})
        (foo -namearg1)
    )
    {:namearg1 true :namearg2 nil}
)
(test/exec :defn34
    (fn ->
        (defn foo [:namearg1 :namearg2] {:namearg1 namearg1 :namearg2 namearg2})
        (foo -namearg2)
    )
    {:namearg1 nil :namearg2 true}
)
(test/exec :defn35
    (fn ->
        (defn foo [:namearg1 :namearg2] {:namearg1 namearg1 :namearg2 namearg2})
        (foo -namearg1 -namearg2)
    )
    {:namearg1 true :namearg2 true}
)
(test/exec :defn36
    (fn ->
        (defn foo [:namearg1: :namearg2] {:namearg1 namearg1 :namearg2 namearg2})
        (foo -namearg1: "Hi" )
    )
    {:namearg1 "hi" :namearg2 nil}
)
(test/exec :defn37
    (fn ->
        (defn foo [:namearg1: :namearg2] {:namearg1 namearg1 :namearg2 namearg2})
        (foo -namearg1: "Hi" -namearg2)
    )
    {:namearg1 "hi" :namearg2 true}
)
(test/exec :defn38
    (fn ->
        (defn foo [:namearg1: :namearg2:] {:namearg1 namearg1 :namearg2 namearg2})
        (foo -namearg2: "there")
    )
    {:namearg1 nil :namearg2 "there"}
)
(test/exec :defn39
    (fn ->
        (defn foo [:namearg1: :namearg2:] {:namearg1 namearg1 :namearg2 namearg2})
        (foo -namearg2: "there" -namearg1: "hi")
    )
    {:namearg1 "hi" :namearg2 "there"}
)
(test/exec :defn40
    (fn ->
        (defn foo [x y :namearg1: :namearg2:] {:namearg1 namearg1 :namearg2 namearg2 :x x :y y})
        (foo -namearg2: "there" -namearg1: "hi" 3 5)
    )
    {:namearg1 "hi" :namearg2 "there" :x 3 :y 5}
)
(test/exec :defn41
    (fn ->
        (defn foo [x y :namearg1: :namearg2:] {:namearg1 namearg1 :namearg2 namearg2 :x x :y y})
        (foo 3 -namearg2: "there" 7 -namearg1: "hi")
    )
    {:namearg1 "hi" :namearg2 "there" :x 3 :y 7}
)
; test a mix of position parameters, named parameters and &args
(test/exec :defn42
    (fn ->
        (defn foo [:name1 &args] [name1 args])
        (foo 1 2 3 4)
    )
    [null '(1 2 3 4)]
)
(test/exec :defn43
    (fn ->
        (defn foo [:name1 &args] [name1 args])
        (foo 1 2 -name1 3 4)
    )
    [true '(1 2 3 4)]
)
(test/exec :defn43a
    (fn ->
        (defn foo [:name1 &args] [name1 args])
        ; test double dash handling
        (foo 1 2 --name1 3 4)
    )
    [true '(1 2 3 4)]
)
(test/exec :defn44
    (fn ->
        (defn foo [:name1: &args] [name1 args])
        (foo 1 2 -name1: 3 4)
    )
    [3 '(1 2  4)]
)
(test/exec :defn44a
    (fn ->
        (defn foo [:name1: &args] [name1 args])
        (foo 1 2 --name1: 3 4)
    )
    [3 '(1 2  4)]
)
(test/exec :defn45
    (fn ->
        (defn foo [:name1 &args] [name1 args])
        (foo 1 2 3 4 -name1)
    )
    [true '(1 2 3 4)]
)
(test/exec :defn45a
    (fn ->
        (defn foo [:name1 &args] [name1 args])
        (foo 1 2 3 4 --name1)
    )
    [true '(1 2 3 4)]
)
(test/exec :defn46
    (fn ->
        (defn foo [x :name1 y &args] [x y name1 args])
        (foo 1 2 3 4 -name1)
    )
    [1 2 true '(3 4)]
)
(test/exec :defn46a
    (fn ->
        (defn foo [x :name1 y &args] [x y name1 args])
        (foo 1 2 3 4 --name1)
    )
    [1 2 true '(3 4)]
)
(test/exec :defn47
    (fn ->
        (defn foo [x :name1: y &args] [x y name1 args])
        (foo 1 -name1: 2 3 4)
    )
    [1 3 2 '(4)]
)
(test/exec :defn47a
    (fn ->
        (defn foo [x :name1: y &args] [x y name1 args])
        (foo 1 --name1: 2 3 4)
    )
    [1 3 2 '(4)]
)
(test/exec :defn47b
    (\ ->
        (defn foo [:name1: :name2 &args] [name1 name2 args])
        (foo 1 2 3 -name1: "abc" -name2)
    )
    ["abc" True [1 2 3]]
)
(test/exec :defn47c
    (\ ->
        (defn foo [:name2 :name1: &args] [name1 name2 args])
        (foo -name2 1 2 3 -name1: "abc")
    )
    ["abc" True [1 2 3]]
)
(test/exec :defn47d
    (\ ->
        (defn foo [:name2 :name1: &args] [name1 name2 args])
        (foo -name1: "abc" 1 2 -name2 3 4)
    )
    ["abc" True [1 2 3 4]]
)
(test/exec :defn47e
    (\ ->
        (defn foo [:name2: :name1: &args] [name1 name2 args])
        (foo -name1: "abc" 1 2 -name2: "def" 3 4)
    )
    ["abc" "def" [1 2 3 4]]
)
(test/exec :defn475
    (\ ->
        (defn foo [:name1: :name2: &args] [name1 name2 args])
        (foo 1 2 -name2: "def" 3 4 -name1: "abc")
    )
    ["abc" "def" [1 2 3 4]]
)

;------------------------------------------------------
; test pattern functions with guards
(test/exec :defn48
    ; Test a function using pattern matching with s-expression guards.
    (fn ->
        (defn fizbuz
            | n :where (not (% n 15)) -> "fizbuz"
            | n :where (not (% n 5))  -> "buz"
            | n :where (not (% n 3))  -> "fiz"
            | n -> n
        )
        (range 20 | map fizbuz)
   )
   [1 2 "fiz" 4 "buz" "fiz" 7 8 "fiz" "buz" 11 "fiz"
    13 14 "fizbuz" 16 17 "fiz" 19 "buz"]
)
(test/exec :defn49
    ; test different kinds of patterns with guards
    (fn ->
        (defn zork
             | ^int     :where (> %0 10) -> "big"
             | (^int x) :where (< x 10) -> "small"
             | ^ISeq    :where (count %0 | > 10) -> "Big vector"
             | ^ISeq    -> "vector"
             | ^string  :where (re/match %0  #"red") -> "red"
             | ^string  -> "rando string"
             | n        -> "something else."
        )

        (and
            (zork 1          | == "small")
            (zork 20         | == "big")
            (zork "Hi there" | == "rando string")
            (zork "red"      | == "red")
            (zork [1 2 3]    | == "vector")
            (zork (range 20) | == "big vector")
            (zork {}         | == "something else.")
       )
    )
    true
)
; test specifying multiple patterns in 1 clause
(test/exec :defn50
    (fn ->
        (defn foo
            | 1 | 2 | 3 -> "zork"
            | 4 | 5     -> "zip"
            | 6         -> "zop"
            |           -> "unknown"
        )
        (range 7 | map foo)
    )
    ["zork" "zork" "zork" "zip" "zip" "zop" "unknown"]
)
(test/exec :defn51
    (fn ->
        (defn foo
            | 1 | 3         -> "odd"
            | 8             -> "eight"
            | 2 | 4 | 6     -> "even"
            | 5 | 7 | 9     -> "also odd"
        )
        (range 9 | map foo)
    )
    ["odd" "even" "odd" "even" "also odd" "even" "also odd" "eight" "also odd"]
)

;------------------------------------------------------------------
; test for bug where [(x 2)] was being turned into [(<IList> 2)] due to
; premature optimization.
(test/exec :defn60
    (fn ->
        (let ^IList x [1 2 3])
        (defn foo [(x "abc")] x)
        (foo)
    )
    "abc"
)
(test/exec :defn61
    (fn ->
        (let ^IList x [1 2 3])
        (defn foo [(^string x "abc")] x)
        (foo)
    )
    "abc"
)
(test/exec :defn62
    (fn ->
        (let ^IList x [1 2 3])
        (defn foo [(^string x "abc")] x)
        (foo "def")
    )
    "def"
)

;------------------------------------------------------
; Test type-constrained parameters
(test/exec :typeconstraint1
    (fn ->
        (defn foo [(^ISeq seq)] seq)
        ; ISeq works with vectors
        (foo [1 2 3])
    )
    [1 2 3]
)
(test/exec :typeconstraint2
    (fn ->
        (defn foo [(^ISeq seq)] seq)
        ; ISeq works with vectors and lists
        (foo '(10 20 30))
    )
    '(10 20 30)
)
(test/exec :typeconstraint3
    (fn ->
        (defn foo [(^ISeq seq)] seq)
        ; dictionaries aren't sequences
        (try (foo {:a 1 :b 2}) -catch: "got error")
    )
    "got error"
)
(test/exec :typeconstraint4
    (fn ->
        (defn foo [(^ISeq seq)] seq)
        (try (foo "string")  -catch: "got error")
    )
    "got error"
)
(test/exec :typeconstraint5
    (fn ->
        (defn foo [(^ISeq seq)] seq)
        (try (foo 1)  -catch: "got error")
    )
    "got error"
)
(test/exec :typeconstraint6
    (fn ->
        ; soft type constraintmconverts to string
        (defn foo [(^string? s)] (type-of s))
        (foo 123)
    )
    ^string
)
(test/exec :typeconstraint6a
    (fn ->
        ; strict type constraint fails to convert string
        (defn foo [(^string s)] (type-of s))
        (try (foo 123) | is? ^exception)
    )
    true
)
(test/exec :typeconstraint7
    (fn ->
        ; type-converts to number
        (defn foo [(^int? s)] (type-of s))
        (foo "123")
    )
    ^int
)
(test/exec :typeconstraint8
    (fn ->
        ; type-converts to number
        (defn foo [(^int? s)] (type-of s))
        ; pass invalid number string so we expect an error
        (try (foo "123abc") -catch: "got error")
    )
    "got error"
)

;------------------------------------------------------
; Test type patterns
(test/exec :typepatterns1
    (fn ->
        (defn foo
            | ^int          -> :number
            | ^string       -> :string
            | ^IDictionary  -> :dictionary
            | ^Vector       -> :vector
        )
        (foo 123)
    )
    :number
)
(test/exec :typepatterns2
    (fn ->
        (defn foo
            | ^int          -> :number
            | ^string       -> :string
            | ^IDictionary  -> :dictionary
            | ^Vector       -> :vector
        )
        (foo "abc")
    )
    :string
)
(test/exec :typepatterns3
    (fn ->
        (defn foo
            | ^int          -> :number
            | ^string       -> :string
            | ^IDictionary  -> :dictionary
            | ^Vector       -> :vector
        )
        (foo {:a 1 :b 2})
    )
    :dictionary
)
(test/exec :typepatterns4
    (fn ->
        (defn foo
            | ^int          -> :number
            | ^string       -> :string
            | ^IDictionary  -> :dictionary
            | ^Vector       -> :vector
        )
        (foo [1 2 3])
    )
    :vector
)
(test/exec :typepatterns5
    (fn ->
        (defn foo
            | ^int          -> :number
            | ^string       -> :string
            | ^IDictionary  -> :dictionary
            | ^Vector       -> :vector
        )
        ; no matching case so expect error
        (try (foo (.now ^datetime)) -catch: "got error")
    )
    "got error"
)
(test/exec :typepatterns6
    (fn ->
        (defn foo
            | ^int          -> :number
            | ^string       -> :string
            | ^IDictionary  -> :dictionary
            | ^Vector       -> :vector
            |               -> :unknown
        )
        ; no matching case so expect default
        (foo (.now ^datetime))
    )
    :unknown
)
(test/exec :typepattern7
    (fn ->
        (defn foo
            | (^int x) (^int y) -> "2 ints ${x} ${y}"
            | (^string x) (^string y) -> "string ${x} ${y}"
            | (^int x) -> "1 int ${x}"
        )
        (foo 1 2)
    )
    "2 ints 1 2"
)
(test/exec :typepattern8
    (fn ->
        (defn foo
            | (^int x) (^int y) -> "2 ints ${x} ${y}"
            | (^string x) (^string y) -> "2 strings ${x} ${y}"
            | (^int x) -> "1 int ${x}"
        )
        (foo "a" "b")
    )
    "2 strings a b"
)
(test/exec :typepattern9
    (fn ->
        (defn foo
            | (^int x) (^int y) -> "2 ints ${x} ${y}"
            | (^string x) (^string y) -> "string ${x} ${y}"
            | (^int x) -> "1 int ${x}"
        )
        (foo 10)
    )
    "1 int 10"
)
(test/exec :typepattern10
    (fn ->
        ; Test coercive type constraints (note %0 is not changed)
        (matchp 9.0 | (^int? val) -> (type-of val))
    )
    ^int
)
(test/exec :typepattern11
    (fn ->
        (matchp 13
        ; a coercive string pattern will always match everything. It sould probably go last.
        | ^string?  -> "matched string"
        | ^int      -> "matched int"
        )
    )
    "matched string"
)
(test/exec :typepattern12
    (fn ->
        (forall v [1 (^long? 123) 10i 4.6]
            (matchp v
            ; test multiple type branches into the same variable
            | (^int n)
            | (^double n)
            | (^long n)
            | (^bigint n) -> (type-of n)
            )
        )
    )
    [ ^int ^long ^bigint ^double ]
)

;------------------------------------------------------
; String and Slice Patterns
(test/exec :stringpattern1
    (fn ->
        (defn revstr
            | nil res -> (join res "")
            |  x:xs res -> (recur xs (cons x res))
            | xs -> (recur xs nil)
        )
        (revstr "abcdefg")
    )
    "gfedcba"
)
(test/exec :stringpattern2
    (fn ->
        ; test that the first string is the prefix of the second
        (defn prefix?
            | nil _ -> true
            | _ nil -> false
            | x:xs y:ys ->
                (if (== x y)
                    (recur xs ys)
                    false
                )
        )
        [
            (prefix? "abcd" "abcd")
            (prefix? "abcd" "abcde")
            (prefix? "abcd" "abccde")
            (prefix? "abcd" "abc")
        ]
    )
    [ true true false false ]
)
(test/exec :stringpattern3
    (fn ->
        ; bubble sort function
        (defn bub
            | x: r      -> [x]
            | x:y: r    -> (if (> x y)
                                [@(bub (nconc y r)) x]
                                [@(bub (nconc x r)) y])
            | x:y:xs r  -> (if (> x y)
                                (recur [x @xs] (nconc y r))
                                (recur [y @xs] (nconc x r)))
            | xs -> (recur xs [])
        )
        (join (bub "bcaefdg") "")
    )
    "abcdefg"
)
(test/exec :stringpattern4
    (fn ->
        ; bubble sort function; not really string data
        (defn bub
            | x: r      -> [x]
            | x:y: r    -> (if (> x y)
                                [@(bub (nconc y r)) x]
                                [@(bub (nconc x r)) y])
            | x:y:xs r  -> (if (> x y)
                                (recur [x @xs] (nconc y r))
                                (recur [y @xs] (nconc x r)))
            | xs -> (recur xs [])
        )
        (bub [4 1 5 3 2])
    )
    [1 2 3 4 5]
)
(test/exec :stringpattern5
    (fn ->
        ; Transform words to "Pig Latin"
        (re/split "Hello there world" | map (fn | x:y:xs ->
                (str (if (.char/isupper x) (.char/toupper y) y) xs (.char/tolower x) 'ay')
            )
        )
    )
    [ "Ellohay", "heretay", "orldway" ]
)

;------------------------------------------------------
; Test nested patterns
(test/exec :nestedpattern1
    (fn ->
        ; tail-recursive reverse implementation with nested patterns
        (defn rv
            | [x &xs] r -> (recur xs (concat x r))
            | nil r     -> r
            | lst       -> (recur lst nil)
        )
        (rv [1 2 3 4])
    )
    [4 3 2 1]
)
(test/exec :nestedpattern1a
    (fn ->
        ; tail-recursive reverse implementation with nested patterns
        (defn rv
            | [x &xs] r -> (recur xs (concat x r))
            | nil r     -> r
            | lst       -> (recur lst [])
        )
        (rv "abcdefg")
    )
    "gfedcba"
)
(test/exec :nestedpattern2
    (fn ->
        ; zip implementation with nested patterns
        (defn zp
            | [x &xs] [y &ys] -> (cons (list x y) (zp xs ys))
            | nil nil         -> nil
        )
        (zp [1 2 3] [:a :b :c])
    )
    '((1 "a") (2 "b") (3 "c"))
)
(test/exec :nestedpattern3
    (fn ->
        (defn foo | x [a b &ys] &xs -> [xs ys])
        (foo 1 [10 20 30 40] 2 3 4)
    )
    [[2 3 4] [30 40]]
)
(test/exec :nestedpattern4
    (fn ->
        ; count number of items in a collection.
        (defn cnt
            | [x &xs] t -> (recur xs (++ t))
            | nil t -> t
            | xs -> (recur xs 0)
        )
        (cnt (range 500))
    )
    500
)
(test/exec :nestedpattern5
    (fn ->
        ; count number of items in a collection.
        (defn cnt
            | [x &xs] t -> (recur xs (++ t))
            | nil t     -> t
            | xs        -> (recur xs 0)
        )
        ; try with a string
        (cnt "abcdefg")
    )
    7
)
(test/exec :nestedpattern6
    (fn ->
        ; count number of items in a collection.
        (defn cnt
            | [x &xs] t -> (recur xs (++ t))
            | nil t     -> t
            | xs        -> (recur xs 0)
        )
        ; try with a list
        (cnt '(1 2 3 4 5))
    )
    5
)
(test/exec :nestedpattern7
    (fn ->
        ; count number of items in a collection.
        (defn cnt
            | [x &xs] t -> (recur xs (++ t))
            | nil t -> t
            | xs -> (recur xs 0)
        )
        ; try with a list
        (cnt [1 2 3 4 5 6])
    )
    6
)
(test/exec :nestedpattern8
    (fn ->
        ; arity matches so no error
        ((fn [x] -> x) [1])
    )
    1
)
(test/exec :nestedpattern8a
    (fn ->
        ; arity mismatch should cause an exception
        (try ((fn [x] -> x) [1 2]) | is? ^Exception)
    )
    true
)
(test/exec :nestedpattern8b
    (fn ->
        ((fn [x &xs] -> [x xs]) [1])
    )
    [1 nil]
)
(test/exec :nestedpattern8c
    (fn ->
        ((fn [x &xs] -> [x xs]) [1 2])
    )
    [1 [2]]
)
(test/exec :nestedpattern8d
    (fn ->
        ((fn [x &xs] -> [x xs]) [1 2 3])
    )
    [1 [2 3]]
)

;------------------------------------------------------
; Test use of pinned functions in patterns
(test/exec :pinnedFunctionsInPatterns1
    (fn ->
        (defn v | "grabbed" | "dropped" | "threw" -> %0)

        (defn s | "He" | "She" | "They" -> %0)

        (defn o | "ball" | "hotdog" | "dart" -> %0)

        (defn a | "the" | "a" | "their" -> %0)

        ; test as top-level pattern
        (defn sentence | (%s sub) (%v verb) (%a article) (%o obj) -> [[sub verb] [article obj]])
        (sentence "They" "dropped" "their" "hotdog")
    )
    [["They" "dropped"] ["their" "hotdog"]]
)
(test/exec :pinnedFunctionsInPatterns2
    (fn ->
        (defn v | "grabbed" | "dropped" | "threw" -> %0)

        (defn s | "He" | "She" | "They" -> %0)

        (defn o | "ball" | "hotdog" | "dart" -> %0)

        (defn a | "the" | "a" | "their" -> %0)

        ; test as nested pattern
        (defn sentence | [(%s sub) (%v verb) (%a article) (%o obj)] -> [[sub verb] [article obj]])
        (sentence ["He" "dropped" "a" "ball"])
    )
    [["He" "dropped"] ["a" "ball"]]
)
(test/exec :pinnedFunctionsInPatterns2a
    (fn ->
        (defn v | "grabbed" | "dropped" | "threw" -> %0)

        (defn s | "He" | "She" | "They" -> %0)

        (defn o | "ball" | "hotdog" | "dart" | "flower" -> %0)

        (defn a | "the" | "a" | "their" -> %0)

        ; test as nested pattern
        (defn sentence | [(%s sub) (%v verb) (%a article) (%o obj)] -> [[sub verb] [article obj]])
        (sentence (re/split "She grabbed a flower"))
    )
    [["She" "grabbed"] ["a" "flower"]]
)
(test/exec :pinnedFunctionsInPatterns3
    (fn ->
        ; using predicate functions
        (range 5 | map (fn | %even? -> "even" | %odd? -> "odd" | -> "other"))
    )
    ["odd" "even" "odd" "even" "odd"]
)
(test/exec :pinnedFunctionsInPatterns4
    (fn ->
        ; using predicate functions
        (range 5 | map (fn | (%even? e) -> "even ${e}" | (%odd? o) -> "odd ${o}" | -> "other"))
    )
    ["odd 1" "even 2" "odd 3" "even 4" "odd 5"]
)
(test/exec :pinnedFunctionsInPatterns5
    (fn ->
        ; function to separate a list of numbers into individual even and odd lists.
        (defn evenodd
            | [(%even? e) &args] evens odds -> (recur args (cons e evens) odds)
            | [(%odd? o)  &args] evens odds -> (recur args evens (cons o odds))
            | nil evens odds                -> [(sort evens) (sort odds)]
            | lst                           -> (recur lst nil nil)
        )
        (evenodd [1 2 3 4 5 6 7 8 9 10])
    )
    [[2 4 6 8 10] [1 3 5 7 9]]
)
(test/exec :pinnedFunctionsInPatterns5a
    (fn ->
        ; function to separate a list of numbers into individual even and odd lists.
        ; uses &xs instead of &args
        (defn evenodd
            | [(%even? e) &xs] evens odds  -> (recur xs (cons e evens) odds)
            | [(%odd? o)  &xs] evens odds  -> (recur xs evens (cons o odds))
            | nil evens odds               -> [(sort evens) (sort odds)]
            | lst                          -> (recur lst nil nil)
        )
        (evenodd [1 2 3 4 5 6 7 8 9 10])
    )
    [[2 4 6 8 10] [1 3 5 7 9]]
)


;------------------------------------------------------
; Pattern matching with initializers
(test/exec :patternInitializers1
    (fn ->
        (defn rv | x:xs (r nil) -> (recur xs (cons x r)) | nil r -> r)
        (rv [1 2 3 4 5])
    )
    (list 5 4 3 2 1)
)
(test/exec :patternInitializers2
    (fn ->
        (defn mc | x:xs (r 0) -> (recur xs (+ x r)) | nil r -> r)
        (mc [1 2 3 4])
    )
    10
)
(test/exec :patternInitializers3
    (fn ->
        (defn foo | a (b 2) (c 3) -> [a b c])
        [(foo 1) (foo 10 20) (foo 10 20 30)]
    )
    [[1 2 3] [10 20 3] [10 20 30]]
)
(test/exec :patternInitializers4
    (fn ->
        (defn foo | a (b 2) (c 3) &args -> args)
        [(foo 1) (foo 1 2) (foo 1 2 3) (foo 1 2 3 4)]
    )
    [nil nil nil [4]]
)

;------------------------------------------------------
; Star function pattern tests
(test/exec :starFunctionPattern1
    (fn ->
        (defn foo | a b c -> (+ a b c))
        (defn bar | "hi" (*foo nr) "bye" -> ["hi" nr "bye"])
        (bar "hi" 1 2 3 "bye")
    )
    ["hi" 6 "bye"]
)
(test/exec :starFunctionPattern2
    (fn ->
        (defn value
            | (#"[0-9]+(\.[0-9])?" val:_) -> val
            | (#"[a-z]+" val:)            -> val
            | -> (throw "Missing or invalid value.")
        )
        (defn expr
            | (*value v1) (#"[+*/%-><=]" op:) (*value v2) -> [op v1 v2]
            | (*value v1) -> v1
            | -> (throw "Missing or invalid expr")
        )
        (defn stmt
            | "if" (*expr cond) "then" (*expr truePart) "else" (*expr falsePart) "endif" ->
                ["if" cond truepart falsePart]

            | "if" (*expr cond) "then" (*expr truePart) "endif" ->
                ["if" cond truepart nil]
        )

        (stmt @(re/split "if a > 2 then 3 + 3 else 7 * 4 endif"))
    )
    ["if" [">" "a" "2"] ["+" "3" "3"] ["*" "7" "4"]]
)

;------------------------------------------------------
; Test using things other than &args at the top level of patterns
(test/exec :other&args1
    (fn ->
        ; function that reverses its arguments
         (defn mr
            | x &xs -> (concat (mr @xs) x)
            | x -> x
            | -> nil
         )
         (mr 1 2 3 4)
    )
    [4 3 2 1]
)

;------------------------------------------------------
; Test Generic Pattern Elements with variables.
(test/exec :genericpattern1
    (fn ->
        (matchp 5 | (5 v) -> v)
    )
    5
)
(test/exec :genericpattern2
    (fn ->
        (defn gp1 | (5 v) -> v)
        (gp1 5)
    )
    5
)
(test/exec :genericpattern3
    (fn ->
        (matchp "abc" | ("abc" v) -> v)
    )
    "abc"
)
(test/exec :genericpattern4
    (fn ->
        (defn gp1 | ("abc" v) -> v)
        (gp1 "abc")
    )
    "abc"
)

;------------------------------------------------------
; Committed patterns
(test/exec :committedpattern1
    (fn ->
        (try
            (matchp 1 2 3
            | 1 2 ! 4 -> "foo"
            | -> "bar"
            )
        | is? ^Exception
        )
    )
    true
)

;------------------------------------------------------
; Backtracking
(test/exec :backtracking1
    (fn ->
         (matchp 5 | n <- (!) | -> n)
    )
    5
)

;------------------------------------------------------
; Pattern APIs
(test/exec :patternapi1
    (fn ->
        ; construct a pattern object using the APIs.
        (let pat
            (new ^BraidLang.PatternFunction "zork" "unittests.tl" 8977 " " 0
            ; BUGBUGBUG - this should work with vectors too.
            | .addclause '(1) '("one") null false false
            | .addClause '(n) '("even: ${n}") '(% n 2 | == 0) false false
            | .addClause '(n) '("other: ${n}") null false false
            )
        )

        (and
            (pat 1 | == "one")
            (pat 2 | == "even: 2")
            (pat 3 | == "other: 3")
            (pat 4 | == "even: 4")
            (pat 5 | == "other: 5")
       )
    )
    true
)
;------------------------------------------------------
; Test partial functions
(test/exec :partial1
    (fn ->
        (let dbl (partial * 2))
        (dbl 4)
    )
    8
)
(test/exec :partial2
    (fn ->
        (let +1 (partial + 1))
        (range 5 | map +1)
    )
    [2 3 4 5 6]
)
(test/exec :partial3
    (fn ->
        ; multiply can be used as a partial function
        (range 5 | map (* 2))
    )
    [2 4 6 8 10]
)
(test/exec :partial4
    (fn ->
        (defn strrep [str count] (* str count))
        ; curries the outer argument
        (let byfive (partial strrep 5))
        (byfive "<*>")
    )
    "<*><*><*><*><*>"
)
(test/exec :partial5
    (fn ->
        (defn three [x y z] [x y z])
        ; curries the outer argument
        (let two (partial three 3))
        (two 1 2)
    )
    [1 2 3]
)
(test/exec :partial6
    (fn ->
        (defn three [x y z] [x y z])
        ; curries the outer argument
        (let one (partial (partial three 5) 4))
        (one 1)
    )
    [1 4 5]
)
(test/exec :partial7
    (fn ->
        (defn three [x y z] [x y z])
        ; curries the outer argument
        (let zero (partial (partial (partial three 5) 4) 3))
        (zero)
    )
    [3 4 5]
)
(test/exec :partial8
    (fn ->
        ; test with var args
        ((partial (partial + 2) 3) 4 5)
    )
    14
)
(test/exec :partial9
    (fn ->
        ; partial with local function
        (defn zork [x y] (* x y))
        (range 5 | map (partial zork 2))
    )
    [2 4 6 8 10]
)
(test/exec :partial10
    (fn ->
        ; partial with local function using 'let'
        (let zork (fn x y -> (* x y)))
        (range 5 | map (partial zork 2))
    )
    [2 4 6 8 10]
)
(test/exec :partial11
    (fn ->
        ; partial with function literal
        (range 5 | map (partial (fn x y -> (* x y)) 2))
    )
    [2 4 6 8 10]
)
(test/exec :partial12
    (fn ->
        (let f (with [] (defn t2 [x y] (* x y)) (partial t2 3)))
        (range 5 | map f)
    )
    [3 6 9 12 15]
)
; Test built-in currying for functions like *,%,/,==,!=,<,<=,>,>=, is?, as, map
(test/exec :autocurry10
    (fn ->
        ([5] | map (* 2))
    )
   [10]
)
(test/exec :autocurry11
    (fn ->
        ([5] | map (is? ^int))
    )
    [true]
)
(test/exec :autocurry12
    (fn ->
        (let foo (is? ^int))
        ("5" | map foo)
    )
   [false]
)
(test/exec :autocurry13
    (fn ->
        (let foo (is? ^int?))
        ("5" | map (as ^int?) | map foo)
    )
    [true]
)
(test/exec :autocurry14
    (fn ->
        (let foo (is? ^int?))
        ; immediately-invoked curried function
        (foo ((as ^int?) "123"))
    )
    true
)
(test/exec :autocurry15
    (fn ->
        (range 10 | filter (< 5))
    )
    [1 2 3 4]
)
(test/exec :autocurry16
    (fn ->
        (range 10 | filter (<= 5))
    )
    [1 2 3 4 5]
)
(test/exec :autocurry17
    (fn ->
        (range 10 | filter (> 5))
    )
    [6 7 8 9 10]
)
(test/exec :autocurry18
    (fn ->
        (range 10 | filter (>= 5))
    )
    [5 6 7 8 9 10]
)
(test/exec :autocurry19
    (fn ->
        (range 10 | filter (== 5))
    )
    [5]
)
(test/exec :autocurry20
    (fn ->
        (range 10 | filter (!= 5))
    )
    [1 2 3 4 6 7 8 9 10]
)
(test/exec :autocurry21
    (fn ->
        (range 2 10 2 | map (/ 2))
    )
    [1 2 3 4 5]
)
(test/exec :autocurry22
    (fn ->
        (range 10 | filter (% 2))
    )
    [1 3 5 7 9]
)
(test/exec :autocurry23
    (fn ->
        ([[1 2] [3 4] [5 6]] | map (!! 1))
    )
    [2 4 6]
)
(test/exec :autocurry24
    (fn ->
        ([{:a 7} {:a 8} {:a 9}] | map (!! :a))
    )
    [7 8 9]
)
(test/exec :autocurry25
    (fn ->
        ; not using curried function but it still works.
        ([{:a 7} {:a 8} {:a 9}] | map :a)
    )
    [7 8 9]
)
(test/exec :autocurry26
    (fn ->
        ; "double curried" function
        (let doublelist (map (* 2)))
        (range 5 | doublelist)
    )
    [2 4 6 8 10]
)
(test/exec :curryed1
    (fn ->
        ((fn x -> ((fn y -> (+ x y)) 5)) 3)
    )
    8
)
(test/exec :curried2
    (fn ->
        ((fn z ->
            ((fn x ->
                ((fn y -> (+ x y z))
                    5))
                3))
            2)
    )
    10
)
(test/exec :curried3
    (fn ->
        ; make sure curried functions aren't incorrectly cached.
        (defn xnmap | L M -> (map L (* M)))
        (and
            (==
                ([1 2 3] | xnmap 2)
                [2 4 6])
            (==
                ([1 2 3] | xnmap 3)
                [3 6 9])
            (==
                ([1 2 3] | xnmap 4)
                [4 8 12])
         )
    )
    true
)
(test/exec :curried4
    (fn ->
        ; test currying pattern functions
        (range 10 | filter (in? [2 4 6 8 10]))
    )
    [2 4 6 8 10]
)
(test/exec :curried5
    (fn ->
        (defn foo
            | x -> (partial foo x)
            | x y -> (* x y)
        )
        (range 5 | map (foo 2))
    )
    [2 4 6 8 10]
)
(test/exec :curried6 
    (fn ->
        (defn foo
            | val -> (partial foo val)
            | ^double val -> "double ${val}"
            | ^int    val -> "int ${val}"
            | ^string val -> "string ${val}"
        )
        ([1.0 1 "1"] | map (foo "XYZ"))
    )
    [ "double XYZ" "int XYZ" "string XYZ" ]
)


;------------------------------------------------------
; Test the 'getfunc' function.
(test/exec :getfunc1
    (fn ->
        (defn getfunc1_func [])
        (getfunc "getfunc1_func" | .name)
    )
    "getfunc1_func"
)
(test/exec :getfunc2
    (fn ->
        ; test PowerShell function
        (getfunc "get-childitem" | .name)
    )
    "Get-ChildItem"
)
(test/exec :getfunc3
    (fn ->
        ; get the function object for a regex
        (getfunc #"abc" | is? ^Function)
    )
    "true"
)
(test/exec :getfunc4
    (fn ->
        (getfunc [1 2 3] | is? ^Function)
    )
    "true"
)
(test/exec :getfunc5
    (fn ->
        (getfunc {:a 1} | is? ^Function)
    )
    "true"
)
(test/exec :getfunc6
    (fn ->
        (getfunc :abc | is? ^BraidLang.IInvokeableValue)
    )
    "true"
)
(test/exec :getfunc7
    (fn ->
        (getfunc + | is? ^Function)
    )
    "true"
)
(test/exec :getfunc8
    (fn ->
        (getfunc fn | is? ^UserFunction)
    )
    "true"
)
(test/exec :getfunc9
    (fn ->
        (try (getfunc abcdefghi) | is? ^Exception)
    )
    true
)


;------------------------------------------------------
; Test the 'compliment' function.
(test/exec :compliment1
    (fn ->
        (range 10 | filter (compliment % 2))
    )
    [2 4 6 8 10]
)
(test/exec :compliment2
    (fn ->
        ([:a :b :c :a :b :c] | filter (compliment re/match  #"a"))
    )
    [:b :c :b :c]
)

;------------------------------------------------------
; Test 'compose' function
(test/exec :compose1
    (fn ->
        (let f (compose ++))
        (f 3)
    )
    4
)
(test/exec :$1
    (fn ->
        ; test $ alias for compose
        (let f ($ ++))
        (f 3)
    )
    4
)
(test/exec :compose2
    (fn ->
        (let f (compose ++ ++))
        (f 3)
    )
    5
)
(test/exec :compose3
    (fn ->
        (let f (compose ++ ++ ++))
        (f 3)
    )
    6
)
(test/exec :compose4
    (fn ->
        (let f (compose ++ -- ++ ++ -- --))
        (f 3)
    )
    3
)
(test/exec :compose5
    (fn ->
        (let f (compose ++ (+ 2) (* 3)))    ; defines a function that adds 1 to its argument, then 2 then multiplies by 3
        (f 5)                               ; returns 24
    )
    24
)
(test/exec :compose6
    (fn ->
        (let f (compose range (filter (% 2)) (map ++)))
        (f 10)
    )
    [2 4 6 8 10]
)
(test/exec :compose6a
    (fn ->
        (let f (compose range (filter (partial % 2)) (partial map ++)))
        (f 10)
    )
    [2 4 6 8 10]
)
(test/exec :compose7
    (fn ->
        (let f (compose range (filter (% 2)) (map ++) (take 3)))
        (f 10)
    )
    [2 4 6]
)
(test/exec :compose8
    (fn ->
         ((compose (lazy-filter (partial < 3))) (range 10))
    )
    [1 2]
)
(test/exec :compose9
    (fn ->
        ((compose (partial filter (partial < 3))) (range 10))
    )
    [1 2]
)
(test/exec :compose10
    (fn ->
        ((compose (partial lazy-filter (partial < 3))) (range 10))
    )
    [1 2]
)
(test/exec :compose11
    (fn ->
        ((compose range (lazy-filter (fn n -> (if (== n 9) (break)))) first (* 3)) 10)
    )
    27
)
(test/exec :compose12
    (fn ->
        ; test with dictionary as a function
        (let func {:a 1 :b 2 :c 3})
        ((compose func (* 2)) :b)
    )
    4
)
(test/exec :compose13
    (fn ->
        ; test with vector as a function
        (let func ["a" "b" "c"])
        ((compose func (+ "b")) 1)
    )
    "bb"
)
(test/exec :compose14
    (fn ->
        ; test scoped function resolution
        (let f
            (with []
                (defn foo [x] (* x 3))
                (compose ++ foo (+ 2))
            )
        )
        (f 7)
    )
    26
)
(test/exec :compose15
    (fn ->
        ; make sure the function returned by 'compose' is properly closed.
        (let v 4)
        (let f
            (with []
                (let v 3)
                (defn foo [x] (* x v))
                (compose ++ foo (+ 2))
            )
        )
        (let v 5)
        (f 7)
    )
    26
)
(test/exec :compose16
    (fn ->
        ; test scoped function resolution using 'partial'
        (let v 4)
        (let f
            (with []
                (let v 3)
                (defn foo [x y] (* x y))
                (compose ++ (partial foo v) (+ 3))
            )
        )
        (let v 5)
        (f 7)
    )
    27
)
(test/exec :compose17
    (fn ->
        ; use a composed function with filter
        (range 10 | filter (compose (% 2) (== 0)))
    )
    [2 4 6 8 10]
)
(test/exec :compose18
    (fn ->
        ; use a composed function with both filter and map
        (let v 2)
        (range 10 | filter (compose (% 2) (== 0)) | map (compose (partial * v) ++))
    )
    [5 9 13 17 21]
)
(test/exec :compose19
    (fn ->
        ; tested nested calls to 'compose'.
        (range 10 | filter (compose ++ (compose -- (% 2)) (== 0)))
    )
    [2 4 6 8 10]
)

;------------------------------------------------------
; Test 'or$' ('or-compose') function
(test/exec :or$1
    (fn ->
        (range 10 | filter (or$ ($ (% 3) not) ($ (% 5) not)))
    )
    [3 5 6 9 10]
)
(test/exec :or$2
    (fn ->
        (let f (or$ (> 8) (< 3)))
        [(f 1) (f 5) (f 10)]
    )
    [true false true]
)
(test/exec :or$3
    (fn ->
        ((or$ .char/isupper .char/islower .char/isdigit) \9)
    )
    true
)
(test/exec :or$3a
    (fn ->
        ((or$ .char/isupper .char/islower .char/isdigit) \a)
    )
    true
)
(test/exec :or$3b
    (fn ->
        ((or$ .char/isupper .char/islower .char/isdigit) \A)
    )
    true
)
(test/exec :or$3c
    (fn ->
        ((or$ .char/isupper .char/islower .char/isdigit) \+)
    )
    false
)
(test/exec :or$3d
    (fn ->
        ((or$ .char/isupper .char/islower) \9)
    )
    false
)
(test/exec :or$4
    (fn ->
        (chars "HelloWorld" | list/all (or$ .char/islower .char/isupper))
    )
    true
)
(test/exec :or$4a
    (fn ->
        (chars "Hello9World" | list/all (or$ .char/islower .char/isupper))
    )
    false
)
(test/exec :or$4b
    (fn ->
        (chars "Hello9World" | list/all (or$ .char/islower .char/isupper .char/isdigit))
    )
    true
)
(test/exec :or$5
    (fn ->
        ; things that aren't functions should result in an error
        (try (or$ true false) | is? ^Exception)
    )
    true
)
(test/exec :or$6
    (fn ->
        (range 10 | filter (or$ (< 3) (> 7)))
    )
    [1 2 8 9 10]
)

;------------------------------------------------------
; Test 'and$' ('and-compose') function
(test/exec :and$1
    (fn ->
        (range 10 | filter (and$ (>= 5) (<= 8)))
    )
    [5 6 7 8]
)
(test/exec :and$2
    (fn ->
        (range 10 | filter (and$ ($ (< 5) not) (<= 8)))
    )
    [5 6 7 8]
)
(test/exec :and$3
    (fn ->
        ; things that aren't functions should result in an error
        (try (and$ true false) | is? ^Exception)
    )
    true
)
(test/exec :and$4
    (fn ->
        (range \a \z | filter (and$ (> \h) (< \t) even?) | map ^char? | join "")
    )
    "jlnpr"
)
(test/exec :and$5
    (fn ->
        ; test resolution of variables
        (let lower (> \h))
        (let upper (< \t))
        (let int-even ($ ^int? even?))
        (range \a \z | filter (and$ lower upper int-even) | map ^char? | join "")
    )
    "jlnpr"
)

;------------------------------------------------------
; Test 'recur' and 'loop' functions
(test/exec :loop1
    (fn ->
        ; basic recur with the loop function
        (loop [x 42 s 0]
            (if x
                (recur (-- x) (+ x s))
                s
           )
       )
    )
    903
)
(test/exec :recur2
    (fn ->
        ; test recur in an immediately invoked function literal
        ((fn (x 42) (s 0) -> (if x (recur (-- x) (+ x s)) s)))
    )
    903
)
(test/exec :recur3
    (fn ->
        ; test recur in a normal function
        (defn testrevimpl
            "Function to reverse a list using recur"
            [listOfValues (out null)]

             (if (some? listOfValues)
                (recur (cdr listOfValues) (cons (car listOfValues) out))
                out
             )
        )
        (testrevimpl [1 2 3 4 5 6])
    )
    [6 5 4 3 2 1]
)
(test/exec :recur4
    (fn ->
        ; test recur with the loop and matchp functions.
        (defn foo []
            (loop [x 10 y 0]
                (matchp x y
                | 0 s -> s
                | n s -> (recur (-- n) (+ s n))
                )
            )
        )
        (foo)
    )
    55
)
(test/exec :recur5
    (fn ->
        ; test recur with a function with pattern parameters
        (defn rev
            [x:xs (res null)]

            (if xs
                (recur xs (cons x res))
                (cons x res)
            )
        )
        (range 10 | rev)
    )
    [ 10 9 8 7 6 5 4 3 2 1]
)
(test/exec :recur6
    (fn ->
         ; test exponentiation function that uses recur
         (defn mexpr [m n] (if (> n 1) (recur (+ m m) (-- n)) m))
         ; with big ints
         (mexpr 2i 64)
    )
    18446744073709551616
)
(test/exec :recur7
    (fn ->
        ; tail-recursive routine to find an entry in an ISeq
        (defn fil
            | x:xs v :where (== v x) -> true
            | _:xs v -> (recur xs v)
            | -> false
        )
        (fil [1 2 3 4 5] 3)
    )
    true
)
(test/exec :recur8
    (fn ->
        ; tail-recursive routine to find an entry in an ISeq
        (defn fil
            | x:xs v :where (== v x) -> true
            | _:xs v -> (recur xs v)
            | -> false
        )
        (fil [1 2 3 4 5] 6)
    )
    false
)
(test/exec :recur9
    (fn ->
        ; tail-recursive routine to find an entry in an ISeq
        (defn fil
            | x:xs v :where (== v x) -> true
            | _:xs v -> (recur xs v)
            | -> false
        )
        (fil (range 1000) 999)
    )
    true
)
(test/exec :recur10
    (fn ->
        ; tail-recursive routine to find an entry in an ISeq
        (defn fil
            | x:xs v :where (== v x) -> true
            | _:xs v -> (recur xs v)
            | -> false
        )
        (range 1000 | fil 1010)
    )
    false
)
(test/exec :recur11
    (fn ->
        ; currency denominations
        (const denom [20 10 5 1 0.50 0.25 0.10 0.05 0.01])

        ; tail-recursive function to calculate the change for a given value
        (defn change
            | val x:xs (r nil) :where (<= x val ) ->
                (recur (.math/round (% val x) 2) xs (cons (cons x (truncate-number (/ val x))) r))

            | val x:xs (r nil) ->
                (recur val xs r)

            | _ nil r ->
                r
        )

        (change 73.26 denom)
   )
   '((0.01 . 1) (0.25 . 1) (1 . 3) (10 . 1) (20 . 3))
)
(test/exec :recur12
    (fn ->
        ; currency denominations
        (const denom [20 10 5 1 0.50 0.25 0.10 0.05 0.01])

        ; tail-recursive function to calculate the change for a given value
        (defn change
            | _ nil r -> r
            | val x:xs r :where (<= x val ) ->
                (recur (.math/round (% val x) 2) xs (cons (cons x (truncate-number (/ val x))) r))
            | val x:xs r -> (recur val xs r)
            | val denom -> (recur val denom nil)
        )

        (change 373.05 denom)
   )
   '((0.05 . 1) (1 . 3) (10 . 1) (20 . 18))
)
(test/exec :recur13
    (fn ->
        ; currency denominations
        (const denom [20 10 5 1 0.50 0.25 0.10 0.05 0.01])

        ; tail-recursive function to calculate the change for a given value
        (defn change
            | _ nil r -> r
            | val x:xs r :where (<= x val ) ->
                (recur (.math/round (% val x) 2) xs (cons (cons x (truncate-number (/ val x))) r))
            | val x:xs r -> (recur val xs r)
            | val denom -> (recur val denom nil)
        )

        (change 0.66 denom)
    )
    '((0.01 . 1) (0.05 . 1) (0.1 . 1) (0.5 . 1))
)
(test/exec :recur14
    ; test that captured variables are handled properly in function arguments
    (fn ->
        
        ; reduce is a functional primitive that can be used to define the others.
        (defn rreduce 
            | [x &xs] rfn   -> (recur xs rfn x)
            | [x &xs] rfn t -> (recur xs rfn (rfn t x))
            | nil _ t       -> t
        )
        
        ; define a map function using the rreduce function
        (defn mmap [xs f2a]
            (rreduce xs (\ x y -> (concat x (f2a y))) [])
        ) 
        
        ; define a filter function using the rreduce function
        (defn ffilter [xs f]
            (rreduce xs (\ r x -> (if (f x) (add r x) r)) [])
        )
        
        [ 
            (mmap (range 4) sqr)       ; returns [1 4 9 16]
            (ffilter (range 6) even?)  ; returns [2 4 6]
        ]
        
    )
    [[1 4 9 16] [2 4 6]]
)

;-----------------------------------------------------
; Test the 'deftype' function
(test/exec :deftype1
    (fn ->
        ; simple type with two dynamically typed fields
        (deftype ^foo x y)
        (let obj (new ^foo 10 20))
        (and (== (.x obj) 10) (== (.y obj) 20))
    )
    true
)
(test/exec :deftype1a
    (fn ->
        ; simple type with two dynamically typed fields
        (deftype ^namespace.foo x y)
        (let obj (new ^namespace.foo 10 20))
        (and (== (.x obj) 10) (== (.y obj) 20))
    )
    true
)
(test/exec :deftype2
    (fn ->
        ; simple type with two explicitly typed fields
        (deftype ^foo2 ^int x ^string y)
        (let obj (new ^foo2 123 "abc"))
        (and
            (is? (.x obj) ^int)
            (==  (.x obj) 123)
            (is? (.y obj) ^string)
            (==  (.y obj) "abc")
        )
    )
    true
)
(test/exec :deftype3
    (fn ->
        ; simple type with two explicitly typed fields
        (deftype ^foo2 ^int x ^string y)
        (let result (try (new ^foo2 "123" 20)))
        (is? result ^Exception)
    )
    true
)
(test/exec :deftype4
    (fn ->
        (deftype ^foo
            ^int x
            ^int y
            ; Test a method.
            :defm sum (fn this extra ->
                (+ (.x this) (.y this) extra)
            )
        )
        (let obj (new ^foo 10 20))
        (.sum obj 30)
    )
    60
)
; a more complex object test
(test/exec :deftype6
    (fn ->

        ;
        ; Define the test class
        ;
        (deftype ^npoint

            ; data members
            ^int x
            ^int y

            ; Method to set the x & y elements of this object
            :defm set
                (fn this x y ->
                    (.x this x)
                    (.y this y)
                    this
                )

            ; Method to update this object with the values from a new object
            :defm update
                (fn this obj ->
                    (.x this (.x obj))
                    (.y this (.y obj))
                    this
                )

            ; Method to add two ^npoint objects together to get a new object
            :defm add
                (lambda [this (^npoint other)]
                    (new ^npoint
                        (+ (.x other) (.x this))
                        (+ (.y other) (.y this))
                    )
                )

            ; Method to increment the x & y members of this object
            :defm incr
                (fn this ->
                    (.x this (+ 1 (.x this)))
                    (.y this (+ 1 (.y this)))
                    this
                )

            ; Returns a new object scaled by the specified amount
            :defm scale
                (fn this factor ->
                    (new ^npoint (* factor (.x this)) (* factor (.y this)))
                )

            :defm SayIt
                (fn this ->
                    "I am npoint1: ${this} !!"
                )
        )

        (let obj1 (new ^npoint 2 3))
        (let obj1 (.scale obj1 10))
        (.incr obj1)

        ;
        ; define a subclass of npoint
        ;
        (deftype ^npoint2 -extends: ^npoint
            ^int z

            ; override the SayIt method.
            :defm SayIt
                (fn this ->
                    "I am npoint2: ${this} !!"
                )
        )

        (let obj2 (new ^npoint2 4))
        (.set obj2 15 30)

        [
            (.sayit obj1)
            (.sayit obj2)
        ]
    )
    [
        "I am npoint1: {\"x\" : 21, \"y\" : 31} !!"
        "I am npoint2: {\"z\" : 4, \"x\" : 15, \"y\" : 30} !!"
    ]
)
(test/exec :deftype7
    (fn ->
        (deftype ^foo
            ^int x
            ^int y

            ; test the constructor.
            :defm new (fn this x y -> (.x this (* x 2)) (.y this (* y 3)))

            :defm get (fn this -> [ (.x this) (.y this) ])
        )
        (.get (new ^foo 2 3))
    )
    [4 9]
)

(test/exec :deftype8
    (fn ->
        (deftype ^foo
            ^int x
            ^int y
            :defm get (fn this -> [ (.x this) (.y this) ])
            ; don't have constructor overloads yet...
            :defm new (fn this &args ->
                (matchp @args
                | x y -> (this | .x (* x 2) | .y (* y 3))
                | x   -> (this | .x x | .y (* x 2))
                |     -> (throw "Invalid number of arguments to constructor.")
                )
            )
        )
        [ (.get (new ^foo 2 3)) (.get (new ^foo 10)) ]
    )
    [[4 9] [10 20]]
)

(test/exec :deftype9
    (fn ->
        ; test extending non-braid types.
        (deftype ^MyVector -extends: ^vector
            ^int zork
            :defm status (fn this ->
                [ (.count this) (.zork this) ]
            )
        )

        (let v (new ^MyVector))
        (.addrange v [1 2 3])
        (.zork v 33)
        (.status v)
    )
    [3 33]
)
(test/exec :deftype10
    (fn ->
        ; test overloads based on arity.
        (deftype ^MyVector -extends: ^vector
            :defm foo (fn this -> "zero")
            :defm foo (fn this x -> "one")
            :defm foo (fn this x y -> "two")
            :defm foo (fn this x y z -> "three")
        )

        (let obj (new ^MyVector))
        [(.foo obj) (.foo obj 1) (.foo obj 1 2) (.foo obj 1 2 3)]
    )
    ["zero" "one" "two" "three"]
)
(test/exec :deftype11
    (fn ->
        ; test overloads based on arity.
        (deftype ^MyVector -extends: ^vector
            ^int a
            :defm foo (fn this -> "zero")
            :defm foo (fn this x -> "one")
            :defm foo (fn this x y -> "two")
            :defm foo (fn this x y z -> "three")
        )

        (deftype ^MyVector2 -extends: ^MyVector ^int b ^string c)

        (let obj (new ^MyVector2))
        [(.foo obj) (.foo obj 1) (.foo obj 1 2) (.foo obj 1 2 3)]
    )
    ["zero" "one" "two" "three"]
)
(test/exec :deftype12
    (fn ->
        (deftype ^mytype :defm foo (fn ^string this (^int x) (^int y) -> (^string? (+ x y))))
        (let f (new ^mytype))
        (let result (.foo f 2 3))
        (and
            (== result 5)
            (is? result ^string))
   )
   true
)
(test/exec :deftype13
    (fn ->
        ; verify void functions 'return' null.
        (deftype ^mytype :defm foo (fn ^void? this (^int x) (^int y) -> (+ x y)))
        (let f (new ^mytype))
        (let result (.foo f 2 3))
   )
   null
)
(test/exec :deftype14
    (fn ->
        ; if the 'this' parameter is missing an error should be raised.
        (try (deftype ^mytype :defm foo (fn ^void (^int x) (^int y) -> (+ x y)))
        | is? ^Exception
        )
    )
    true
)
(test/exec :deftype15
    (fn ->
        ; test lexical scoping of types
        (and
            ; child scope has the defined type
            (with [] (deftype ^ZZZZ a) (contains? *types* "ZZZZ"))
            ; but the parent does not
            (not (contains? *types* "ZZZZ")))
    )
    true
)
(test/exec :deftype16
    (fn ->
        ; test self-referential method return types
        (deftype ^buz
            x
            :defm bar (fn ^buz this a -> (new ^buz a))
        )
        (let a (new ^buz 1))
        (let b (.bar a 22))
        [(.x a) (.x b)]
    )
    [1 22]
)
(test/exec :deftype20
    (fn ->
        ; test static method definitions
        (deftype ^foo
            ^int x
            :defm imethod (fn this s -> (.x this | * s))
            :defm /smethod (fn x y -> (+ x y))
        )
        [
            (.foo/smethod 2 3)
            (.imethod (new ^foo 13) 2)
        ]
    )
    [5 26]
)
(test/exec :deftype21
    (fn ->
        ; test static method overloads
        (deftype ^foo
            ^int x
            :defm imethod (fn this s -> (.x this | * s))
            :defm /smethod (fn ^int x y -> (+ x y))
            :defm /smethod (fn x -> (* x 3))
        )
        [
            (.foo/smethod 2 3)
            (.foo/smethod 4)
            (.imethod (new ^foo 13) 2)
        ]
    )
    [5 12 26]
)
(test/exec :deftype22
    (fn ->
        ; test calling a static method from an instance method with overloads
        (deftype ^foo
            ^int x

            :defm imethod (fn this s ->
                (.foo/smethod (.x this | * s))
            )

            :defm /smethod (fn x y -> (+ x y))
            :defm /smethod (fn x -> (* x 3))
        )
        [
            (.foo/smethod 2 3)          ; returns (+ 2 5)
            (.foo/smethod 4)            ; returns (* 4 3)
            (.imethod (new ^foo 13) 2)  ; returns (* 13 2 3)
        ]
    )
    [5 12 78]
)
(test/exec :deftype23
    (fn ->
        ; test static properties
        (deftype ^foo
            /x
            /y
        )
        (.foo/x 12)
        (.foo/y 14)
        (+ .foo/x .foo/y)
    )
    26
)
(test/exec :deftype24
    (fn ->
        ; test static properties
        (deftype ^foo
            ^int /x
            ^int /y
        )
        (.foo/x 12)
        (.foo/y 14)
        (+ .foo/x .foo/y)
    )
    26
)
(test/exec :deftype25
    (fn ->
        ; test static method with no args
        (deftype ^foo
            ^int /x
            :defm /next (fn ->
                (.foo/x (+ 1 .foo/x))
                .foo/x
            )
        )
        (.foo/x 0)
        [(.foo/next) (.foo/next) (.foo/next)]
    )
    [1 2 3]
)
(test/exec :deftype26
    (fn ->
        ; test static method with no args and explicit return type
        (deftype ^foo
            ^int /x
            :defm /next (fn ^int ->
                (.foo/x (+ 1 .foo/x))
                .foo/x
            )
        )
        (.foo/x 0)
        [(.foo/next) (.foo/next) (.foo/next)]
    )
    [1 2 3]
)
(test/exec :deftype27
    (fn ->
        ; test static method with no args and ^void return.
        (deftype ^foo
            ^int /x
            :defm /next (fn ^void ->
                (.foo/x (+ 1 .foo/x))
                .foo/x
            )
        )
        (.foo/x 0)
        ; return the results (should all be null) and the current value of /x
        [(.foo/next) (.foo/next) (.foo/next) .foo/x]
    )
    [null null null 3]
)
(test/exec :deftype28
    (fn ->
        ; test static and instance methods with no args and explicit return type
        (deftype ^foo
            ^int /x
            ^int y
            :defm inext (fn ^int this ->
                (.y this (+ 2 (.y this)))
                (.y this)
            )
            :defm /next (fn ^int ->
                (.foo/x (+ 1 .foo/x))
                .foo/x
            )
        )
        (.foo/x 0)
        (let f (new ^foo))
        [(.foo/next) (.inext f) (.foo/next) (.inext f) (.foo/next) (.inext f)]
    )
    [1 2 2 4 3 6]
)
(test/exec :deftype29
    (fn ->
        ; test static and instance methods with one typed arg and explicit return type
        (deftype ^foo
            ^int /x
            ^int y
            ; add the argument amount to y
            :defm inext (fn ^int this (^int m) ->
                (.y this (+ m (.y this)))
                (.y this)
            )
            ; add the argument amount to x
            :defm /next (fn ^int (^int n) ->
                (.foo/x (+ n .foo/x))
                .foo/x
            )
        )
        (.foo/x 0)
        (let f (new ^foo))
        ;    1              1           (+ 1 2)     (+ 1 3)       (+ 3 3)       (+ 4 2)
        [(.foo/next 1) (.inext f 1) (.foo/next 2) (.inext f 3) (.foo/next 3) (.inext f 2)]
    )
    [1 1 3 4 6 6]
)
(test/exec :deftype30
    (fn ->
        ; test static and instance methods with two typed args and explicit return type
        (deftype ^foo
            ^int /x
            ^int y
            ; add the argument amount to y
            :defm inext (fn ^int this (^int m) (^int n) ->
                (.y this (+ m n (.y this)))
                (.y this)
            )
            ; add the argument amount to x
            :defm /next (fn ^int (^int m) (^int n) ->
                (.foo/x (+ m n .foo/x))
                .foo/x
            )
        )
        (.foo/x 0)
        (let f (new ^foo))
        ;    2              3             (+ 2 2 2)       (+ 3 1 3)       (+ 6 3 1)       (+ 7 2 5)
        [(.foo/next 1 1) (.inext f 1 2) (.foo/next 2 2) (.inext f 1 3) (.foo/next 3 1) (.inext f 2 5)]
    )
    [2 3 6 7 10 14]
)
(test/exec :deftype31
    (fn ->
        ; test static and instance methods with two typed args and void return type
        (deftype ^foo
            ^int /x
            ^int y
            ; add the argument amount to y
            :defm inext (fn ^void this (^int m) (^int n) ->
                (.y this (+ m n (.y this)))
                (.y this)
            )
            ; add the argument amount to x
            :defm /next (fn ^void (^int m) (^int n) ->
                (.foo/x (+ m n .foo/x))
                .foo/x
            )
        )
        (.foo/x 0)
        (let f (new ^foo))

        ;    2       
        (.foo/next 1 1 | and (throw "return value was not null"))
        ;    3
        (.inext f 1 2 | and (throw "return value was not null"))
        ; (+ 2 2 2)
        (.foo/next 2 2 | and (throw "return value was not null"))
        ; (+ 3 1 3)
        (.inext f 1 3 | and (throw "return value was not null"))
        ; (+ 6 3 1)
        (.foo/next 3 1 | and (throw "return value was not null"))
        ;(+ 7 2 5)
        (.inext f 2 5 | and (throw "return value was not null"))

        [.foo/x (.y f)]
    )
    [10 14]
)
(test/exec :deftype32
    (fn ->
        ; testnamespaced  static and instance methods with two typed args and void return type
        (deftype ^foo.bar
            ^int /x
            ^int y
            ; add the argument amount to y
            :defm inext (fn ^void this (^int m) (^int n) ->
                (.y this (+ m n (.y this)))
                (.y this)
            )
            ; add the argument amount to x
            :defm /next (fn ^void (^int m) (^int n) ->
                (.foo.bar/x (+ m n .foo.bar/x))
                .foo.bar/x
            )
        )
        (.foo.bar/x 0)
        (let f (new ^foo.bar))

        ;    2       
        (.foo.bar/next 1 1 | and (throw "return value was not null"))
        ;    3
        (.inext f 1 2 | and (throw "return value was not null"))
        ; (+ 2 2 2)
        (.foo.bar/next 2 2 | and (throw "return value was not null"))
        ; (+ 3 1 3)
        (.inext f 1 3 | and (throw "return value was not null"))
        ; (+ 6 3 1)
        (.foo.bar/next 3 1 | and (throw "return value was not null"))
        ;(+ 7 2 5)
        (.inext f 2 5 | and (throw "return value was not null"))

        [.foo.bar/x (.y f)]
    )
    [10 14]
)

;-----------------------------------------------------
; Test the 'undeftype' function
(test/exec :undeftype1
    (fn ->
        (with []
            (deftype ^undeftype1_type)
            (undeftype ^undeftype1_type)
            (try ^undeftype1_type "success" -catch: "nosuchtype")
        )
    )
    "nosuchtype"
)
(test/exec :undeftype2
    (fn ->
        (deftype ^undeftype2_type)
        (with []
            (deftype ^undeftype2_type)
            (undeftype ^undeftype2_type)
        )
        (try ^undeftype2_type "success" -catch: "nosuchtype")
    )
    "success"
)


;-----------------------------------------------------
; Test the 'defmethod' function
(test/exec :defmethod1
    (fn ->
        (deftype ^foo
            ^int x
            ^int y
        )

        ; define an method separately from the type
        (defmethod ^foo sum
            (fn this extra ->
                (+ (.x this) (.y this) extra)
            )
        )

        (let obj (new ^foo 10 20))
        (.sum obj 30)
    )
    60
)
(test/exec :defmethod2
    (fn ->
        ; define an "extension method" on a .net type
        (defmethod ^vector sumvector
            (fn this ->
                (sum this)
            )
        )

        (let vect [1 2 3 4])
        (.sumvector vect)
    )
    10
)
(test/exec :defmethod3
    (fn ->
        ; define a pair of "extension method" that call each other
        ; on a .net type

        (defmethod ^Vector sqrvector
            (fn this -> (this | map sqr))
        )

        (defmethod ^vector sumvector
            (fn this ->
                (sum (.sqrvector this))
            )
        )

        (let vect [1 2 3 4])
        (.sumvector vect)
    )
    30
)
(test/exec :defmethod4
    (fn ->
        ; define a method on the base class then call it
        ; from an instance of a derived class.
        (defmethod ^vector getme (fn this -> 3.14))
        (deftype ^VectorPrime -extends: ^vector)
        (let obj (new ^VectorPrime))
        (.getme obj)
    )
    3.14
)
(test/exec :defmethod5
    (fn ->
        ; define a method on the base class then call it
        ; from an instance of a derived class.
        (defmethod ^vector getme (fn this -> 3.14))
        (deftype ^VectorPrime -extends: ^vector :defm getme (fn this -> 6.28))
        (let obj (new ^VectorPrime))
        (.getme obj)
    )
    6.28
)
(test/exec :defmethod6
    (fn ->
        ; define a method on the base class then call it
        ; from an instance of a derived class.
        (defmethod ^vector getme (fn this -> 3.14))
        (deftype ^VectorPrime -extends: ^vector :defm getme2 (fn this -> 6.28))
        (let obj (new ^VectorPrime))
        (defmethod ^VectorPrime getme3 (fn this -> "hello"))
        [ (.getme obj) (.getme2 obj) (.getme3 obj) ]
    )
    [
        3.14    ; base class extension method
        6.28    ; derived-class "native" method
        "hello" ; derived-class extension method
   ]
)

(test/exec :defmethod7
    (fn ->
        ; Try a couple layers of subclassing. First augment ^Vector
        (defmethod ^vector getme (fn this -> 3.14))

        ; then derive from it.
        (deftype ^VectorPrime -extends: ^vector :defm getme (fn this -> 6.28))

        ; and derive again.
        (deftype ^V3 -extends: ^VectorPrime)

        ; create an object from the most derived class
        (let obj (new ^V3))

        ; try monkey-patching the subclass after the instance has been created.
        ; this shouldn't work - extension methods don't override concrete members
        ; BUGBUGBUG - should probably generate an error if you try to hide an existing member...
        (defmethod ^VectorPrime getme (fn this -> "Tada"))

        (.getme obj)
    )
    6.28
)

;-----------------------------------------------------
; Test the 'definterface' function
(test/exec :definterface1
    (fn ->
        (definterface ^mypoint x y :defm get (fn ^Vector this ->))
        (.IsInterface ^mypoint)
    )
    true
)
(test/exec :definterface2
    (fn ->
        (definterface ^mypoint x y :defm get (fn ^Vector this ->))
        (try
            (deftype ^zork -implements: ^mypoint)
        | is? ^Exception
        )
    )
    true
)
(test/exec :definterface3
    (fn ->
        (definterface ^mypoint x y :defm get (fn ^Vector this ->))
        ; define a new interface inline with a new type definition inline with an instantiation of that type
        (let p (new (deftype ^cpoint -implements: ^mypoint x y :defm get (fn ^Vector this -> [(.x this) (.y this)])) 2 3))
        (.get p)
    )
    [2 3]
)
(test/exec :definterface4
    (fn ->
        ; test passing multiple interfaces
        (definterface ^foo a b)
        (definterface ^bar b c)
        (deftype ^baz -implements: [^foo ^bar ] a b c)
        (let x (new ^baz 1 2 3))
        (== 1 (.a x) 2 (.b x) 3 (.c x))
    )
    true
)
(test/exec :definterface5
    (fn ->
        ; test error thrown for missing interface elements
        (definterface ^foo a b)
        (definterface ^bar b c)
        (try (deftype ^baz -implements: [^foo ^bar ] a c) | is? ^Exception)
    )
    true
)
(test/exec :definterface6
    (fn ->
        ; test error thrown for missing interface elements
        (definterface ^foo a b)
        (definterface ^bar b c)
        (try (deftype ^baz -implements: [^foo ^bar ] a b) | is? ^Exception)
    )
    true
)
(test/exec :definterface7
    (fn ->
        ; test passing multiple interfaces to an interface definition
        (definterface ^foo a b)
        (definterface ^bar b c)
        (definterface ^baz -implements: [^foo ^bar ] d)
        (deftype ^buz -implements: ^baz a b c d)
        (let x (new ^buz 1 2 3 4))
        (== 1 (.a x) 2 (.b x) 3 (.c x) 4 (.d x))
    )
    true
)
(test/exec :definterface8
    (fn ->
        ; verify that the type does reference the interfaces
        (definterface ^foo a b)
        (definterface ^bar b c)
        (definterface ^baz -implements: [^foo ^bar ] d)
        (deftype ^buz -implements: ^baz a b c d)
        (let ifs (.getinterfaces ^buz))
        (and
            (contains? ifs ^foo)
            (contains? ifs ^bar)
            (contains? ifs ^baz))
    )
    true
)
(test/exec :definterface9
    (fn ->
        ; test interfaces plus base class
        (definterface ^foo a b)
        (definterface ^bar b c)
        (definterface ^baz -implements: [^foo ^bar ] d)
        (deftype ^thebase e)
        (deftype ^buz -extends: ^thebase -implements: ^baz a b c d)
        (let ifs (.getinterfaces ^buz))
        (and
            (contains? ifs ^foo)
            (contains? ifs ^bar)
            (contains? ifs ^baz)
            (is? ^buz ^thebase))
    )
    true
)
(test/exec :definterface10
    (fn ->
        ; test interfaces plus base class
        (definterface ^foo a b)
        (definterface ^bar b c)
        (definterface ^baz -implements: [^foo ^bar ] d)
        (deftype ^thebase e)
        (deftype ^buz -extends: ^thebase -implements: ^baz
            a b c d
            ; need an explict constructor
            :defm new (fn this a b c d e ->
                (this | .a a | .b b | .c c | .d d | .e e)
            )
        )
        (let x (new ^buz 1 2 3 4 5))
        (== 1 (.a x) 2 (.b x) 3 (.c x) 4 (.d x) 5 (.e x))
    )
    true
)
(test/exec :definterface11
    (fn ->
        ; test self-referential method return types
        (definterface ^foo x :defm bar (fn ^foo this x ->))
        (deftype ^buz -implements: ^foo
            x
            :defm bar (fn ^foo this a -> (new ^buz a))
        )
        (let a (new ^buz 1))
        (let b (.bar a 22))
        [(.x a) (.x b)]
    )
    [1 22]
)

;-----------------------------------------------------
; Test the 'type-alias' function
(test/exec :type-alias1
    (fn ->
        (deftype ^rec2 ^int a ^string b ^int c)
        (type-alias ^aliased_type ^rec2)
        (let rec (new ^aliased_type 1 "2" 3))
        (and
            (.a rec | == 1)
            (.b rec | is? ^string)
            (.c rec | == 3))
    )
    true
)

;-----------------------------------------------------
; Test tasks
(test/exec :task1
    ; single task resolves to the value returned by the task.
    (fn -> (await (async (fn -> 8))))
    8
)
(test/exec :task1a
    ; a vector literal is returned as a vector
    (fn -> (await (async (fn -> [1 2 3]))))
    [1 2 3]
)
(test/exec :resolve1
    (fn -> (async (fn -> (* 2 3)) | await))
    6
)
(test/exec :task2
    ; task with a parameter
    (fn -> (try (await (async (fn x -> (* x 4)) 3))))
    12
)
(test/exec :task3
    (fn ->
        ; await multiple tasks with explict parameter
        (await (forall v (range 5) (async (fn v -> (* v v)) v)))
    )
    [1 4 9 16 25]
)
(test/exec :task3a
    (fn ->
        ; await multiple tasks with explict parameter returning vectors
        (await (forall v (range 5) (async (fn v -> [(* v v)]) v)))
    )
    ; expect nested vectors
    [[1] [4] [9] [16] [25]]
)
(test/exec :task4
    (fn ->
        ; sequence of tasks (continuations)
        ( async (fn -> "hi")
        | async (fn n -> (join [n "there"]))
        | async (fn n -> (join [n "world."]))
        | await
        )
    )
    "hi there world."
)
; try task with a built-in n-ary function
(test/exec :task5
    (fn ->
        (async sum (range 10) | await)
    )
    55
)
(test/exec :task7
    (fn ->
        ; a task that returns nested tasks so need to call await twice
        (async (fn n -> (forall i (range n) (async (fn x -> (* x 2)) i))) 3 | await | await)
    )
    [2 4 6]
)
(test/exec :task7a
    (fn ->
        ; nested tasks returning vectors
        (async (fn n -> (forall i (range n) (async (fn x -> [x x]) i))) 3 | await | await)
    )
    [[1 1] [2 2] [3 3]]
)
(test/exec :map-parallel1
    (fn -> (range 5 | map-parallel  #(* 2 %0) | sum))
    30
)
(test/exec :map-parallel2
    (fn ->
        (defn doit [x] (* x 2))
        ; call a function inherited from the parent environment
        (range 5 | map-parallel doit | sum)
    )
    30
)
(test/exec :map-parallel3
    (fn -> (range 5 | map-parallel (fn x -> (* 2 x)) | sum))
    30
)
(test/exec :map-parallel4
    (fn ->
        ; parallel quick sort
        (defn qsp
            | [] -> []
            | p:xs :where (length xs | > 100) ->
                (list/split xs (<= p) | map-parallel qsp | (fn x:y: -> [@x p @y]))
            | p:xs -> (list/split xs (<= p) | map qsp | (fn x:y: -> [@x p @y]))
        )

        ; rather than comparing the result, just make sure it's monotonically increasing
        (random 1000 | qsp | list/monotonic)
    )
    true
)
(test/exec :task-continuations1
    (fn ->
        (async  #(echo 10) | async #(+ 15 %0) | await)
    )
    25
)
(test/exec :task-continuations2
    (fn ->
        ( async  #(echo 10)
        | async  #(+ 15 %0)
        | async  #(+ 5 %0)
        | async  #(+ -6 %0)
        | async  #(/ %0 12)
        | await)
    )
    2
)
(test/exec :task-continuations2a
    (fn ->
        ; mix pattern and regular functions
        ( async  #(echo 10)
        | async  (fn n -> (+ 15 n))
        | async  #(+ 5 %0)
        | async  (fn | n -> (+ -6 n))
        | async  #(/ %0 12)
        | await)
    )
    2
)

(test/exec :task-continuations2b
    (fn ->
        ; mix pattern and regular functions
        ( async  (fn -> 10)
        | async  (fn n m -> (+ n m)) 15
        | async  #(+ 5 %0)
        | async  (fn | n m -> (+ m n)) -6
        | async  #(/ %0 12)
        | await)
    )
    2
)

(test/exec :async1
    (fn -> (await (async (fn -> 8))))
    8
)

(test/exec :async1a
    (fn -> (await (async (fn n -> n) 8)))
    8
)

(test/exec :async1b
    (fn -> (await (async (fn n m -> [n m]) 8 9)))
    [8 9]
)

(test/exec :async1c
    (fn -> (await (async (fn n m o -> [n m o]) 8 9 10)))
    [8 9 10]
)

(test/exec :async2
    (fn ->
        (vlet t (async (fn -> "hello") | async  #(str ">>" %0) | async (fn n -> (str n "<<"))))
        (await t)
    )
    ">>hello<<"
)
(test/exec :await1
    (fn -> (try (await (async (fn x -> (* x 4)) 3))))
    12
)
(test/exec :await2
    (fn ->
        (async (fn -> 10) | async (fn n -> (* n 2)) | await)
    )
    20
)
(test/exec :await3
    (fn ->
        ; await 3 tasks
        (await
            (async (fn -> 10))
            (async (fn -> 20))
            (async (fn -> 30)))
    )
    [10 20 30]
)
(test/exec :await4
    (fn ->
        ; await 3 tasks in a vector
        (await [
            (async (fn -> 10))
            (async (fn -> 20))
            (async (fn -> 30))
        ])
    )
    [10 20 30]
)
(test/exec :await5
    (fn ->
        ; await a mix of individual tasks and collections of tasks
        (await
            (async (fn -> 1))
            [
                (async (fn -> 10))
                (async (fn -> 20))
                (async (fn -> 30))
            ]
            (async (fn -> 100))
        )
    )
    [1 10 20 30 100]
)
(test/exec :await6
    (fn ->
        ; await a larger mix of individual tasks and collections of tasks
        (await
            (async (fn -> 1))
            [
                (async (fn -> 10))
                (async (fn -> 20))
                (async (fn -> 30))
            ]
            (async (fn -> 100))
            (async (fn -> 1))
            [
                (async (fn -> 10))
                (async (fn -> 20))
                (async (fn -> 30))
            ]
            (async (fn -> 100))
        )
    )
    [1 10 20 30 100 1 10 20 30 100]
)
(test/exec :await7
    (fn ->
        ; using both regular and pattern functions
        (await
            (async (fn | -> 1))
            [
                (async (fn | -> 10))
                (async (fn | -> 20))
                (async (fn | -> 30))
            ]
            (async (fn | -> 100))
            (async (fn | -> 1))
            [
                (async (fn | -> 10))
                (async (fn -> 20))
                (async (fn -> 30))
            ]
            (async (fn | -> 100))
        )
    )
    [1 10 20 30 100 1 10 20 30 100]
)
(test/exec :await8
    (fn ->
        ; using both regular and pattern functions and continuations
        (await
            (async (fn | -> 1))
            [
                (async (fn | -> 5) | async (fn | n -> (* n 2)))
                (async (fn | -> 20))
                (async (fn | -> 30))
            ]
            (async (fn | -> 100))
            (async (fn | -> 1) | async (fn n -> (* n 2)) | async (fn | n -> (+ n 3)))
            [
                (async (fn | -> 10))
                (async (fn -> 10) | async (fn n -> (* n 2)))
                (async (fn -> 30))
            ]
            (async (fn | -> 100))
        )
    )
    [1 10 20 30 100 5 10 20 30 100]
)

;-----------------------------------------------------
; implicit indexing dictionary and vector indexing.
(test/exec :implicit-dict-indexing1
    (fn ->
        ({:a 1 :b 2 :c 3} :b)
    )
    2
)
(test/exec :implicit-dict-indexing1a
    (fn ->
        (let data {:a 1 :b 2 :c 3})
        (data | :b)
    )
    2
)
(test/exec :implicit-dict-indexing2
    (fn ->
        (let x {:a 10 :b 20 :c 30})
        (x :b)
    )
    20
)
(test/exec :implicit-dict-indexing3
    (fn ->
        (let x {:a 10 :b {:x 1 :y 2} :c 30})
        (x :b | :y)
    )
    2
)
(test/exec :implicit-dict-indexing4
    (fn ->
        (let x {:a 10 :b {:x 1 :y {:m 111 :n 222}} :c 30})
        (and
            (== (x :b | :y | :n) 222)
            (== (x :b | :x) 1)
            (== (x :a) 10)
            (== (x :c) 30)
        )
    )
    true
)
(test/exec :implicit-dict-indexing5
    (fn ->
        (let x {:a 10 :b 20 :c 30})
        (x :b 200)
    )
    {:a 10 :b 200 :c 30}
)
(test/exec :implicit-dict-indexing6
    (fn ->
        (let x {:a 10 :b 20 :c 30})
        ; pipeline works because (:keyword dict) and (dict :keyword) are both valid
        (x :b 200 | :c 300)
        x
    )
    {:a 10 :b 200 :c 300}
)
(test/exec :implicit-dict-indexing7
    (fn ->
        ({} | :a 1 | :b 2 | :c 3 | :d 4)
    )
    {:a 1 :b 2 :c 3 :d 4}
)

(test/exec :implicit-vector-indexing1
    (fn ->
        ([0 1 2 3 4] 2)
    )
    2
)
(test/exec :implicit-vector-indexing2
    (fn ->
        (let x [0 1 2 3 4])
        (x 2)
    )
    2
)
(test/exec :implicit-vector-indexing3
    (fn ->
        (let x [0 1 2 3 4])
        (x 2 20)    ; assignment
    )
    [0 1 20 3 4]
)
(test/exec :implicit-vector-indexing4
    (fn ->
        (let data [0 1 2 3 4])
        (data 2)
    )
    2
)
(test/exec :implicit-vector-indexing5
    (fn ->
        (let data [0 1 20 3 4])
        (data | !! 2)
    )
    20
)

;-----------------------------------------------------
; math routines
(test/exec :sin     (fn -> (== (sin 0.5) (.math/sin 0.5))) true)
(test/exec :cos     (fn -> (== (cos 0.5) (.math/cos 0.5))) true)
(test/exec :tan     (fn -> (== (tan 0.5) (.math/tan 0.5))) true)
(test/exec :sqrt1   (fn -> (sqrt 9))   3)
(test/exec :sqrt2   (fn -> (9 | sqrt)) 3)
(test/exec :sqrt3   (fn -> (sqrt -5 | tostring)) "nan")
(test/exec :sqr1    (fn -> (sqr 3))     9)
(test/exec :sqr2    (fn -> (sqr -3))    9)
(test/exec :sqr3    (fn -> (is? (sqr 9.3) ^double)) true)
(test/exec :abs1    (fn -> (abs 0.5))   0.5)
(test/exec :abs2    (fn -> (abs -0.5))  0.5)
(test/exec :abs3    (fn -> (abs 1))     1)
(test/exec :abs4    (fn -> (abs -1))    1)
(test/exec :abs5    (fn -> (abs "-1"))  1)
(test/exec :sign1   (fn -> (sign -123)) -1)
(test/exec :sign2   (fn -> (sign 123)) 1)
(test/exec :truncate-number1 (fn -> (truncate-number 0.5)) 0)
(test/exec :truncate-number2 (fn -> (truncate-number 2.5)) 2)
(test/exec :truncate-number3 (fn -> (truncate-number 2.5 | type-of)) ^int)
(test/exec :floor1 (fn -> (floor 1.23)) 1)
(test/exec :floor2 (fn -> (is? (floor 1.23) ^int)) true)
(test/exec :ceiling1 (fn -> (ceiling 1.23)) 2)
(test/exec :ceiling2 (fn -> (is? (ceiling 1.23) ^int)) true)
(test/exec :round1  (fn -> (round 0.4)) 0)
(test/exec :round2  (fn -> (round 0.5)) 0)
(test/exec :round3  (fn -> (round 0.51)) 1)
(test/exec :round4  (fn -> (round 0.6)) 1)
(test/exec :round5  (fn -> (round 3.1415 0)) 3)
(test/exec :round6  (fn -> (round 3.1415 1)) 3.1)
(test/exec :round7  (fn -> (round 3.1415 2)) 3.14)
(test/exec :round8  (fn -> (round 3.1415 3)) 3.142)

; Test the 'log' function.
; BUGBUGBUG - NOTE lexically "10." and ".5" don't work.
(test/exec :log1    (fn -> (log 10.0 10)) 1)
(test/exec :log2    (fn -> (log 10 10)) 1)
(test/exec :log3    (fn -> (log 10 10.0)) 1)
(test/exec :log4    (fn -> (log 10.0 10.0)) 1)
(test/exec :log5    (fn -> (log .math/e)) 1)

; Test the 'not' function
(test/exec :not1    (fn -> (not true)) false)
(test/exec :not2    (fn -> (not false)) true)
(test/exec :not3    (fn -> (not 1)) false)
(test/exec :not4    (fn -> (not 0)) true)
(test/exec :not5    (fn -> (not "abc")) false)
(test/exec :not6    (fn -> (not "")) true)
(test/exec :not7    (fn -> (not [])) true)
(test/exec :not8    (fn -> (not [1])) false)

;-----------------------------------------------------
; test new function
(test/exec :new1
    (fn ->
        (is? (new ^int[] 10) ^int[])
    )
    true
)
(test/exec :new2
    (fn ->
        (is? (new ^System.Collections.Generic.List[int]) ^System.Collections.Generic.List[int])
    )
    true
)
(test/exec :new3
    (fn ->
        (is? (new ^System.Collections.Generic.List[int] 100) ^System.Collections.Generic.List[int])
    )
    true
)
(test/exec :new4
    (fn ->
        (let sl (new ^System.Collections.SortedList))
        (.add sl 5 "foo")
        (.add sl 2 "foo")
        (.add sl 4 "foo")
        (.add sl 1 "foo")
        (.add sl 3 "foo")
        (.keys sl | map ^int)
    )
    [1 2 3 4 5]
)
(test/exec :new5
    (fn ->
        (let sb (new ^stringbuilder))
        (.append sb "foo")
        (.append sb "bar")
        (.append sb "baz")
        (.tostring sb)
    )
    "foobarbaz"
)
(test/exec :new6
    (fn ->
        (let dt (new ^System.Data.DataTable))
        (type-of dt)
    )
    ^System.Data.DataTable
)

;-----------------------------------------------------
; Test PowerShell commands

(when IsWindows ; can only run on windows
    (test/exec :powershell1
        (fn ->
            ; verify that there is a non-null instance property "Name".
            (^bool? (.name (get-ciminstance 'win32_bios)))
        )
        true
    )
    (test/exec :powershell2
        (fn ->
             (get-ciminstance 'win32_bios | type-of | == ^System.Management.Automation.PSObject)
        )
        true
    )
    (test/exec :powershell3
        (fn ->
             (get-ciminstance 'win32_bios | baseobject | type-of | == ^Microsoft.Management.Infrastructure.CimInstance)
        )
        true
    )
)
(test/exec :powershell5
    (fn ->
        (get-item "." | type-of)
    )
    ^psobject
)
(test/exec :powershell6
    (fn ->
        (get-item "." | baseobject | type-of)
    )
    ^System.IO.DirectoryInfo
)
(test/exec :powershell7
    (fn ->
        (get-item (join-path braidhome "autoload.tl") | baseobject | type-of)
    )
    ^System.IO.FileInfo
)
(test/exec :powershell8
    (fn ->
        (get-process | !! 0 | baseobject | is? ^System.Diagnostics.Process)
    )
    true
)
(test/exec :powershell9
    (fn ->
        ([(defobject :a 1) (defobject :a 2) (defobject :a 3) (defobject :a 4)]
        | where-object :a -ge 3
        | foreach-object :a)
    )
    [3 4]
)
(test/exec :powershell10
    (fn ->
        ([(defobject :a 1) (defobject :a 2) (defobject :a 3) (defobject :a 4)]
        | where-object :a -ge 3
        | map .a
        )
    )
    [3 4]
)
(test/exec :powershell11
    (fn ->
        ([(defobject :a 1) (defobject :a 2) (defobject :a 3) (defobject :a 4)]
        | where-object :a -ge 3
        | map (fn o -> (. o :a))
        )
    )
    [3 4]
)
(test/exec :powershell12
    (fn ->
        ([(defobject :a 1) (defobject :a 2) (defobject :a 3) (defobject :a 4)]
        | filter (fn o -> (>= (.a o) 3))
        | foreach-object :a
        | map baseobject
        )
    )
    [3 4]
)
(test/exec :powershell13
    (fn ->
        (let so (defobject :a 1 :b 2 :c 3 | select-object ["a" "c"]))
        (and
            (.a so | == 1)
            (.c so | == 3)
            (try (.b so) | is? ^Exception) ; accessing b should raise an hour
        )
    )
    true
)
(test/exec :powershell14
    (fn ->
        (let so [(defobject :p 1) (defobject :p 2) (defobject :p 3)])
        (so | foreach-object "p")
    )
    [1 2 3]
)
(test/exec :powershell15
    (fn ->
        (let so [(defobject :p 1) (defobject :p 2) (defobject :p 3)])
        (so | where-object "p" -ge 2 | measure-object | foreach-object "count")
    )
    2
)
(if (and IsWindows IsDesktop)
    (test/exec :powershell16
         #(get-eventlog -logname: "system" -newest: 10 | !! 0 | baseobject | is? ^System.Diagnostics.EventLogEntry)
        true
    )
)
(test/exec :create-scriptblock1
    (fn ->
        (let myadd (create-scriptblock "param ($x, $y) $x+$y"))
        (myadd 5 6)
    )
    11
)
(test/exec :create-scriptblock2
    (fn ->
        (range 5 | foreach-object (create-scriptblock "$_*2"))
    )
    [2 4 6 8 10]
)
(test/exec :create-scriptblock3
    (fn ->
        (range 10 | where-object (create-scriptblock "$_ % 2"))
    )
    [1 3 5 7 9]
)

;-----------------------------------------------------------
; PowerShell-specific functions shell, psvar
(test/exec :psvar1
    (fn ->
        (psvar 'psversiontable | .value | is? ^hashtable)
    )
    true
)
(test/exec :psvar1a
    (fn ->
         (psvar :psversiontable | .value | !! "psversion" | .major | >= 5)
    )
    true
)
(if isWindows
    (test/exec :shell1
        (fn ->
            (shell "get-process | where-object name -like csrss | select-object  -first 1 | foreach-object processname")
        )
        "csrss"
    )
)
(test/exec :shell2
    (fn ->
       (shell "1..10 | foreach {$_ * 2} | measure-object -sum | foreach sum")
    )
    110
)
(test/exec :shell3
    (fn ->
       (shell "1..10 | foreach {$_ * 2} | measure-object -sum" | .sum)
    )
    110
)

;-----------------------------------------------------
; test memoize function
(test/exec :memoize1
    (fn ->
        ; standard naive recursive fib function
        (defn mfib
            | 0 -> 1
            | 1 -> 1
            | n -> (+
                (mfib (- n 1))
                (mfib (- n 2))
            )
        )
        ; rebind the function
        (def mfib (memoize mfib))
        ; without memoization, this would take a very long time
        (mfib 50)
    )
    20365011074
)

;-----------------------------------------------------
; test 'sleep'
(test/exec :sleep1
    (fn ->
        (sleep 20)
        3.14
    )
    3.14
)

;-----------------------------------------------------
; test the 'pid' command
(test/exec :pid1
    (fn ->
        (^bool? (pid))
    )
    true
)
(test/exec :pid2
    (fn ->
        (== (pid) ((.System.Diagnostics.Process/GetCurrentProcess) | .id))
    )
    true
)

;-----------------------------------------------------
; test the 'tid' command
(test/exec :tid1
    (fn ->
        (^bool? (tid))
    )
    true
)

;-----------------------------------------------------
; test the 'path' command
(test/exec :path1
    (fn ->
        (^bool? (path))
    )
    true
)
(test/exec :path2
    (fn ->
        ; case matters on Linux BUGBUGBUG - this should be fixed
        (path | == (get-env :PATH))
    )
    true
)

;-----------------------------------------------------
; test the 'read-file' function
(test/exec :read-file1
    (fn ->
        (read-file (file/join-path braidhome "autoload.tl") | count | > 1000)
    )
    true
)
(test/exec :read-file2
    (fn ->
        (read-file  (file/join-path braidhome "autoload.tl")  #"defn.*re/match-all" | count)
    )
    1
)
; need to be fixed to match deployment structure
;(test/exec :read-file3
;    (fn ->
;        ; read the file 'braid.cs' looking for class 's_Expr' then extracting it's name
;        (read-file (file/join-path braidhome "braid.cs")  #"public.* class +(s_Expr)" (fn _ m -> (m 1)))
;    )
;    ["s_Expr"]
;)
(test/exec :read-file4
    (fn ->
        ; test input of PSObjects
        (get-childitem -path: braidhome -filter: "*.tl" | take 20 | read-file | count | > 1000)
    )
    true
)
(test/exec :read-file5
    (fn ->
        (read-file
            (file/join-path braidhome "autoload.tl")
             #""
            (fn line matches lineno fname ->
                (if (== lineno 3000) [lineno (file/basename fname)])))
    )
    [[3000 "autoload"]]
)

;-----------------------------------------------------
; test the 'get-env' command
(test/exec :get-env1
    (fn ->
        ; case matters on Linux BUGBUGBUG - this should be fixed
        (get-env :PATH | == (path))
    )
    true
)

;-----------------------------------------------------
; test the 'set-env' command
(test/exec :set-env1
    (fn ->
        (set-env :zorkzork 3.14)
        (get-env :zorkzork | == 3.14)
    )
    true
)
(test/exec :set-env2
    (fn ->
        (set-env :zorkzork 3.14)
        (set-env :zorkzork null) ; delete it by setting it to null
        (not (get-env :zorkzork))
    )
    true
)

;-----------------------------------------------------
; test pwd
(test/exec :pwd1
    (fn ->
        (^bool? (pwd))
    )
    true
)
(test/exec :pwd2
    (fn ->
        (== (pwd) .environment/CurrentDirectory)
    )
    true
)


;-----------------------------------------------------
; test 'taskid' function
(test/exec :taskid1
    (fn ->
        ; taskid is null by default
        (== (taskid) null)
    )
    true
)
(test/exec :taskid2
    (fn ->
        ; task id is an integer in a task
        (is? (await (async (fn -> (taskid)))) ^int)
    )
    true
)

;-----------------------------------------------------
; test the 'compare' function
(test/exec :compare1
    (fn ->
        (compare 1 2)
    )
    -1
)
(test/exec :compare2
    (fn ->
        (compare 3 2)
    )
    1
)
(test/exec :compare3
    (fn ->
        (compare 3 3)
    )
    0
)
(test/exec :compare4
    (fn ->
        (compare "abc" "xy")
    )
    -1
)
(test/exec :compare5
    (fn ->
        (compare "xy" "abcd")
    )
    1
)
(test/exec :compare6
    (fn ->
        (compare "hello" "hello")
    )
    0
)
(test/exec :compare7
    (fn ->
        (compare "123" 9)
    )
    -1
)
(test/exec :compare8
    (fn ->
        (compare 123 "000009")
    )
    1
)
; test currying...
(test/exec :compare9
    (fn ->
        (range 10 | map (compare 5))
    )
    [-1 -1 -1 -1 0 1 1 1 1 1]
)
(test/exec :compare10
    (fn ->
        (range 10 | filter (compare 5))
    )
    [1 2 3 4 6 7 8 9 10]
)

;-----------------------------------------------------
; test parse-text function
(test/exec :parse-text1
    (fn ->
        (let ex (parse-text "+ 2 3"))
        (== (car ex) '+)
    )
    true
)
(test/exec :parse-text2
    (fn ->
        (let ex (parse-text "+ 2 3"))
        (== (cadr ex) 2)
    )
    true
)
(test/exec :parse-text3
    (fn ->
        (let ex (parse-text "+ 2 3"))
        (== (caddr ex) 3)
    )
    true
)
(test/exec :parse-text4
    (fn ->
        (let ex (parse-text "+ 2 3"))
        (eval ex)
    )
    5
)
(test/exec :parse-text5
    (fn ->
        (let ex (parse-text "do (+ 2 3) (* 4 3)"))
        (eval ex)
    )
    12
)
(test/exec :parse-text6
    (fn ->
        ; compose the code
        (let exprstr
            (str
                "forall"
                " i (range "
                5
                ") i"
            )
        )
        (eval (parse-text exprstr))
    )
    [1 2 3 4 5]
)
(test/exec :parse-text7
    (fn ->
        ; Fuzz test the parser. Generate random strings
        ; then feed them to the parser. If any exception
        ; is thrown that isn't a Braid user exception, that
        ; exception will be rethrown failing the test.
        (repeat 100
            (try
                (parse-text (random 1000 | map ^char | join ""))
                -catch: (fn e ->
                    (if (not (is? e ^BraidLang.BraidUserException))
                        (throw e)
                    )
                )
            )
        )
    )
    null
)

;-----------------------------------------------------
; test quasiquote templating and expansion.
(test/exec :quasi-quote1
    (fn ->
        (let x '(range 5))
        `(foreach i ~x (print i))
    )
    '(foreach i (range 5) (print i))
)
(test/exec :quasi-quote2
    (fn ->
        (let x '(range 5))
        (let res `(foreach i ~@x (print i))) ; splatting
        (tostring res)
    )
    "(foreach i range 5 (print i))"
)

(; BUGBUGBUG - this was broken when defn became a macro. Quasiquotes should suppress macro expansions.
(test/exec :quasi-quote3
    (fn ->
        (let name 'bob)
        (let args ['x 'y])
        (eval `(defn ~name ~args "I'm bob"))
        (bob 2 3)
    )
    "I'm bob"
)
;)
(test/exec :quasi-quote4
    (fn ->
        (let x 10)
        (let y 20)
        `(+ ~x ~y)
    )
    '(+ 10 20)
)
(test/exec :quasi-quote5
    (fn ->
        (let c [1 2 3])
        `(+ ~c)
   )
   (list + [1 2 3])
)
(test/exec :quasi-quote6
    (fn ->
        (let c [1 2 3])
        `(+ ~@c)
    )
    (list + 1 2 3)
)
(test/exec :quasi-quote7
    (fn ->
        ; testing expansion nnon-s_Expr enumerables.
        (let a 1)
        (let b 5)
        (let c [2 3 4])
        `(+ ~a ~@c ~b)
    )
    (list + 1 2 3 4 5)
)
(test/exec :quasi-quote8
    (fn ->
        ; testing expansion nnon-s_Expr enumerables.
        (let a 1)
        (let b '(5 6 7))
        (let d [8 9 10])
        (let c [2 3 4])
        `(+ ~a ~@c ~@b ~@d)
    )
    (list + 1 2 3 4 5 6 7 8 9 10)
)
(test/exec :quasi-quote9
    (fn ->
        ; testing expansion non-s_Expr enumerables.
        (let a 1)
        (let b '(5 6 7))
        (let d [8 9 10])
        (let c [2 3 4])
        `(+ ~a ~@c ~b ~d 11 12)
    )
    (list + 1 2 3 4 (list 5 6 7) [8 9 10] 11 12)
)
(test/exec :quasi-quote10
    (fn ->
        ; testing expansion in vector literals
        (with [a 1 b 2 c 3] `[~a ~b ~c] | .valuelist)
    )
    '(1 2 3)
)
(test/exec :quasi-quote11
    (fn ->
        ; testing expansion in vector literals
        (with [a 3 b 2 c 1] `[~a ~b ~c] | .valuelist)
    )
    '(3 2 1)
)
(test/exec :quasi-quote12
    (fn ->
         (with [a 1 b 2 c 3] `[~a [~b ~c]] | eval)
    )
    [1 [2 3]]
)
(test/exec :quasi-quote13
    (fn ->
         (with [a 1 b 2 c 3] `(list ~a [~b ~c]) | eval)
    )
    (list 1 [2 3])
)
(test/exec :quasi-quote14
    (fn ->
         (with [a 1 b 2 c 3] `[~a '(~b ~c)] | eval)
    )
    [1 '(2 3)]
)
(test/exec :quasi-quote15
    (fn ->
         (with [a 1 b 2 c 3] `[[~a ~b] ~c] | eval)
    )
    [[1 2] 3]
)
(test/exec :quasi-quote16
    (fn ->
        ; eval'ing ([2 3] 1) is an index operation
         (with [a 2 b 3 c 1] `([~a ~b] ~c) | eval)
    )
    3
)
(test/exec :quasi-quote17
    (fn ->
         (with [a 1 b 2 c 3] `['(~a ~b) ~c] | eval)
    )
    ['(1 2) 3]
)
(test/exec :quasi-quote18
    (fn ->
        ; test expansion in hashes
        (with [a 10 b 20 c 30] `{:a ~a :b ~b :c ~c} | eval)
    )
    {
        :a : 10,
        :b : 20,
        :c : 30
    }
)
(test/exec :quasi-quote19
    (fn ->
        ; test expansion in hashes
        (with [a 10 b 20 c 30] `{:a ~a :b ~b :c ~c} | eval)
    )
    {
        :a : 10,
        :b : 20,
        :c : 30
    }
)
(test/exec :quasi-quote20
    (fn ->
        ; test expansion in hashes
        (matchp @(with [sym "foo" a 1 b 2] `{~sym ~a :b ~b} | .ValueList)
        | "foo" 1 _ 2  -> "success"
        | &args -> (warn "Match failed") (foreach e (car args) (warn "    " e "  type:" (type-of e)))
        )
    )
    "success"
)
(test/exec :quasi-quote21
    (fn ->
        ; test expansion in hashes
        (matchp @(with [sym "foo" a 1 b 2] `{~sym ~a :b [ ~b ]} | .ValueList)
        | "foo" 1 ^BraidLang.KeywordLiteral ^BraidLang.VectorLiteral :where (.valuelist %3 | == '(2)) ->
            "success"
        | &xs ->
            ; debugging stuff - could be removed.
            (warn "Match failed")
            (foreach e xs
                (warn "    " e "  type:" (type-of e))
            )
        )
    )
    "success"
)
(test/exec :quasi-quote22
    (fn ->
        ; test expansion in hashes
        (with [sym "foo" a 1 b 2] `{~sym ~a "b" [ ~b ]} | eval)
    )
    {"foo" 1 "b" [ 2 ]}
)
(test/exec :quasi-quote23
    (fn ->
        ; test expansion in nested hashes
        (with [sym "foo" a 1 b 2 c 3] `{~sym ~a :b {:c  ~b}} | eval)
    )
    {"foo" 1 :b {:c 2}}
)
(test/exec :quasi-quote24
    (fn ->
        ; test expansion in nested hashes and vectors.
        (with [sym "foo" a 1 b 2 c 3] `{~sym ~a "b" {:c  [ ~b ]}} | eval)
    )
    {"foo" 1 "b" {:c [ 2 ]}}
)
(test/exec :quasi-quote25
    (fn ->
        ; test expansion in nested hashes and vectors.
        (with [sym "foo" a 1 b 2 c 3] `{~sym ~a "b" {~sym  [ ~b ]}} | eval)
    )
    {"foo" 1 "b" {"foo" [ 2 ]}}
)
(test/exec :quasi-quote26
    (fn ->
        ; test expansion in nested hashes and vectors.
        (with [sym "foo" a 1 b 2 c 3] `[~a {~sym  [ ~b ]}] | eval)
    )
    [1 {"foo" [ 2 ]}]
)
(test/exec :quasi-quote27
    (fn ->
        ; test expansion in nested hashes and vectors.
        (with [sym "foo" a 1 b 2 c 3] `[{"a" ~a} {~sym  [ ~b ]} [~c]] | eval)
    )
    [{"a" 1} {"foo" [ 2 ]} [3]]
)
(test/exec :quasi-quote28
    (fn ->
        ; test expansion in nested hashes and vectors.
        (with [sym "foo" a 1 b 2 c 3] `[{"a" ~a} {~sym  [ ~b ]} [[[~c]]]] | eval)
    )
    [{"a" 1} {"foo" [ 2 ]} [[[3]]]]
)
(test/exec :quasi-quote29
    (fn ->
        ; test expansion in nested hashes and vectors.
        (with [sym "foo" a 1 b 2 c 3] `[{"zork" [{"a" ~a} {~sym  [ ~b ]}]} [[[~c]]]] | eval)
    )
    [{"zork" [{"a" 1} {"foo" [ 2 ]}]} [[[3]]]]
)
(test/exec :quasi-quote30
    (fn ->
        ; BUGBUGBUG - this `#{ ~a ~b } should work but quote handling only allows for one quote
        ; test expansion with hashsets.
        (with [a 1 b 2] `[#{ ~a ~b }] | eval)
    )
    [  #{ 1 2 } ]
)

;-----------------------------------------------------
; test 'return' function
(test/exec :return1
    (fn ->
        (defn foo [] (return) "bad")
        (foo)
    )
    nil
)
(test/exec :return2
    (fn ->
        (defn foo [] (return 1) "bad")
        (foo)
    )
    1
)
(test/exec :return3
    (fn ->
        (defn foo [] (return 1 2 3) "bad")
        (foo)
    )
    [1 2 3]
)
(test/exec :return4
    (fn ->
        (defn foo [] (return 1 [4 5] 3) "bad")
        (foo)
    )
    [1 [4 5] 3]
)
(test/exec :return5
    (fn ->
        (defn foo
            [x y]

            1
            2
            (return (+ 3 6) {:a 1 :b 2} [x y])
            "bad"
        )
        (foo 10 20)
    )
    [9 {:a 1 :b 2} [10 20]]
)
(test/exec :return6
    (fn ->
        ; return a splatted literal
        (defn foo [] (return @[1 [4 5] 3]) "bad")
        (foo)
    )
    [1 [4 5] 3]
)
(test/exec :return7
    (fn ->
        (defn foo []
            ; return splatted variable
            (let val [1 2 3])
            (return @val)
            "bad"
        )
        (foo)
    )
    [1 2 3]
)
(test/exec :return8
    (fn ->
        (defn foo []
            ; return splatted variable
            (return @(range 5))
            "bad"
        )
        (foo)
    )
    [1 2 3 4 5]
)
(test/exec :return9
    (fn ->
        (defn foo []
            ; return splatted variable
            (return @(range 5 | map (* 2)))
            "bad"
        )
        (foo)
    )
    [2 4 6 8 10]
)
(test/exec :return10
    (fn ->
        (defn foo ^int [(^int? x)] (return x))
        (foo "123" | type-of)
    )
    ^int
)
(test/exec :return10a
    (fn ->
        (defn foo ^int [(^int x)] (return x))
        (try (foo "123" | type-of) | is? ^Exception)
    )
    true
)
(test/exec :return10b
    (fn ->
        ; Try coercive return type
        (defn foo ^int? [x] (return x))
        (foo "123" | type-of)
    )
    ^int
)
(test/exec :return11
    (fn ->
        ; test return in a loop
        (defn foo []
            (for (let i 0) (< i 10) (incr i)
                (if (== i 5)
                    (return "returned ${i}")
                )
            )
            (return "done")
        )
        (foo)
    )
    "returned 5"
)
(test/exec :return12
    (fn ->
        (defn foo []
            (foreach i (range 10)
                (if (== i 6)
                    (return "returned ${i}")
                )
            )
            "at end"
        )
        (foo)
    )
    "returned 6"
)
(test/exec :return13
    (fn ->
        (defn foo []
            (forall i (range 10)
                (if (== i 6)
                    (return "returned ${i}")
                )
            )
            "at end"
        )
        (foo)
    )
    "returned 6"
)
(test/exec :return14
    (fn ->
        (defn foo []
            (forall j (range 10)
                (forall i (range 10)
                    (if (== i 7)
                        (return "returned ${i}")
                    )
                )
            )
            "at end"
        )
        (foo)
    )
    "returned 7"
)
(test/exec :return15
    (fn ->
        (defn foo []
            (let n 20)
            (while (pincr n)
                (forall i (range 10)
                    (if (== i 7)
                        (return "returned ${i}")
                    )
                )
            )
            "at end"
        )
        (foo)
    )
    "returned 7"
)

;-----------------------------------------------------
; test 'cond' function
(test/exec :cond1
    (fn ->
        (let v 2)
        (cond
            (== v 1) "one"
            (== v 2) "two"
            (== v 3) "three"
            true "DEFAULT"
        )
    )
    "two"
)
(test/exec :cond2
    (fn ->
        (let v "hi")
        (cond
            (== v 1)  "one"
            (#"hi" v) "hello"
            true "DEFAULT"
        )
    )
    "hello"
)
(test/exec :cond3
    (fn ->
        (let v "zork")
        (cond
            (== v 1)  "one"
            (#"hi" v) "hello"
            true "DEFAULT"
        )
    )
    "DEFAULT"
)

;-----------------------------------------------------
; test the 'case' macro
(test/exec :case1
    (fn ->
        (case 1
            1 "one"
            2 "two"
            true "DEFAULT"
        )
    )
    "one"
)
(test/exec :case2
    (fn ->
        (case 2
            1 "one"
            2 "two"
            true "DEFAULT"
        )
    )
    "two"
)
(test/exec :case3
    (fn ->
        (case "zork"
            1 "one"
            2 "two"
            true "DEFAULT"
        )
    )
    "DEFAULT"
)
(test/exec :case4
    (fn ->
        (case ^int
            ^string "one"
            ^int "two"
            true "DEFAULT"
        )
    )
    "two"
)
(test/exec :case5
    (fn ->
        (case ^int
            ^string "one"
            ^int (+ 2 3)
            true "DEFAULT"
        )
    )
    5
)
(test/exec :case6
    (fn ->
        (case ^int
            "abc" "a string"
            ^int  (+ 2 3)
            7.5   "a double"
            true  "DEFAULT"
        )
    )
    5
)
(test/exec :case7
    (fn ->
        (case "abc"
            "abc" "a string"
            ^int  (+ 2 3)
            7.5   "a double"
            true  "DEFAULT"
        )
    )
    "a string"
)
(test/exec :case8
    (fn ->
        (case 7.5
            "abc" "a string"
            ^int  (+ 2 3)
            7.5   "a double"
            true  "DEFAULT"
        )
    )
    "a double"
)
(test/exec :case9
    (fn ->
        (case null
            "abc" "a string"
            ^int  (+ 2 3)
            7.5   "a double"
            true  "DEFAULT"
        )
    )
    "DEFAULT"
)

;-----------------------------------------------------
; test 'get' function
(test/exec :get1
    (fn ->
        (let zork 123)
        (let name "zork")
        (get name)
    )
    123
)
(test/exec :get2
    (fn ->
        (let zork 123)
        (let name "zork")
        (name | get)
    )
    123
)

;-----------------------------------------------------
; test 'gcd' function
(test/exec :gcd1
    #(gcd 32 68)
    4
)
(test/exec :gcd2
    #(gcd 9980 6820)
    20
)
(test/exec :gcd3
    #(gcd (* 417 311)  (* 976 311))
    311
)

;-----------------------------------------------------
; test 'splice' function
;   - if arg 0 is a list it appends to the end of that list
;   - if arg 0 is not a list; it wraps the value in a list then appends arg1
;   - it always returns a list
(test/exec :splice1
    (fn ->
        (let foo '(1 2 3))
        (splice foo '(4 5 6))
        foo
    )
    '(1 2 3 4 5 6)
)
(test/exec :splice2
    (fn ->
        (let foo [1 2 3])
        (splice foo [4 5 6])
        foo
    )
    ; a new list is created in this case
    [1 2 3]
)
(test/exec :splice2a
    (fn ->
        (let foo [1 2 3])
        (splice foo [4 5 6])
    )
    ; a new list is created in this case
    (list 1 2 3 4 5 6)
)
(test/exec :splice3
    (fn ->
        (let foo (list 1 2 3))
        (splice foo [4 5 6])
        foo
    )
    (list 1 2 3 4 5 6)
)
(test/exec :splice4
    (fn ->
        (let foo [1 2 3])
        (splice foo '(4 5 6))
    )
    ; a new list is created in this case
    (list 1 2 3 4 5 6)
)
(test/exec :splice4a
    (fn ->
        (let foo [1 2 3])
        (splice foo '(4 5 6))
        foo
    )
    ; a new list is created in this case
    [1 2 3]
)
(test/exec :splice5
    (fn ->
        (let foo '(1 2 3))
        (foo | splice '(4 5 6))
        foo
    )
    '(1 2 3 4 5 6)
)
(test/exec :splice6
    (fn ->
        (let foo [1 2 3])
        [ (foo | splice [4 5 6]) foo]
    )
    ; a new list is created in this case
    [ (list 1 2 3 4 5 6) [1 2 3] ]
)
(test/exec :splice7
    (fn ->
        (let foo (list 1 2 3))
        (foo | splice [4 5 6])
        foo
    )
    (list 1 2 3 4 5 6)
)
(test/exec :splice8
    (fn ->
        ; a new list is created in this case because foo is a vector
        (let foo [1 2 3])
        (let newlist (foo | splice '(4 5 6)))
        [foo newlist]
    )
    [[1 2 3] (list 1 2 3 4 5 6)]
)
(test/exec :splice9
    (fn ->
        (list 1 2 3 4 | splice (list 5 6))
    )
    (list 1 2 3 4 5 6)
)
(test/exec :splice10
    (fn ->
        (1 | splice '(2 3 4))
    )
    '(1 2 3 4)
)
(test/exec :splice11
    (fn ->
        ({:a 1 :b 2} | splice 10)
    )
    (list {:a 1 :b 2} 10)
)
(test/exec :splice12
    (fn ->
        (splice null '(1 2 3))
    )
    '(1 2 3)
)
(test/exec :splice13
    (fn ->
        (splice '(1 2 3) null)
    )
    '(1 2 3)
)
(test/exec :splice14
    (fn ->
        (let foo null)
        (splice foo null)
        null
    )
    null
)
(test/exec :splice15
    (fn ->
        (splice null null null null)
    )
    null
)
(test/exec :splice16
    (fn ->
        (let foo '(1 2 3))
        (splice foo '(4 5) '(6 7 8) 9 10)
        foo
    )
    '(1 2 3 4 5 6 7 8 9 10)
)
(test/exec :splice17
    (fn ->
        (let foo '(1 2 3))
        (splice null null null foo '(4 5) '(6 7 8) 9 10)
        foo
    )
    '(1 2 3 4 5 6 7 8 9 10)
)
(test/exec :splice18
    (fn ->
        (let foo '(1 2 3))
        (splice null null null foo null '(4 5) null '(6 7 8) 9 10 null)
        foo
    )
    '(1 2 3 4 5 6 7 8 9 10)
)
(test/exec :splice19
    (fn ->
        (let foo '(1 2 3))
        (splice foo 4 {:num 5}  6 [7 8] 9 10)
        foo
    )
    (append 1 2 3 4 {:num 5} 6 [7 8] 9 10)
)

;-----------------------------------------------------
; test a mutually recursive function
;
(; BUGBUGBUG variables are bound now in the new scope, after evaluation so this doesn't work
(test/exec :evenodd1
    (fn ->
        (let
            [
                sub1      (fn n -> (- n 1))
                is-even?  (fn n -> (zero? n | or (sub1 n | is-odd?)))
                is-odd?   (fn n -> (and (not (zero? n)) (is-even? (sub1 n))))
            ]

            (is-odd? 107)
        )
    )
    true
)
(test/exec :evenodd2
    (fn ->
        (let
            [
                sub1 (fn n -> (- n 1))
                is-even?  (fn n -> (zero? n | or (sub1 n | is-odd?)))
                is-odd?  (fn n -> (and (not (zero? n)) (is-even? (sub1 n))))

            ]

            (is-even? 80)
        )
    )
    true
)
; END BUGBUGBUG
;)

;-----------------------------------------------------
; Test the 'contains-key' function
(test/exec :contains-key1
    (fn ->
        (let data {
                :foo [1 2 3]
                :bar [1 2 3 {:a 1 :b 2 :c 3} 4 5 6]
                :baz {:a 12 :b 2}
                :buz {:a 10 :b 20 :c 30}
            }
        )
        (contains-key data :b 2)
    )
    [
        {
            :a : 1,
            :b : 2,
            :c : 3
        },
        {
            :a : 12,
            :b : 2
        }
    ]
)
(test/exec :contains-key1a
    (fn ->
        (let data {
                :foo [1 2 3]
                :bar [1 2 3 {:a 1 :b 2 :c 3} 4 5 6]
                :baz {:a 12 :b 2}
                :buz {:a 10 :b 20 :c 30}
            }
        )
        (contains-key data :b (== 2))
    )
    [
        {
            :a : 1,
            :b : 2,
            :c : 3
        },
        {
            :a : 12,
            :b : 2
        }
    ]
)
(test/exec :contains-key1b
    (fn ->
        (let data {
                :foo [1 2 3]
                :bar [1 2 3 {:a 1 :b 2 :c 3} 4 5 6]
                :baz {:a 12 :b 2}
                :buz {:a 10 :b 20 :c 30}
            }
        )
        ; regex as a function
        (contains-key data :b  #"2")
    )
    [
        {
            :a : 1,
            :b : 2,
            :c : 3
        },
        {
            :a : 12,
            :b : 2
        },
        {
            :a 10
            :b 20
            :c 30
        }
    ]
)
(test/exec :contains-key1c
    (fn ->
        (let data {
                :foo [1 2 3]
                :bar [1 2 3 {:a 1 :b 2 :c 3} 4 5 6]
                :baz {:a 12 :b 2}
                :buz {:a 10 :b 20 :c 30}
            }
        )
        (contains-key data :b (>= 2))
    )
    [
        {
            :a : 1,
            :b : 2,
            :c : 3
        },
        {
            :a : 12,
            :b : 2
        },
        {
            :a 10
            :b 20
            :c 30
        }
    ]
)
(test/exec :contains-key2
    (fn ->
        (let data {
                :foo [1 2 3]
                :bar [1 2 3 {:a 1 :b 2 :c 3} 4 5 6]
                :baz {:a 12 :b 2}
                :buz {:a 10 :b 20 :c 30}
            }
        )
        ; find the dictionary and extract the :c key value
        (contains-key data :b 20 | car | :c)
    )
    30
)
(test/exec :contains-key2a
    (fn ->
        (let data {
                :foo [1 2 3]
                :bar [1 2 3 {:a 1 :b 2 :c 3} 4 5 6]
                :baz {:a 12 :b 2}
                :buz {:a 10 :b 20 :c 30}
            }
        )
        ; find the dictionary and extract the :c key value
        (contains-key data :b (fn v -> (contains? [10 20 20] v)) | car | :c)
    )
    30
)
(test/exec :contains-key3
    (fn ->
        (let data {
                :foo [1 2 3]
                :bar [1 2 3 {:a 1 :b 2 :c 3} 4 5 6]
                :baz {:a 12 :b 2}
                :buz {:a 10 :b 20 :c {:q 5 :r 10 :s 15}}
            }
        )
        ; compose 2 calls to the function
        (contains-key data :b  #"20" | contains-key :r 10)
    )
    [{:q 5 :r 10 :s 15}]
)
(test/exec :contains-key4
    (fn ->
        (let data {
                :foo [1 2 3]
                :bar [1 2 3 {:a 1 :b 2 :c 3} 4 5 6]
                :baz {:a 12 :b 2}
                :buz {:a 10 :b 20 :c 30}
            }
        )
        ; get keys with no value to test for
        (contains-key data :b)
    )
    [
        {
            :a : 1,
            :b : 2,
            :c : 3
        },
        {
            :a : 12,
            :b : 2
        },
        {
            :a : 10,
            :b : 20,
            :c : 30
        }
    ]
)

;-----------------------------------------------------
; Test curried functions in pattern matching
(test/exec :curried-functions
    (fn ->
        ; a function that qualifies numbers between 1 and 10
        (defn sml
            | (< 3) -> "small"
            | (< 6) -> "medium"
            | -> "large"
        )
        (range 10 | map sml)
    )
    ["small" "small" "medium" "medium" "medium" "large" "large" "large" "large" "large"]
)

;-----------------------------------------------------
;
; Test the iterator function which produces lazy infinite
; sequences.
;
(test/exec :iterator1
    (fn ->
        ; verify that an iterator object is returned not a reified sequence.
        (type-of (iterator ++ 1))
    )
    ^BraidLang.BraidEnumerable
)
(test/exec :iterator2
    (fn ->
        (iterator ++ 1 | take 10)
    )
    [1 2 3 4 5 6 7 8 9 10]
)
(test/exec :iterator3
    (fn ->
        (iterator (* 3) 1 | take 5)
    )
    [1 3 9 27 81]
)
(test/exec :iterator4
    (fn ->
        (iterator (* 5) 10 | take 5)
    )
    [10 50 250 1250 6250]
)
(test/exec :iterator5
    (fn ->
        (iterator (fn n -> (+ n 0.5)) 0 | take 5)
    )
    [0 0.5 1 1.5 2]
)
(test/exec :iterator6
    (fn ->
        ; test the iterator with lazy map
        (iterator (fn n -> (+ n 0.5)) 0 | lazy-map (+ 10) | take 5)
    )
    [10 10.5 11 11.5 12]
)
(test/exec :iterator7
    (fn ->
        ; create a infinite sequence (returns an enumerable)
        (def en (iterator ++ 1 | lazy-map (* 10)))
        ; get an instance of that sequence (i.e. get an enumerator)
        (def een (.getenumerator en))
        ; take some values from the sequence; should be monotonic
        [ @(een | take 1) @(een | take 2) @(een | take 1) @(een | take 3) ]
    )
    [10 20 30 40 50 60 70]
)
(test/exec :iterator8
    (fn ->
        ; generate the 10th value in the fibinocci sequence using vectors
        (iterator (fn x:y: -> [y (+ x y)]) [1 1] | take 10 | last | !! 1)
    )
    89
)
(test/exec :iterator8a
    (fn ->
        ; generate the 10th value in the fibinocci sequence using lists
        (iterator (fn x:y: -> (list y (+ x y))) '(1 1) | take 10 | last | !! 1)
    )
    89
)
(test/exec :iterator9
    (fn ->
        ; test bounded iterator
        (iterator (+ 2) 0 10)
    )
    (range 0 10 2)
)
(test/exec :iterator10
    (fn ->
        ; count the numer of "3"s in 5000th element
        ; of the Fibonacci sequence.
        (iterator (fn x:y: -> [y, (+ x y)]) [1i 1i]
        | take 5000
        | last
        | last
        | chars
        | filter \3
        | count
        )
   )
   96
)
; iterator is aliased to "unfold" so test that also...
(test/exec :unfold1
    (fn ->
        ; count the numer of "2"s in the 10000th element
        ; of the Fibonacci sequence.
        (unfold (fn x:y: -> [y, (+ x y)]) [1i 1i]
        | take 1000
        | last
        | last
        | chars
        | filter \1
        | count
        )
   )
   28
)

;-------------------------------------------------------------
; Test the 'list-add' function
(test/exec :list-add1
    (fn ->
        (list-add '(1 2 3 4) 5 | type-of)
    )
    ^List
)
(test/exec :list-add2
    (fn ->
        (list-add '(1 2 3 4) 5)
    )
    '(1 2 3 4 5)
)
(test/exec :list-add3
    (fn ->
        (list-add 5 '(1 2 3 4))
    )
    '(5 (1 2 3 4))
)
(test/exec :list-add4
    (fn ->
        (list-add [1 2 3] 4)
    )
    (list [1 2 3] 4)
)
(test/exec :list-add5
    (fn ->
        (list-add 1 2)
    )
    '(1 2)
)
(test/exec :list-add6
    (fn ->
        (list-add null 2)
    )
    '(2)
)
(test/exec :list-add7
    (fn ->
        ; creates a list containing '1' then adds null to the end.
        (list-add 1 null)
    )
    (list 1 null)
)
(test/exec :list-add8
    (fn ->
        (list-add null null)
    )
    null
)

;-------------------------------------------------------------
;
; Test the = macro which transforms infix expressions to braid
; prefix expressions

(test/exec :=1
    (fn ->
        (= 2+2)
    )
    4
)
(test/exec :=2
    (fn ->
        (= 2 + 3 * 4)
    )
    14
)
(test/exec :=3
    (fn ->
        (= 10+3*2-12)
    )
    4
)
(test/exec :=4
    (fn ->
        (= 10+3*(2-12))
    )
    -20
)
(test/exec :=5
    (fn ->
        (= 1_0 + 3 * ( 2 - 12 ))
    )
    -20
)
(test/exec :=6
    (fn ->
        (= 10+3*(2-12) + 10)
    )
    -10
)
(test/exec :=7
    (fn ->
        ; test with variables
        (with [a 3 b 10] (= 10+a*(2-12) + b))
    )
    -10
)

;-------------------------------------------------------------
;
; Test the 'let=' macro which transforms infix assignment expressions to braid
; prefix expressions

(test/exec :let=1
    (fn ->
        (let= x 2+2)
        x
    )
    4
)
(test/exec :let=2
    (fn ->
        (let= a 2 + 3 * 4)
        a
    )
    14
)
(test/exec :let=3
    (fn ->
        (let= b 10+3*2-12)
        b
    )
    4
)
(test/exec :let=4
    (fn ->
        (let= c 10+3*(2-12))
        c
    )
    -20
)
(test/exec :let=5
    (fn ->
        (= 1_0 + 3 * ( 2 - 12 ))
    )
    -20
)
(test/exec :let=6
    (fn ->
        (let= d 10+3*(2-12) + 10)
        d
    )
    -10
)
(test/exec :let=7
    (fn ->
        ; test with variables
        (with [a 3 b 10]
            (let= complex 10+a*(2-12) + b)
            complex
        )
    )
    -10
)

;---------------------------------------------------------------
; Test the 'set' function.
(test/exec :set1
    (fn ->
        (let v 'xyz)
        (set v 3.14)
        xyz
    )
    3.14
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Test the 'assoc-in' function which takes a 'path' composed of
; individual keys and a value to create/update.
;
(test/exec :assoc-in1
    (fn ->
        ; empty data an path
        (assoc-in {}  [] 5)
    )
    {}
)
(test/exec :assoc-in2
    (fn ->
        ; non-empty data but path is empty
        (assoc-in {:a 1 :b 2 :c 3}  [] 5)
    )
    {:a 1 :b 2 :c 3}
)
(test/exec :assoc-in3
    (fn ->
        ; empty data, non-empty path and value
        (assoc-in {}  [:x] 5)
    )
    {:x 5}
)
(test/exec :assoc-in4
    (fn ->
        ; basic function test - update a member in the table
        (assoc-in {:a 1 :b 2} [:c] 3)
    )
    {:a 1 :b 2 :c 3}
)
(test/exec :assoc-in5
    (fn ->
        ; testing creation of non-existant element
        (assoc-in {:a 1 :b 2} [:c :d :e] 3)
    )
    {
        :a : 1,
        :b : 2,
        :c : {
            :d : {
                :e : 3
            }
        }
    }
)
(test/exec :assoc-in6
    (fn ->
        ; update and create new nodes
        (assoc-in {:a 1 :b 2 :c 3 } [:c :d :e] 30)
    )
    {
        :a : 1,
        :b : 2,
        :c : {
            :d : {
                :e : 30
            }
        }
    }
)
(test/exec :assoc-in7
    (fn ->
        (assoc-in {:a 1 :b 2} [:c :d :e] {:x 10 :y 20})
    )
    {
        :a : 1,
        :b : 2,
        :c : {
            :d : {
                :e : {
                    :x : 10
                    :y : 20
                }
            }
        }
    }
)
(test/exec :assoc-in8
    (fn ->
        (assoc-in {:a 1 :b 2 :c {:x 1 :y 2}} [:c :d :e] 30)
    )
    {
        :a : 1,
        :b : 2,
        :c : {
            :x : 1,
            :y : 2,
            :d : {
                :e : 30
            }
        }
    }
)
(test/exec :assoc-in9
    (fn ->
        (assoc-in {:a 1 :b {} :c 3} [:b] {:k 6 :v 7})
    )
    {
        :a : 1,
        :b : {
            :k : 6,
            :v : 7
        },
        :c : 3
    }
)
(test/exec :assoc-in10
    (fn ->
        ; test piplines of assoc-in
        ( {:a 1 :b 2 :c {:x 1 :y 2}}
            | assoc-in  [:c :d :e] 30
            | assoc-in [:b :t] 123
            | assoc-in [:c :x :z] 456
        )
    )
    {
        :a : 1,
        :b : {
            :t : 123
        }
        :c : {
            :x : {
                :z : 456
            }
            :y : 2,
            :d : {
                :e : 30
            }
        }
    }
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Test closure conversion
;
(test/exec :closure1
    (fn ->
        ; function to generate counters
        (defn gen [v] (lambda [] (incr v)))
        ; define a couple of counters
        (let cntr1 (gen 10))
        (let cntr2 (gen 5))

        (and
            (== (cntr1) 11)
            (== (cntr2) 6)
            (== (cntr1) 12)
            (== (cntr2) 7)
        )
    )
    true
)
(test/exec :closure2
    (fn ->
        ; function to generate counters
        (defn gen [v]  #(incr v))
        ; define a couple of counters
        (let cntr1 (gen 10))
        (let cntr2 (gen 5))

        (and
            (== (cntr1) 11)
            (== (cntr2) 6)
            (== (cntr1) 12)
            (== (cntr2) 7)
        )
    )
    true
)
(test/exec :closure3
    (fn ->
        ; function to generate counters
        (defn gen [v] (fn -> (incr v)))
        ; define a couple of counters
        (let cntr1 (gen 10))
        (let cntr2 (gen 5))

        (and
            (== (cntr1) 11)
            (== (cntr2) 6)
            (== (cntr1) 12)
            (== (cntr2) 7)
        )
    )
    true
)
(test/exec :closure4
    (fn ->
        ; function to generate counters
        (defn gen [v]
            (defn counter [] (incr v))
            counter
        )
        ; define a couple of counters
        (let cntr1 (gen 10))
        (let cntr2 (gen 5))

        (and
            (== (cntr1) 11)
            (== (cntr2) 6)
            (== (cntr1) 12)
            (== (cntr2) 7)
        )
    )
    true
)
(test/exec :closure5
    (fn ->
        ; function to generate counters that take parameters
        (defn gen [v] (fn scale -> (* scale (incr v))))
        ; define a couple of counters
        (let cntr1 (gen 10))
        (let cntr2 (gen 5))

        (and
            (== (cntr1 2) 22)
            (== (cntr2 3) 18)
            (== (cntr1 4) 48)
            (== (cntr2 5) 35)
        )
    )
    true
)
(test/exec :closure6
    (fn ->
        ; function to generate counters that take parameters
        (defn gen [v] (fn scale -> (* scale (incr v))))

        ; function to generate counters where the paramter is established at
        ; creation time
        (defn sgen [scale start]
            (let ctr (gen start))
            (fn -> (ctr scale))
        )

        ; define a couple of counters
        (let cntr1 (sgen 10 2))
        (let cntr2 (sgen 5 2))

        (and
            (== (cntr1) 30)
            (== (cntr2) 15)
            (== (cntr1) 40)
            (== (cntr2) 20)
        )
    )
    true
)
(test/exec :closure7
    (fn ->
        (defn gen [v] (fn -> (incr v)))
        (let c (gen 0))
        (repeat-all 10 (c))
    )
    (range 10)
)
(test/exec :closure8
    (fn ->
        (defn gen [v] (fn -> (incr v)))
        (defn get-counter [] (gen 10))
        (let c (get-counter))
        (range 10 | map  #(c))
    )
    (range 11 20 | to-vector)
)
(test/exec :closure9
    (fn ->
        ; a function that returns a function that returns a function.
        (defn one [x]
            (fn ->
                (let y 3.14)
                (fn -> [x y])
            )
        )
        ; need three levels of evaluation
        (((one 10)))
    )
    [10 3.14]
)
(test/exec :closure10
    (fn ->
        ; return 2 functions sharing the same parent scope
        (let c1:c2: (with [var 0]
            [  #(str "c1 " (incr var)) #(str "c2 " (incr var))]))

        ; each call will increment 'var'
        [ (c1) (c2) (c1) (c2) ]
    )
    ; In the result, the function names alternate but the number should be monotonic
    [ "c1 1" "c2 2" "c1 3" "c2 4" ]
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
(test/exec :repeat1
    (fn ->
        (let total 0)
        (repeat 100 (incr total))
        total
    )
    100
)
(test/exec :repeat2
    (fn ->
        (let total 0)
        (repeat 0 (incr total))
        total
    )
    0
)
(test/exec :repeat-all1
    (fn ->
        (let n 0)
        (repeat-all 5 (incr n))
    )
    [1 2 3 4 5]
)
(test/exec :repeat-all2
    (fn ->
        (repeat-all 0 (incr n))
    )
    null
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
(test/exec :bound?1
    (fn ->
        (bound? 'map)
    )
    true
)
(test/exec :bound?2
    (fn ->
        (bound? 'no-such-variable)
    )
    false
)
(test/exec :bound?3
    (fn ->
        (let no-such-variable true)
        (bound? 'no-such-variable)
    )
    true
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
(test/exec :sieve-impl1
    (fn ->
        ; one-line "Sieve of Eratosthenes" after Haskell, Miranda, etc.
        (defn sieve | x:xs -> (cons x (filter xs (fn n -> (% n x)) | sieve)) | null -> )
        ; the range to compute must start at three and skip the even numbers
        (range 3 30 2 | sieve)
    )
    '(3 5 7 11 13 17 19 23 29)
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
(test/exec :def-dynamic1
    (fn ->
        ; define a function to set a variable in the caller's scope
        (defn setincaller [n] (def-dynamic 'a n))

        ; call the function in a subscope.
        ((fn -> (let a 22.7) (setincaller 3.14) a))
    )
    "3.14"
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
(test/exec :sieve1
    (fn ->
        (sieve 20)
    )
    [3 5 7 11 13 17 19]
)
(test/exec :sieve2
    (fn ->
        (sieve 100)
    )
    [3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71 73 79 83 89 97]
)
(test/exec :sieve3
    (fn ->
        (sieve 500 | last)
    )
    499
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
(test/exec :asarray1
    (fn ->
        ([1 2 3] | asarray | type-of)
    )
    ^object[]
)
(test/exec :asarray2
    (fn ->
        (["a" "b" "c"] | asarray ^string | type-of)
    )
    ^string[]
)
(test/exec :asarray3
    (fn ->
        ((list "a" "b" "c") | asarray ^string | type-of)
    )
    ^string[]
)
(test/exec :asarray4
    (fn ->
        ([1.0 2.0 3.0] | asarray ^double | type-of)
    )
    ^double[]
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
(test/exec :traverse1
    ; test a tail-recursive tree traversal function
    (fn ->
        ; define the tree to traverse
        (let tree
            [1 2
                [3
                    [4 5 6
                        [7 8]
                    ]
                    [9 10]
                ]
                [11
                    [12
                        [13
                            [14]
                        ]
                        15 16
                    ]
                    17 18
               ]
               19 20
               [21 22 23 24
                   [25
                      [26
                          [27
                              [28 29 30]
                           31
                              [32 33 34 35 36]
                          ]
                       37 38 39 40
                      ]
                    41 42 43 44
                   ]
                   [45 46 47 48
                      [49
                          [50]
                      ]
                   ]
               ]
            ]
        )

        ; the traversal pattern function
        (defn traverse
            | x:xs acc :where (seq? x)   -> (recur (append x xs) acc)
            | x:xs acc :where (some? xs) -> (recur xs (+ acc x))
            | x: acc                     -> (+ x acc)
            | xs                         -> (recur xs 0)
        )

        (traverse tree)
    )
    1275
)

(test/exec :traverse2
    (fn ->
        ; define the tree to traverse
        (let tree
            [1 2
                [3
                    [4 5 6
                        [7 8]
                    ]
                    [9 10]
                ]
                [11
                    [12
                        [13
                            [14]
                        ]
                        15 16
                    ]
                    17 18
               ]
               19 20
               [21 22 23 24
                   [25
                      [26
                          [27
                              [28 29 30]
                           31
                              [32 33 34 35 36]
                          ]
                       37 38 39 40
                      ]
                    41 42 43 44
                   ]
                   [45 46 47 48
                      [49
                          [50]
                      ]
                   ]
               ]
            ]
        )

        ; tail-recursive traverse function using cond.
        (defn traverse
            [node:nodes (acc 0)]

            (cond
                (seq? node)
                    ; flatten 1 level
                    (recur (append node nodes) acc)

                (some? nodes)
                    (recur nodes (+ acc node))

                true
                    (+ node acc)
            )
        )
        (traverse tree)
    )
    1275
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; test a couple of "quicksort" functions.
;
(test/exec :qsort10
    (fn ->
        (defn qs1
            | pivot:xs ->
                [
                    @(filter xs (<= pivot) | qs1)
                    pivot
                    @(filter xs (>  pivot) | qs1)
                ]
            | -> []
       )

       (qs1 [5 2 6 1 3 7 9 4 10 8])
    )
    [1 2 3 4 5 6 7 8 9 10]
)
(test/exec :qsort11
    (fn ->
        ; qsort using list/split
        (defn qs2
            | [] -> []
            | pivot:xs ->
                 (let small:large: (list/split xs (<= pivot)))
                 (append (qs2 small) pivot (qs2 large))
        )

        (qs2 [5 2 6 1 3 7 9 4 10 8])
    )
    [1 2 3 4 5 6 7 8 9 10]
)

;---------------------------------------------------------
; Test the 'recur-to' function
(test/exec "recur-to1"
    (fn ->
        (defn foo [i]
            (defn bar []
                (when (decr i)
                    (recur-to foo i)
                )
                "all done!"
            )
            (bar)
        )
        (foo 3)
    )
    "all done!"
)
(; BUGBUGBUG disabled because it doesn't work anymore. May just remove the recur-to feature
(test/exec :recur-to2
    (fn ->
        ; tail-recursive quick sort in continuation-passing style.
        (defn trqsort
            | []   f -> (f nil)
            | x:   f -> (f x)
            | x:xs f ->
                (let s:l: (list/split xs (<= x)))
                (recur s (fn m ->
                    (recur-to trqsort l (fn n ->
                        (f (append m x n))))))
            | xs     -> (recur xs echo)
        )
        (trqsort [5 2 6 1 3 7 9 4 10 8])
    )
    [1 2 3 4 5 6 7 8 9 10]
)
;)

;---------------------------------------------------------
; Test the 'eval' function
(test/exec :eval1
    #(eval '(+ 2 3))
    5
)

;---------------------------------------------------------
; Test the 'eval-string' function
(test/exec :eval-string1
    #(eval-string "- 7 4")
    3
)

;---------------------------------------------------------
; Test the 'xor' function
(test/exec :xor1
    (fn -> (xor false false))
    false
)
(test/exec :xor2
    (fn -> (xor true false))
    true
)
(test/exec :xor3
    (fn -> (xor false true))
    true
)
(test/exec :xor4
    (fn -> (xor true true))
    false
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Test Immediately Invoked Function Expressions
;
(test/exec :indirectinvocation1
    (fn ->
        (let y {
                  :a (fn x y -> (+ x y))
                  :b (fn x y -> (* x y))
               }
        )

        [
            ((y :a) 3 5)
            ((y :b) 3 5)
        ]
    )
    [8 15]
)
(test/exec :indirectinvocation2
    (fn ->
        ((:b {:b (fn x y -> (+ x y))}) 5 6)
    )
    11
)
(test/exec :indirectinvocation3
    (fn ->
        (let table {:b (fn x y -> (+ x y))})
        ((:b table) 7 6)
    )
    13
)
(test/exec :indirectinvocation4
    (fn ->
        ((fn x y -> (+ x y)) 10 20)
    )
    30
)
(test/exec :indirectinvocation5
    (fn ->
        (let zork (fn x y -> (+ x y)))
        [
            ((echo zork) 15 25)
            (zork 40 60)
        ]
    )
    [40 100]
)
(test/exec :indirectinvocation6
    (fn ->
        ((* 5) 6)
    )
    30
)
(test/exec :indirectinvocation7
    (fn ->
        ((partial - 10) 3)
    )
    -7
)
(test/exec :indirectinvocation8
    (fn ->
        ((partial (fn n m -> (+ n m)) 2) 3)
    )
    5
)
(test/exec :indirectinvocation9
    (fn ->
        ((fn data -> (data :b | > (data :e))) {:b 2 :e 1})
    )
    true
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Test the void function.
(test/exec :void1
    (fn ->
        ([1 2 3 4] | void | == null)
    )
    true
)
(test/exec :void2
    (fn ->
        (let x 0)
        ; void just discards the input. It does not run the enumerator.
        ([1 2 3] | lazy-map (fn n -> (def x (+ x n))) | void)
        x
    )
    0
)
; Test cast to ^void
(test/exec :void3
    (fn ->
        ([1 2 3 4] | ^void | == null)
    )
    true
)
(test/exec :void4
    (fn ->
        (let x 0)
        ; ^void just discards the input. It does not run the enumerator.
        ([1 2 3] | lazy-map (fn n -> (def x (+ x n))) | ^void)
        x
    )
    0
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Test drain
(test/exec :drain1
    (fn ->
        (let x 0)
        ; drain all the elements of the enumerator, test by side-effect.
        ([1 2 3] | lazy-map (fn n -> (def x (+ x n))) | drain)
        x
    )
    6
)
(test/exec :drain2
    (fn ->
        (let x 0)
        ; drain all the elements of the enumerator, test by side-effect.
        ([1 2 3] | lazy-filter (fn n -> (def x (+ x n))true) | drain)
        x
    )
    6
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; test Str-To-Lower, Str-To-Lower-All, Str-To-Upper and Str-To-Upper0All
(test/exec :str-to-lower1
    (fn ->
        ; verify that only the first char is uppercased by turning the chars
        ; into codepoints and comparing those values
        (str-to-lower "ABC" | chars | map ^int? | == (map [\a \B \C] ^int?))
    )
    true
)
(test/exec :str-to-lower-all1
    (fn ->
        (str-to-lower-all "ABC" | chars | filter (fn c -> (contains? (range \a \z) c)))
    )
    ["a" "b" "c"]
)
(test/exec :str-to-upper1
    (fn ->
        (str-to-upper "abc" | chars | map ^int? | == (map [\A \b \c] ^int?))
    )
    true
)
(test/exec :str-to-upper-all1
    (fn ->
        (str-to-upper-all "abc" | chars | filter (fn c -> (contains? (range \A \Z) c)))
    )
    ["A" "B" "C"]
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Test the y-combinator
(test/exec :ycombinator1
    (fn ->
        ;
        ; Define the Y combinator
        ;
        (defn Y [f]
          ((fn x -> (x x))
            (fn x ->
              (f (fn &args ->
                ((x x) @args))))))

        ; non-recursive factorial
        (let fac
          (fn f ->
            (fn n ->
              (if (zero? n) 1 (* n (f (-- n)))))))

        ; invoke with Y combinator
        ((y fac) 10)
    )
    (fact 10)
)
(test/exec :ycombinator2
    (fn ->
        ;
        ; Define the Y combinator
        ;
        (defn Y [f]
          ((fn x -> (x x))
            (fn x ->
              (f (fn &args ->
                ((x x) @args))))))

       (let fibfunc
          (fn f ->
            (fn
              | 1 -> 1
              | 2 -> 2
              | n -> (+ (f (- n 1))
                (f (- n 2))))))

        ; invoke with Y combinator
        ((y fibfunc) 10)
    )
    (fib 10)
)
(test/exec :ycombinator3
    (fn ->
        ;
        ; Define the Y combinator
        ;
        (defn Y [f]
          ((fn x -> (x x))
            (fn x ->
              (f (fn &args ->
                ((x x) @args))))))

        (def len
          (fn f ->
            (fn
              | x:xs -> (+ 1 (f xs))
              |      -> 0)))

        ; invoke with Y combinator
        ((y len) (range 200))
    )
    200
)
(test/exec :ycombinator4
    (fn ->
        ;
        ; Define the Y combinator
        ;
        (defn Y [f]
          ((fn x -> (x x))
            (fn x ->
              (f (fn &args ->
                ((x x) @args))))))

        ; reverse a string
        (let yrev
            (fn f -> 
                (fn
                    | x:xs -> (append (f xs) x)
                    |      -> [])))

        ((Y yrev) (range 20))
    )
    (reverse (range 20))
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; test to-vector
(test/exec :to-vector1
    (fn ->
        (list 1 2 3 | to-vector | type-of)
    )
    ^vector
)
(test/exec :to-vector1a
    (fn ->
        (to-vector '(1 2 3) | type-of)
    )
    ^vector
)
(test/exec :to-vector2
    (fn ->
        (list 1 2 3 | to-vector | .count)
    )
    3
)
(test/exec :to-vector3
    (fn ->
        (null | to-vector | type-of)
    )
    ^vector
)
(test/exec :to-vector4
    (fn ->
        (null | to-vector | .count)
    )
    0
)
(test/exec :to-vector5
    (fn ->
        ; turn the 'unfold' enumerable into a vector
        (unfold ++ 1 10 | to-vector | .count)
    )
    10
)
(test/exec :to-vector6
    (fn ->
        ; to-vector shreds a dictionary into pairs
       (to-vector {:a 1 :b 2 :c 3} | !! 0 | is? ^System.Collections.Generic.KeyValuePair[object,object])
    )
    true
)
(test/exec :to-vector6a
    (fn ->
       ({:a 1 :b 2 :c 3} | to-vector | !! 0 | is? ^System.Collections.Generic.KeyValuePair[object,object])
    )
    true
)
(test/exec :to-vector6b
    (fn ->
       ({:a 1 :b 2 :c 3} | to-vector | map .key)
    )
    [:a :b :c]
)
(test/exec :to-vector6c
    (fn ->
       ({:a 1 :b 2 :c 3} | to-vector | map .value)
    )
    [1 2 3]
)
(test/exec :to-vector7
    (fn ->
        ; shred the dictionary then splat the result.
        { @({:a 1 :b 2 :c 3} | to-vector) }
    )
    {:a 1 :b 2 :c 3}
)

;-----------------------------------------------------------
; Test copy-vector function
(test/exec :copy-vector1
    (fn ->
        (let a [1 2 3 4])
        (let b (copy-vector a))
        [(== a b) (=== a b)]
    )
    [true false]
)
(test/exec :copy-vector2
    (fn ->
        (let a [1 2 3 4])
        (let b (copy-vector a))
        (!! b 0 10)
        [a b]
    )
    [[1 2 3 4] [10 2 3 4]]
)

;-----------------------------------------------------------
; Test aslist function
(test/exec :aslist1
    (fn ->
        ([1 2 3] | aslist | is? ^list)
    )
    true
)
(test/exec :aslist2
    (fn ->
        (12 | aslist | is? ^list)
    )
    true
)
(test/exec :aslist3
    (fn ->
        ("hello" | aslist | is? ^list)
    )
    true
)
(test/exec :aslist4
    (fn ->
        ("hello" | aslist | .car)
    )
    "hello"
)
(test/exec :aslist5
    (fn ->
        ("hello" | aslist | .cdr)
    )
    null
)
(test/exec :aslist6
    (fn ->
        ("hello" | aslist | .count)
    )
    1
)
(test/exec :aslist7
    (fn ->
        ("hello" | aslist | >cons "dude" | .count)
    )
    2
)
(test/exec :aslist8
    (fn ->
        ("hello" | aslist | >cons "dude")
    )
    '("dude" "hello")
)

;-----------------------------------------------------------
; Test type-of function
(test/exec :type-of1
    (fn ->
        (type-of "abc")
    )
    ^string
)
(test/exec :type-of2
    (fn ->
        (type-of 123)
    )
    ^int
)
(test/exec :type-of3
    (fn ->
        (type-of 12.3)
    )
    ^double
)
(test/exec :type-of4
    (fn ->
        (type-of [1 2 3])
    )
    ^vector
)
(test/exec :type-of5
    (fn ->
        ([1 "2" {}] | map type-of)
    )
    ; BUGBUGBUG - there needs to be a space between the end of the type and the close ']' of the vector.
    [^int ^string ^System.Collections.Generic.Dictionary[Object,Object] ]
)

;-----------------------------------------------------------
; test casts, especially covarient casts
(test/exec :cast1
    (fn ->
        (^int? "123" | type-of)
    )
    ^int
)
(test/exec :cast1a
    (fn ->
        (try (^int "123") | is? ^Exception)
    )
    true
)
(test/exec :cast2
    (fn ->
        (^int? "123" | + 5)
    )
    128
)
(test/exec :cast3
    (fn ->
        (^string? {} | type-of)
    )
    ^system.string
)
(test/exec :cast4
    (fn ->
        (^char[]? "abc" | type-of)
    )
    ^char[]
)
(test/exec :cast4a
    (fn ->
        (^char[]? "abc" | !! 1)
    )
    \b
)
(test/exec :cast5
    (fn ->
        ; cast a vector to an int array
        (^int[]? [1 2 3] | type-of)
    )
    ^int[]
)
(test/exec :cast6
    (fn ->
        ; cast a vector to an int array
        (^string[]? [1 2 3] | type-of)
    )
    ^string[]
)
(test/exec :cast7
    (fn ->
        (^System.Collections.Generic.List[int]? 123 | type-of)
   )
   ^System.Collections.Generic.List[int]
)
(test/exec :cast7a
    (fn ->
        (^System.Collections.Generic.List[int]? 123 | !! 0)
   )
   123
)
(test/exec :cast8
    (fn ->
        ; converts string to int
        (^System.Collections.Generic.List[int]? "123" | type-of)
   )
   ^System.Collections.Generic.List[int]
)
(test/exec :cast9
    (fn ->
        ; invalid casts through...
        (try (^int "adc") | is? ^Exception)
    )
    true
)
(test/exec :cast10
    (fn ->
        ; converts string to int
        (^int? "1" | type-of)
   )
   ^int
)
(test/exec :cast11
    (fn ->
        (^list null)
    )
    null
)
(test/exec :cast12
    (fn ->
        (try (^int null) | is? ^Exception)
    )
    true
)
(test/exec :cast13
    (fn ->
        (^int? null)
    )
    0
)

;-----------------------------------------------------------
; Test Slice
(test/exec :slice1
    (fn ->
        (cdr [1 2 3 4] | type-of)
    )
    ^Slice
)
(test/exec :slice2
    (fn ->
        (slice [1 2 3 4] | !! 0)
    )
    1
)
(test/exec :slice3
    (fn ->
        (slice [1 2 3 4] 1 | !! 0)
    )
    2
)
(test/exec :slice4
    (fn ->
        (slice [1 2 3 4] 1 | count)
    )
    3
)
(test/exec :slice5
    (fn ->
        (slice [1 2 3 4] 1 2 | count)
    )
    2
)
(test/exec :slice6
    (fn ->
        (slice [1 2 3 4] 1 2 | !! 1)
    )
    3
)
(test/exec :slice7
    (fn ->
        ((slice [1 2 3 4] 1 2) 0)
    )
    2
)
(test/exec :slice8
    (fn ->
        (try (slice [1 2 3 4] 1 2 | !! 2) | is? ^Exception)
    )
    true
)
(test/exec :slice9
    (fn ->
        (try ((slice [1 2 3 4] 1 2) 2) | is? ^Exception)
    )
    true
)
(test/exec :slice10
    (fn ->
        (let s (slice [1 2 3]))
        (try (!! s 1 10) | is? ^Exception)
    )
    true
)
(test/exec :slice11
    (fn ->
        (let s (slice [1 2 3]))
        (try (s 1 10) | is? ^Exception)
    )
    true
)
(test/exec :slice12
    (fn ->
        (let s (slice [1 2 3]))
        (count s)
    )
    3
)
(test/exec :slice13
    (fn ->
        (let s (slice [1 2 3] 1))
        (count s)
    )
    2
)
(test/exec :slice14
    (fn ->
        ; destructuring a list returns a slice
        (defn qs2
            | [] -> []
            | p:xs -> (list/split xs (<= p) | map qs2 | (fn s:l: -> [@s p @l]))
        )
        (qs2 [5 3 1 4 2])
    )
    [1 2 3 4 5]
)
(test/exec :slice15
    (fn ->
        (defn qs2
            | [] -> []
            | p:xs -> (list/split xs (<= p) | map qs2 | (fn s:l: -> [@s p @l]))
        )
        (qs2 [1 2 3 4 5])
    )
    [1 2 3 4 5]
)
(test/exec :slice16
    (fn ->
        (defn qs2
            | [] -> []
            | p:xs -> (list/split xs (<= p) | map qs2 | (fn s:l: -> [@s p @l]))
        )
        (qs2 [1])
    )
    [1]
)
(test/exec :slice17
    (fn ->
        (defn qs2
            | [] -> []
            | p:xs -> (list/split xs (<= p) | map qs2 | (fn s:l: -> [@s p @l]))
        )
        (qs2 [])
    )
    []
)

;-----------------------------------------------------------
; Test group
(test/exec :group1
    (fn ->
        (group (range 10) (% 2))
    )
    {
        1 : [ 1, 3, 5, 7, 9 ],
        0 : [ 2, 4, 6, 8, 10 ]
    }
)
(test/exec :group2
    (fn ->
        (group (range 10) (% 2) sum)
    )
    { true : 25, false : 30 }
)
(test/exec :group3
    (fn ->
        (group (range 10) odd?)
    )
    {
        1 : [ 1, 3, 5, 7, 9 ],
        0 : [ 2, 4, 6, 8, 10 ]
    }
)
(test/exec :group4
    (fn ->
        (group (range 10) odd? sum)
    )
    { true : 25, false : 30 }
)
(test/exec :group5
    (fn ->
        ("Hi you world" | re/split | group (fn w -> (.length w)))
    )
    { 2 : [ "Hi" ], 3 : [ "you" ], 5 : [ "world" ] }
)

;-----------------------------------------------------------
; test the 'from' macro
(test/exec :from1
    (fn ->
        (from [a [1 2 3]] a)
    )
    [1 2 3]
)
(test/exec :from2
    (fn ->
        (from [a [1 2] b [1 2]] [a b])
    )
    [[1 1] [2 1] [1 2] [2 2]]
)
(test/exec :from3
    (fn ->
        (from [a [1 2] b [1 2] c [:a :b]] [a b c])
    )

    [[1 1 :a] [2 1 :a] [1 2 :a] [2 2 :a] [1 1 :b] [2 1 :b] [1 2 :b] [2 2 :b]]
)


;-----------------------------------------------------------
; test 'dict/accessor' function.
(test/exec :dict/accessor1
    (fn ->
        (let afunc (dict/accessor :foo))
        (afunc {:foo 1 :bar 2})
    )
    1
)
(test/exec :dict/accessor2
    (fn ->
        (let afunc (dict/accessor :foo))
        (afunc
            [
                {:a 10 :foo 1 :b 20}
                {:c 30 :foo 2}
                {:foo 3 :d 40}])
    )
    [1 2 3]
)

;-----------------------------------------------------------
(;
    Test tuples

    Things that should work but don't - enumerating
    over the tuple elements; indexing both implict (tup 1)
    and explicit (!! tup 1)

    Destructing is tested elsewhere but more should be done.
;)
(test/exec :tuple2
    (fn ->
        (tuple 1 2 3 | type-of)
    )
    ^System.Tuple[object,object,object]
)
(test/exec :tuple3
    (fn ->
        (tuple 1 2 3 | .item2)
    )
    2
)
(test/exec :tuple4
    (fn ->
        (tuple 1 2 3 | .tostring)
    )
    "(1, 2, 3)"
)
(test/exec :tuple5
    (fn ->
        (tuple 1 2 3)
    )
    (tuple 1 2 3)
)

;-----------------------------------------------------------
; Test help functionality
(test/exec :help1
    ; helpsource should execute without errors, returning nothing
    #(null? (helpsource.tl))
    true
)
(test/exec :help2
    ; test for built-in help
    #(some? (help let))
    true
)
(test/exec :help3
    ; help for cmd that doesn't exist is ""
    #(some? (help 'zzzzzzzzzzz))
    false
)
(test/exec :doc1
    #(some? (doc let))
    true
)
(test/exec :doc2
    ; make sure 'autoload.tl' functions are documented.
    #(some? (doc abs))
    true
)
(test/exec :doc3
    (fn ->
        ; test dynamically created help for functions
        (defn zork [x y] (+ x y))
         #(some? (doc zork))
    )
    true
)
(test/exec :doc4
    (fn ->
        ; test dynamically created help for patterns
        (defn zork | x y -> (+ x y))
         #(some? (doc zork))
    )
    true
)
(test/exec :doc5
    (fn ->
        ; test dynamically created help for special functions
        (defspecial zork | x y -> (+ x y))
         #(some? (doc zork))
    )
    true
)
(test/exec :doc6
    (fn ->
        ; test doc on a predefined macro
        (some? (doc fn))
    )
    true
)
(test/exec :doc7
    (fn ->
        ; test doc on a new macro; remove it when test complete
        (try
            (defmacro zzzzz [a b] null)
            (some? (doc zzzzz))
        -finally: (fn -> (undef zzzzz))
        )
    )
    true
)

;-----------------------------------------------------------
; Test 'completer' functionality - these tests are fragile as
; they depend on the contents of the default Braid directory.
(test/exec :completer1
    #(completer "'auto" null 0 | first)
    "'autoload.tl"
)
(test/exec :completer2
    #(completer "'au" null 0 | first)
    "'autoload.tl"
)
(test/exec :completer3
    #(completer "(au" null 0 | first)
    "(autoload.tl"
)
(test/exec :completer4
    #(completer "(.sub" null 0 | first | contains? "(.SubString")
    true
)
(test/exec :completer5
    #(completer "(.subt" null 0 | first | contains? "(.Subtract")
    true
)
(test/exec :completer6
    #(completer ".math/sig" null 0 )
    [ ".math/Sign" ]
)
(test/exec :completer7
    #(completer "(.math/sig" null 0)
    [ "(.math/Sign" ]
)
(test/exec :completer8
    #(completer ":auto" null 0 | first )
    ":autoload.tl"
)
(test/exec :completer9
    #(completer ":au" null 0 | first)
    ":autoload.tl"
)
(test/exec :completer10
    #(completer "(:au" null 0 | first )
    "(:autoload.tl"
)
(test/exec :complete10a
    (fn ->
        ; test completion on dictionary keys, no leading '('
        (global :_completion_test_ {:z12345678 13})
        (let result (completer ":z123" null 0))
        (undef _completion_test_)
        result
    )
    [ ":z12345678" ]
)
(test/exec :complete10b
    (fn ->
        ; test completion on dictionary keys with leading '('
        (global :_completion_test_ {:z12345678 13})
        (let result (completer "(:z123" null 0))
        (undef _completion_test_)
        result
    )
    [ "(:z12345678" ]
)
(test/exec :completer11
    #(completer "(.console/wri" null 0)
    [ "(.console/WriteLine", "(.console/Write" ]
)
(test/exec :completer12
    #(completer ".console/wri" null 0)
    [ ".console/WriteLine", ".console/Write" ]
)
(test/exec :completer13
    #(completer "(.console/write" null 0)
    [ "(.console/WriteLine", "(.console/Write" ]
)
(test/exec :completer14
    #(completer ".console/write" null 0)
    [ ".console/WriteLine", ".console/Write" ]
)
(test/exec :completer15
    #(completer "(.console/writel" null 0)
    [ "(.console/WriteLine" ]
)
(test/exec :completer16
    #(completer ".console/writel" null 0)
    [ ".console/WriteLine" ]
)
(test/exec :completer17
(completer "^funct" null 0)
    [ "^function" ]
)
(test/exec :completer18
(completer "(^funct" null 0)
    [ "(^function" ]
)
(test/exec :completer19
    (fn ->
         (completer "" "(gps -" "" | contains? "-WarningAction:")
    )
    true
)
(test/exec :completer20
    (fn ->
         (completer "" "(files -" "")
    )
    [ "-new " ]
)
(test/exec :completer21
    (fn ->
        (completer "" "| map " "")
    )
    [ "(\ x -> x)" ]
)

;-----------------------------------------------------------
; Test the 'project' function
(test/exec :project1
    ; smoke test
    #(get-process | take 10 | project :name :id :ws | count | > 2)
    true
)
(test/exec :project1a
    ; smoke test using alternate syntax
    #(count (project (get-process) :name :id :ws) | > 2)
    true
)
(test/exec :project2
    ; test with objects
    #(get-childitem 'autoload.tl | project :name :length | map .name)
    [ "autoload.tl" ]
)
(test/exec :project2a
    ; test with objects
    #(project (get-childitem 'autoload.tl) :name :length | map .name)
    [ "autoload.tl" ]
)
(test/exec :project3
    (fn ->
        ; Test with dictionaries
        (let out ([{:a 1 :b 2} {:a 10 :b 11 :c 13}] | project :a :b))
        (and (out 0 | .a | == 1) (out 1 | .b | == 11))
    )
    true
)
(test/exec :project4
    (fn ->
        (let out ([{:a 1 :b 2} {:a 10 :b 11 :c 13}] | project :a :c))
        (and (out 0 | .a | == 1) (out 1 | .c | == 13))
    )
    true
)
(test/exec :project4a
    (fn ->
        (let out ([{:a 1 :b 2} {:a 10 :b 11 :c 13}] | project))
        (and (out 0 | .a | == 1) (out 1 | .c | == 13))
    )
    true
)
(test/exec :project4b
    (fn ->
        (let out ([{:a 1 :b 2} {:a 10 :b 11 :c 13} {:a 100 :b 200}] | project))
        (and
            (out 0 | .a | == 1)
            (out 1 | .c | == 13)
            (out 2 | .b | == 200))
    )
    true
)
(test/exec :project4c
    (fn ->
        (let out ([{:a 1 :b 2} {:a 10 :b 11 :c 13} {:a 100 :b 200} {:d 1000}] | project))
        (and
            (out 0 | .a | == 1)
            (out 1 | .c | == 13)
            (out 2 | .b | == 200)
            (out 3 | .d | == 1000)
            (out 3 | .?a |  == null)
        )
    )
    true
)
(test/exec :project5
    (fn ->
        ; try it with mixed objects and dictionaries.
        (let data [
                (defobject {:a 1 :b 2})
                {:a 11 :b 22}
            ]
        )
        (let out (project data :a :b))
        (and
            (out 0 | .a | == 1)
            (out 0 | .b | == 2)
            (out 1 | .a | == 11)
            (out 1 | .b | == 22))
    )
    true
)
(test/exec :project6
    (fn ->
        (let obj (project {:a 1 :b 2 :c 3}))
        (and
            (.a obj | == 1)
            (.b obj | == 2)
            (.c obj | == 3))
    )
    true
)
(test/exec :project7
    (fn ->
        ; compare object values
        (let obj1 (project {:a 1 :b 2 :c 3}))
        (let obj2 (project {:a 1 :b 2 :c 3}))
        (== obj1 obj2)
    )
    true
)
(test/exec :project8
    (fn ->
        (let obj1 (project {:a 1 :b 2 :c 3}))
        (let obj2 (project {:a 1 :b 20 :c 3}))
        (== obj1 obj2)
    )
    false
)
(test/exec :project9
    (fn ->
        (let obj1 (project {:a 1 :b 2 :c 3}))
        (let obj2 (project {:a 10 :b 12 :c 13}))
        ; objects are different but should use the underlying anonymous type.
        (== (type-of obj1) (type-of obj2))
    )
    true
)

;-----------------------------------------------------------
; Test the 'defenum' function
(test/exec :defenum1
    (fn ->
        (undeftype ^col)
        (defenum ^col {:red 0x1234 :blue 0x456 :green 0x1024})
        [(.red ^col) (.blue ^col) (.green ^col)]
    )
    [ 0x1234 0x456 0x1024 ]
)
(test/exec :defenum1a
    (fn ->
        (undeftype ^col)
        (defenum ^col {:red 0x1234 :blue 0x456 :green 0x1024})
        ; test static member accessors
        [.col/red .col/green .col/blue]
    )
    [ "red" "green" "blue" ]
)
(test/exec :defenum1b
    (fn ->
        (undeftype ^col)
        ; use keyword for type name
        (defenum :col {:red 0x1234 :blue 0x456 :green 0x1024})
        ; test static member accessors
        [.col/red .col/green .col/blue]
    )
    [ "red" "green" "blue" ]
)
(test/exec :defenum1c
    (fn ->
        (undeftype ^col)
        ; use string for type name
        (defenum "col" {:red 0x1234 :blue 0x456 :green 0x1024})
        ; test static member accessors
        [.col/red .col/green .col/blue]
    )
    [ "red" "green" "blue" ]
)
(test/exec :defenum1d
    (fn ->
        (undeftype ^col1)
        (let tn "col3")
        ; use string for type name
        (defenum "${tn}" {:red 0x1234 :blue 0x456 :green 0x1024})
        ; test static member accessors
        [.col3/red .col3/green .col3/blue]
    )
    [ "red" "green" "blue" ]
)
(test/exec :defenum2
    (fn ->
        (undeftype ^col)
        (defenum ^col {:red 1 :blue 2 :green 3})
        (let ^col? foo :red)
        (== "red" foo)
    )
    true
)
(test/exec :defenum2a
    (fn ->
        (undeftype ^col)
        (defenum ^col {:red 1 :blue 2 :green 3})
        (let ^col? foo "red")
        (== 1 foo)
    )
    true
)
(test/exec :defenum3
    (fn ->
        (undeftype ^col)
        (defenum ^col {:red 1 :blue 2 :green 3})
        (let ^col? foo "red")
        (let foo :blue)
        (== "blue" foo)
    )
    true
)
(test/exec :defenum3a
    (fn ->
        (undeftype ^col)
        (defenum ^col {:red 1 :blue 2 :green 3})
        (let ^col? foo :red)
        (let foo :blue)
        (== 2 foo)
    )
    true
)
(test/exec :defenum4
    (fn ->
        (undeftype ^col)
        (defenum ^col {:red 1 :blue 2 :green 3})
        (let ^col? foo :red)
        (let foo :blue)
        (+ 2 foo)
    )
    4
)
; definition with default values 1, 2, ...
(test/exec :defenum5
    (fn ->
        (undeftype ^col)
        (defenum ^col red blue green)
        [(.red ^col) (.green ^col) (.blue ^col)]
    )
    ["red" "green" "blue"]
)
(test/exec :defenum6
    (fn ->
        (undeftype ^col)
        (defenum ^col red blue green)
        (let ^col? foo :red)
        (== "red" foo)
    )
    true
)
(test/exec :defenum7
    (fn ->
        (undeftype ^col)
        (defenum ^col red blue green)
        (let ^col? foo :red)
        (let foo :blue)
        (== "blue" foo)
    )
    true
)
(test/exec :defenum7a
    (fn ->
        (undeftype ^col)
        (defenum ^col red blue green)
        (let ^col? foo :red)
        (let foo :blue)
        (== 1 foo)
    )
    true
)
(test/exec :defenum8
    (fn ->
        (undeftype ^col)
        (defenum ^col red blue green)
        (let ^col? foo :red)
        (let foo :blue)
        (+ 2 foo)
    )
    3
)
(test/exec :defenum9
    (fn ->
        (undeftype ^col)
        (defenum ^col red blue green)
        (let ^col? foo :red)
        (try (let foo 7) | is? ^Exception)
    )
    true
)
(test/exec :defenum10
    (fn ->
        (undeftype ^col)
        (defenum ^col red blue green)
        (defn foo [(^col? c)] c)
        (try (foo 7) | is? ^Exception)
    )
    true
)
(test/exec :defenum11
    (fn ->
        (undeftype ^bits)
        (defenum ^bits {:one 1 :two 2 :three 0b100 :four 0b1000})
        (bor .bits/three .bits/one 2)
   )
   7
)
(test/exec :defenum12
    (fn ->
        (undeftype ^bits)
        (defenum ^bits {:one 1 :two 2 :three 0b100 :four 0b1000})
        (bor 2 .bits/three .bits/one)
   )
   7
)
(test/exec :defenum13
    (fn ->
        (undeftype ^bits)
        (defenum ^bits {:one 1 :two 2 :three 0b100 :four 0b1000})
        (band (^int? .bits/three) (^int? .bits/three) 7)
   )
   4
)
(test/exec :defenum14
    (fn ->
        (undeftype ^bits)
        (defenum ^bits {:one 1 :two 2 :three 0b100 :four 0b1000})
        (band 7 .bits/three .bits/three)
   )
   4
)
(test/exec :defenum15
    (fn ->
        (undeftype ^bits)
        (defenum ^bits {:one 1 :two 2 :three 0b100 :four 0b1000})
        (bor (band .bits/three 7 .bits/three) .bits/four)
   )
   12
)
(test/exec :defenum16
    (fn ->
        (undeftype ^bits)
        (defenum ^bits {:one 1 :two 2 :three 0b100 :four 0b1000})
        (bor (band .bits/three .bits/three 7) 0x1000)
   )
   0x1004
)
(test/exec :defenum17
    (fn ->
        (undeftype ^bits)
        (defenum ^bits {:one 1 :two 2 :three 0b100 :four 0b1000})
        (bor .bits/four (band .bits/three 7 .bits/three 7))
   )
   12
)
(test/exec :defenum18
    (fn ->
        (undeftype ^bits)
        (defenum ^bits {:one 1 :two 2 :three 0b100 :four 0b1000})
        (bor 0x1000 (band .bits/three .bits/three 7))
   )
   0x1004
)
(test/exec :defenum19
    (fn ->
        (undeftype ^bits)
        (defenum ^bits {:one 1 :two 2 :three 0b100 :four 0b1000})
        (band .bits/three (bor 0x1000 .bits/three 7))
   )
   4
)

;----------------------------------------------------------
; Test breadth-search function searching for a target value in a numeric sequence.
(test/exec :breadth-search1
    (fn ->
        (breadth-search 5 35 (fn x -> [(+ x 3) (* x 2) (- x 7)]))
    )
    [5 8 16 32 35]
)
(test/exec :breadth-search2
    (fn ->
        (breadth-search 5 159 (fn x -> [(+ x 3) (* x 2) (- x 7)]))
    )
    [5 10 20 40 80 83 166 159]
)
(test/exec :breadth-search2a
    (fn ->
        ; use a goal function
        (breadth-search 5 (== 159) (fn x -> [(+ x 3) (* x 2) (- x 7)]))
    )
    [5 10 20 40 80 83 166 159]
)
(test/exec :breadth-search3
    (fn ->
        ; test vector as legal move generator 
        (breadth-search 0 3 [1 2 3 4 5])
    )
    [0 1 2 3]
)
(test/exec :breadth-search4
    (fn ->
        ; test with dictionary as legal move generator
        (breadth-search :a :d {:a :b :b [:c :e] :c :d :e [:d :f]})
    )
    [:a :b :c :d]
)
(test/exec :breadth-search4a
    (fn ->
        ; test with dictionary as legal move generator using a dictionary function
        (breadth-search :a (getfunc {:d true}) {:a :b :b [:c :e] :c :d :e [:d :f]})
    )
    [:a :b :c :d]
)
(test/exec :breadth-search5
    (fn ->
        ; test using a goal function instead of a fixed value
        (breadth-search :a (fn v -> (== v :d)) {:a :b :b [:c :e] :c :d :e [:d :f]})
    )
    [:a :b :c :d]
)
(test/exec :breadth-search5a
    (fn ->
        ; test using a composed goal function instead of a fixed value
        (breadth-search :a ($ (== :d)) {:a :b :b [:c :e] :c :d :e [:d :f]})
    )
    [:a :b :c :d]
)

;----------------------------------------------------------
; Test the trampoline function
(test/exec :trampoline1
    (fn ->
        ; mutually recursive functions for testing if a number is even or odd

        (defn my-even? [n]
          (if (zero? n)
            true
             #(my-odd? (-- (abs n)))))

        (defn my-odd? [n]
          (if (zero? n)
            false
             #(my-even? (-- (abs n)))))

        (and
            (trampoline my-even? 500)
            (not (trampoline my-even? 501))
            (trampoline my-odd? 501)
            (not (trampoline my-odd? 500))
        )
    )
    true
)

;----------------------------------------------------------
; Test the use of ByRef variables. Passing a quoted symbol
; as the ByRef argument will result in the 'out' value being
; being stored in the local variable corresponding to the
; symbol.
;
(test/exec :byref1
    (fn ->
        (let xxx null)
        [ (.trygetvalue {:a 1 :b 2} :b 'xxx) xxx ]
    )
    [true 2]
)
(test/exec :byref2
    (fn ->
        (let xxx null)
        [ (.trygetvalue {:a 1 :b 2 :c "Hello"} :c 'xxx) xxx ]
    )
    [true "hello"]
)
(test/exec :byref3
    (fn ->
        (let xxx null)
        [ (.trygetvalue {:a 1 :b 2 :c "Hello"} :d 'xxx) xxx ]
    )
    [false null]
)
(test/exec :byref4
    (fn ->
        ; junk in the ByRef field is ignored. BUGBUGBUG - is this right?
        (.trygetvalue {:a 1 :b 2 :c "Hello"} :a 1)
    )
    true
)
(test/exec :byref5
    (fn ->
        (const xxx null)
        ; setting a constant should throw an exception.
        (try (.trygetvalue {:a 1 :b 2 :c "Hello"} "c" 'xxx) | is? ^Exception)
    )
    true
)

;--------------------------------------------------------------------
; Test creating event handlers
(test/exec :aseventhandler1
    (fn ->
        (aseventhandler (fn o e -> null) | type-of)
    )
    ^System.EventHandler
)
(test/exec :aseventhandler2
    (fn ->
        ; test pattern function
        (aseventhandler (fn | o e -> null) | type-of)
    )
    ^System.EventHandler
)
(test/exec :aseventhandler3
    (fn ->
        (let x 123)
        (aseventhandler (fn o e -> (let x 456)) | .Invoke null null)
        x
    )
    123
)
(test/exec :aseventhandler4
    (fn ->
        (let x 123)
        ; test assignment across scopes
        (aseventhandler (fn o e -> (def x 456)) | .Invoke null null)
        x
    )
    456
)
(test/exec :aseventhandler5
    (fn ->
        (let x 123)
        ; test assignment across 3 levels of scope
        (with []
            (with []
                (aseventhandler (fn o e -> (def x 456)) | .Invoke null null)
            )
        )
        x
    )
    456
)
(test/exec :aseventhandler6
    (fn ->
        (let x 123)
        ; test assignment across 3 levels of scope
        (with []
            (with []
                ; use pattern function
                (aseventhandler (fn | o e -> (def x 456)) | .Invoke null null)
            )
        )
        x
    )
    456
)
(test/exec :aseventhandler7
    (fn ->
        (let x 123)
        ; test assignment across 3 levels of scope
        (with []
            (with [x 0]
                (aseventhandler (fn o e -> (def x 456)) | .Invoke null null)
            )
        )
        x
    )
    123
)
(test/exec :aseventhandler8
    (fn ->
        (let x 123)
        ; test assignment across 3 levels of scope
        (with [x 0]
            (with []
                (aseventhandler (fn o e -> (def x 456)) | .Invoke null null)
            )
        )
        x
    )
    123
)
(test/exec :aseventhandler9
    (fn ->
        (let eh (aseventhandler (fn o e -> (def x 456))) | .Invoke null null)
        (let x 123)
        (.invoke eh null null)
        x
    )
    456
)
(test/exec :aseventhandler10
    (fn ->
        ; parent scope assignment in eventhandler invoking an event handler
        (let eh (aseventhandler (fn o e -> (def x 456))))
        (let eh2 (aseventhandler (fn | o e -> (.invoke eh null null))))
        (let x 123)
        (.invoke eh2 null null)
        x
    )
    456
)
(test/exec :aseventhandler11
    (fn ->
        ; test exception in event handler
        (let eh (aseventhandler (fn o e -> (throw "foo"))))
        (try (.invoke eh null null) | is? ^System.Exception)
    )
    true
)

;--------------------------------------------------------------------
; Test file/filename
(test/exec :file/filename1  #(file/filename "baz.tl") "baz.tl")
(test/exec :file/filename2  #(file/filename "/foo/bar/baz.tl") "baz.tl")
(when IsWindows
    (test/exec :file/filename3  #(file/filename @"\foo\bar\baz.tl") "baz.tl")
)

;--------------------------------------------------------------------
; Test file/basename
(test/exec :file/basename1  #(file/basename "baz.tl") "baz")
(test/exec :file/basename2  #(file/basename "/foo/bar/baz.tl") "baz")
(when IsWindows
    (test/exec :file/basename3  #(file/basename @"\foo\bar\baz.tl") "baz")
)

;--------------------------------------------------------------------
; Test file/dirname
(test/exec :file/dirname1  #(file/dirname "baz.tl") "")
(test/exec :file/dirname2  #(file/dirname "/foo/bar/baz.tl") (if isUnix "/foo/bar" @"\foo\bar"))
(when IsWindows
    (test/exec :file/dirname3  #(file/dirname @"\foo\bar\baz.tl")  @"\foo\bar")
)

;--------------------------------------------------------------------
; Test 'file/tempFileName'
(test/exec :file/tempFileName1  #(file/tempFileName | file/extension | == ".tmp") true)
(test/exec :file/tempFileName2  #(file/tempFileName ".cs" | file/extension | == ".cs") true)
(test/exec :file/tempFileName3  #(file/tempFileName "cs" | file/extension | == ".cs") true)
(test/exec :file/tempFileName4  #(file/tempFileName "cs" | file/filename | re/match #"^tmp[0-9a-z]+\.cs$") true)
(test/exec :file/tempFileName5  #(file/tempFileName ".tl" | file/filename | re/match #"^tmp[0-9a-z]+\.tl$") true)

;--------------------------------------------------------------------
; Test 'file/isRooted'
(test/exec :file/isRooted1  #(file/tempFileName | file/isRooted) true)
(test/exec :file/isRooted2  #("foo.txt" | file/isRooted) false)
(test/exec :file/isRooted3  #(file/isRooted "foo.txt") false)

;--------------------------------------------------------------------
; test the 'file/join-path' command
(test/exec :file/join-path1
    (fn ->
         (let ps (.io.path/DirectorySeparatorChar))
         (== (file/join-path "a" "b" "c") (join ["a" "b" "c"] ps))
    )
    true
)
(test/exec :file/join-path2
    (fn ->
         (let ps (.io.path/DirectorySeparatorChar))
         (== (file/join-path "a" "" "b" "c") (join ["a" "b" "c"] ps))
    )
    true
)
(test/exec :file/join-path3
    (fn ->
         (let ps (.io.path/DirectorySeparatorChar))
         ; the underlying API only supports 4 parameters, we use a loop to handle more.
         (== (file/join-path "a" "" "b" "" "c" "") (join ["a" "b" "c"] ps))
    )
    true
)
; all empty strings should result in an empty string.
(test/exec :file/join-path4  #(file/join-path "" "" "" "" "" "") "")

;--------------------------------------------------------------------
; Test 'file/exists'
(test/exec :file/exists1  #(file/exists braidhome) false) ; fails if the target is a dir
(test/exec :file/exists2  #(file/exists (file/join-path braidhome "autoload.tl")) true)
(test/exec :file/exists3  #(file/exists (file/join-path braidhome "autoload.tl")) true)
(test/exec :file/exists4  #(file/exists "no such file") false)
(test/exec :file/exists5  #(file/exists "") false)
(test/exec :file/exists6 (fn -> (try (file/exists null) | is? ^System.Exception)) true)
(test/exec :file/exists7 (fn -> (try (file/exists null) | is? ^System.Exception)) true)

;--------------------------------------------------------------------
; Test 'file/dir-exists'
(test/exec :file/dir-exists1  #(file/dir-exists braidhome) true) ; fails if the target is a dir
(test/exec :file/dir-exists2  #(file/dir-exists "no such dir") false) ; fails if the tardet is a dir
(test/exec :file/dir-exists3 (fn -> (try (file/dir-exists null) | is? ^System.Exception)) true)

;--------------------------------------------------------------------
; Test 'file/extension'
(test/exec :file/extension1   #(file/extension "foo.tl") ".tl")
(test/exec :file/extension2   #(file/extension "/foo/barfoo.tl") ".tl")
(test/exec :file/extension3   #(file/extension @"\foo\barfoo.tl") ".tl")
(test/exec :file/extension4   #(file/extension "foo") "")
(test/exec :file/extension5   #(file/extension "") "")
(test/exec :file/extension6  (fn -> (try (file/extension null) | is? ^System.Exception)) true)
(test/exec :file/extension7   #(file/extension "foo.tl" ".cs") "foo.cs")
(test/exec :file/extension8   #(file/extension "foo.tl" "cs") "foo.cs")
(test/exec :file/extension9   #(file/extension "/foo/barfoo.tl" ".cs") "/foo/barfoo.cs")
(test/exec :file/extension10  #(file/extension "/foo/barfoo.tl" "cs") "/foo/barfoo.cs")
(test/exec :file/extension11  #(file/extension @"\foo\barfoo.tl" ".cs") @"\foo\barfoo.cs")
(test/exec :file/extension12  #(file/extension @"\foo\barfoo.tl" "cs") @"\foo\barfoo.cs")

;--------------------------------------------------------------------
; Test 'let-default'
(test/exec :let-default1
    (fn ->
        (let-default no-such-var 10)
        no-such-var
    )
    10
)
(test/exec :let-default2
    (fn ->
        (let foo null)
        (let-default foo 123)
        foo
    )
    123
)
(test/exec :let-default3
    (fn ->
        (let foo 456)
        (let-default foo 123)
        foo
    )
    456
)
(test/exec :let-default4
    (fn ->
        (let foo 5)
        (let-default foo 1 10)
        foo
    )
    5
)
(test/exec :let-default5
    (fn ->
        (let foo 0)
        (let-default foo 1 10)
        foo
    )
    1
)
(test/exec :let-default6
    (fn ->
        (let foo 11)
        (let-default foo 1 10)
        foo
    )
    10
)
(test/exec :let-default7
    (fn ->
        ; if the value doesn't match the target type, initialize to the lower bound
        (let foo "abc")
        (let-default ^int foo 1 10)
        foo
    )
    1
)


;--------------------------------------------------------------------
; Test 'get-args'
(test/exec :get-args1
    (fn ->
        (matchp 1 2 3 | -> (get-args))
    )
    [1 2 3]
)
(test/exec :get-args2
    (fn ->
        (matchp 1 2 3
        | (^int x) -> "ex ${x}"
        | -> "Expected one integer argument, not <<${(join (get-args))}>>"
        )
    )
    "Expected one integer argument, not <<1 2 3>>"
)

;--------------------------------------------------------------------
; Test hashsets
(test/exec :hashset1 #(type-of #{1 2 3}) ^HashSet
)
(test/exec :hashset1a #(type-of #{}) ^HashSet)
(test/exec :hashset1b #(count #{1 2 3}) 3)
(test/exec :hashset1c #(count #{}) 0)
(test/exec :hashset2
    (fn -> (!!  #{0 1 2 3} 2))
    2
)
(test/exec :hashset2a
    (fn -> (!!  #{0 1 2 3} 10))
    null
)
(test/exec :hashset2c
    (fn ->
        (let v  #{0 1 2 3})
        (.add v 4)
        v
    )
#{0 1 2 3 4}
)
(test/exec :hashset2d
    ; enumerations compare equal
    (fn ->
        (let v  #{0 1 2 3})
        (.add v 4)
        v
    )
    [0 1 2 3 4]
)
(test/exec :hashset3
    (fn -> (contains?  #{0 1 2 3} 2))
    true
)
(test/exec :hashset4
    (fn -> (contains?  #{0 1 2 3} 10))
    false
)
;BUGBUGBUG - can't splat a hashset directly i.e. @#{1 2 3}
(test/exec :hashset5
    ; splatting in hashsets
    (fn ->  #{1 @(range 2 5) 6})
    #{1 2 3 4 5 6}
)
(test/exec :hashset6
    (fn ->
        (let x [2 3 4 5])
         #{1 @x 6}
    )
    #{1 2 3 4 5 6}
)
(test/exec :hashset7
    (fn ->
        (let x [2 3 4])
         #{1 @x @(reverse x) 1}
    )
    #{1 2 3 4 4 3 2 1}
)
(test/exec :hashset8
    (fn ->
        (let x  #{2 3 4})
         #{1 @x 1}
    )
    #{1 2 3 4}
)
(test/exec :hashset9
    (fn ->
        (let r 0)
        (foreach i  #{1 2 3} (incr r i))
        r
    )
    6
)
(test/exec :hashset10
    (fn ->
        (#{1 2 3} | sum)
    )
    6
)
(test/exec :hashset11
    (fn ->
         #{0 @(echo #{@(range 2 8 | filter even?)}) 10}
    )
    #{0 2 4 6 8 10}
)
;hashset literal as a function
(test/exec :hashset20
    (fn ->
        (#{1 2 3 4} 2)
    )
    true
)
(test/exec :hashset21
    (fn ->
        (#{1 2 3 4} 5)
    )
    false
)
(test/exec :hashset22
    (fn ->
        (#{1 2 3 4} 5 true) ; add an item
    )
    #{1 2 3 4 5}
)
(test/exec :hashset23
    (fn ->
        (#{1 2 3 4} 5 false)
    )
    #{1 2 3 4}
)
(test/exec :hashset24
    (fn ->
        (#{1 2 3 4} 2 false) ; remove an item
    )
    #{1 3 4}
)
; hash set as a function
(test/exec :hashset25
    (fn ->
        (let hs  #{1 2 3 4})
        (hs 3)
    )
    true
)
(test/exec :hashset26
    (fn ->
        (let hs  #{1 2 3 4})
        (hs 5)
    )
    false
)
(test/exec :hashset27
    (fn ->
        (let hs  #{1 2 3 4})
        (hs 5 true)
    )
    #{1 2 3 4 5}
)
(test/exec :hashset28
    (fn ->
        (let hs  #{1 2 3 4})
        (hs 3 false)
    )
    #{1 2 4}
)
(test/exec :hashset29
    (fn ->
        (let hs  #{1 2 3 4})
        (hs 5 true)
        hs
    )
    #{1 2 3 4 5}
)
(test/exec :hashset30
    (fn ->
        (let hs  #{1 2 3 4})
        (hs 3 false)
        hs
    )
    #{1 2 4}
)

;--------------------------------------------------------------------
; Test the .signature API
(test/exec :signature1
    (fn ->
        (defn foo [x] x)
        (.signature foo)
    )
    "(foo [x])"
)
(test/exec :signature2
    (fn ->
        (defn foo [(x "hello")] x)
        (.signature foo)
    )
    "(foo [(x \"hello\")])"
)
(test/exec :signature3
    (fn ->
        (defn foo [(x 3.0)] x)
        (.signature foo)
    )
    "(foo [(x 3.0)])"
)
(test/exec :signature4
    (fn ->
        (defn foo ^int [(x 3.0)] x)
        (.signature foo)
    )
    "(foo ^int [(x 3.0)])"
)
(test/exec :signature5
    (fn ->
        (defn foo ^int [(^double x 3.0)] x)
        (.signature foo)
    )
    "(foo ^int [(^double x 3.0)])"
)
(test/exec :signature6
    #(.signature **)
    "(** ^double [(^double? x) (^double? y)])"
)

;--------------------------------------------------------------------
; Test the ToStringSource function
(test/exec :tosourcestring1  #(tosourcestring "abc") "\"abc\"" )
(test/exec :tosourcestring2  #(tosourcestring 3) "3" )
(test/exec :tosourcestring3  #(tosourcestring 3.0) "3.0" )
(test/exec :tosourcestring4  #(tosourcestring 3.14) "3.14" )
(test/exec :tosourcestring5  #(tosourcestring #"abc") "#\"abc\"" )
(test/exec :tosourcestring5a #(tosourcestring #"a\nc") "#\"a\\\\nc\"" )
(test/exec :tosourcestring6  #(tosourcestring null) "nil" )
(test/exec :tosourcestring7  #(tosourcestring fib)  "fib")
(test/exec :tosourcestring8  #(tosourcestring #{1 2 3} | re/replace "\s+" " ") "#{ 1, 2, 3 }")
(test/exec :tosourcestring9  #(tosourcestring [1 2 3] | re/replace "\s+" " ") "[ 1, 2, 3 ]")
(test/exec :tosourcestring10 #(tosourcestring {"a" 1 "b" 2} | re/replace "\s+" " ") "{ \"a\" : 1, \"b\" : 2 }")
(test/exec :tosourcestring11 #(tosourcestring ^int) "^System.Int32")
(test/exec :tosourcestring12 (fn -> (let t ^double) (tosourcestring t)) "^System.Double")
(test/exec :tosourcestring13 #(tosourcestring 123i) "123i")
(test/exec :tosourcestring14   #(tosourcestring "a\nb\nc") "\"a\\nb\\nc\"")
(test/exec :tosourcestring15
    ; test check for loops in stringization - should result in an exception (this is a bit slow)
    (fn ->
        (let a {:a 1 :b 2})
        (a :c a)
        (try (tosourcestring a) | is? ^Exception)
    )
    true
)
(test/exec :tosourcestring16 #(tosourcestring .substring) ".substring")
(test/exec :tosourcestring17 #(tosourcestring 'foo) "foo")
(test/exec :tosourcestring18 #(tosourcestring :foo) ":foo")
(test/exec :tosourcestring19 #(tosourcestring 123) "123")
(test/exec :tosourcestring20 #(tosourcestring 123.45) "123.45")
(test/exec :tosourcestring21 #(tosourcestring 000123.45) "123.45")
(test/exec :tosourcestring22 #(tosourcestring sum) "sum")   ; returns the name of a named function
(test/exec :tosourcestring23 #(tosourcestring (fn x y -> (+ x y))) "(lambda [x y] (+ x y))") ; returns the body of an anonymous function

;--------------------------------------------------------------------
; Test 'tokenize-string'
(test/exec :tokenize-text1
    (fn ->
        (tokenize-text "123" | !! 0 | .Type)
    )
    .braidlang.tokentype/number
)
(test/exec :tokenize-text2
    (fn ->
        (tokenize-text "\"abc\"" | !! 0 | .Type)
    )
    .braidlang.tokentype/string
)
(test/exec :tokenize-text3
    (fn ->
        (tokenize-text "  (  + 1 2 )" | count)
    )
    5
)
(test/exec :tokenize-text3a
    (fn ->
        (tokenize-text "  (  + 1.01 222 )" | count)
    )
    5
)
(test/exec :tokenize-text3b
    (fn ->
        (tokenize-text "  (  + 1.01 (* 222 4))" | count)
    )
    9
)

(test/exec :tokenize-text4
    (fn ->
        ; make sure the right token types are being returned
        (matchp @(tokenize-text "(+ 2 3)")
        | {Type .braidlang.tokentype/paren}
          {Type .braidlang.tokentype/builtInFunction}
          {Type .braidlang.tokentype/number}
          {Type .braidlang.tokentype/number}
          {Type .braidlang.tokentype/paren}
          ->
            true
        )
    )
    true
)
(test/exec :tokenize-text4a
    (fn ->
        ; make sure the right token types are being returned
        (matchp @(tokenize-text "(+ \"ab\" 3)")
        | {Type .braidlang.tokentype/paren}
          {Type .braidlang.tokentype/builtInFunction}
          {Type .braidlang.tokentype/string}
          {Type .braidlang.tokentype/number}
          {Type .braidlang.tokentype/paren}
          ->
            true
        )
    )
    true
)
(test/exec :tokenize-text4b
    (fn ->
        ; make sure the right token types are being returned
        (let paren   .braidlang.tokentype/paren)
        (let builtin .braidlang.tokentype/builtInFunction)
        (let num     .braidlang.tokentype/number)
        (let string  .braidlang.tokentype/string)
        (let sym     .braidlang.tokentype/symbol)
        (matchp @(tokenize-text "(nosuchfunc \"ab\" 3)")
        | {Type %symbol} {Type %symbol} {Type %string} {Type %num} {Type %paren} -> true
        )
    )
    true
)
(test/exec :tokenize-text5
    (fn ->
        (tokenize-text "(+ 2 3)" | map .tokenstring)
    )
    ["(" "+" "2" "3" ")"]
)
(test/exec :tokenize-text5a
    (fn ->
        (tokenize-text "(+ 2 (* 3 4))" | map .tokenstring)
    )
    ["(" "+" "2" "(" "*" "3" "4" ")" ")"]
)
(test/exec :tokenize-text6
    (fn ->
        (matchp @(tokenize-text "(defn foo [a b])" | map .tokenstring)
        | "(" "defn" name "[" v1 v2 "]" ")" -> [name v1 v2]
        )
    )
    ["foo" "a" "b"]
)
(test/exec :tokenize-text7
    (fn ->
        (matchp @(tokenize-text "(defn foo [a b])" | map .type)
        | _ .braidlang.tokentype/macro &args -> true
        )
    )
    true
)
(test/exec :tokenize-text8
    (fn ->
        (let txt "
            (defn foo [x] (* x 2))
            (let zzz 123)
            (defn bar [] (+ 3 4))
            (info 'some 'text)
            (if true
                (defn baz [] 'hello)
            )
        ")

        ; loop through the tokens getting the names of defined functions
        (loop [tokens (tokenize-text txt) result []]
            (matchp @tokens
            | {TokenString "defn" Type .braidlang.tokentype/macro} {TokenString name} &args ->
                (recur args (nconc name result))
            | _ &args ->
                (recur args result)
            | -> result
            )
        )
    )
    ["foo" "bar" "baz"]
)

;--------------------------------------------------------------------
; Test examples using pattern matching
(test/exec :patternexample11
    (fn ->
        ; split a sentence into words on spaces using patterns, character literals and recur
        (defn ws
            ; space means word is complete so add w to l, reset w and recur
            | [\space &xs] (w "") (l []) -> (recur xs "" (nconc w l))

            ; add char to the current word w
            | [c &xs] (w "") (l []) -> (recur xs (str w c) l)

            ; join trailing words and filter out empty strings
            | %none? w l -> (nconc w l | filter some?)
        )
        (ws "Hello  there world   how are you")
    )
    [ "Hello", "there", "world", "how", "are", "you" ]
)
(test/exec :patternexample2
    (fn ->
        ; function to extract matching pairs
        (defn pairs
            ; use a pinned variable to establish "pairness"; only keep 1 value
            | [[x %x] &xs] (l []) -> (recur xs (nconc x l))

            ; ignore other values and keep scanning the list
            | [x &xs] (l []) -> (recur xs l)

            ; at the end of the list, return the aggregated results
            | nil (l []) -> l
        )
        (pairs [[1 2] [3 3] [4 5] [6 6] [7 8]])
    )
    [3 6]
)
(test/exec :patternexample3
    (fn ->
        ; function to extract pairs satisfying a predicate function 
        (defn pairs
            | [[x y] &xs] func (l []) :where (func x y) -> (recur xs func (nconc [x y] l))
            | [x &xs] func (l []) -> (recur xs func l)
            | nil func (l []) -> l
        )
        ; try it with ==
        (pairs [[1 2] [3 3] [4 5] [6 6] [7 8]] ==)
    )
    [[3 3] [6 6]]
)
(test/exec :patternexample4
    (fn ->
        ; function to extract pairs satisfying a predicate function 
        (defn pairs
            | [[x y] &xs] func (l []) :where (func x y) -> (recur xs func (nconc [x y] l))
            | [x &xs] func (l []) -> (recur xs func l)
            | nil func (l []) -> l
        )
        ; try it with ==
        (pairs [[1 2] [3 3] [4 5] [6 6] [7 8]] <)
    )
    [[1 2] [4 5] [7 8]]
)
(test/exec :patternexample5
    (fn ->
        ; function to extract pairs satisfying a predicate function 
        (defn pairs
            | [[x y] &xs] func (l []) :where (func x y) -> (recur xs func (nconc (first %0) l))
            | [x &xs] func (l []) -> (recur xs func l)
            | nil func (l []) -> l
        )
        ; try it with a custom function checking for pairs that add up to an even number
        (pairs
            [[1 2] [3 3] [4 2] [6 6] [7 8]]
            (fn x y -> (+ x y | % 2 | == 0)))
    )
    [[3 3] [4 2] [6 6]]
)
(test/exec :patternexample6
    (fn ->
        ; count the number of letter pairs in a string. Four adjacent letters are counted as 2 pairs.
        (loop [chars (chars "Hello therrrre worldd ") count 0]
            (matchp chars count
            | [x %x &more] count -> (recur more (++ count))
            | [x &more]    count -> (recur more count)
            | nil          count -> count
            )
        )
    )
    4
)

;--------------------------------------------------------------------
; Test examples using property patterns

; literal matches
(test/exec :propertypattern1
    (fn ->
        ([{:a 1 :b 1} {:a 2 :b 2}] | project | flatmap (fn | {a 2 b _} -> b | ->))
    )
    [2]
)
(test/exec :propertypattern1a
    (fn ->
        ([{:a "red" :b 1} {:a "blue" :b 2}] | project | flatmap (fn | {a "RED" b _} -> b | ->))
    )
    [1]
)
(test/exec :propertypattern1b
    (fn ->
        ([{:a "red" :b 1} {:a "blue" :b 2}] | project | flatmap (fn | {a "Blue" b _} -> b | ->))
    )
    [2]
)
(test/exec :propertypattern1c
    (fn ->
        ([{:a "red" :b 1} {:a "blue" :b 2}] | project | flatmap (fn | {a _ b 2} -> a | ->))
    )
    ["blue"]
)
(test/exec :propertypattern1d
    (fn ->
        ([{:a "red" :b 1} {:a "blue" :b 2}] | project | filter (fn | {a _ b 2} -> true | -> false) | !! 0 | .a)
    )
    "blue"
)
(test/exec :propertypattern1e
    (fn ->
        ; direct use of a property pattern in a filter expression
        ([{:a "red" :b 1} {:a "blue" :b 2}] | project | filter {a _ b 2} | !! 0 | .a)
    )
    "blue"
)
(when isWindows
    (test/exec :propertypattern1m
        (fn ->
            ; count the number of services with autostart that are running.
            (Get-Service -ea: "silentlycontinue"
            | flatmap (fn
                | {status "running" starttype "automatic" displayname _ } -> %0 
                | ->
                )
            | count 
            | > 0
            )
        )
        true
    )
    (test/exec :propertypattern1n
        (fn ->
            ; count processes with working set > 10 million.
            (Get-Process 
            | flatmap (fn | {ws (> 10_000_000) name _} -> name | ->)
            | count 
            | > 10)
        )
        true
    )
)

; regex property patterns
(test/exec :propertypattern2
    (fn ->
        ([{:a "red" :b 1} {:a "blue" :b 2}] | project | flatmap (fn | {a #"e" b _} -> b | ->))
    )
    [1 2]
)
(test/exec :propertypattern2a
    (fn ->
        ([{:a "red" :b 1} {:a "blue" :b 2}] | project | flatmap (fn | {a #"re" b _} -> b | ->))
    )
    [1]
)

; type property patterns
(test/exec :propertypattern3
    (fn ->
        ([{:a "red" :b "one"} {:a 2 :b "two"}] | project | flatmap (fn | {a ^int b _} -> b | ->))
    )
    ["two"]
)
(test/exec :propertypattern3a
    (fn ->
        ([{:a "red" :b "one"} {:a 2 :b "two"}] | project | flatmap (fn | {a ^string b _} -> b | ->))
    )
    ["one"]
)
(test/exec :propertypattern3b
    (fn ->
        ([{:a "red" :b "one"} {:a 2 :b "two"}] | project | flatmap (fn | {a ^double b _} -> b | ->))
    )
    []
)
(test/exec :propertypattern3c
    (fn ->
        ; test with supplied var
        ([{:a "red" :b "one"} {:a 2.0 :b "two"}] | project | flatmap (fn | {a (^double zork) b _} -> [zork b] | ->))
    )
    [2.0 "two"]
)

; expression property patterns
(test/exec :propertypattern4
    (fn ->
        ([{:a 1} {:a 2} {:a 3} {:a 4}] | map project | map (fn | {a (% 2)} -> "odd" | -> "even"))
    )
    ["odd" "even" "odd" "even"]
)
(test/exec :propertypattern5
    (fn ->
        ([{:a 1 :b 10} {:a 2 :b 20} {:a 3 :b 30}] | project | flatmap (fn | {a (>= 2) b _} -> [a b] | ->))
    )
    [ 2, 20, 3, 30]
)

; more regex property patterns
(test/exec :propertypattern10
    (fn ->
        ([{:a 1 :b 10} {:a 2 :b 20} {:a 3 :b 30}] | project
            | flatmap (fn | {a #"[23]" b bee} -> [a bee] | ->))
    )
    ["2", 20, "3", 30]
)
(test/exec :propertypattern11
    (fn ->
        ([{:a 1 :b 10} {:a 2 :b 20} {:a 3 :b 30}] | project |
            flatmap (fn | {a (#"[23]" eh) b bee} -> [eh bee] | ->))
    )
    ["2", 20, "3", 30]
)

; pinned variables and functions in property patterns
(test/exec :propertypattern20
    (fn ->
        (let x 5)
        (matchp (project {:a 5}) | {a %x} -> true | -> false)
    )
    true
)
(test/exec :propertypattern21
    (fn ->
        (let x 5)
        (matchp (project {:a 6}) | {a %x} -> true | -> false)
    )
    false
)
(test/exec :propertypattern22
    (fn ->
        ; test using a binding from the property pattern in a later pattern match
        (let x 5)
        (matchp (project {:a 6}) 6 | {a xyz} %xyz -> true | -> false)
    )
    true
)
(test/exec :propertypattern25
    (fn ->
         (matchp (project {:a 123}) | {a %some?} -> "some ${a}" | -> "none")
    )
    "some 123"
)
(test/exec :propertypattern26
    (fn ->
         (matchp (project {"a" null}) | {a %some?} -> "some ${a}" | -> "none")
    )
    "none"
)
(test/exec :propertypattern27
    (fn ->
        (matchp (project {"a" 123}) | {a (fn o -> (some? o))} -> "some ${a}" | -> "none")
    )
    "some 123"
)
(test/exec :propertypattern28
    (fn ->
        (matchp (project {"a" null}) | {a (fn o -> (some? o))} -> "some ${a}" | -> "none")
    )
    "none"
)

; nested property patterns
(test/exec :propertypattern50
    (fn ->
        ; property pattern containing a sequence pattern
        ((fn | {a [x &xs]} -> xs | -> false) (project {:a [1 2 3]}))
    )
    [2 3]
)
(test/exec :propertypattern51
    (fn ->
        ; vector containing property pattern containing vector
        ((fn | [ 1 {a [_ foo _]} 3] -> foo | -> false) [1 (project {:a [1 2 3]}) 3] )
    )
    2
)
(test/exec :propertypattern52
    (fn ->
        ; property pattern containing a property pattern
        ((fn | {a {x ex y ey } b 2} -> [ey ex] | -> false) (project {:a (project {:x 10 :y 20}) :b 2} ))
    )
    [20 10]
)
(test/exec :propertypattern52a
    (fn ->
        ; matchp with a property pattern containing a property pattern
        (let nestedObject
            (project {:a
                (project {:x 10 :y 20}) :b 2}))

        (matchp nestedObject
        | {a {x ex y ey } b 2} -> [ey ex]
        | -> false
        )
    )
    [20 10]
)
(test/exec :propertypattern52c
    (fn ->
        ; matchp with a property pattern containing a property pattern containing a sequence pattern
        (let nestedObject
            (project {
                :a
                (project {
                    :x [:a :b :c]
                    :y 20
                })
                :b 2
            })
        )

        (matchp nestedObject | {a {x [_ l _] y _} b 2} -> [l y b] | -> false)
    )
    [:b 20 2]
)
; test with dictionaries
(test/exec :propertypattern55
    (fn ->
        ([{:a 1 :b 2}] | filter {:a 1})
    )
    [{:a 1 :b 2}]
)
(test/exec :propertypattern56
    (fn ->
        ([{:a 1 :b 2} {:a 2 :b 3}] | filter {:a 2})
    )
    [{:a 2 :b 3}]
)
(test/exec :propertypattern57
    (fn ->
        (list {:a 1 :b 2} {:a 2 :b 3} | filter {:a 2})
    )
    [{:a 2 :b 3}]
)

;--------------------------------------------------------------------
; Test select-type (this is slow)
(test/exec :select-type1
    (fn ->
        (select-type #"^BraidLang.Vector$" | !! 0)
    )
    ^BraidLang.Vector
)
;--------------------------------------------------------------------
; Test extract-min
(test/exec :extract-min1
    (fn ->
        (extract-min [4 2 1 6 5] 1)
    )
    [ 1 ]
)
(test/exec :extract-min2
    (fn ->
        (extract-min [4 2 1 6 5] 2)
    )
    [ 1 2 ]
)
(test/exec :extract-min3
    (fn ->
        (extract-min [4 2 1 6 5] 0)
    )
    nil
)
(test/exec :extract-min4
    (fn ->
        (extract-min ["one" "two" "three"] 1)
    )
    ["one"]
)
(test/exec :extract-min5
    (fn ->
        (extract-min ["one" "two" "three"] 2)
    )
    ["one" "three"]
)
(test/exec :extract-min6
    (fn ->
        (extract-min [] 2)
    )
    []
)
(test/exec :extract-min7
    (fn ->
        (try (extract-min [4 2 1 6 5] -1) | is? ^exception)
    )
    true
)
(test/exec :extract-min8
    (fn ->
        (try (extract-min [4 2 1 6 5] -2) | is? ^exception)
    )
    true
)
(test/exec :extract-min9
    (fn ->
        (extract-min [4 2 1 6 5] "2")
    )
    [1 2]
)
(test/exec :extract-min10
    (fn ->
        (try (extract-min [4 2 1 6 5] "one") | is? ^exception)
    )
    true
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; End of tests
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(.stop total-test-time-stopwatch)

(alert "

============================================
Test run completed; duration: ${(.elapsed total-test-time-stopwatch | .TotalSeconds)} seconds.

Total number of tests: ${_counttests}
Tests passed:          ${_passed} tests passed.
Tests failed:          ${(count _failures)} failures.
")

(alert "============================================")

(alert "Average test duration (time in ms):" (test-durations | map .value | average | round 4))

(alert "Slowest tests (time in ms):")
(test-durations | sort -descending .value | take 10 | each info )

(alert "============================================")

(when _failures
    (_failures | each error)
)

