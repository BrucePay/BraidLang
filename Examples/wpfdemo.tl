
(using-module wpf)

(let window (wpf-new "
<Window
    xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"
    xmlns:x=\"http://schemas.microsoft.com/winfx/2006/xaml\"
    x:Name=\"Window\">
    <Grid x:Name=\"Grid\">
        <Grid.RowDefinitions>
            <RowDefinition Height=\"Auto\"/>
            <RowDefinition Height=\"Auto\"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width=\"Auto\"/>
            <ColumnDefinition Width=\"Auto\"/>
        </Grid.ColumnDefinitions>
        <TextBox x:Name = \"PathTextBox\"
            Width=\"150\"
            Grid.Column=\"0\"
            Grid.Row=\"0\"
        />
        <Button x:Name = \"ValidateButton\"
            Content=\"Validate\"
            Grid.Column=\"1\"
            Grid.Row=\"0\"
        />
        <Button x:Name = \"RemoveButton\"
            Content=\"Remove\"
            Grid.Column=\"0\"
            Grid.Row=\"1\"
        />
    </Grid>
</Window>
"))

(let pathTextBox (wpf-control window "PathTextBox"))

(wpf-click window "ValidateButton" (fn e o ->
        (if (not (Test-Path (.text pathTextBox)))
            (.text pathTextBox "")
        )
    )
)

(wpf-click window "RemoveButton" (fn e o ->
        (If (.text pathTextBox)
            (If (Test-Path (.text pathTextBox))
                (Remove-Item (.text pathTextBox))
            )
        )
    )
)

(wpf-show window)


