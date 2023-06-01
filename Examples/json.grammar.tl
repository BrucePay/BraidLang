;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Braid grammar for JSON
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(let json/lex_pattern #"true|false|null|\"(\\\\.|[^\"])*\"|[0-9.]+|[\\[\\]{},:]|\\b+")

(defn json/tokenize
"Function to break a string containing JSON objects into tokens."
    [str]

    ( .matches json/lex_pattern str
    | map .value
    | filter -not .string/isnullorempty
    )
)

;---------------------------------------------------------------
;
; The JSON grammar patterns...
;

(defn json/string
    | (#"^\".*$" s) -> (.value (!! s 0))
    | ->
)

(defn json/number
    | (#"^[0-9.].*$" n:) -> (^double? (.value n))
    | ->
)

(defn json/value
    | "[" (*json/elements e) "]"  -> e
    | "{" (*json/members m) "}"   -> { @m }
    | (*json/string s)            -> s
    | (*json/number n)            -> n
    | "true"                      -> true
    | "false"                     -> false
    | "null"                      -> "null"
)

(defn json/elements
    | (*json/value v) (*json/elements-1 elist) -> [ v @elist ]
    | (*json/value v) -> v
    | -> [] ; allow empty element sets

    | ^ ->
        (defn json/elements-1
            | "," (*json/value v) (*json/elements-1 elist) -> [ v @elist ]
            | -> []
        )
)

(defn json/member
    | (*json/string s) ":" (*json/value v) -> {s v}
    | ->
)

(defn json/members
    | (*json/member m) (*json/members-1 mlist) -> { @m @mlist }
    | (*json/member m) -> m
    | -> [] ; allow empty member sets

    | ^ -> 
        (defn json/members-1
            | "," (*json/member m ) (*json/members-1 mlist) -> [ m @mlist ]
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
            (json/value @tokens)
        )
        (do
             (json/value @tokens)
        )
    )
)

;---------------------------------------------------------------
;
; Very basic test
;
(println "result" (json/parse "
    [
        { \"m\" : 10},
        1,
        2,
        {
            \"a\" : 12,
            \"b\" : [
                100,
                200,
                300
            ],
            \"see\" : \"A string with spaces\",
            \"d\" : {\"x\":1, \"y\": 2},
            \"e\" : [ 2 ],
            \"f\" : null
        },
        3,
        { \"m\" : 10}
    ]
"))

