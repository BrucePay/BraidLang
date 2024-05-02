FROM mcr.microsoft.com/powershell
COPY . /Braid
SHELL ["/bin/pwsh", "-nologo","-command"]
RUN @( \
    Get-ChildItem -Path /Braid -Recurse -Filter Braidlang.dll | \
        Select-Object -First 1 | \
            Copy-Item -Destination /Braid/stage/ -PassThru | Out-Host \
    && \ 
    New-Item -Path \$Profile -ItemType File -Force | Add-Content -Value '/Braid/Start-Braid.ps1' \
)