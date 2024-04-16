
#requires -Module PSDevOps

Import-BuildStep -SourcePath (
    Join-Path $PSScriptRoot 'GitHub'
) -BuildSystem GitHubWorkflow

Push-Location ($PSScriptRoot | Split-Path | Split-Path)

New-GitHubWorkflow -Job TestPowerShellOnLinux, TagReleaseAndPublish, BuildBraid -OutputPath @'
.\.github\workflows\BuildBraid.yml
'@ -Name "Build Braid" -On Push, PullRequest -Environment ([Ordered]@{
    REGISTRY = 'ghcr.io'
    IMAGE_NAME = '${{ github.repository }}'
})

Pop-Location

