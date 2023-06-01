;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Script to demonstrate/test Task usage in braid.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

lambda [
    ; the number of reps to execute.
    (reps 10)
]

(using-module http)

(alert "Getting the main Wikipedia page ${reps} times, single-threaded")

(time
    (repeat-all reps (http/get "https://wikipedia.org")
    | map .length
    | println)
)

(alert "\n\nGetting the main Wikipedia page ${reps} times, using map-parallel")

(time
    (range reps
    | map-parallel (fn _ -> (http/get "https://wikipedia.org"))
    | map .length
    | println
    )
)

(alert "\nGetting the main wikipedia page ${reps} times using async/await")

(time
    (repeat-all reps (http/getAsync "https://wikipedia.org")
    | await
    | map .length
    | println)
)

(alert "\n\nGetting the main Wikipedia page once using Invoke-WebRequest")

(time
    (Invoke-WebRequest "https://wikipedia.org"
    | map .statuscode
    | println)
)

