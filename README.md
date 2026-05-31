# BraidLang

Braid is an experimental shell and scripting language by Bruce Payette. It is implemented in C#, hosted from PowerShell, and uses Lisp-like `.tl` source files for the language prelude, libraries, tests, and examples.

## Repository layout

- `src\` - interpreter/runtime, parser, evaluator, built-ins, REPL host, and staged `.tl` runtime files.
- `src\BraidCore.csproj` - default SDK-style .NET 8 project.
- `src\braidlang.csproj` - legacy .NET Framework project used only with `.\build.ps1 -NonCore`.
- `Braid\` - PowerShell module helpers for building, launching, invoking, and formatting Braid.
- `Tests\` - Braid test scripts.
- `Examples\` - sample Braid programs and demos.
- `stage\` - generated runnable runtime created by `.\build.ps1`.

## Build and run

Use PowerShell 7.4 or newer from the repository root:

```powershell
.\build.ps1
```

The default build path uses:

```powershell
dotnet build .\src\BraidCore.csproj
```

Run a non-interactive smoke test:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\stage\BraidRepl.ps1 str "Braid runtime OK"
```

Start the interactive REPL:

```powershell
.\Start-Braid.ps1
```

Run a single Braid command:

```powershell
.\Start-Braid.ps1 str "hello from Braid"
```

Useful build switches:

```powershell
.\build.ps1 -Clean
.\build.ps1 -Optimize
.\build.ps1 -NonCore
```

`-NonCore` uses the legacy .NET Framework project and requires MSBuild. Normal development should use the default .NET 8 path.

## PowerShell module

Import the module from the repository root:

```powershell
Import-Module .\Braid\Braid.psd1
```

Build and locate the staged runtime:

```powershell
Invoke-BraidBuild
Get-BraidHome
```

`Build-Braid` is also exported as an alias for `Invoke-BraidBuild`.

Invoke a Braid command without starting an interactive session:

```powershell
Invoke-Braid str "hello from the module"
```

Start the REPL through the module:

```powershell
Start-Braid
```

For advanced PowerShell interop scenarios, explicitly load the Braid runtime into the current PowerShell process:

```powershell
Import-BraidRuntime
```

The module also loads `Braid.Format.ps1xml`, which gives common scalar Braid runtime objects a readable `ToString()`-based PowerShell display.

## Continuous integration and release artifacts

The GitHub Actions workflow builds and smoke-tests Braid on:

- Windows
- Linux
- macOS

Each workflow run uploads the staged runtime as an artifact named for the platform. This is the release foundation: a tagged release can promote those tested artifacts without changing the build path.

## Tests and validation

For code changes, at minimum run:

```powershell
.\build.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\stage\BraidRepl.ps1 str "Braid runtime OK"
```

For language/runtime behavior changes, inspect and prefer the existing Braid test harness in `Tests\unittests.tl` rather than adding a separate test framework.

## Roadmap

Bruce Payette's "Next steps" slide maps to these repository tracks:

- Clean/refactor the code: keep interpreter changes focused and extract shared loader/build logic as it stabilizes.
- Make Braid into a PowerShell module: `Braid\` now exposes build, start, invoke, runtime import, and formatting helpers.
- Add formatting configuration for Braid types: `Braid\Braid.Format.ps1xml` covers common scalar Braid runtime objects.
- High-level documentation: this README documents layout, build/run, module usage, CI, validation, and release artifacts.
- Build process improvements: the default build is SDK-style .NET 8, avoids machine-specific MSBuild paths, and CI runs on every major hosted platform.
- Create a release: CI now produces tested staged artifacts suitable for promotion into a GitHub release.
