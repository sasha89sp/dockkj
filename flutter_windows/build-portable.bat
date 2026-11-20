@echo off
chcp 65001 >nul
setlocal

echo ======================================================
echo   Сборка портативной версии AeroDock (Flutter Windows)
echo ======================================================

where flutter >nul 2>nul
if errorlevel 1 (
  echo [ОШИБКА] Flutter SDK не найден в PATH.
  echo Установите Flutter или соберите в облаке через GitHub Actions.
  pause
  exit /b 1
)

if not exist "windows" (
  echo [1/5] Инициализация Windows-раннера Flutter...
  call flutter create --platforms=windows --project-name aerodock .
  if errorlevel 1 ( pause & exit /b 1 )
)

if exist "assets\app_icon.ico" (
  echo [2/5] Установка фирменной иконки aerodock.exe...
  copy /Y "assets\app_icon.ico" "windows\runner\resources\app_icon.ico" >nul
)

echo [3/5] Загрузка зависимостей (pub get)...
call flutter pub get
if errorlevel 1 ( pause & exit /b 1 )

echo [4/5] Компиляция Release-версии под Windows x64...
call flutter build windows --release
if errorlevel 1 ( pause & exit /b 1 )

echo [5/5] Упаковка портативной папки AeroDock-Portable-EXE...
if exist "AeroDock-Portable-EXE" rmdir /s /q "AeroDock-Portable-EXE"
mkdir "AeroDock-Portable-EXE"
xcopy /E /I /Y "build\windows\x64\runner\Release\*" "AeroDock-Portable-EXE\" >nul
copy /Y "aerodock-config.json" "AeroDock-Portable-EXE\aerodock-config.json" >nul

echo.
echo Готово! Портативная версия собрана в папке: AeroDock-Portable-EXE
explorer "AeroDock-Portable-EXE"
pause
