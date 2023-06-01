;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Examples using the turtle from the graphics module
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

lambda []

(using-module graphics)

;
; Draw a multi-colored square
;
(defn drawturtlesquare []
    (Graphics/DrawPicture 600 500 (fn ->
            (Graphics/moveto 100 100)
            (Graphics/SetPen 3 (.system.drawing.color/Yellow))
            (Graphics/Turtle-Forward 300)
            (Graphics/Turtle-Right 90)
            (Graphics/SetPen 3 (.system.drawing.color/Green))
            (Graphics/Turtle-Forward 300)
            (Graphics/Turtle-Right 90)
            (Graphics/SetPen 3 (.system.drawing.color/Cyan))
            (Graphics/Turtle-Forward 300)
            (Graphics/Turtle-Right 90)
            (Graphics/SetPen 3 (.system.drawing.color/Red))
            (Graphics/Turtle-Forward 300)
        )
    )
)

;
; Draw a turtle circle
;
(defn drawCircle []
    (Graphics/DrawPicture 500 500 (fn ->
            (Graphics/moveto 250 100)
            (repeat 100
                (Graphics/Turtle-Forward 10)
                (Graphics/Turtle-Right 5)
            )
        )
    )
)

;
; Rotating squares
;
(defn rotating-squares []
    (Graphics/DrawPicture 500 500 (fn ->
            (Graphics/moveto 250 250)

            ; function to draw a square with sides 
            (defn drawsquare [size]
                (repeat 3
                    (Graphics/Turtle-Forward size)
                    (Graphics/Turtle-Right 90))
            )
        
            (defn drawsquares [number_of_times size]
                (repeat number_of_times 
                    (drawsquare size)        ; draw the square  
                    (incr size 3)            ; make the size of :size 2 step bigger
                    (Graphics/Turtle-Right 3)             ; between each square
                )
            )
        
            (drawsquares 100 5)
        )
    )
)


;
; Wheel of color
;
(defn drawwheelOfColor []
    (Graphics/DrawPicture 600 600 (fn ->
            (foreach item [
                    (.System.Drawing.Color/red) 
                    (.System.Drawing.Color/blue) 
                    (.System.Drawing.Color/yellow) 
                    (.System.Drawing.Color/green) 
                ]
    
                (Graphics/SetPen 5 item)
                (foreach n (range 150)
                    (Graphics/MoveTo 300 300)
                    (Graphics/Turtle-Right 8)
                    (Graphics/Turtle-Forward (* n 2))
                )
            )
        )
    )
)

;
; Spiraling star
;
(defn DrawSpiralingStar []
    (Graphics/DrawPicture 500 500 (fn ->
            (Graphics/moveto  250 250)
            (foreach item (range 40)
                (Graphics/Turtle-Forward (* item 10))
                (Graphics/Turtle-Right 144)
            )
        )
    )
)

;
; Draw Serpienski's Gasket using the Turtle
;
(defn drawgasket [n]

    (defn sierpinski
        | 0 _ -> 
        | n length ->
            (repeat 3
                (Graphics/PushContext)
                (sierpinski (-- n)  (/ length 2))
                (Graphics/PopContext)
                (Graphics/Turtle-Forward length)
                (Graphics/Turtle-Right 120)
            )
    )
    
    (Graphics/DrawPicture 500 500 (fn ->
            (Graphics/moveto 50 50)
            (Graphics/setpen 2 (.system.drawing.color/orange)) 
            (sierpinski n 400)
        )
    )
)

;
; Draw the Snowflake Fractal 
;
(defn drawsnowflake []
    (Graphics/drawpicture 500 500 (fn ->
            (Graphics/setpen 2 (.system.drawing.color/lightblue)) 
            (Graphics/moveto 100 150) 
        
            (defn snowflake_side [length depth]
                (if depth
                    (do
                        (decr depth)
                        (let length (= length / 3))
                        (snowflake_side length depth)
                        (Graphics/Turtle-Left 60)
                        (snowflake_side length depth)
                        (Graphics/Turtle-Right 120)
                        (snowflake_side length depth)
                        (Graphics/Turtle-Left 60)
                        (snowflake_side length depth)
                    )
                    (do
                        (Graphics/Turtle-Forward length)
                    )
                )
            )
            
            (defn snowflake [length depth]
                (repeat 4
                    (snowflake_side length depth)
                    (Graphics/Turtle-Right 120)
                )
            )
        
            (snowflake 300 4)
        )
    )
)

;
; Draw a fractal tree using the Turtle
;
(defn drawfractal []
    (Graphics/drawpicture 600 600
        (fn ->
            (defn tree [len angle st]
                (if (>= len st)
                    (do
                        (Graphics/PushContext)
                        (let len (= len / 2))
                        (Graphics/Turtle-Forward len)
                        (Graphics/Turtle-Left angle)
                        (tree len angle st)
                        (Graphics/Turtle-Right angle)
                        (tree len angle st)
                        (Graphics/Turtle-Right angle)
                        (tree len angle st)
                        (Graphics/Turtle-Left angle)
                        ; Restore the previous position; equivalent of back...
                        (Graphics/PopContext)
                    )
                )
            )
        
            (Graphics/SetBackgroundColor (.System.Drawing.Color/black))
            (Graphics/MoveTo 0 300)
            (Graphics/SetPen 1 (.system.drawing.color/lightgreen)) 
            (tree 400 50 3)
        )
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Create the menu form for the demos.

(wf/button-stack "Turtle Graphics Demos"
    "Draw a Square"             drawturtlesquare
    "Draw a Circle"             drawCircle
    "Draw Spiraling Squares"    rotating-squares
    "Wheel of Color"            drawwheelofcolor
    "Draw a Star"               drawspiralingstar
    "Sierpinski's Triangle" #(drawgasket 5)
    "Snowflake Fractal"         drawsnowflake
    "Fractal Tree"              drawfractal
)
