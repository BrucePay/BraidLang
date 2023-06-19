;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Braid script to draw the Mandelbrot set on the console.
; (Translated from the PowerShell original.)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(let screenY         40.0)
(let screenX         80.0)

(let minReal         -2.0)
(let maxReal          1.0)
(let minImaginary    -1.2)
(let MaxImaginary     1.2)

(let realFactor      (/
                        (- maxReal minReal )
                        (- screenX 1.0 )))

(let imaginaryFactor (/
                        (- MaxImaginary minImaginary)
                        (- screenY 1.0)))

(let cImaginary      0.0)
(let cReal           0.0)

(let zReal           0.0)
(let zImaginary      0.0)

(let zRealSq         0.0)
(let zImaginarySq    0.0)

(let interCount      0)
(let xOrd            0)
(let yOrd            0)
(let bailout        16)

;
; Map an int to a valid color
;
(let color-map [
        .ConsoleColor/Blue
        .ConsoleColor/DarkBlue
        .ConsoleColor/Green
        .ConsoleColor/DarkGreen
        .ConsoleColor/Cyan
        .ConsoleColor/DarkCyan
        .ConsoleColor/Yellow
        .ConsoleColor/DarkYellow
        .ConsoleColor/Gray
        .ConsoleColor/DarkGray
        .ConsoleColor/Magenta
        .ConsoleColor/DarkMagenta
        .ConsoleColor/Red
        .ConsoleColor/DarkRed
        .ConsoleColor/White
        .ConsoleColor/Black
    ]
)

(let oldBackgroundColor .console/backgroundcolor)
(let oldForegroundColor .console/foregroundcolor)

(console/BackColor "black")

(.Console/clear)

(while (< yOrd  (/ screenY 2))
    (let cImaginary (- MaxImaginary (* yOrd imaginaryFactor)))
    
    (let xOrd 0)
    (while (< xOrd  screenX)
        (let cReal (+ minReal (* xOrd realFactor)))

        (let zReal cReal)
        (let zImaginary cImaginary)
        
        (let interCount  0)
        (while (< interCount bailout)
            (let zRealSq (* zReal zReal))
            (let zImaginarySq (* zImaginary zImaginary))
            
            (if (> (+ zRealSq  zImaginarySq) 4)
                (break)
            )

            (let zImaginary (+ (* 2.0  zReal zImaginary) cImaginary))
            (let zReal (+ (- zRealSq zImaginarySq) cReal))
            (incr interCount)
        )
        
        (when (< interCount bailout)
            (let col (!! color-map (% interCount 15)))
            (printat -bg: col xOrd yOrd " ")
            (printat -bg: col xOrd (-- (- screenY yOrd)) " ")
        )

        (incr xOrd)
    )
    (incr yOrd)
)

(console/BackColor oldBackgroundColor) 
(console/ForeColor oldForegroundColor)
(console/WriteAt 0 (+ screenY 1) "All done 'mandel'!\n")

