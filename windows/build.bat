@echo off
setlocal enabledelayedexpansion

echo ========================================
echo    Notchbeat for Windows - Build Tool
echo ========================================
echo.

:: 1. Check if dotnet is in PATH
where dotnet >nul 2>nul
if %ERRORLEVEL% equ 0 (
    set "DOTNET_CMD=dotnet"
    goto :BUILD
)

:: 2. Check standard 64-bit installation folder
if exist "%ProgramFiles%\dotnet\dotnet.exe" (
    set "DOTNET_CMD=%ProgramFiles%\dotnet\dotnet.exe"
    set "PATH=%ProgramFiles%\dotnet;!PATH!"
    goto :BUILD
)

:: 3. Check 32-bit Program Files (x86)
if exist "%ProgramFiles(x86)%\dotnet\dotnet.exe" (
    set "DOTNET_CMD=%ProgramFiles(x86)%\dotnet\dotnet.exe"
    set "PATH=%ProgramFiles(x86)%\dotnet;!PATH!"
    goto :BUILD
)

:: 4. Check Local AppData installation folder
if exist "%LocalAppData%\Microsoft\dotnet\dotnet.exe" (
    set "DOTNET_CMD=%LocalAppData%\Microsoft\dotnet\dotnet.exe"
    set "PATH=%LocalAppData%\Microsoft\dotnet;!PATH!"
    goto :BUILD
)

:: If not found anywhere, show helpful error and offer to download
echo [ERROR] .NET 8 SDK was not found on your system!
echo.
echo To build Notchbeat into an .exe, you need the .NET 8 SDK.
echo.
echo Quick options to fix this:
echo  1. Run this command in Windows Terminal (PowerShell):
echo        winget install Microsoft.DotNet.SDK.8
echo.
echo  2. Or download the installer directly:
echo        https://dotnet.microsoft.com/download/dotnet/8.0
echo.
set /p OPEN_BROWSER="Would you like to open the .NET download page in your browser? (Y/N): "
if /i "%OPEN_BROWSER%"=="Y" (
    start https://dotnet.microsoft.com/download/dotnet/8.0
)
goto :END

:BUILD
echo Found .NET at: !DOTNET_CMD!
echo.
echo Building self-contained single-file Notchbeat.exe...
echo This will take a moment on first run...
echo.

"!DOTNET_CMD!" publish Notchbeat/Notchbeat.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o build

if %ERRORLEVEL% equ 0 (
    echo.
    echo ========================================
    echo    BUILD SUCCEEDED!
    echo ========================================
    echo Executable created: build\Notchbeat.exe
    echo.
    set /p RUN_NOW="Would you like to run Notchbeat now? (Y/N): "
    if /i "!RUN_NOW!"=="Y" (
        start "" "build\Notchbeat.exe"
    )
) else (
    echo.
    echo [ERROR] Build failed. Check the error messages above.
)

:END
echo.
pause
