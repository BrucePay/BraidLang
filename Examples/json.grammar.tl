;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Braid grammar for JSON using "star functions".
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(let json/lex_pattern #"true|false|null|\"(\\\\.|[^\"])*\"|[0-9.]+|[\\[\\]{},:]|\\b+")

(defn json/tokenize
"Function to break a string containing JSON syntax objects into tokens."
    [str]

    ( .matches json/lex_pattern str
    | map .value
    | filter -not .string/isnullorempty
    )
)

;---------------------------------------------------------------
;
; The JSON grammar rules...
;

(defn json/string
    | (#"^\".*\"$" s) -> (.value (!! s 0))
    | ->
)

(defn json/number
    | (#"^[0-9.].*$" n) -> (^double? (.value (!! n 0)))
    | ->
)

(defn json/value
    | "[" (*json/elements e) "]"  -> e
    | "{" (*json/members pairlist) "}"   ->
        (let result {})
        (foreach pair pairlist (!! result (.key pair) (.value pair)))
        result
    | (*json/string s)            -> s
    | (*json/number n)            -> n
    | "true"                      -> true
    | "false"                     -> false
    | "null"                      -> "null"
)

(defn json/elements
    | (*json/value v) (*json/elements-1 elist) -> (.insert elist 0 v)
    | (*json/value v) -> v
    | -> [] ; allow empty element sets

    | ^ ->
        (defn json/elements-1
            | "," (*json/value v) (*json/elements-1 elist) -> (.insert elist 0 v)
            | -> []
        )
)

(defn json/member
    | (*json/string k) ":" (*json/value v) -> (new ^System.Collections.Generic.KeyValuePair[object,object] k v)
    | ->
)

(defn json/members
    | (*json/member m) (*json/members-1 mlist) -> (concat m mlist)
    | (*json/member m) -> m
    | -> [] ; allow empty member sets

    | ^ -> 
        (defn json/members-1
            | "," (*json/member m1 ) (*json/members-1 mlist1) -> (concat m1 mlist1)
            | -> []
        )

)

;---------------------------------------------------------------
;
; Driver function that tokenizes a string then parses the result.

(defn json/parse [str :t]
    (let tokens (json/tokenize str))
    (if t
        (do
            (info "TOKENS:" @tokens)
            (trace (json/value @tokens))
        )
        (do
             (json/value @tokens)
        )
    )
)

;---------------------------------------------------------------
;
; Very basic tests
;
(alert "Test 1")
(println "dictonary test\n" (json/parse "{ \"a\" : 1, \"b\" : 2 }"))

(alert "Test 2")
(println "array test\n" (json/parse "[1, 2, [3, 4], 5, [6, [7, [8], 9], 10], 11]"))

(alert "Test 3")
(println "complex test\n" (json/parse "
    [
        { \"m\" : 15.67},
        1,
        2,
        [ 3, 4, 5 ],
        {
            \"a\" : 12,
            \"b\" : [
                100,
                200,
                300,
                400
            ],
            \"d\" : {
                \"x\" : 1,
                \"y\" : 3
            },
            \"see\" : \"A string with spaces\",
            \"e\":null,
            \"f\" : [ 1, [2, 3], [[[4]]]]
        },
        3,
        { \"m\" : 10}
    ]
"))

