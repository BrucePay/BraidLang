;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This script implements a simple Tic-Tac-Toe game
; in Braid using WinForms. This particular implementation uses
; types/classes to contain all the logic. These classes derive from
; and extend existing Windows Forms (Winforms) classes.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;:

(using-module winforms)

(type-alias ^sdc ^system.drawing.color)

;-----------------------------------------------------------------
;
; A class representing a tile/button in the Tic-Tac-Toe game.
; This class extends the Winforms button class to add game-specific
; features
;
(deftype ^ticTacToeButton -extends: ^System.Windows.Forms.Button

    ;-----------------------------------------------------------------
    ;
    ; initialize this instance
    ;
    :defm new (fn this buttonNumber ->
        (this
        | .Size     (wf/Size 75 75) 
        | .Font     (wf/font "Courier New" 18)
        | .TabIndex  buttonNumber
        | .reset    buttonNumber ; call the reset method to finish the initialization.
        )

        ; bind the click event handler for the button. This handles all of the business
        ; logic for:
        ;   - making X's move
        ;   - checking the board for wins or cat's games.
        ;   - making the computer's moves 
        ;   - checking again for wins or cat's games
        (.add_Click this
            (aseventhandler 
                (fn this x ->

                    ; check to see if there are no moves left
                    (if (.CatsGame mainform) (return))

                    ; perform X's move.
                    (.mark this "X")
                    (when (.CheckWin  mainform "X")
                        (let result
                            (wf/messagebox
                                "\n\tCongradulations!\n\t\tYou WIN!!!\n\n\nDo you want to play again?"
                                "Question" "okcancel"
                            )
                        )

                        (if (== result "OK")
                            (.newGame mainform)
                            (.close mainform)
                        )

                        (return)
                    )
                    
                    ; check again - it could be a cat's game now.
                    (if (.CatsGame mainform) (return))
                    
                    ; Make the computer's move
                    (.ComputersMove mainform)
                    (when (.CheckWin mainform "O")
                        (let result (wf/messagebox
                            "\nToo bad!\n\tYOU LOST :-(\n\n\nDo you want to play again?"
                                "Question" "okcancel"))

                        (if (== result "OK")
                            (.newGame mainform)
                            (.Close MainForm)
                        )

                        (return)
                    )
                    
                    ; and one more check for tied games.
                    (.CatsGame mainform)
                )
            )
        )
    )

    ;-----------------------------------------------------------------
    ;
    ; Reset the button to its default state
    ;
    :defm Reset (fn this (^string buttonNumber) ->
        (this
        | .Text      buttonNumber
        | .BackColor .sdc/Gray
        | .ForeColor .sdc/white
        | .Enabled   true
        )
    )

    ;-----------------------------------------------------------------
    ;
    ; A method to mark the button as being owned by either X or O
    ;
    :defm Mark (fn this player ->
        (this
        | .Text      player
        | .ForeColor .sdc/black
        | .BackColor (if (== player "X") .sdc/cyan .sdc/lightyellow)
        | .Enabled   false
        )
    )

    ;-----------------------------------------------------------------
    ;
    ; See how this button has been marked if at all
    ;
    :defm GetMark (fn this ->
        (let btext (.text this))
        (if (contains? "XO" btext)
            btext   ; button has been claimed by a player
            ; otherwise
            " "     ; the button is unclaimed so return space
        )
    )
)

;-----------------------------------------------------------------
;
; This class models the game board and manages all the buttons.
; It derives from Winforms ^Form class.
;
(deftype ^tictactoe -extends: ^System.Windows.Forms.Form

    ; Member variables holding the move tables.
    ^Vector      winningMoves
    ^IDictionary WinningMovesToTry
    ^IDictionary BlockingMovesToTry
    ^IDictionary StrategicMovesToTry

    ;-----------------------------------------------------------------
    ;
    ; the board constructor initializes the board and creates all the buttons.
    ;
    :defm new (fn this ->

        ;
        ; Any of the sequences of tiles in this vector represents a winning move.
        ;
        (.winningMoves this [
                [0 1 2]
                [3 4 5]
                [6 7 8]
                [0 3 6]
                [1 4 7]
                [2 5 8]
                [0 4 8]
                [2 4 6]
            ]
        )

        ;
        ; Build a dictionary of winning moves to try. The key contains
        ; the pattern to check while the value is where to make the
        ; next move.
        ;
        (.WinningMovesToTry this {
                ;012345678
                "OO ......"     2
                "O O......"     1
                " OO......"     0
                "...OO ..."     5
                "...O O..."     4
                "... OO..."     3
                "......OO "     8
                "......O O"     7
                "...... OO"     6
                " ...O...O"     0
                "O... ...O"     4
                "O...O... "     8
                "..O. .O.."     4
                ".. .O.O.."     2
                "..O.O. .."     6
                "O..O.. .."     6
                "O.. ..O.."     3
                " ..O..O.."     0
                ".O..O.. ."     7
                ".O.. ..O."     4
                ". ..O..O."     1
                "..O..O.. "     8
                "..O.. ..O"     5
                ".. ..O..O"     2    
            }
        )

        ;
        ; Build the blocking move table. It's identical to the winning move
        ; table except with X instead of O
        ;
        (.BlockingMovesToTry this {})
        (foreach key (.WinningMovesToTry this | .keys)
            (let newKey (re/replace key "O" "X"))
            (!! (.BlockingMovesToTry this) newkey (!! (.WinningMovesToTry this) key))
        )

        ;
        ; Defines the best move to make when all other things are equal.
        ;
        (.StrategicMovesToTry this {
                     ;012
                     ;345
                     ;678
                (str ".X."
                     "..X"
                     "...") 2
                (str ".X."
                     "X.."
                     "...") 0
                (str "..."
                     "..X"
                     ".X.") 8
                (str "..."
                     "X.."
                     ".X.") 6
                ;012345678
                "X ......." 1
                " .X......" 0
                "....... X" 7
                "......X ." 7
                ".... ...." 4
            }
        )

        ;
        ; Some layout utility routines
        ;
        (defn rightedge  [control offset] (.right control | + offset))
        (defn bottomEdge [control offset] (.bottom control | + offset))

        (let xPos         12)
        (let yPos         30)
        (let lastcontrol  nil)

        ; create and add all of the button controls
        (forall buttonNumber (range 9)
            (let button (new ^ticTacToeButton buttonNumber))
            (.Location  button (wf/Point xPos yPos))
            (let xPos (rightEdge button 12))
            (let lastControl button)
            (when (% buttonNumber 3 | == 0)
                (let xPos 12)
                (let yPos (bottomEdge lastControl 12))
            )
            (.controls this | .add button)
        )

        ;
        ; now configure the rest of this form...
        ;
        (this
        | .Text          "Tic-Tac-Toe"
        | .StartPosition .System.Windows.Forms.FormStartPosition/centerscreen
        | .BackColor     .sdc/gray
        | .add_Shown     (aseventhandler (fn e o -> (.Activate this)))
        )

        ; Add the menus
        (wf/menustrip this [
                (wf/menu "File" [
                        (wf/menuitem "New Game" (fn e o -> (.NewGame this)))
                        ;(wf/separator)
                        (wf/menuitem "Quit"     (fn e o -> (.Close this)))
                    ]
                )
            ]
        )

        ; Finally adjust the size of the containing form to just wrap the buttons.
        (.ClientSize this
            (wf/Size
                (RightEdge  lastControl 12)
                (BottomEdge lastControl 12)
            )
        )
    )

    ;-----------------------------------------------------------------
    ;
    ; A method to start the game; this is really the only end-user method
    ;
    :defm Play (fn ^void this -> (.showdialog this))

    ;-----------------------------------------------------------------
    ;
    ; Method to reset the game board...
    ;
    :defm NewGame (fn this ->
        (let buttonNumber 1) 
        (foreach button (.controls this | filter ^ticTacToeButton)
            (.reset button (pincr buttonNumber))))

    ;-----------------------------------------------------------------
    ;
    ; Gets the board state as a simple string so it can
    ; be matched against the move tables.
    ;
    :defm getBoardAsString (fn this ->
        (.controls this | filter ^ticTacToeButton | map .getMark | join ""))

    ;-----------------------------------------------------------------
    ;
    ; Check for a cat's game (no winner). This is
    ; when there are no open spaces left on the board
    ; but there is no winning sequence.
    ;
    :defm CatsGame (fn this ->
        (if (not (contains? (.getBoardAsString this) " "))
            (do
                (wf/messagebox "\n\n\t\tCats Game!\n\n\tClick OK for a new game.\n")
                (.NewGame this)
                true
            )
            false
        )
    )

    ;-----------------------------------------------------------------
    ;
    ; Check to see if anybody won...
    ;
    :defm CheckWin (fn this player ->
        (let buttons (.controls this | filter ^ticTacToeButton))
        (foreach move (.winningMoves this)
            (let win true)
            (foreach index move
                (if (not (re/match (.Text (!! buttons index)) player))
                    (do
                        (let win false)
                        (break)
                    )
                )
            )

            (when win
                ;
                ; Blink the winning row for a while
                ; then leave it marked...
                ;
                (let fg
                    (if (== player 'x')
                        (.sdc/green)
                        (.sdc/red)
                   )
                )

                (let bg .sdc/gray)

                ; blink the winning buttons
                (repeat 7
                    (foreach index move
                        (.BackColor (!! buttons index) fg)
                        (.ForeColor (!! buttons index) bg)
                    )

                    (.update this)
                    (sleep 200)
                    ; swap the colors
                    (swap fg bg)
                )
                
                ;
                ; Disable the remaining buttons so no more play happens...
                ;
                (foreach button buttons
                    (.enabled button false)
                )

                (return true)
            )
        )

        false
    )

    ;-----------------------------------------------------------------
    ;
    ; A method that implements the computer move strategy
    ;
    :defm ComputersMove (fn this ->

        (let board (.GetBoardAsString this))
        (let buttons (.controls this | filter ^ticTacToeButton))

        ; look for potential wins first...
        (foreach e (.WinningMovesToTry this)
            (when (re/match board (.key e))
                (.mark (!! buttons (.value e)) "O")
                (return)
            )
        )

        ; Check blocking moves next...
        (foreach e (.BlockingMovesToTry this)
            (when (re/match board (.key e))
                (.mark (!! buttons (.value e)) "O")
                (return)
            )
        )
        
        ; Check strategic moves next...
        (foreach e (.StrategicMovesToTry this)
            (when (re/match board (.key e))
                (.mark (!! buttons (.value e)) "O")
                (return)
            )
        )
        
        ; Otherwise just pick a move at random...
        (let limit 100)
        (while (decr limit)
            (let move (random 1 0 8))
            (when (re/match (!! board move) " ")
                (.mark (!! buttons move) "O")
                (return)
            )
        )

        (wf/messagebox "ERROR - no valid move found!")
    )
)

;-----------------------------------------------------------------
;
; And finally create a game instance and start it...
;
(let mainform (new ^tictactoe))
(.play mainform)

