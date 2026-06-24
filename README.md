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

The GitHub Actions workflow builds, smoke-tests, validates the module, and runs the portable Braid `.tl` test suite on:

- Windows
- Linux
- macOS

Each workflow run uploads the staged runtime and Braid test logs as artifacts named for the platform. This is the release foundation: a tagged release can promote those tested artifacts without changing the build path.

The portable test suite is exclusion-based: new tests are expected to be portable unless they are explicitly excluded for a documented reason, such as Windows-only APIs, interactive console/completion behavior, or a known headless/full-suite gap. Windows CI also runs an additional Windows-only suite for PowerShell/file-system integration coverage.

Release policy:

- Use semantic version tags in the form `vMAJOR.MINOR.PATCH`, for example `v0.2.0`.
- Publish only artifacts produced by a successful workflow run for that tag.
- Keep automatic release creation disabled until tag-triggered release notes, checksums, and any signing policy are explicit.
- Keep the PowerShell module version in `Braid\Braid.psd1` aligned with the release tag.

## Tests and validation

For code changes, at minimum run:

```powershell
.\build.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\stage\BraidRepl.ps1 str "Braid runtime OK"
```

Run the CI-safe portable Braid test suite:

```powershell
.\Tests\Run-BraidTests.ps1
```

The runner defaults to `-Suite portable`, which is the same named suite used on Windows, Linux, and macOS CI. It verifies that tests actually ran, enforces a minimum test count, captures optional logs with `-LogPath`, and fails the PowerShell process if the harness reports failures or autoload errors.

Useful suites:

```powershell
.\Tests\Run-BraidTests.ps1 -Suite portable
.\Tests\Run-BraidTests.ps1 -Suite windows
.\Tests\Run-BraidTests.ps1 -Suite interactive
```

To try the full harness locally:

```powershell
.\Tests\Run-BraidTests.ps1 -All
```

Some full-suite tests currently depend on interactive console/completion behavior or known failing behavior and are not suitable for required headless CI. For language/runtime behavior changes, keep tests in the portable suite unless they need an explicit exclusion.

## Roadmap

Bruce Payette's "Next steps" slide maps to these repository tracks:

- Clean/refactor the code: keep interpreter changes focused and extract shared loader/build logic as it stabilizes.
- Make Braid into a PowerShell module: `Braid\` now exposes build, start, invoke, runtime import, and formatting helpers.
- Add formatting configuration for Braid types: `Braid\Braid.Format.ps1xml` covers common scalar Braid runtime objects.
- High-level documentation: this README documents layout, build/run, module usage, CI, validation, and release artifacts.
- Build process improvements: the default build is SDK-style .NET 8, avoids machine-specific MSBuild paths, and CI runs on every major hosted platform.
- Create a release: CI now produces tested staged artifacts suitable for promotion into a GitHub release.
