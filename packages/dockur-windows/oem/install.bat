@echo off
rem dockur OEM entry: runs during Windows setup (C:\OEM\install.bat).
rem Launches the provisioning script hidden; log goes to C:\OEM\install.log.
setlocal
set LOG=C:\OEM\install.log
echo [%date% %time%] OEM install.bat started >> "%LOG%"
if exist "C:\OEM\setup.ps1" (
  echo [%date% %time%] launching setup.ps1 >> "%LOG%"
  powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\OEM\setup.ps1" >> "%LOG%" 2>&1
  echo [%date% %time%] setup.ps1 exit code %errorlevel% >> "%LOG%"
) else (
  echo [%date% %time%] setup.ps1 NOT FOUND >> "%LOG%"
)
echo [%date% %time%] OEM install.bat finished >> "%LOG%"
