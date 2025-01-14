
$FontName = 'Noto Sans'
$AnimateColors = [Ordered]@{
    dur='10s'
    Values='#199ac1;#359DA8;#199ac1'
    RepeatCount='indefinite'
}


Push-Location ($psScriptRoot | Split-Path | Split-Path)

svg -ViewBox 300, 100 @(        
    SVG.GoogleFont -FontName $FontName
    
    SVG.path -D @(
        "M 90, 0"
        
        $pixelRange    = 0..100
        $angleStart    = 180
        $angleIncrease = 360 / $pixelRange.Length

        foreach ($t in $pixelRange) {         

            "$((100 + ([Math]::Cos((($angleStart + ($t*$angleIncrease)) * [Math]::PI)/180) * 10)), $t)"
        }
        "M 110, 0"
        foreach ($t in $pixelRange) {
            "$((100 + ([Math]::Cos((($angleStart + ($t*$angleIncrease)) * [Math]::PI)/180) * -10)), $t)"
        }        
    ) -Stroke "#199ac1" -Fill 'transparent' @(
        SVG.animate -AttributeName stroke @AnimateColors
    )
    

    svg.text -X 50% -Y 50% -TextAnchor 'middle' -DominantBaseline 'middle' -Style "font-family: '$FontName', sans-serif" -Fill '#199AC1' -Class 'foreground-fill' -Content @(
        SVG.tspan -FontSize .5em -Content 'Braid'
        SVG.animate -AttributeName fill @AnimateColors
    ) -FontSize 4em -FontWeight 500
    
) -OutputPath (Join-Path $pwd Braid.svg)

Pop-Location