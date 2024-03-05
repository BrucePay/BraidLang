;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Braid script to find out which functions defined in 'autoload.tl have no
; corresponding tests in 'unittests.tl
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
 
(let testsFile  (join-path braidhome "unittests.tl"))

; Get the list of defined functions using the 'functions' primitive
(let definedFuncs
    (functions
    ;| filter (fn f ->  (#"built-in|autoload" (where-defined (.value f))))
    | filter ($ .value where-defined #"built-in|autoload")
    | map .key | map .value | sort)
)

(warn "Loading test information...")
(let testedFuncs
    (loop [t (tokenize-file 'unittests.tl) results []]
        (matchp t
        | [{Type .braidlang.tokentype/paren} {TokenString "test/exec"} {TokenString n} &args] ->
            (recur args (nconc n results))
        | [_ &args] ->
            (recur args results)
        | nil -> results)
    | re/replace-all #"[0-9]+[a-z]?$"
    | distinct
    | re/replace-all "^:"
    | sort
    | intersect definedFuncs
    )
)

;(let difference (except definedFuncs testedFuncs))
(let difference (definedFuncs | filter (fn n -> (not (contains? testedFuncs n)))))

(alert "=========================================================")
(alert "Functions with no corresponding unit tests.")
(alert "=========================================================")

(let ^int width (map difference .length | reduce max))
(let ^int size (.console/windowwidth | div width))
(list/wrapprint difference info)

(alert "Number of defined functions:" (count definedFuncs))
(alert "Number of tested functions: " (count testedFuncs))
(alert "Difference:                 " (count difference))
(alert "=========================================================")

; return nothing...
null
