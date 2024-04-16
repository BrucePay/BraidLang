FROM mcr.microsoft.com/powershell
COPY . /Braid
ENTRYPOINT ["pwsh", "-file", "/Braid/Start-Braid.ps1"]