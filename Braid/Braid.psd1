@{
    RootModule = 'Braid.psm1'
    ModuleVersion = '0.2.0'
    GUID = '7f38ada8-7318-408c-a539-3b6b5d2bf84d'
    Author = 'Bruce Payette'
    CompanyName = 'Braid'
    Copyright = '(c) Bruce Payette. All rights reserved.'
    Description = 'PowerShell module helpers for building, launching, and hosting the Braid experimental shell language.'
    PowerShellVersion = '7.4'
    CompatiblePSEditions = @('Core')
    FormatsToProcess = @('Braid.Format.ps1xml')
    FunctionsToExport = @(
        'Get-BraidHome',
        'Import-BraidRuntime',
        'Invoke-Braid',
        'Invoke-BraidBuild',
        'Start-Braid'
    )
    AliasesToExport = @('Build-Braid')
    CmdletsToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @(
                'Braid',
                'Language',
                'Shell',
                'PowerShell'
            )
            LicenseUri = 'https://github.com/BrucePay/BraidLang/blob/main/LICENSE'
            ProjectUri = 'https://github.com/BrucePay/BraidLang'
            ReleaseNotes = 'Module helpers for building, launching, invoking, formatting, and explicitly importing the Braid runtime.'
        }
    }
}
