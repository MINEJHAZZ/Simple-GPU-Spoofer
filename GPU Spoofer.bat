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

:: Set variables for values (customize if needed for other GPUs)
set "ORIGINAL_DESC=@oem61.inf,%%amd7590.23%%;AMD Radeon RX 9060 XT"
set "SPOOF_DESC=@oem61.inf,%%amd747E.38%%;AMD Radeon RX 7800 XT"

:: Prompt user for the PCI device instance path
echo Please provide the PCI device instance path of your GPU.
echo You can find it in Device Manager:
echo Under "Display Adapters" -^> Right Click your GPU -^> Properties -^> Details Tab -^> Select "Device Instance Path" from the dropdown.
echo ......
echo Enter the PCI device instance path (e.g., PCI^(Other Random Values^)):
set /p "PCI_PATH="

if "%PCI_PATH%"=="" (
    echo No path provided. Exiting.
    pause
    exit /b
)

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

:: Determine action based on current value or prompt user
echo.
echo Choose an option:
echo 1. Set to original (AMD Radeon RX 9060 XT)
echo 2. Set to spoof (AMD Radeon RX 7800 XT)
echo 3. Toggle (switch to the other one)
set /p "choice=Enter 1, 2, or 3: "

if "%choice%"=="1" (
    set "NEW_DESC=%ORIGINAL_DESC%"
) else if "%choice%"=="2" (
    set "NEW_DESC=%SPOOF_DESC%"
) else if "%choice%"=="3" (
    if "%CURRENT_DESC%"=="%ORIGINAL_DESC%" (
        set "NEW_DESC=%SPOOF_DESC%"
    ) else if "%CURRENT_DESC%"=="%SPOOF_DESC%" (
        set "NEW_DESC=%ORIGINAL_DESC%"
    ) else (
        echo Current value doesn't match original or spoof. Choose 1 or 2.
        pause
        exit /b
    )
) else (
    echo Invalid choice. Exiting.
    pause
    exit /b
)

:: Change DeviceDesc
reg add "%ENUM_KEY%" /v DeviceDesc /t REG_SZ /d "%NEW_DESC%" /f
if %errorLevel% == 0 (echo DeviceDesc updated successfully to: %NEW_DESC%) else (echo Failed to update DeviceDesc. Check permissions/ownership.)

:: Prompt to restart
echo Changes applied. Restart your PC to apply them? (Y/N)
set /p "restart="
if /i "%restart%"=="Y" (shutdown /r /t 0)

pause