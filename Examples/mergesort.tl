;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Tail-recursive implementation of merge sort in Braid.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

lambda

[(^int numItems 500)]
;
; Tail-recursive merge-list that merges two sorted lists together.
;
(defn merge-list
    | x:xs y:ys  (r null) :where (< x y) -> (recur xs %1 (splice r x))
    | x:xs y:ys  (r null)                -> (recur %0 ys (splice r y))
    | l1   null  (r null)                -> (splice r l1)
    | null l2    (r null)                -> (splice r l2)
    | -> (throw "invalid arguments to 'merge-list'. Thus function requires two sorted enumerable lists to merge.")
)

;
; Tail-recursive merge-sort function.
;
(defn merge-sort
    | x:     null -> x                                      ; if it's a 1 element list and r is empty we're done
    | x:     r    -> (recur (cons x r) null)                ; if it's a 1 element list and r not empty, join x to r and recurse
    | x:y:   r    -> (recur (cons (merge-list x y) r) null) ; merge the last pair, then recurse with all the sublists
    | x:y:zs r    -> (recur zs (cons (merge-list x y) r))   ; merge each pair of sublists into r
    | xs          -> (recur (map xs list) null)             ; split list into a list of 1 element lists
    | nil    _    -> nil                                    ; if the argument is nil, return nil
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Testing the routines
;

; use a nested scope to run the tests so the file can be loaded with minimal
; contamination of the caller's scope.
(let []
    ; First test the merge-list routine.
    (alert "Testing merge-list; result should be: (1 2 3 4 5 6 7)")
    (println (merge-list [1 2 5] [3 4 6 7]))


    ; Then test merge-sort itself.
    (alert "Testing merge-sort; result should be: (1 2 3 4 5 6 7 8 9)")
    (println (merge-sort [7 5 9 1 8 3 2 4 6]))

    ; test numItems items; throw if it fails
    (alert "Testing ${numItems} items:")
    (let data (random numItems))
    (if (== (merge-sort data) (sort data))
        (alert "\tpassed.")
        (throw "merge-sort failed!")
    )
)

