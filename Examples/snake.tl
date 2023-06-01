;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; A Braid script that implements a variation on the arcade game 'Snake'.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

lambda [
    :numPellets:     ; number of pellets to consume
    :delay:          ; delay between movements
    :game-time:      ; how long the game lasts
]

(using-module Console)

;
; Process defaults for the game
;

(let-default numPellets  15)
(let-default delay      150)
(let-default game-time  150)

;
; Initial list of segments that make up the snake's body
; where body elements are '=' and the head is '@' e.g. =====@
;
(let SegmentList
    [
        [13 25] ; the end of the tail.
        [14 25]
        [15 25]
        [16 25]
        [17 25]
        [18 25]
        [19 25]
        [20 25]
        [21 25] ; the head @ is the last segment in the list
    ]
)

;
; The direction the snake is currently moving in (e -east - by default)
;
(let Direction  "e")

;
; Function to draw the snake on the screen. Uses 'recur'
; instead of an imperative loop. Print the snake from the
; head (@) to the tail (=) (i.e backwards)
;
(defn Render 
    [(segcount (-- (count SegmentList))) (charToPrint "@")]

    (Console/writeat @(SegmentList segcount) charToPrint)

    (if (> segcount 0)
        (recur (-- segcount) "=")
    )
)

;
; Move the snake one cell forward in the current direction.
;
(defn Move
    []

    ; See if the snake ate a pellet i.e. the head location is the same as the tail location.
    (let atePellet (CheckForPellet (last SegmentList)))
    (let tl nil)

    ; If we didn't get a pellet, remove the last segment
    (unless atePellet
        (let tl (!! SegmentList 0))
        (Console/writeat @tl " ")
        (.removeat SegmentList 0)
    )

    ; Duplicate the head of the snake so we can update it.
    (let lst (last SegmentList)) 
    (let snakeHead [ @lst ])
    (matchp Direction
         | "n" ->
            (if (>= (snakeHead 1) (- (.Console/WindowHeight) 2))
                (def Direction "e")
                (snakeHead 1 (++ (snakeHead 1)))
            )
    
         | "s" ->
            (if (<= (snakeHead 1) 0)
                (def Direction "w")
                (snakeHead 1 (-- (snakeHead 1)))
            )
    
         | "e" ->
            (if (>= (++ (first snakeHead)) (.Console/WindowWidth))
                (def Direction "s")
                (snakeHead 0 (++ (first snakeHead)))
            )
    
         | "w" ->
            (if (< (-- (first snakeHead)) 0)
                (def Direction "n")
                (snakeHead 0 (-- (first snakeHead)))
            )
    )

    (.add SegmentList snakeHead)

    (render)
)

(let Score 0)   ; multiple of the number of pellets consumed

(let Pellets [])  ; List of the pellet locations

(let StatusColor .ConsoleColor/cyan)

; Function to show the game status.
(defn ShowStatus
    []

    (let oldFg (.Console/ForeGroundColor))
    (let secondsRemaining (timeRemaining | .totalSeconds | ^int?))

    (let StatusColor 
        (if (<= secondsRemaining 30)
            ; If time is running out, blink the status bar red and yellow.
            (if (== Statuscolor .ConsoleColor/yellow) .consolecolor/red .consolecolor/yellow)
            (.Consolecolor/cyan)
        )
    )
    
    (.Console/ForegroundColor Statuscolor)
    (Console/writeat 0 (- (.Console/WindowHeight) 1)
        (.string/format
            "Score: {0,3} Pellets remaining {1,3} Time remaining: {2,3} seconds.    "
            score
            (length pellets)
            secondsRemaining
        )
    )
    (.Console/ForegroundColor oldFg)
)

;
; Initialize the pellet field
;
(defn Initialize []
    ; Generate the pellet locations by taking two random lists and zipping them together.
    (let snake_len (length SegmentList))
    (let oldFg (.Console/ForeGroundColor))

    (def pellets
        (random (+ numpellets snake_len) 1 (.Console/WindowWidth)
        | zip (random (+ numPellets snake_len) 1 (- (.Console/WindowHeight) 3))
        ; make sure none of them land on the snake
        | filter -not (fn p -> (contains? SegmentList p))
        | first numPellets
        )
    )
    
    ; Then draw the pellets on the screen.
    (.Console/ForegroundColor .ConsoleColor/green)
    (foreach p pellets
        (Console/writeat @p "o")
    )

    (.Console/ForegroundColor oldFg)
    (ShowStatus)
)

(let ColorList [.Consolecolor/yellow .Consolecolor/green .Consolecolor/cyan .Consolecolor/magenta .Consolecolor/red])
(let ColorIndex 0)

(defn NextColor []
    (def colorIndex (% (+ colorIndex 1) (length ColorList)))
    (ColorList ColorIndex)
)

;
; Function that handles the case where the snake eats a pellet.
; Does the eating animation.
;
(defn CheckForPellet [location]
    ; See if the pellet list contains this location
    (if (contains? Pellets location)
        (do
            ; If so, show the eating animation
            (let oldFg (.Console/ForeGroundColor))

            (foreach it (range 0 3)
                (.Console/ForegroundColor .ConsoleColor/red)
                (Console/writeat @location "X")
                (sleep 75)
                (Console/writeat @location "+")
                (sleep 75)
            )

            (.Console/ForegroundColor oldFg)

            ; Increment the score
            (incr score 10)

            ; And remove the pellet from the list.
            (def Pellets (Pellets | filter (!= location)))
            (showStatus)

            ; Change the snakes color
            (.Console/ForegroundColor (NextColor))
            true
        )
        (do
            (showStatus)
            false
        )
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; The main game loop.
;

(def oldFg (.Console/ForeGroundColor))

(try
    -finally: (fn e ->
        (.Console/CursorVisible true)
        (Console/ForeColor oldFg)
        (error "Snake error:" e)
    )

    (cls)
    (.Console/CursorVisible false)

    (def key
        (.key
            (Announce
                (.string/format (qstr
                    Welcome to the Snake Game. Your job is to guide the snake 
                    over the playing field so it can eat all of the food pellets.
                    If you get all of the pellets before the time runs "out," you
                    win! In this game, you have to eat "{0}" pellets 
                    in "{1}" seconds. Use the arrow keys to control the 
                    "snake's" direction, the space bar will cause the snake to have a burst of speed. 
                    You can quit at any time by pressing "'q'". Get ready to play!)
                        numPellets game-time 
                )
                "green"
            )
        )
    )

    (if (== key "q")
        (do
            (cls)
            (println "Thanks for playing! Bye bye!")
            (return)
        )
    )

    (cls)
    (let fastCount 0)   ; The number of iterations to move the snake quickly.
    (.Console/ForegroundColor .ConsoleColor/yellow)
    (let endTime (.datetime/now | .AddSeconds game-time))
    (let timeRemaining (- endTime  (.datetime/now)))
    (Initialize)
    (Render)
    (while true
        (Move)
        (let timeRemaining (- endTime  (.datetime/now)))

        ; If time runs out, you lose.
        (when (<= timeRemaining 0)
            (let msg (.string/format
                "Time has run out and the game is over! You earned {0} points; There were {1} pellets left."
                    score (length pellets)))
            (Announce msg "yellow")
            (cls)
            (break)
        )

        ; If the pellet count is zero, you win the game.
        (if (zero? (length pellets))
            (do
                (Announce
                    (str
                        "Game over! You win with " Score " points "
                        "and " (^int? (. timeRemaining 'TotalSeconds))
                        " seconds left. Congratulations!"
                    )
                    "green"
                )

                (cls)
                (break)
            )
        )

        ; Figure out if we should iterate slow or fast.
        (if (== fastCount 0)
            (sleep delay)
            (decr fastCount)
        )

        ; Process the user key presses.
        (if (.Console/KeyAvailable)
            (matchp (.Console/ReadKey true)
                | {Key .Consolekey/LeftArrow}  -> (def Direction "w")
                | {Key .Consolekey/RightArrow} -> (def Direction "e")
                | {Key .Consolekey/UpArrow}    -> (def Direction "s")
                | {Key .Consolekey/DownArrow}  -> (def Direction "n")
                | {Key .Consolekey/f}          -> (def FastCount 20)
                | {Key .Consolekey/Spacebar}   -> (def FastCount 20)
                | {Key .Consolekey/q}          ->
                                  (Announce "Thanks for playing! Hope you had a good time!")
                                  (cls)
                                  (break)
                |                              -> ; ignore all other key presses
            )
        )
    )
) ; try

(.Console/CursorVisible true)
(Console/ForeColor oldFg)
(println "Bye bye!")

