;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; A graphical animation of the "Towers of Hanoi" puzzle written in Braid.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

lambda [(numDisks 4) :auto :fast :width: :height:]

(using-module winforms)

(let-default ^int width  2 4)
(let-default ^int height 2 4)

(type-alias ^Color              ^System.Drawing.Color)
(type-alias ^ContentAlignment   ^System.Drawing.ContentAlignment)
(type-alias ^Label              ^System.Windows.Forms.Label)
(type-alias ^Button             ^System.Windows.Forms.Button)
(type-alias ^Form               ^System.Windows.Forms.Form)
(type-alias ^Application        ^System.Windows.Forms.Application)
(type-alias ^DragDropEffects    ^System.Windows.Forms.DragDropEffects)

(let DiskHeight         (* height 20))
(let DiskWidthFactor    (* width 20))
(let Top                100)
(let UpperBound         (- top diskHeight))
(let TowerOffset        (+ 100 DiskWidthFactor))
(let TowerWidth         (numDisks | * DiskWidthFactor))
(let BaseY              (+ top (* numDisks diskHeight)))
(let Delay              1)

;---------------------------------------------------------------
;
; A type to model a single tower.
;
(deftype ^Tower -extends: ^Label

    ^Vector disks
    ^int    center
    
    :defm new (fn this id center ->
        (this
        | .text      (str "T" id)
        | .width     TowerWidth
        | .Height    DiskHeight
        | .center    center
        | .Left      (center | - (/ TowerWidth 2))
        | .Top       BaseY
        | .backcolor .Color/Green
        | .forecolor .Color/White
        | .textAlign .ContentAlignment/MiddleCenter
        | .disks     []
        | .AllowDrop true
        )

        (.add_DragEnter this
            (^System.Windows.Forms.DragEventHandler?
                (fn sender e ->
                    (.effect e .DragDropEffects/Copy)
                    (info (+ "in DragEnter " (.text this)))
                )
            )
        )

        (.add_DragDrop this
            (^System.Windows.Forms.DragEventHandler?
                (fn sender e ->
                    (info "in DragDrop")
                    (.backcolor this .color/red)
                )
            )
        )
    )

    :defm addDisk (fn this disk ->
        (if (and disks (!! disks 0 | .width | < (.width disk)))
            (throw "Bigger disks can't go on smaller disks.")
        )
    )
)

;---------------------------------------------------------------
;
; A type to model a single disk
;
(deftype ^Disk -extends: ^Button

    :defm new (fn this (^int width) ->
        ; construct a new disk. Each disk is positioned lower than the previous one
        (this
        | .Width     (* DiskWidthFactor width)
        | .Height    diskHeight
        | .Top       (pincr top diskHeight)
        | .Left      (towerOffset | - (* DiskWidthFactor width | / 2) | ^int?)
        | .BackColor (wf/next-color)
        | .AllowDrop true
        )

        ; drag and drop
        (.add_MouseDown this
            (^System.Windows.Forms.MouseEventHandler?
                (fn sender e ->
                    (.DoDragDrop this this .DragDropEffects/Move)
                )
            )
         )
        
    )

    :defm Reset     (fn this -> (.left this (towerOffset | - (.width this | / 2) | ^int?)))

    :defm MoveUp    (fn this -> (.top this (.top this | - diskHeight)))

    :defm MoveDown  (fn this -> (.top this (.top this | + diskHeight)))

    :defm MoveLeft  (fn this -> (.left this (.left this | - 20)))

    :defm MoveRight (fn this -> (.left this (.left this | + 20)))

    ;
    ; animate moving a disk from one tower to another.
    ;
    :defm Move (fn this (^tower t1) (^tower t2) ->

        (.disks t1 | .remove this)

        ; move this disk up, refreshing just the disk control
        (while (.top this | >= upperBound)
            (.moveUp this)
            (unless fast
                (.update this)
                (sleep 5)
            )
        )

        ; move this disk over, right or left
        (let dist (.center t2 | - (.center t1)))
        (if (neg? dist)
            (for (let dist (abs dist)) (> dist 0) (incr dist -20)
                (.moveLeft this)
                (unless fast
                    (.update this)
                    (sleep 5)
                )
            )
            ; otherwise
            (while (> dist 0)
                (.moveRight this)
                (unless fast
                    (.update this)
                    (sleep 5)
                )
                (incr dist -20)
            )
        )
        
        ; move this disk down
        (let targetTop
            (if (.disks t2)
                (.disks t2 | !! -1 | .top)
                (.top t2)))

        (let downDist (- targetTop (+ (.top this) diskHeight)))

        (while (> downDist 0)
            (.moveDown this)
            (incr downDist (neg diskHeight))
            (unless fast
                (.update this)
                (sleep 5)
            )
        )

        (.disks t2 | .add this)

        ; now update the entire form instead of just the disk
        (.TopLevelControl this | .update)

        (if fast
            (when (.datetime/now | .millisecond | % 500 | == 0)
                (.TopLevelControl this | .update)
            )
            (do
                (.TopLevelControl this | .update)
            )
        )

        (sleep 1)
    )
)

;---------------------------------------------------------------
;
; A type to encapsulate the whole puzzle
;
(deftype ^TowersOfHanoi -extends: ^Form

    ^Vector Towers
    ^Vector Disks

    ;
    ; Constructor for the puzzle.
    ;
    :defm new (fn this ->
        (this
        | .Text "Towers of Hanoi"
        | .Height (+ baseY (* diskHeight 4))
        | .Backcolor .Color/black
        | .StartPosition .System.Windows.Forms.FormStartPosition/CenterScreen
        | .FormBorderStyle .System.Windows.Forms.FormBorderStyle/FixedDialog
        | .MaximizeBox false
        | .MinimizeBox false
        )

        ; manual start
        (.add_Click this
            (^EventHandler?
                (fn e o -> (.run this))
            )
        )

        ; automatic start
        (.add_Shown this
            (^EventHandler?
                (fn e o ->
                    (when auto
                        (.Run this)
                        (sleep 300)
                        (.close this)
                    )
                )
            )
        )

        ; Create the all disks and add them to the form
        (.Disks this
            (forall width (range 1 NumDisks)
                (.controls this | .add (let disk (new ^disk width)))
                disk
            )
        )

        ; create the three towers
        (let t1 (new ^tower 1 TowerOffset))
        (.controls this | .add t1)

        (let t2 (new ^tower 2 (+ (.right t1) (/ TowerWidth 2 | ^int) 20)))
        (.controls this | .add t2)

        (let t3 (new ^tower 3 (+ (.right t2) (/ TowerWidth 2 | ^int) 20)))
        (.controls this | .add t3)
        
        (.Towers this [t1 t2 t3])

        (.ResetDisks this)

        (.width this (.right t3 | + TowerWidth))
    )

    ; Run the animation.
    :defm Run (fn this ->
        (.ResetDisks this)
        (.update this)
        ;(.System.Windows.Forms.Cursor/Current .System.Windows.Forms.Cursors/WaitCursor)
        (.dohanoi this numDisks 3 1 2)
        ;(.System.Windows.Forms.Cursor/Current .System.Windows.Forms.Cursors/Default)
        (.update this)
    )

    ;
    ; Method to move all of the disks (back) to the first tower.
    ;
    :defm ResetDisks (fn this ->
        (foreach t (.Towers this)
            (.disks t | .clear)
        )

        (let t1 (.Towers this | !! 0))
        (foreach d (.Disks this)
            (.Reset d)
            (.disks t1 | .insert 0 d)
        )
    )

    ;
    ; Method that implements the the core ToH recursive algorithm.
    ;
    :defm doHanoi (fn this n to from using ->
        (if (== n 1)
            (do
                (let t1 (.Towers this | !! (-- from)))
                (let t2 (.Towers this | !! (-- to)))
                (.move (.disks t1 | last) t1 t2)
                ; flush queued events
                (.System.Windows.Forms.Application/doEvents)
                (sleep Delay)
            )
            ; otherwise
            (do
                (decr n)
                (.DoHanoi this n using from to)

                (let t1 (.Towers this | !! (-- from)))
                (let t2 (.Towers this | !! (-- to)))
                (.Move (.Disks t1 | last) t1 t2)
                ; flush queued events
                (.Application/doEvents)
                (sleep Delay)

                (.doHanoi this n to using from)
            )
        )
    )
)

;
; Create and start the puzzle.
;
;(new ^TowersOfHanoi | .Application/Run | void)
(new ^TowersOfHanoi | .ShowDialog | void)
