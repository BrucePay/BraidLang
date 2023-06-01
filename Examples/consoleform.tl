;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Module that lets you build fullscreen forms on the console
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(using-module console)

;---------------------------------------------------
;
; define the "widget" types
;
;---------------------------------------------------

;
; base type for inactive widgets like label and box
;
(deftype ^Inactive)

;
; Define the label widget
;
(defType ^label -extends: ^Inactive
    ^int x
    ^int y
    ^string text

    :defm render (fn this ->
        (console/writeat -foreground: "cyan" (.x this) (.y this) (.text this))
    )
)

;
; Define a box render object
;
(deftype ^box -extends: ^Inactive
    ^int x
    ^int y
    ^int length
    ^int width
    ^consolecolor? color

    :defm render (fn this ->
        (drawbox (.x this) (.y this) (.length this) (.width this) (.color this))
    )

    :defm new (fn this x y length width (^consolecolor? color) ->
        (this
        | .x x
        | .y y
        | .length length
        | .width width
        | .color color
        )
    )
)

;
; Define the button widget
;
(deftype ^button 
    ^int x
    ^int Y
    ^string text
    ^int width
    Action          ; Holds a callback that implements the button's action.
                    ; It's called with the parent control as it's first parameter

    :defm render (fn this ->
        ; center and frame the button
        (let pad (^int (/ (- (.width this) (length (.text this))) 2)))
        (let text (str "<" (* " " pad) (.text this) (* " " pad) ">"))
        (console/writeat (.x this) (.y this) text)
    )

    :defm Activate (fn this ->
        (let oldfg (.console/foregroundcolor))
        (let oldbg (.console/backgroundcolor))
        (.console/foregroundcolor .consolecolor/black)
        (.console/backgroundcolor .consolecolor/yellow)
        (.render this)

        (let keypress "")
        (matchp @(console/readkey)
        | _ "DownArrow" _ ->
            (let keypress ["DownArrow"])

        | _ "UpArrow" _ -> 
            (let keypress ["UpArrow"])

        | _ "LeftArrow" _  -> 
            (let keypress ["LeftArrow"])

        | _ "RightArrow" _ ->
            (let keypress ["RightArrow"])

        | _ "Enter" _ ->
            (let keypress ["Action" (.action this)])

        | _ "SpaceBar" _ ->
            (let keypress ["Action" (.action this)])

        | _ "Tab" "Shift" ->
            (let keypress ["ShiftTab"])

        | _ "Tab" _ ->
            (let keypress ["Tab"])

        | _ "Escape" _ ->
            (let KeyPress ["Escape"])

        | -> ; ignore all of the other keys
        ) 

        (.console/foregroundcolor oldFg)
        (.console/backgroundcolor oldBg)
        (.render this)
        keypress
    )
)

;
; Define the editable field widget
;
(deftype ^Field
    ^int x
    ^int y
    ^string Name
    ^int Width
    ^string CurrentText
    ^string HelpText

    ; Method to render the field
    :defm render (fn this ->
        (console/writeat (-- (.x this)) (.y this) (str "[" (* " " (.width this)) "]"))
        (console/writeat (.x this) (.y this) (.currenttext this))
    )

    :defm Activate (fn this ->

        (let result (.CurrentText this))
        (let keypress "")
        (let oldfg (.console/foregroundcolor))
        (let oldbg (.console/backgroundcolor))
        (let oldCursor (.console/cursorvisible))

        (try 
            (.console/foregroundcolor oldBg)
            (.console/backgroundcolor oldFg)
            (.console/cursorSize 25)
            (.console/cursorvisible true)

            (.console/SetCursorPosition (.x this) (.y this))
            (let pos (.console/cursorleft))
            (let endx (.x this | + (.width this) | - 1))
            (let loop true)
            (while loop
                ; first blank the field, then write it
                (console/writeat (.x this) (.y this) (* " " (.width this)))
                (console/writeat (.x this) (.y this) (.currenttext this))
                (.console/setcursorposition (^int pos) (.y this))
    
                (let maxtext (+ (.x this) (length (.currenttext this))))
                (matchp @(console/readkey)
                | _ "DownArrow" _ ->
                    (let KeyPress "DownArrow")
                    (let loop false)
    
                | _ "UpArrow" _ -> 
                    (let KeyPress "UpArrow")
                    (let loop false)
    
                | _ "LeftArrow" _  -> 
                    (.console/setcursorposition (^int (decr pos)) (.y this))
                        (when (< pos (.x this)) (let pos (.x this)))
    
                | _ "RightArrow" _ ->
                    (.console/setcursorposition (^int (incr pos)) (.y this))
                        (when (> pos maxtext) (let pos maxtext))
    
                | _ "End" _ ->
                    (let pos maxtext)

                | _ "Home" _ ->
                    (let pos (.x this))

                | _ "Enter" _ -> 
                    (let result (.currenttext this))
                    (let KeyPress "Enter")
                    (let loop false)
    
                | _ "Escape" _ ->
                    (let KeyPress "Escape")
                    (let loop false)

                | _ "Tab" "Shift" ->
                    (let KeyPress "ShiftTab")
                    (let loop false)
       
                | _ "Tab" _ ->
                    (let KeyPress "Tab")
                    (let loop false)
    
                | _ "Backspace" _ ->
                        (let deletePos (- (^int32 pos) (.x this)))
                        (when (> deletePos 0)
                            (let text (.currentText this))
                            (let text
                                (str
                                    (.substring text 0 (- deletePos 1))
                                    (.substring text deletePos)
                                )
                            )
                            (.currentText this text)
                            (decr pos)
                            (when (< pos (.x this))
                                (let pos (.x this))
                            )
                        )
                    
                | key _ _ ->
                    (when (re/match key #"[0-9a-z _]")
                        (let insertPos (- (^int32 pos) (.x this)))
                        (let text (.currentText this))
                        (let text (str (.substring text 0 insertPos) key (.substring text insertPos)))
                        (when (length text | < (.width this))
                            (.currentText this text)
                            (incr pos)
                            (when (> pos endx)
                                (let pos endx)
                            )
                        )
                    )
                | -> ; ignore everything else
                )
            )

   
        -finally:
            (do 
                (.console/foregroundcolor oldFg)
                (.console/backgroundcolor oldBg)
                (.console/cursorvisible oldCUrsor)
                (.render this)
            )
        ) ; try
       [keypress result]
    )
)

;---------------------------------------------------
;
; The console form class. This is the one you actually
; work with
;
(deftype ^ConsoleForm

    ; The form title
    ^string Title

    ; All renderable form elements (label, button and field)
    ^Vector Elements

    ; All activatable form elements (button and field)
    ^IDictionary Fields

    ; Index of the current form element
    ^int Index

    :defm new (fn this title -> (this | .Elements [] | .Fields {} | .Title title))

    :defm AddField (fn this x y name width initialText helpText ->
        (let field (new ^field x y name width initialText helptext))
        (!! (.fields this) name field)
        (.Elements this | .add field)
        this
    )

    :defm AddLabel (fn this x y text ->
        (let label (new ^Label x y text))
        (.Elements this | .add label)
        this
    )

    :defm AddBox (fn this x y length width color ->
        (let box (new ^Box x y length width "cyan"))
        (.Elements this | .add box)
        this
    )
        

    :defm AddButton (fn this x y text width action ->
        (let button (new ^button x y text width action))
        (.Elements this | .add button)
        this
    )

    ; method to move to the next activatable field
    :defm _moveNext (fn this inc ->
        (when (.Elements this)
            (.index this (% (+ (.index this) inc) (length (.Elements this))))
            (while (!! (.Elements this) (.index this) | is? ^Inactive)
                (.index this (% (+ (.index this) inc) (length (.Elements this))))
                (if (< (.index this) 0) (.index this (- (length (.Elements this)) 1))) 
            )
            (.render (!! (.elements this) (.index this)))
        )
    )

	; while true, keep looping processing input; exit on false
    ^bool loop

    ; if true return the form contents otherwise return null.
    ^bool accept

    :defm CancelForm (fn this -> (.accept this false) (.loop this false))

    :defm AcceptForm (fn this -> (.accept this true) (.loop this false))

    :defm Activate (fn this ->
        (cls)

        (when (not (.Elements this))
            (return)
        )

        ; render all of the controls
        (foreach f (.elements this) (.render f))

        ; select the first activatable control
        (.index this 0)

        (._moveNext this 1)

        (.loop this true)
        (while (.loop this)
            (let key:val:_ (.activate (!! (.Elements this) (.index this)) | append [ null null null ]))
            (matchp key
            | "Escape"      -> (.loop this false)
            | "LeftArrow"   -> (._MoveNext this -1)
            | "UpArrow"     -> (._MoveNext this -1)
            | "ShiftTab"    -> (._MoveNext this -1)
            | "DownArrow"   -> (._MoveNext this 1)
            | "RightArrow"  -> (._MoveNext this 1)
            | "Tab"         -> (._MoveNext this 1)
            | "Action"      ->
                    ; invoke the lambda returned by the button
                    (val this)
                    (when (.loop this)
                        (cls)
                        (foreach f (.elements this) (.render f))
                    )

            | "Enter" -> 
                (.loop this false)
            | -> ; ignore other keys
            )
        )

        ; get all of the field values and return them
        (let result {})
        (when (.accept this)
            (let result {})
            (foreach f (.Fields this)
                (!! result (.key f) (.CurrentText (.value f)))
            )
        )
        result
    )
)

;---------------------------------------------------
;
; Build some test forms.
;
;---------------------------------------------------

;
; A form that's just a stack of buttons
;
(let optionForm (new ^ConsoleForm "The Menu Form"
    | .addBox 15 4 60 20 "Cyan"
    | .addLabel 20 6 "The Menu Form: Select an Action then hit Enter."
                       ;012345678901234567890123456789
    | .addButton 30 10 "          Turtle Demo         " 30
        (fn form -> (turtle.tl))
    | .addButton 30 12 "          Snake Game          " 30
        (fn form -> (snake.tl))
    | .addButton 30 14 "         Time and Date        " 30
        (fn form -> (announce "The time and date are:  ${(.datetime/now)}" .consolecolor/cyan))
    | .addButton 30 16 "     Get BIOS Information     " 30
        (fn form -> (announce (get-ciminstance 'win32_bios | out-string) .consolecolor/cyan))
    | .addButton 30 18 "       Tic-Tac-Toe Game       " 30
        (fn form -> (tictactoe.tl))
    | .addButton 30 20 "             Exit             " 30
        (fn form -> (.CancelForm form))
    )
)

;
; The main "address" form.
;
(let addressForm
    (new ^ConsoleForm "Address Form"
    ;| .addLabel 5  6 (* "=" 90)
    | .addBox 3 4 90 20 "Cyan"
    | .addLabel 20 5 "Address Information Form 17b"

    | .addlabel 5 10 "First Name:"
    | .addfield 20 10 "fn" 25 "" "Help text"

    | .addlabel 50 10 "Last Name:"
    | .addfield 65 10 "ln" 25 "" "Help text"

    | .addlabel 5 12 "Address:"
    | .addfield 20 12 "ad"  70 "" "Help text"

    | .addlabel 5 14 "City:"
    | .addfield 20 14 "ci" 15 "Seattle" "Help text"

    | .addlabel 37 14 "State:"
    | .addField 47 14 "st" 15 "Washington" "Help text"

    | .addlabel 65 14 "Country:"
    | .addfield 75 14 "cy" 15 "USA" "Help text"


    ;| .addLabel 5  18 (* "=" 90)

    | .addbutton 20 20 "Accept"  10 (fn form -> (.AcceptForm form))
    | .addbutton 35 20 "Options" 10 (fn form -> (.Activate   optionForm))
    | .addbutton 50 20 "Cancel"  10 (fn form -> (.Cancelform form))
    )
)

(let result (.Activate  addressform))

result

