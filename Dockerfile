FROM mcr.microsoft.com/powershell
COPY . /Braid
SHELL ["/bin/pwsh", "-nologo","-command"]
RUN @( \
    New-Item -Path \$Profile -ItemType File -Force | Add-Content -Value '/Braid/Start-Braid.ps1' \
)