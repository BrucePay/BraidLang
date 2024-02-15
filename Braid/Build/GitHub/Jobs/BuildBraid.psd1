@{
    "runs-on" = "windows-latest"
    if = '${{ success() }}'
    steps = @(
        @{
            name = 'Check out repository'
            uses = 'actions/checkout@v3'
        },
        @{
            name = 'GitLogger'
            uses = 'GitLogging/GitLoggerAction@main'
            id = 'GitLogger'
        },
        @{
            name = 'setup .net'
            uses = 'actions/setup-dotnet@v3'  
            with = @{
                'dotnet-version' = '7.0.x'
            }    
        },
        @{
            name = 'install dependencies'
            run  = 'dotnet restore ./src/BraidCore.csproj'
        },
        @{
            name = 'dotnet build'
            run  = 'dotnet build ./src/BraidCore.csproj'
        }
        @{
            name = 'braidlang.dll artifact'
            uses = 'actions/upload-artifact@v3'
            with = @{
                name = 'braidlang.zip'
                path = '**/src/bin/**/braidlang.dll'
            }            
        }
        @{
            name = 'Use PSSVG Action'
            uses = 'StartAutomating/PSSVG@main'
            id = 'PSSVG'
        },
        'RunPipeScript',
        'RunEZOut',
        'RunHelpOut'
    )
}
