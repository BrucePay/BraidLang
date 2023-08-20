;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; A collection of utilities for working with the console.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;
; Line drawing characters for drawing boxes.
;
(let *line-chars* {
        :horizontal         (^char? 0x2550)
        :vertical           (^char? 0x2551)
        :top-left-corner    (^char? 0x2554)
        :bottom-left-corner (^char? 0x255A)
        :top-right-corner   (^char? 0x2557)
        :bottom-right-corner (^char? 0x255D)
        :top-join           (^char? 0x2566)
        :bottom-join        (^char? 0x2569)
    }
)

(defn Chomp
"
Split a string into 'num' length segments. Splitting is done on whitespace.
"
    [str (^int num 40)]

    (if (> num (length str))
        ; if the line is shorter than the string just return
        (defobject first str rest "")
        (do
            (while (< num (length str))
                (if (.char/IsWhiteSpace (!! str num))
                    (break)
                )
                (incr num)
            )
            (defobject
                first (.substring str 0 (as num ^int))
                rest (.substring str (as num ^int))
            )
        )
    )
)

(defn ChompAll
"
Split a string into specified length segments.
"
    [str (^int num 40)]

    (with [ allResults [] result nil ]

        (while true
            (def result (chomp str num))
            (.add allResults (.trim (. result 'first)))
            (if (not (. result 'rest))
                (break)
            )
            (def str (. result 'rest))
        )
        allResults
    )
)

(defn DrawBox
"
Draw a box on the screen.
"
    [x y width height (^ConsoleColor? color (console/forecolor))]

    (let oldfg (.console/ForeGroundColor))

    ; First clear the box area
    (let spaces (* " " width))
    (foreach it (range y (+ y height))
        (printat x y spaces)
    )

    (let hlines (* (str (*line-chars* :Horizontal)) width))

    ; Then draw the box.
    (.console/foregroundcolor color)

    ; Print the top
    (printat x y hlines)

    ; print the sides
    (foreach it (range y (+ y height))
        (printat x it (*line-chars* :Vertical))
        (printat (+ x width) it (*line-chars* :Vertical))
    )

    ; print the bottom
    (printat x (+ y height) hlines)

    ; finally print the corners
    (printat x y  (*line-chars* :top-left-corner))
    (printat (+ x width) y (*line-chars* :top-right-corner))
    (printat x (+ y height) (*line-chars* :bottom-left-corner))
    (printat (+ x width) (+ y height) (*line-chars* :bottom-right-corner))

    (.console/ForegroundColor oldfg)
    null
)

(defn console/readkey []
    (let key (.console/readkey true))
    [(.keychar key) (.key key) (tostring (.modifiers key))]
)

(defn Announce
"
Show an announcement in a box at the center of screen, surrounded by a box. The
content will be broken up to fit the size of the box.
"
    [ (^string? msg) (^ConsoleColor? color (.console/ForeGroundColor)) (^int width 40)]

    (with [
            oldFg      (.console/ForegroundColor)
            linewidth  0
            height     0
            line       ""
            x          0
            y          0
        ]

        ; split the message into chunks
        (let width (if (< width 40) 40 width ))
        (let width (if (> width (- (.console/WindowWidth) 4)) (- (.console/WindowWidth) 4) width))
        (let msg (echo (.trim msg) | re/replace "[ \n\t]+" " " | ChompAll width))

        ; Get the width of the longest line.
        (let linewidth (max-list msg .length | length | + 4))
        (let width (max linewidth width))

        (.add msg "")
        (.add msg (+ (* " " (.math/round (as (/ (- width 30) 2) ^decimal))) "Press any key to continue."))
        (let height (+ 4 (length msg)))

        (let x (.console/WindowWidth  | - width  | / 2 | ^int?))
        (let y (.console/WindowHeight | - height | / 2 | ^int?))

        ; Erase the announcement area.
        (let line (* " " width))
        (foreach y1 (range y (+ y height))
            (printAt x y1 line)
        )

        ; Draw the outline.
        (DrawBox x y width height color)

        ; Write the text inside the box
        (incr x 3)
        (incr y 2)
        ;(try
            (.console/ForegroundColor color)
            (foreach line msg
                (printat x y line)
                (incr y)
            )
            ;-finally: (do
                (.console/ForegroundColor oldFg)
                (.console/SetCursorPosition 0 0)
            ;)
        ;)
        (.console/readkey true)
    )
)


