@echo off
chcp 65001 >nul
echo ============================================================
echo   AeroDock Portable v3.0 — Сборка Windows Release (Flutter)
echo ============================================================
echo.

flutter config --enable-windows-desktop
if not exist "windows" (
  flutter create --platforms=windows --project-name aerodock .
)
if exist "test\widget_test.dart" del /f /q "test\widget_test.dart"
if exist "assets\app_icon.ico" copy /y "assets\app_icon.ico" "windows\runner\resources\app_icon.ico" >nul

flutter pub get
if errorlevel 1 exit /b 1

flutter build windows --release
if errorlevel 1 exit /b 1

if exist "dist\AeroDock-Portable" rmdir /s /q "dist\AeroDock-Portable"
mkdir "dist\AeroDock-Portable"
mkdir "dist\AeroDock-Portable\Skins"
mkdir "dist\AeroDock-Portable\Icons"
mkdir "dist\AeroDock-Portable\Docklets"
mkdir "dist\AeroDock-Portable\Languages"

xcopy /e /i /y "build\windows\x64\runner\Release\*" "dist\AeroDock-Portable\" >nul
if exist "Settings.ini" copy /y "Settings.ini" "dist\AeroDock-Portable\Settings.ini" >nul
if exist "README-FLUTTER-RU.txt" copy /y "README-FLUTTER-RU.txt" "dist\AeroDock-Portable\README-RU.txt" >nul

echo.
echo Готово! Портативная сборка находится в: dist\AeroDock-Portable\aerodock.exe
pause
