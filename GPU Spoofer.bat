@echo off

:: Check for admin privileges and self-elevate if needed
net session >nul 2>&1
if %errorLevel% == 0 (
    echo Running with admin privileges...
) else (
    echo Requesting admin privileges...
    powershell "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Database file (same directory as script)
set "DB_FILE=%~dp0gpu_spoofer_db.txt"

:: Initialize database with defaults if missing (placeholders only)
if not exist "%DB_FILE%" (
    >"%DB_FILE%" (
        echo ORIGINAL_NAME=
        echo SPOOF_NAME=AMD Radeon RX 7700 XT
        echo ORIGINAL_DESC=
        echo SPOOF_TOKEN=%%amd747E.27%%
        echo OEM_INF=
        echo LAST_PCI_PATH=
    )
)

:: Load database values
for /f "usebackq tokens=1,* delims== eol=#" %%A in ("%DB_FILE%") do (
    set "KV_%%A=%%B"
)

:: Set variables from DB
set "ORIGINAL_NAME=%KV_ORIGINAL_NAME%"
set "SPOOF_NAME=%KV_SPOOF_NAME%"
set "ORIGINAL_PREFIX=%KV_ORIGINAL_DESC%"
set "SPOOF_TOKEN=%KV_SPOOF_TOKEN%"
set "OEM_INF=%KV_OEM_INF%"

:: Prompt user for the PCI device instance path (prefill from DB if available)
set "PCI_PATH=%KV_LAST_PCI_PATH%"
echo Please provide the PCI device instance path of your GPU.
echo You can find it in Device Manager: Display Adapters -> [Your GPU] -> Properties -> Details -> "Device Instance Path".
if defined PCI_PATH echo Press Enter to reuse saved path: %PCI_PATH%
set /p "PCI_PATH="

if "%PCI_PATH%"=="" (
    echo No path provided. Exiting.
    pause
    exit /b
)

:: Persist selected PCI path to DB
call :UpdateDbKey LAST_PCI_PATH "%PCI_PATH%"

:: Set ENUM_KEY using the user-provided path
set "ENUM_KEY=HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\%PCI_PATH%"

:: Get current DeviceDesc value
set "CURRENT_DESC="
for /f "tokens=3,*" %%A in ('reg query "%ENUM_KEY%" /v DeviceDesc ^| find "DeviceDesc"') do set "CURRENT_DESC=%%A %%B"

:: If current not found, show error
if not defined CURRENT_DESC (
    echo Error: Unable to retrieve current DeviceDesc. Check if the key exists, the path is correct, and permissions are set.
    pause
    exit /b
)

:: Report the current DeviceDesc
echo Found current DeviceDesc: %CURRENT_DESC%

:: Extract prefix (INF + token) and display name from CURRENT_DESC
set "CURRENT_PREFIX="
set "CURRENT_NAME="
for /f "tokens=1,2 delims=;" %%I in ("%CURRENT_DESC%") do (
    set "CURRENT_PREFIX=%%I"
    set "CURRENT_NAME=%%J"
)

:: Extract INF and TOKEN parts from CURRENT_PREFIX -> @oemNN.inf,%%amdXXXX.YY%%
set "CURRENT_INF="
set "CURRENT_TOKEN="
for /f "tokens=1,2 delims=," %%X in ("%CURRENT_PREFIX%") do (
    set "CURRENT_INF=%%X"
    set "CURRENT_TOKEN=%%Y"
)

:: FIRST-RUN CAPTURE: write ORIGINAL_NAME, ORIGINAL_DESC, and OEM_INF only if not yet set
if not defined ORIGINAL_NAME (
    call :UpdateDbKey ORIGINAL_NAME "%CURRENT_NAME%"
    set "ORIGINAL_NAME=%CURRENT_NAME%"
    echo Saved ORIGINAL_NAME: %ORIGINAL_NAME%
)
if not defined ORIGINAL_PREFIX (
    call :UpdateDbKey ORIGINAL_DESC "%CURRENT_PREFIX%"
    set "ORIGINAL_PREFIX=%CURRENT_PREFIX%"
    echo Saved ORIGINAL_DESC (prefix): %ORIGINAL_PREFIX%
)
if not defined OEM_INF (
    call :UpdateDbKey OEM_INF "%CURRENT_INF%"
    set "OEM_INF=%CURRENT_INF%"
    echo Saved OEM_INF: %OEM_INF%
)

echo.
echo Choose an option:
echo 1. Set to original (%ORIGINAL_NAME%)
echo 2. Set to spoof (%SPOOF_NAME%)
echo 3. Toggle (switch to the other one)
echo Type "bypass" to enable changing locked values (ORIGINAL_*, OEM_INF).
set /p "choice=Enter 1, 2, 3 or bypass: "

set "BYPASS="
if /i "%choice%"=="bypass" set "BYPASS=1" & echo Bypass mode enabled.

:: In non-bypass mode, NEVER alter OEM_INF or ORIGINAL_* values.
:: In bypass mode, allow updating OEM_INF and ORIGINAL_* (optional prompts).
if defined BYPASS (
    echo.
    echo [Bypass] Press Enter to keep current OEM_INF (^%OEM_INF^), or input a new one (e.g., @oem61.inf):
    set /p "NEW_OEM_INF="
    if not "%NEW_OEM_INF%"=="" (
        call :UpdateDbKey OEM_INF "%NEW_OEM_INF%"
        set "OEM_INF=%NEW_OEM_INF%"
        echo Updated OEM_INF to: %OEM_INF%
    )

    echo [Bypass] Press Enter to keep ORIGINAL_NAME (^%ORIGINAL_NAME^), or input a new one:
    set /p "NEW_ORIG_NAME="
    if not "%NEW_ORIG_NAME%"=="" (
        call :UpdateDbKey ORIGINAL_NAME "%NEW_ORIG_NAME%"
        set "ORIGINAL_NAME=%NEW_ORIG_NAME%"
        echo Updated ORIGINAL_NAME to: %ORIGINAL_NAME%
    )

    echo [Bypass] Press Enter to keep ORIGINAL_DESC (^%ORIGINAL_PREFIX^), or input a new prefix "@oemNN.inf,%%amdXXXX.YY%%":
    set /p "NEW_ORIG_PREFIX="
    if not "%NEW_ORIG_PREFIX%"=="" (
        call :UpdateDbKey ORIGINAL_DESC "%NEW_ORIG_PREFIX%"
        set "ORIGINAL_PREFIX=%NEW_ORIG_PREFIX%"
        echo Updated ORIGINAL_DESC (prefix) to: %ORIGINAL_PREFIX%
    )
)

:: Apply OEM_INF override to CURRENT_PREFIX's INF part (keep token)
if defined OEM_INF (
    for /f "tokens=1,2 delims=," %%X in ("%CURRENT_PREFIX%") do (
        set "CURRENT_PREFIX=%OEM_INF%,%%Y"
    )
)

:: Build desired prefixes:
:: - For Original: use ORIGINAL_PREFIX (locked after first run)
set "TARGET_ORIG_PREFIX=%ORIGINAL_PREFIX%"

:: - For Spoof: if SPOOF_TOKEN provided, build using locked OEM_INF + SPOOF_TOKEN; else reuse CURRENT_PREFIX
set "TARGET_SPOOF_PREFIX=%CURRENT_PREFIX%"
if defined SPOOF_TOKEN (
    set "TARGET_SPOOF_PREFIX=%OEM_INF%,%SPOOF_TOKEN%"
)

setlocal EnableDelayedExpansion
if "%choice%"=="1" (
    set "NEW_DESC=!TARGET_ORIG_PREFIX!;%ORIGINAL_NAME%"
) else if "%choice%"=="2" (
    set "NEW_DESC=!TARGET_SPOOF_PREFIX!;%SPOOF_NAME%"
) else if "%choice%"=="3" (
    if /i "!CURRENT_NAME!"=="%ORIGINAL_NAME%" (
        set "NEW_DESC=!TARGET_SPOOF_PREFIX!;%SPOOF_NAME%"
    ) else if /i "!CURRENT_NAME!"=="%SPOOF_NAME%" (
        set "NEW_DESC=!TARGET_ORIG_PREFIX!;%ORIGINAL_NAME%"
    ) else (
        echo Current device name doesn't match original or spoof. Choose 1 or 2.
        endlocal
        pause
        exit /b
    )
) else if /i "%choice%"=="bypass" (
    :: In bypass, keep NEW_DESC from above prompts by selecting desired mode interactively:
    echo.
    echo [Bypass] Choose apply target:
    echo   a) Apply ORIGINAL
    echo   b) Apply SPOOF
    set /p "bm=Enter a or b: "
    if /i "!bm!"=="a" (
        set "NEW_DESC=!TARGET_ORIG_PREFIX!;%ORIGINAL_NAME%"
    ) else if /i "!bm!"=="b" (
        set "NEW_DESC=!TARGET_SPOOF_PREFIX!;%SPOOF_NAME%"
    ) else (
        echo Invalid bypass selection.
        endlocal
        pause
        exit /b
    )
) else (
    echo Invalid choice. Exiting.
    endlocal
    pause
    exit /b
)
endlocal & set "NEW_DESC=%NEW_DESC%"

:: Change DeviceDesc
reg add "%ENUM_KEY%" /v DeviceDesc /t REG_SZ /d "%NEW_DESC%" /f
if %errorLevel% == 0 (echo DeviceDesc updated successfully to: %NEW_DESC%) else (echo Failed to update DeviceDesc. Check permissions/ownership.)

:: Prompt to restart
echo Changes applied. Restart your PC to apply them? (Y/N)
set /p "restart="
if /i "%restart%"=="Y" (shutdown /r /t 0)

pause
goto :eof

:: --- Helpers ---

:UpdateDbKey
:: %1=KEY, %2=VALUE (quoted)
setlocal EnableDelayedExpansion
set "KEY=%~1"
set "VAL=%~2"
set "TMP=%DB_FILE%.tmp"
break >"%TMP%"
set "FOUND="
for /f "usebackq tokens=1,* delims== eol=#" %%A in ("%DB_FILE%") do (
    if /i "%%A"=="%KEY%" (
        echo %%A=%VAL%>>"%TMP%"
        set "FOUND=1"
    ) else (
        echo %%A=%%B>>"%TMP%"
    )
)
if not defined FOUND echo %KEY%=%VAL%>>"%TMP%"
move /y "%TMP%" "%DB_FILE%" >nul
endlocal & goto :eof