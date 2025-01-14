;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; A set of utilities for generating HTML
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(using-assembly system.web)

(defn html/encode [(^string text)]
    (.system.web.HttpUtility/HtmlEncode text)
)

(defn html/doc
    "Generate an HTML document"
    [header body]
    (str
        "<!DOCTYPE HTML>\n<html>\n<header>\n"
        (join (flatten header) "\n")
        "\n</header>\n<body>\n"
        (join (flatten body) "\n")
        "\n</body>\n</html>\n"
    )
)

(defn html/p
    "Generate a paragraph tag"
    [&args]
    (str "<p>" (join (flatten args) "\n") "</p>")
)

(defn html/title
    "Insert the document title."
    [&args]
    (str "<title>" (join (flatten args)) "</title>")
)

(defn html/b
    "Bold tag"
    [&args]
    (str "<b>" (join (flatten args)) "</b>")
)

(defn html/i
    "Italics tag"
    [&args]
    (str "<i>" (join (flatten args)) "</i>")
)

(defn html/em
    "Emphasis tag"
    [&args]
    (str "<em>" (join (flatten args)) "</em>")
)

(defn html/string
    "Strong tag"
    [&args]
    (str "<strong>" (join (flatten args)) "</strong>")
)

(defn html/h1
    "Generate a header 1 tag."
    [&args]
    (str "<h1>" (join (flatten args)) "</h1>")
)

(defn html/h2
    "Generate a header 2 tag."
    [&args]
    (str "<h2>" (join (flatten args)) "</h2>")
)

(defn html/h3
    "Generate a header 3 tag."
    [&args]
    (str "<h3>" (join (flatten args)) "</h3>")
)

(defn html/table
    "Generate a table"
    [&args]
    (str "\n<table>\n" (join (flatten args)) "\n</table>\n")
)

(defn html/tr
    "Generate a table row"
    [&args]
    (str "<tr>\n" (join (flatten args)) "\n</tr>\n")
)

(defn html/th
    "Generate a table header element"
    [&args]
    (str "<th>" (join (flatten args)) "</th>")
)

(defn html/td
    "Generate a table data element."
    [&args]
    (str "<td>" (join (flatten args)) "</td>")
)

(defn html/style
    "Insert an HTML CSS style string."
    [styleString]
    (str "\n<style>\n" styleString "\n</style>\n")
)

(defn html/input
    "Insert an input element into the document."
    [(^IDictionary elements)]

    (let result "<input ")
    (if (contains? elements "name")
        (let result (str result " name=\"" (elements :name) "\""))
    )
    (if (contains? elements "type")
        (let result (str result " type=\"" (elements :type) "\""))
    )
    (if (contains? elements "size")
        (let result (str result " size=" (elements :size) " "))
    )
    (if (contains? elements "formaction")
        (let result (str result " formaction=\"" (elements :formaction) "\""))
    )
    (if (contains? elements "value")
        (let result (str result " value=\"" (elements :value) "\""))
    )
    (let result (str result " >\n"))
    
    result
)

(defn html/form
    "Insert a form into the html document."
    [(^IDictionary elements) &args]

    (let result "")

    (let result "<form ")
    (if (contains? elements "action")
        (let result (str result "action=\"" (elements :action) "\" "))
    )
    (if (contains? elements "name")
        (let result (str result "name=\"" (elements :name)))
    )
    (if (contains? elements "method")
        (let result (str result "method=\"" (elements :method)))
    )
    (if (contains? elements "get")
        (let result (str result "get=\"" (elements :method)))
    )
    (let result (str result " >\n"))

    (str result (join args) "\n</form>\n")
)

(defn html/extractLinks
"
A function to extract all of the links in a piece of HTML text.
Currently it doesn't distinguish between \" and \'. It also
doesn't handle relative links because it doesn't have the original URL.

Examples:
    (http/get | html/extractLinks)

See also: http/get
"
    [text]

    (.matches #"href *= *[\"']([^\"']*)[\"']" text
    | map (fn m -> (.groups m | !! 1 | .value))
    | re/replace-all "^//" "http://"
    )
)

;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Example doc
;
(comment
    (setq doc
        (html/doc
            (list
                (html/title "This is an HTML Document")
                (html/style  "
                    body {
                        font-family: \"Open Sans\", Helvetica, Arial, Sans-Serif;
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
                ")
            )
            (list
                (html/h1 "This is an H1 Header")
                (html/p
                    "This is a paragraph"
                    "split over a number of lines."
                    "with a" (html/b "Bold section")
                    "and so on"
                )
                (html/h2 "This is an H2 Header")
                (html/p
                    "This is a paragraph
                    as a single string spanning multiple lines
                    with a ${(html/b \"Bold section\")}
                    and so on"
                )
    
                (html/table
                    (html/tr (html/th 'one) (html/th 'two) (html/th 'three))
                    (html/tr (html/td 1) (html/td 2) (html/td 3))
                    (html/tr (html/td 1) (html/td 2) (html/td 3))
                    (html/tr (html/td 1) (html/td 2) (html/td 3))
                    (html/tr (html/td 1) (html/td 2) (html/td 3))
                )
    
                (html/h2 "Some file information")
    
                (html/table
                    (html/tr (html/th 'name) (html/th 'length) (html/th 'Mode) (html/th "Last Write Time"))
                    (forall fl (ls '*.tl)
                        (html/tr
                            (html/td (.name fl))
                            (html/td (.length fl))
                            (html/td (.mode fl))
                            (html/td (.LastWriteTime fl))
                        )
                    )
                )
            )
        )
    )
) ; end comment
