;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Generate a HTML view of the Braid function help
; content.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

lambda [:quiet]

(using-module htmlutils)

(load (file/join-path braidhome "helpsource.tl"))

(defn get-help-text
    "Get the associated help text for this item"
    [func]

    (get-assoc func :helptext | tostring | .trim)
)

(let ofile "helptext.html")

; Delete the old output file if there was one...
(remove-item -ea: "ignore" ofile)

; Create the output HTML file...
(let htmltext
    (html/doc
        ; Document head
        (list
            (html/title "Braid Functions")
            (html/style """
                    body {
                        font-family: "Open Sans", Helvetica, Arial, Sans-Serif;
                    }
                    table {
                        border: 1px solid black;
                    }
                    th {
                        padding: 10px;
                        text-align: center;
                        background-color: #e0e0e0; 
                    }
                    td {
                        padding: 10px;
                        text-align: left;
                        vertical-align: top;
                    }
                    tr:nth-child(even) {background-color: #f2f2f2;}
            """)
        )

        ; Document body.
        (list
            (html/h2 "Braid Function Documentation")

            ; generate a table of the functions and their help content
            (html/p
                """
                This page lists all of the Braid functions generally
                available to the user. Functions are either built into
                <br>
                the interpreter directly, defined in the file ${(html/b "autoload.tl")}
                or loaded from other utility modules.
                <br>
                """
            )

            (html/table
                ; the table header
                (html/tr
                    (html/th "No")
                    (html/th "Function")
                    (html/th "Origin")
                    (html/th "Description")
                )

                ; generate the table data for all of the functions.
                (vlet cnt 0)
                ((functions) | map (\ f ->
                        (let syntax     "")
                        (let body       "")
                        (let example    "")
                        (let examples   "")
                        (let see-also   "")
                        (let helpinfo   (get-help-text (.value f)))

                        ( html/encode helpinfo
                        | re/split #"[\r\n]+"       ; split into lines to simplify parsing.
                        | each (\
                            | #"^Syntax[: ]"  -> (let syntax %0)
                            | #"^Examples:"   -> (let example (str "<br>" %0 ))
                            | #"^See also:"   -> (let see-also (str "<i>" %0 "</i>"))
                            | #"^  "          -> (let examples (str examples "<br>" %0))
                            | line            -> (let body (str body "<br>" line))
                            )
                        )

                        (if (not syntax) (let syntax "<i>Currently undocumented.</i>"))

                        (let formatted (str syntax "<br>" body "<br>" example "<pre>" examples "</pre>" see-also))

                        (html/tr
                            (html/td (incr cnt))
                            (html/td (html/b (.key f)))
                            (html/td (where-defined (.value f)))
                            (html/td formatted)
                        )
                    )
                )
            )
        )
    )
)

; Write the generated HTML text to the output file.
(write-text htmltext ofile)

(if (not quiet)
    ; launch the browser on the content
    (start ofile)
)

