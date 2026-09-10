# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project overview

Braid is an experimental shell and scripting language by Bruce Payette. It is implemented mostly in C# and hosted from PowerShell. The language is Lisp-like, uses `.tl` source files for Braid code, and integrates closely with PowerShell and .NET.

## Repository layout

- `src\` - Core interpreter/runtime, parser, evaluator, built-ins, REPL host, and staged `.tl` runtime files.
- `src\BraidCore.csproj` - Default SDK-style .NET project used by `build.ps1`.
- `src\braidlang.csproj` - Legacy .NET Framework project used only with `build.ps1 -NonCore`.
- `src\autoload.tl` - Main Braid prelude/standard-library bootstrap loaded by the REPL.
- `Tests\` - Braid test scripts.
- `Examples\` - Example Braid programs and demos.
- `Braid\` - PowerShell module/build packaging scaffolding.
- `stage\` - Generated runnable output created by `build.ps1`; do not commit it.

## Build and run

Use PowerShell from the repository root.

```powershell
.\build.ps1
```

The default build path uses:

```powershell
dotnet build .\src\BraidCore.csproj
```

After a successful build, the runtime is staged into `.\stage`. Run a simple smoke test with:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\stage\BraidRepl.ps1 str "Braid runtime OK"
```

To start the interactive REPL:

```powershell
.\Start-Braid.ps1
```

Use `.\build.ps1 -Optimize` for Release builds and `.\build.ps1 -Clean` to clean before building.

## MSBuild and Visual Studio

Do not hard-code a machine-specific `MSBuild.exe` path.

Normal development should not require MSBuild because `build.ps1` defaults to `dotnet build` for `src\BraidCore.csproj`. Only use MSBuild for the legacy .NET Framework project via:

```powershell
.\build.ps1 -NonCore
```

If `-NonCore` is needed, resolve MSBuild in this order:

1. `msbuild` already available in `PATH`.
2. `VsDevShell` PowerShell module, if installed, to populate the current process environment.
3. A small set of standard Visual Studio 2022 install paths.
4. Fail clearly if MSBuild is still unavailable.

## Tests and validation

For code changes, run the most relevant existing validation. At minimum, build and smoke-run Braid:

```powershell
.\build.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\stage\BraidRepl.ps1 str "Braid runtime OK"
```

For language/runtime behavior changes, inspect `Tests\unittests.tl` and prefer running the existing Braid test harness instead of inventing a separate test framework.

The default test runner suite is portable and is expected to pass on Windows, Linux, and macOS:

```powershell
.\Tests\Run-BraidTests.ps1 -Suite portable
```

Use `-Suite windows` for Windows-only integration coverage and `-All` only for exploratory full-suite runs; full-suite failures are not currently a CI baseline.

Documentation-only changes do not require a build unless they alter documented commands or generated artifacts.

## Coding conventions

- Keep changes small and focused; this is an experimental language implementation with many tightly coupled runtime behaviors.
- Prefer existing interpreter patterns in `src\braid.cs`, `src\parse.cs`, `src\evaluate.cs`, and `src\builtins.cs`.
- Preserve PowerShell/.NET interop behavior unless the requested change explicitly alters it.
- Use Windows path separators in commands and documentation.
- Use ASCII in source and docs unless the edited file already uses non-ASCII or the change requires it.
- Avoid broad catch blocks or silent fallbacks. Surface build/runtime errors clearly.

## Generated files and cleanup

Do not commit generated build output:

- `stage\`
- `src\bin\`
- `src\obj\`

After local validation, remove generated artifacts unless the user explicitly wants them left in place.

Leave unrelated user files and changes alone, including temporary Office lock files such as `~$*.pptx`.
