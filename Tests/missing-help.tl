;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; A Braid script to detect functions for which
; there is no help documentation. This script
; operates against the currently loaded functions.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

lambda [(^regex filterPattern #".")]

(functions
| filter -not (fn f -> (doc (.value f)))
| map .key
| filter filterPattern
| list/WrapPrint info
)

