
; load the WPF assembly
(using-assembly PresentationFramework)

(defn wpf-new
    "Parses the argument string into XAML then creates a Window out of it."
    [(^string xamltext)]

    (let xml (^xml? xamltext))
    (let reader (new ^System.Xml.XmlNodeReader xml))
    (let window (.Windows.Markup.XamlReader/Load reader))
    window
)

(defn wpf-control
    "Find a control matching the specified name"
    [(^system.windows.window window) (^string controlName)]

    (let control (.FindName window controlname))
    (if (null? control)
        (throw "cannot find control '${controlname}' in the DOM.")
    )
    control
)

(defn wpf-click
    "Adds a click action to the passed control."
    [(^system.windows.window window) (^string controlName) action]

    (let control (wpf-control window controlname))
    (.add_Click control
        (^System.Windows.RoutedEventHandler? action)
    )
)

(defn wpf-show
    "Shows a WPF window"
    [(^system.windows.window window)]

    (.ShowDialog window)
)
