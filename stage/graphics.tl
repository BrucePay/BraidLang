;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; A small set of utility functions for working with Windows Forms Graphics
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;
; Load the Windows Forms utilities 
;
(using-module winforms)

(unless (bound? 'Graphics/Stack)
    (let Graphics/Stack (new ^System.Collections.Stack))
)

(let LastLastX 0)
(let LastLastY 0)
(let LastX     0)
(let LastY     0)

;
; Function for creating the drawing pen
;
(let DrawingPen null)
(defn Graphics/SetPen
"Set the default drawing pen."
    [(^int width) (^System.Drawing.Color? color)]

    (if DrawingPen (.Dispose DrawingPen))
    (def DrawingPen (new ^System.Drawing.Pen color))
    (.width DrawingPen Width)
)

;
; Function for setting the drawing background color
;
(let DrawingBrush null)
(defn Graphics/SetBackgroundColor
"Set the background color on the drawing surface."
    [(^System.Drawing.Color? color)]

    (def DrawingBrush (new ^System.Drawing.SolidBrush? color))
    (.fillRectangle graphics/formGraphics DrawingBrush rec)
)

;
; Draw a line
;
(let graphics/formGraphics null)
(defn Graphics/DrawLine
"Draw a line from [x1 y1] to [x2 y2]."
    [ x1 y1 x2 y2 ]

    (if (null? graphics/formGraphics)
        (throw "Graphics/DrawLine: graphics object is not initialized")
    )
    (.drawLine graphics/formGraphics DrawingPen (^int x1) (^int y1) (^int x2) (^int y2))
    (.System.Windows.Forms.Application/doEvents)
    (def LastLastX LastX)
    (def LastLastY LastY)
    (def LastX x2)
    (def LastY y2)
)

(defn Graphics/DrawTo
"Draw starting from the last location."
    [x2 y2]

    (Graphics/DrawLine LastX LastY x2 y2)
)

(defn Graphics/MoveTo
"Move the drawing pen to a new location."
    [x1 y1]

    (def LastX x1)
    (def LastY y1)
)

;
; Variables used for the drawing surface
;
(let DrawingSurface null)
(let opacity 1.0)
(let FormSize null)
(let cx 0)
(let cy 0)
(let rec null)
(let ^double LastAngle 0.0)
(def Graphics/Stack (new ^System.Collections.Stack 0))

(defn Graphics/CreateDrawingSurface
"Function to create the drawing surface."
    [x y]

    ; Create the drawing surface form
    (def opacity 1.0)
    (def FormSize (wf/size x y))
    (def DrawingSurface (wf/form 
            :Text "Drawing Surface -- Click the X to exit."
            :TopMost true
            :Opacity opacity
            :Size formSize
            :OnClick (fn o e -> (.close DrawingSurface))
        )
    )

    ; create the drawing surface with same size as the form
    (def cx (.ClientRectangle DrawingSurface | .Width))
    (def cy (.ClientRectangle DrawingSurface | .Height))
    (def rec (new ^System.Drawing.Rectangle 0 0 cx cy ))
    (def graphics/formGraphics (.CreateGraphics DrawingSurface))
    (def LastX 0)
    (def LastY 0)
    (def LastLastX 0)
    (def LastLastY 0)
    (def LastAngle 0.0)
    (if DrawingPen (.dispose DrawingPen))
    (def DrawingPen null)
    (if DrawingBrush (.dispose DrawingBrush))
    (def DrawingBrush null)
    (def Graphics/Stack (new ^System.Collections.Stack 0))
)

(defn Graphics/ShowDrawingSurface
"Show the drawing surface."
    []

    (.ShowDialog DrawingSurface)
    (.dispose DrawingSurface)
    (def DrawingSurface null)
    (if DrawingPen (.dispose DrawingPen))
    (def DrawingPen null)
    (if DrawingBrush (.dispose DrawingBrush))
    (def DrawingBrush null)
    (def LastX 0)
    (def LastY 0)
    (def LastLastX 0)
    (def LastLastY 0)
    (def LastAngle 0.0)
)

(defn Graphics/SetDrawingScript
"Set the script that will draw on the form."
    [drawingFunction]

    (if (null? drawingFunction)
        (throw "Graphics/SetDrawingScript: Drawing script was null")
    )

    (.add_Shown DrawingSurface
        (asEventHandler
            (lambda [o e]
                (graphics/SetBackgroundColor .system.drawing.color/black)
                (Graphics/SetPen 2 .drawing.color/white)

                ; call the closed-over script
                (drawingFunction)
                (.update DrawingSurface)
            )
        )
    )
)

(defn Graphics/DrawPicture
"
Show an x by y drawing surface and execute the argument function.
"
    [x y drawingFunction]

    (Graphics/CreateDrawingSurface x y)
    (Graphics/SetDrawingScript drawingFunction)
    (graphics/ShowDrawingSurface)
)


;-------------------------------------------------------------------
;
; Turtle graphics functions
;

(unless (bound? 'graphics-conversion-factor)
    (const graphics-conversion-factor (2.0 | * .math/pi | / 360))
)

(defn graphics/PolarToCartesian
"Utility to convert polar to cartesian coordinates."
    [angle length]

    (let angle (* angle graphics-conversion-factor))
    [
        (angle | .math/cos | * length | ^int?)
        (angle | .math/sin | * length | ^int?)
    ]
)

;
; Save the turtle context as an vector of 3 elements on the stack
;
(defn Graphics/PushContext []
    (.push Graphics/Stack [ LastX LastY LastAngle ])
)

;
; Restore the saved turtle context
;
(defn Graphics/PopContext []
    (let context (.pop Graphics/Stack))
    (def LastX:LastY:LastAngle: context)
)

; Turn right (positive angle)
;
(defn Graphics/Turtle-Right [degrees]
    (def LastAngle (LastAngle | + degrees | % 360 | ^double?))
)

;
; Turn left (negative angle)
;
(defn Graphics/Turtle-Left [degrees]
    (def LastAngle (LastAngle | - degrees | % 360 | ^double?))
)

;
; Move forward drawing a line.
;
(defn Graphics/Turtle-Forward [length]
    (let coordx:coordy: (graphics/PolarToCartesian LastAngle length))
    (Graphics/DrawTo (+  LastX coordX) (+  LastY coordy))
)

