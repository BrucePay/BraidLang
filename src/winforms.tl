;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; A Small Winforms library in Braid. This library provides helper functions
; for creating and manipulating various types of Windows forms.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;
; First load the WinForms assembly
;
(using-assembly System.Drawing System.Windows.Forms)

(type-alias ^Cursor  ^System.Windows.Forms.Cursor)
(type-alias ^Cursors ^System.Windows.Forms.Cursors)

;---------------------------------------------------------------------------
;
; Bind a function to cycle through a list of colors
;
(let wf/next-color
    (with
        [
            colors
            [
                .System.Drawing.Color/DeepSkyBlue
                .System.Drawing.Color/Red
                .System.Drawing.Color/Violet
                .System.Drawing.Color/Salmon
                .System.Drawing.Color/Indigo
                .System.Drawing.Color/LawnGreen
                .System.Drawing.Color/DarkSalmon
                .System.Drawing.Color/Yellow
                .System.Drawing.Color/Pink
                .System.Drawing.Color/Green
                .System.Drawing.Color/Orange
                .System.Drawing.Color/LightGray
                .System.Drawing.Color/Tan
                .System.Drawing.Color/Blue
                .System.Drawing.Color/White
                .System.Drawing.Color/Fuchsia
                .System.Drawing.Color/Silver
                .System.Drawing.Color/Crimson
                .System.Drawing.Color/LightYellow
                .System.Drawing.Color/Cyan
                .System.Drawing.Color/Gold
                .System.Drawing.Color/SkyBlue
                .System.Drawing.Color/PaleGoldenrod
                .System.Drawing.Color/Turquoise
                .System.Drawing.Color/RosyBrown
            ]
        
            color-index 0
        ]

        (lambda
            ;^System.Drawing.Color
            ;"Get the next colour in the cycle."
            []

            (def color-index (% (++ color-index) (length colors)))
            (!! colors color-index)
        )
    )
)
    
;---------------------------------------------------------------------------
;
(defn wf/point
"
Creates a new WinForms point object.

Examples:
    (wf/Point 15 20)
"
    [(^int? x) (^int? y)] 

    (new ^System.Drawing.Point x y)
)

;---------------------------------------------------------------------------
;
(defn wf/size
"
Creates a WinForms size object.

Examples:
    (wf/size 10 20)
"
    [(^int? x) (^int? y)]

    (new ^System.Drawing.Size x y)
)

;---------------------------------------------------------------------------
;
(defn wf/font
"
Creates a font object from the specified family and size.

Examples:
    (wf/font :Consolas 16)
"
    [(^string? family) (^int? size)]

    (new ^System.Drawing.Font family size)
)

;---------------------------------------------------------------------------
;
(defn wf/menustrip
"
Create a menu strip for a Windows form. The first argument
is the form to add the menu strip to. The second argument is
a list of menus to add to the menu strip.

Examples:
    (wf/menustrip MainForm [
            (wf/menu \"File\"
                [
                    (wf/menuitem \"New Game\" (lambda [e o] (NewGame)))
                    (wf/menuitem \"Quit\"     (lambda [e o] (.Close MainForm)))
                ]
            )
        ]
    )

See also: wf/menu wf/menuitem
"
    [(^System.Windows.Forms.Form form) (^Vector menuItems)]

    (if (not form)
        (throw "wf/menuitem: argument 'form' cannot be null.")
    )

    (let ms
        (wf/control 'MenuStrip
            {
                :Location   (wf/point 0 0)
                :Name       "menuStrip"
                :Size       (wf/Size 292 24)
            }
        )
    )

    (foreach item menuItems
        (.Items ms | .add item)
    )

    (.controls form | .add ms)
    (.MainMenustrip form ms)
)

;---------------------------------------------------------------------------
;
(defn wf/Menu
"
Create a menu with a specific list of items.

Examples:
    (wf/menu :File
        [
            (wf/menuitem \"New Game\" (fn e o -> (NewGame)))
            (wf/menuitem :Quit        (fn e o -> (.Close MainForm)))
        ]
    )
"
    [name menuitems]

    (let menu (wf/control 'ToolStripMenuItem {:Text name}))
    (foreach item (menuitems | where some?) (.DropDownItems menu | .add item))
    menu
)

;---------------------------------------------------------------------------
;
(defn wf/MenuItem
"
Create an individual item to add to a menu. The first argument is the name of
the menu item to create and the second is the lambda that acts as the
event handler for the menu item. The result of this function should be added
to the items on the menu itself.

Examples:
    (wf/menuitem :Quit  (fn e o -> (.Close MainForm)))

See also: wf/Menu wf/MenuStrip
"
    [(^string? name) (^Callable? action)]

    (wf/Control :ToolStripMenuItem :Text name :OnClick (aseventhandler action))
)

;---------------------------------------------------------------------------
;
(defn wf/messagebox
"
Shows a message box on the screen. The default button is OK but
can also be OK, OKCancel, AbortRetryIgnore, YesNoCancel, YesNo or RetryCancel

Examples:
    (wf/message \"The message\" \"The Title\" :OkCancel)
"
    [messageText (title "MessageBox") (buttons "OK")]

    (let buttons (^System.Windows.Forms.MessageBoxButtons? buttons))
    (.System.Windows.Forms.MessageBox/Show messageText title buttons | tostring)
)

;---------------------------------------------------------------------------
;
(defn wf/QuestionBox
"
This function displays a question dialog box containing the question text and
an input field for the user to enter their answer. The last \"owner\" parameter
is optional but can be used to specify the parent form for the question box.

Examples:
    (wf/QuestionBox \"My Title\" \"initial text\")
"
    [message :multiline (title "QuestionBox Box") (initialText "") (owner null) :width: :action:]

    (let dlgresult null)
    (when (not width | or (< width 400))
        (let width 400)
    )
    (let center (/ width 2))

    (let mb
        (wf/control :Form
             :Width             width
             :Height            (if multiline 340 140)
             :Text              title
             :StartPosition     (if (some? owner)
                                    .System.Windows.Forms.FormStartPosition/CenterParent
                                    .System.Windows.Forms.FormStartPosition/CenterScreen
                                )
             :FormBorderStyle   .System.Windows.Forms.FormBorderStyle/FixedDialog
             :Controls [
                 (wf/control :label
                     :Text       message
                     :TextAlign  "middlecenter"
                     :Width      (- width 40)
                     :Anchor     "Top,Left,Right"
                     :Location   (wf/Point  (- center (/ (- width 40) 2)) 10)
                     :Font       (wf/font "Microsoft Sans Serif" 12)
                 )
 
                 (let textBox
                     (wf/control :TextBox
                         :Text      initialText
                         :Multiline (^bool? multiline)
                         :Width     (- width 40)
                         :Anchor    "Top,Left,Right,Bottom"
                         :Location  (wf/Point 10 35)
                         :Font      (wf/font "Courier New" 12)
                         :OnKeyUp   (^System.Windows.Forms.KeyEventHandler?
                                         (fn o e ->
                                             (matchp (.KeyCode e)
                                             | "Return" :where (not multiline) ->
                                                ; for single-line dialogs, handle the enter key
                                                (.Handled e true)
                                                (def dlgresult (.Text textbox))
                                                (.close mb)

                                             | "Escape" ->
                                                (.Handled e true)
                                                (def dlgresult null)
                                                (.close mb)

                                             | -> null
                                                ; for every other key, just continue
                                             )
                                         )
                                    )
                     )
                 )
                 
                 (let buttony 70)

                 (when multiline
                    (.Height textbox 220)
                    (incr buttony 200)
                 )

                 (.focus textbox)
 
                 (wf/control :button
                     :Text       "Ok"
                     :Width      80
                     :Location   (wf/Point (- center 100) buttony)
                     :Anchor     "Bottom,Left,Right"
                     :OnClick    (fn o e ->
                                    (if action
                                       ; if a custom action is supplied, run it
                                       (do
                                           (try
                                               (.Cursor/Current .Cursors/WaitCursor)
                                               (.text mb "Running action...")
                                               (def dlgresult (action mb (.Text textbox)))
                                               (.Cursor/Current .Cursors/default)
                                               (.close mb)
                                               -catch: (fn e ->
                                                   (wf/messagebox (str e) "wf/questionbox Error")
                                                   (def dlgresult "")
                                                   (.Close mb)
                                               )
                                           )
                                       )
                                       ; otherwise run the default action
                                       (do
                                           (def dlgresult (.Text textbox))
                                           (.close mb)
                                       )
                                    )
                                )
                 )

                 (wf/control :button
                     :Text       "Cancel"
                     :Width      80
                     :Location   (wf/Point (+ center 20) buttony)
                     :Anchor     "Bottom,Left,Right"
                     :OnClick    (fn o e ->
                                    (def dlgresult nil)
                                        (.close mb))
                  )
             ]
        )
    )

    (when (some? owner)
        (.owner mb owner)
    )

    ; Show the message box.
    (.showDialog mb)

    ; Return the contents of the text box
    dlgresult
)

;---------------------------------------------------------------------------
;
(defn wf/listbox
"
Function that displays a listbox of options from which the user must
select 1 (or more) items.
    
Examples:
   (wf/listbox \"Choose a file\" -source: #(ls '*.tl) -selectaction: #(gvim %0))
   ; select and stop a process
   (wf/listbox \"Processes\"
        -source: #(get-process | project :id :name :ws | out-string -stream | skip 3)
        -selectaction: #(stop-process -id: (car (.trim (!! %0 0)))))
"
    [title :source: :owner: :multiselect :SelectAction: :Menus: :forecolor:]

    (let-default ^System.Drawing.Color? forecolor .system.drawing.color/green)

    (unless source
        (wf/messagebox "Input list for 'wf/listbox' was empty." "wf/listbox Error")
        (return)
    )

    (if (function? source)
        (let data (source | map tostring))
    )

    ; figure out the size of the listbox based on the content
    (let ^int? lwidth (data | max-list .length | length | * 10))
    (let lwidth (cond
            (< lwidth 300) 300
            (> lwidth 1024) 1024
            true
                lwidth))

    (defn refresh-listbox-data []
        (.System.Windows.Forms.Cursor/Current .System.Windows.Forms.Cursors/WaitCursor)
        (try
            (.items lb | .clear)
            (let data source)
            (when (is? source ^lambda)
                (let data (source | map tostring))
            )

            (foreach e data
                (lb | .items | .add (tostring e))
            )

        -finally: (.System.Windows.Forms.Cursor/Current .System.Windows.Forms.Cursors/Default)
        )
    )
 
    (let app
        (wf/form
            :text       title
            :backcolor  "gray"
            :forecolor  "white"
            :width      lwidth
            :height     600
            :OnShown    (fn e o ->
                            (.focus app)
                            (.focus lb)
                        )
            :controls
            [
                (let lb
                    (wf/control :listbox
                        :Font       (wf/font "Consolas" 12)
                        :height     120
                        :dock       "fill" 
                        :anchor     "top,left"
                        :margin     5
                        :Padding    5
                        :backcolor  "black"
                        :forecolor  forecolor
                        :horizontalscrollbar true
                        :selectionmode (if multiselect
                                            .System.Windows.Forms.SelectionMode/MultiSimple
                                            .System.Windows.Forms.SelectionMode/one)
                        :onDoubleClick
                            (fn e o ->
                                (if selectAction
                                    (selectAction (.SelectedItems lb | to-vector))
                                    (wf/messagebox "No Select Action has been set for this tool.")
                                )
                            )

                        :onKeyPress (^System.Windows.Forms.KeyPressEventHandler?
                            (fn o e ->
                                (matchp (.KeyChar e | ^char?)
                                | \return -> ; carriage return
                                    (.Handled e true) 
                                    (if SelectAction
                                        (selectAction (.SelectedItems lb | to-vector))
                                        (wf/messagebox "No select action has been set for this tool.")
                                    )

                                | \esc -> ; escape char
                                    (.Handled e true)
                                    (.SelectedItems lb | .clear)

                                | \q -> ; quit
                                    (.Handled e true)
                                    (def result null)
                                    (.close app)

                                | -> ; let everything else pass through

                                )
                            )
                        )

                        :OnKeyUp (^System.Windows.Forms.KeyEventHandler?
                            (fn o e ->
                                (matchp (.KeyCode e) (.Control e) (.Alt e) (.Shift e)
                                | "f5" _ _ _ ->
                                        (.Handled e true) 
                                        (if SelectAction
                                            (selectAction (.SelectedItems lb | to-vector))
                                            (wf/messagebox "No select action has been set for this tool.")
                                        )

                                | "/" _ _ _ ->
                                    (filter-data)

                                | "Escape" _ _ _ ->
                                    (.Handled e true)
                                    (.SelectedItems lb | .clear)

                                | "q" -> ; quit

                                | -> ; let everything else pass through

                                )
                            )
                        )
                    )
                )
            ]
        )
    )

    (defn filter-data
    "filter the listbox items using a regex"
        [&args]

        (let filterString (wf/QuestionBox "Enter filter string:" "Enter filter string."))
        (when filterString
            (.items lb | .clear)
            (foreach item (source | re/match-all filterString)
                (lb | .items | .add (tostring item))
            )
        )
    )

    (wf/menustrip app [
            (wf/menu "&Action" [
                    (wf/menuitem "&Accept Selection (F5)"
                        (fn e o -> 
                            (if SelectAction
                                (selectAction (.SelectedItems lb | to-vector))
                                (wf/messagebox "No select item has been set for this tool.")
                            )
                        )
                    )

                    ; if the source is a lambda, add the menu items for filtering and refreshing.
                    (when (is? source ^Lambda)
                        (wf/menuitem "Refresh &Data"
                            (fn e o -> (refresh-listbox-data))
                        )
                    )

                    (when (is? source ^Lambda)
                        (wf/menuitem "&Filter Data" filter-data)
                    )

                    (when (is? source ^Lambda)
                        (wf/menuitem "&Reset Filter"
                            (fn e o ->
                                (let filterString null)
                                (.items lb | .clear)
                                (foreach e (source | re/match-all filterString)
                                    (lb | .items | .add (tostring e))
                                )
                            )
                        )
                    )

                    (wf/menuItem "&Clear Selection (Esc)" 
                        (fn e o ->  (.SelectedItems lb | .clear)))

                    (wf/menuitem "&Quit (q)"
                        (fn e o -> (.Close app)))
                ]
            )

            ; Add any provided user menus
            @(if (some? menus) menus)
        ]
    )

    (refresh-listbox-data)

    (.showdialog app)
)

;---------------------------------------------------------------------------
;
; A dialog used for displaying or editing text.
;
(defn wf/editor
    "Form to display or edit text."
    [title inputValue :selectline :nonblocking :readonly (^IDictionary highlights {}) (Menus nil) (owner null)]

    ; get the text to be shown in the edit box
    (let textToShow
        (if (is? inputValue ^Lambda)
            ; evaluate the lambda then tostring the results.
            (inputValue | tostring)
            ; otherwise just turn the input into a string. 
            (tostring inputValue)))

    ; handles the search function in the text box
    (let search-text "")
    (defn HandleSearch
        "Handle searching through the editor buffer."
        [&args]

        (let selected (.selectedtext editbox))
        (if selected
            (def search-text selected)
        )

        (def search-text
            (wf/QuestionBox "Enter text to search for:" "Search:" search-text app))

        (if search-text
            (do
                (let index (++ (.selectionStart editbox)))
                (let index (.find editbox search-text index .System.Windows.Forms.RichTextBoxFinds/none))
                (if (== index -1)
                    (do
                        (wf/messagebox "String '${search-text}' not found." "Find...")
                    )
                    (do
                        (.ScrollToCaret editbox)
                    )
                )
            )
        )

        (.Focus editbox)
    )

    ; handle subsequent search requests
    (defn HandleSearchNext
        "Handle searching for the next match in the buffer."
        [&args]

        (let index (++ (.selectionStart editbox)))
        (if search-text
            (do
                (let index (.find editbox search-text index .System.Windows.Forms.RichTextBoxFinds/none))
                (if (== index -1)
                    (wf/messagebox "String '${search-text}' not found." "Find...")
                )
            )
        )
        (.Focus editbox)
    )

    (let app
        (wf/form
            :Text        title
            :Width       1000
            :Height      600
            :Controls [
                (let editBox
                    (wf/control :RichTextBox
                        :Text        textToShow
                        :Multiline   true
                        :AcceptsTab  true
                        :DetectUrls  true
                        :WordWrap    false
                        :Visible     true
                        :TabIndex    0
                        :Dock        "fill"
                        :Font        (wf/font "Consolas" 12)
                        :BackColor   "black"
                        :ForeColor   "cyan"
                        :ReadOnly    readonly
                        :BorderStyle .System.Windows.Forms.BorderStyle/None
                        :OnKeyUp     (^System.Windows.Forms.KeyEventHandler?
                                        (fn o e ->
                                            (matchp (.KeyCode e) (.Control e) (.Alt e) (.Shift e)
                                            | "f" true _ _ -> ;ctrl-f
                                                    (HandleSearch)
                                                    (.Handled e true)

                                            | "n" true _ _ -> ;ctrl-n
                                                    (HandleSearchNext)
                                                    (.Handled e true)

                                            | "f3" _ _ _ ->
                                                    (HandleSearchNext)
                                                    (.Handled e true)
                                            | ->    ; ignore other keys
                                            )
                                        )
                                     )
                    )
                )
            ]
        )
    )

    (defn HandleRefresh [o e]
        (.System.Windows.Forms.Cursor/Current .System.Windows.Forms.Cursors/WaitCursor)
        (try
            (let newText (inputValue | tostring))
            (.Text editbox newText)
            (wf/highlightEditBox editbox selectline highlights)
            -finally: (.System.Windows.Forms.Cursor/Current .System.Windows.Forms.Cursors/Default)
        )
    )

    (wf/menustrip app [
            ; create default menus
            (wf/menu "&Main"
                [
                    (if (is? inputValue ^Lambda)
                        (wf/menuitem "&Refresh" HandleRefresh)
                    )

                    (wf/menuitem "&Find in Text" HandleSearch)
                    (wf/menuitem "Next &Match"   HandleSearchNext)

                    (wf/menuitem "&Highlight Text"
                        (fn e o -> (wf/highlightEditBox editbox selectline highlights))
                    )

                    (wf/menuitem "&Close" (fn e o -> (.Close app)))
               ]
            )

            ; Add any provided user menus
            @(if (some? menus) menus)

        ]
    )

    (if highlights
        (wf/highlightEditBox editbox selectline highlights)
    )

    (when (some? owner)
        (.owner app owner)
    )

    (if nonblocking
        (.Show app)
        (.showDialog app))

    (.text editBox)
)

;---------------------------------------------------------------------------
;
(defn wf/highlightEditBox
    "A function to text do highlighting in a RichTextBox"
    [
        editbox         ; The richtext control to operate on
        selectline      ; if true, color the whole line
        highlights      ; A hashtable of regex/colours to use to do highligting. 
    ]

    (let eventMask (.BraidLang.NativeMethods/SuspendRichtextBoxEvents editbox))

    ;(.BraidLang.nativemethods/LockWindowUpdate (editbox | .Handle | .ToInt32))
    ;(.suspendlayout editbox)
    (const ocolor (.ForeColor editbox))
    (const pos    (.SelectionStart editbox))

    ; Compute the viewport (which is the whole thing really.)
    (const firstVisibleChar (.GetCharIndexFromPosition editbox (wf/point 0 0)))
    (const lastVisibleChar  (.text editbox | count))
    (const textBase         (max 0 (- firstVisibleChar 200)))
    (const vplen            (- lastVisibleChar firstVisibleChar))

    ; set all of the text in the viewport to the base color.
    (.select editbox firstVisibleChar vplen)
    (.SelectionColor editbox ocolor)

    (let vptext (if selectLine
                    (.text editBox)
                    (.text editbox | .substring textbase vplen)))

    ; add the color information...
    (foreach re:color: highlights
        (let color (^System.Drawing.Color? color))
        (foreach m (.matches re vptext)
            (let mindex (+ textBase (.index m)))
            (if selectline
                (do
                    ; marks the whole line containing the token
                    (let lineno
                        (if (zero? mindex)
                            0
                            (.GetLineFromCharIndex editbox mindex | ++)
                        )
                    )

                    ; find the beginning and end of the line then select it.
                    (let c0 (.GetFirstCharIndexFromLine editbox lineno))
                    (let c1 (.GetFirstCharIndexFromLine editbox (++ lineno)) | - 1)
                    (let len (- c1 c0))
                    (if (> len 0)
                        (.select editbox c0 len)
                    )
                )
                (do
                    ; just select the token text
                    (.select editbox mindex (.length m))
                )
            )

            ;Set the foreground color of the selected text.
            (.SelectionColor editBox color)
        )
    )

    (.Select editbox firstVisibleChar 0)
    (if (< firstVisibleChar pos lastVisibleChar)
        (.Select editbox pos 0)
    )

    ;(.BraidLang.nativemethods/LockWindowUpdate 0)
    (.BraidLang.NativeMethods/ResumeRichtextBoxEvents editbox eventMask)
    (.Invalidate editbox true)
    ;(.resumelayout editbox)
    (.SelectionColor editBox ocolor)
)

;---------------------------------------------------------------------------
;
(defn wf/control
"
This is a 'generic' function for creating WinForm controls. It allows you to create
the control, set all of the properties bind events as well as creating child controls
in a 'DSL'. A simple example is as follows: 
    (wf/control :form {:Text \"My Control\" :BackColor \"red\"} | .showdialog)
This example creates a simple form object, sets the text and color and then shows it.
A more complex example is:
    (let main (wf/control :form
            :Text \"My Control\"
            :BackColor \"red\" 
            :Controls [
                (wf/button
                    :Text \"Push Me\"
                    :Font (wf/font \"Courier New\" 20)
                    :Dock :fill
                    :ForeColor \"white\"
                    :Onclick (fn e o -> (println \"Hi there\"))
                )
            ]
        )
    )
This creates a form object containing one child control - a button - that
prints \"hi there\" to the console when pressed. To display this form you would do:
    (.showdialog main)

See also: wf/MenuStrip wf/Menu wf/MenuItem

"
    [controlType &args]

    (if (is? controlType ^Keyword)
        (let controlType (.baseName controlType))
    )

    (let form (new (str "System.Windows.Forms." controlType)))

    ; Process the property settings, events and controls
    (loop [properties args]
        (matchp @properties
        | :controls controls &args ->
            (foreach child (controls | filter ^System.Windows.Forms.Control)
                (.controls form | .add child)
            )

        | #"^On([a-z0-9]+)$" handler &args ->
            (let event (!! matches 1))
            (. form "add_${event}"
                (if (is? handler ^MulticastDelegate)
                    handler
                    (asEventHandler handler)
                )
            )

        | prop propVal &args ->
            (if (is? prop ^Keyword)
                (let prop (.baseName prop))
            )

            (. form prop propVal)
        )

        (if args (recur args))
    )

    form
)

;--------------------------------------------------------------------------a-
;
(defn wf/button [&args]
    (wf/control :button @args)
)

;---------------------------------------------------------------------------
;
(defn wf/form [&args]
    (wf/control :Form @args)
)

;---------------------------------------------------------------------------
;
(defn wf/button-stack
"
A function to create a vertical stack of menu buttons. The form size is adjusted to fit
the content. Actions should be zero-arity functions (callbacks). A 'Quit' button
is automatically added to the bottom of the button stack.

Examples:
    (wf/button-stack \"My Stack\" \"button 1\" #(println 'hi) \"button 2\" #(println 'bye))
"
    [ windowTitle &args]

    (if (length args | % 2 | != 0)
        (throw
            (join
                "The 'wf/button-stack' function requies an even numbered"
                "list of button titles and action functions."
                "Syntax: (wf/button-menu \"title\" menu-title-1 action-1 menu-title-2 action-2 ...)."
            )
        )
    )

    ; position variables for laying out buttons
    (let location 5)
    (let bh 50)

    ; figure out the max button width
    (forall [title _] args (length title) | max-list | * 15 | max 200 | >let bw)
    
    ; a local function to create buttons
    (defn stack-button [name func]
        (let control
            (wf/button
                :Text      name
                :Anchor    "Left,Right,Top"
                :Font      (wf/font "Microsoft Sans Serif" 10)
                ;:Font      (wf/font "Courier New" 12)
                ;:Font      (wf/font "Consolas" 12)
                :Location  (wf/point 5 location)
                :Size      (wf/size bw bh)
                :BackColor (.system.drawing.color/lightgray)
                :OnClick   (fn e o -> (func))
            )
        )

        ; move to next button location
        (incr location (+ bh 5))
        control
    )

    (let stack
        (wf/form
            :Text      windowTitle
            :opacity   1.0
            :Size      (new ^system.drawing.size (+ bw 25) 40)
            :BackColor .system.drawing.color/darkgray
            ; When shown, compute the final form height
            :OnShown #(.height stack (.bottom exit-button | + bh))
        )
    )

    ; add the user buttons
    (loop [buttons args]
        (if (let? title:func:buttons buttons)
            (do
                (.controls stack | .add (stack-button title func))
                (recur buttons)
            )
        )
    )

    ; add an exit button to close the form.
    (.controls stack | .add (let exit-button (stack-button "Exit" #(.close stack))))

    ; and finally show the form
    (.showdialog stack | void)
)

;---------------------------------------------------------------------------
;
(defn wf/datagrid
"
Show the source data in a grid.

Examples:
    (ls -file | map baseobject | wf/datagrid \"Files\")
"
    [source (title "Data Grid View")]

    (wf/form
        :width 600
        :height 400
        :autosize true
        :Text title
        :controls [
            (wf/control :DataGridView
                :dock "fill"
                :AllowUserToOrderColumns true
                :AllowUserToResizeColumns true
                :AutoSizeColumnsMode "Fill"
                :DataSource source
                :OnDataError
                    (^System.Windows.Forms.DataGridViewDataErrorEventHandler?
                        (fn o e -> null))
             )
        ]
    |
    .ShowDialog
    )
)

;---------------------------------------------------------------------------
;
(defn wf/show
"A utility function to display a form."
    [control]

    (.showDialog control)
)
