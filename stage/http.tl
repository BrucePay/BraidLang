;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; HTTP convenience functions
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(using-assembly System.Net.Http)

;--------------------------------------------------------------------------
;
(defn http/get
"
Download a web page as a text string, optionally specifying the headers to use.
The default headers are {\"Accept\" \"*/*\" \"User-Agent\" \"curl/7.55.1\"}.

Examples:
    (http/get  \"http://wikipedia.org\")                    ; download main Wikipedia page
    (http/get -headers: { ... }] \"http://foo.org.org\")    ; specify so headers for the download
    (http/get -verbose \"http://foo.org\")                  ; get verbose output
    (http/get -user \"foo:bar\" \"http://foo.org\")           ; use basic auth for user 'foo'

See also:  http/getData http/getAsync http/getDataAsync http/post http/postAsync
"
    [(^Uri? url) :headers: :verbose :user:]

    (const headers {"Accept" "*/*" "User-Agent" "curl/7.55.1" @headers})

    (when (some? user)
        (const user64 (.System.Text.Encoding/UTF8 | .GetBytes user | .Convert/ToBase64String))
        (!! headers "Authorization" "Basic ${user64}")
    )

    (let wc (new ^System.Net.WebClient))
    (foreach k:v headers
        (try
            (.headers wc | .add (tostring k) (tostring v))
            -catch: (fn e ->
                (throw "error processing header '${k}': ${(.message e)}")
            )
        )
    )

    (if Verbose
        (.headers wc | info)
    )

    (.downloadstring wc url)
)

;--------------------------------------------------------------------------
;
(defn http/getAsync
"
This function asynchronously downloads a web page as a text string. It returns
a Task object. Use 'await' (Resolve) to get the results of this computation.

You can optionally specifying the headers to use.
The default headers are {\"Accept\" \"*/*\" \"User-Agent\" \"curl/7.55.1\"}.

Examples:
    (http/getAsync  \"http://wikipedia.org\" | await)          ; download main Wikipedia page
    (http/getAsync -headers: { ... }] \"http://foo.org.org\")  ; specify so headers for the download
    (http/getAsync -verbose \"http://foo.org\")                ; get verbose output
    (http/getAsync -user \"foo:bar\" \"http://foo.org\")       ; use basic auth for user 'foo'

See also:  http/get http/getAsync http/getDataAsync http/post http/postAsync
"
    [(^Uri? url) :headers: :verbose :user:]

    (const headers {"Accept" "*/*" "User-Agent" "curl/7.55.1" @headers})

    (when (some? user)
        (const user64 (.System.Text.Encoding/UTF8 | .GetBytes user | .Convert/ToBase64String))
        (!! headers "Authorization" "Basic ${user64}")
    )

    (let wc (new ^System.Net.WebClient))
    (foreach k:v headers
        (try
            (.headers wc | .add (tostring k) (tostring v))
            -catch: (fn e ->
                (throw "error processing header '${k}': ${(.message e)}")
            )
        )
    )

    (if Verbose
        (.headers wc | info)
    )

    (.downloadstringTaskAsync wc url)
)

;--------------------------------------------------------------------------
;
(defn http/getData
"
Download a URL as a binary data.

Examples:
    (http/getData imageURL | write-data 'image.png)

See also:  http/get http/getAsync http/getDataAsync http/post http/postAsync
"
    [(^Uri? url)]

    (.downloaddata (new ^System.Net.WebClient) url)
)

;--------------------------------------------------------------------------
;
(defn http/getDataAsync
"
This function asynchronously downloads a web page as binary data. Once the
download starts it will return a Task object. Pass this task object to 'await'
to get the results of this computation.

Examples:
    (http/getDataAsync imageURL | await | !! 0 | write-data 'image.png)

See also:  http/get http/getAsync http/getData http/post http/postAsync
"
    [(^Uri? url)]

    (.downloaddataTaskAsync (new ^System.Net.WebClient) url)
)

;--------------------------------------------------------------------------
;
(defn http/post
"
This function posts a string to the specified URL. If the content argument is
a string, it will be posted as is otherwise the cont will be encoded as JSON
before posting it. By default, the function will return the response string however
if '-eval' is specified, tge response will be parsed and evaluated as a braid script.

Examples:
    (http/post \"http:/someurl.com\" {\"foo\" 123 \"bar\" 456})

See also: http/get http/getAsync http/getData http/getDataAsync http/postAsync
"
    [(^Uri? url) content :parse]

    (if (is? content ^string)
        (let content (new ^System.Net.Http.StringContent content))
        (let content (new ^System.Net.Http.StringContent (ToSourceString content)))
    )

    (let client (new ^System.Net.Http.HttpClient))
    (let response (await (.PostAsync client url content)))
    (let responseStr (response | .content | .ReadAsStringAsync | await))
    (if parse
        (parse-text responseStr | car | eval)
        resposeStr
    )
)

;--------------------------------------------------------------------------
;
(defn http/postAsync
"
This function asynchronously posts a string to the specified URL. If the content argument is
a string, it will be posted as is otherwise the cont will be encoded as JSON
before posting it. By default, the function will return tge response string however
if '-eval' is specified, tge response will be parsed and evakuated as a braid script.

See also: http/get http/getAsync http/getData http/getDataAsync http/post
"
    [(^Uri? url) content]

    (if (is? content ^string)
        (let content (new ^System.Net.Http.StringContent content))
        (let content (new ^System.Net.Http.StringContent (ToSourceString content)))
    )

    (let client (new ^System.Net.Http.HttpClient))
    (.PostAsync client url content)
)

