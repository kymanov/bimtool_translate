@echo off
setlocal EnableDelayedExpansion
REM ===================================================================
REM  VVDI2 BMW TOOL - Turkce/Ingilizce dil yamasi (tek tik kurulum)
REM  Python GEREKTIRMEZ. Windows'ta yerlesik PowerShell'i kullanir.
REM
REM  Kullanim:
REM    Install-Turkish.bat             -> Turkce yama (Deutsch yuvasina)
REM    Install-Turkish.bat en          -> Ingilizce yama
REM    Install-Turkish.bat tr "C:\yol\BMWTOOL"   -> kurulum klasorunu elle ver
REM ===================================================================
chcp 65001 >nul 2>&1
title VVDI2 BMW TOOL - Dil Yamasi

set "SCRIPTDIR=%~dp0"
set "FIELD=%~1"
if "%FIELD%"=="" set "FIELD=tr"
if /I not "%FIELD%"=="tr" if /I not "%FIELD%"=="en" (
  echo [HATA] Gecersiz dil alani: "%FIELD%". Sadece tr veya en kullanin.
  goto :fail
)
set "BMWDIR=%~2"
set "JSON=%SCRIPTDIR%..\i18n\translations.de.json"
set "PS=%SCRIPTDIR%patch_language_dll.ps1"

echo.
echo === VVDI2 BMW TOOL dil yamasi ===
echo Hedef dil alani: %FIELD%
echo.

if not exist "%JSON%" (
  echo [HATA] Ceviri dosyasi bulunamadi: "%JSON%"
  goto :fail
)
if not exist "%PS%" (
  echo [HATA] Yamalayici bulunamadi: "%PS%"
  goto :fail
)

REM --- Kurulum klasorunu bul (parantezli FOR yerine duz if zinciri: paren tuzagi yok) ---
if not "%BMWDIR%"=="" goto :havedir
if not defined BMWDIR if exist "%ProgramFiles%\BMW TOOL\BMWTOOL\BMW_Language.dll" set "BMWDIR=%ProgramFiles%\BMW TOOL\BMWTOOL"
if not defined BMWDIR if exist "%ProgramFiles(x86)%\BMW TOOL\BMWTOOL\BMW_Language.dll" set "BMWDIR=%ProgramFiles(x86)%\BMW TOOL\BMWTOOL"
if not defined BMWDIR if exist "%ProgramW6432%\BMW TOOL\BMWTOOL\BMW_Language.dll" set "BMWDIR=%ProgramW6432%\BMW TOOL\BMWTOOL"
if not defined BMWDIR if exist "C:\BMW TOOL\BMWTOOL\BMW_Language.dll" set "BMWDIR=C:\BMW TOOL\BMWTOOL"

if defined BMWDIR goto :havedir
echo [HATA] BMW TOOL kurulumu otomatik bulunamadi.
echo        BMW_Language.dll iceren klasoru ikinci parametre olarak verin, orn:
echo        Install-Turkish.bat %FIELD% "C:\Program Files\BMW TOOL\BMWTOOL"
goto :fail

:havedir
set "DLL=%BMWDIR%\BMW_Language.dll"
if not exist "%DLL%" (
  echo [HATA] "%DLL%" bulunamadi. Klasor yolu yanlis.
  goto :fail
)
echo Kurulum klasoru: %BMWDIR%
echo.

REM --- Orijinali yedekle (sadece ilk seferde) ---
if not exist "%DLL%.orig" (
  echo Orijinal DLL yedekleniyor -^> BMW_Language.dll.orig
  copy /y "%DLL%" "%DLL%.orig" >nul
  if errorlevel 1 (
    echo [HATA] Yedekleme basarisiz. Yonetici olarak calistirin.
    goto :fail
  )
) else (
  echo Yedek zaten var: BMW_Language.dll.orig ^(yama her zaman orijinalden uretilir^)
)

REM --- Yamayi uret (her zaman temiz .orig uzerinden) ---
echo DLL yamalaniyor...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS%" -Dll "%DLL%.orig" -Translations "%JSON%" -Field %FIELD% -Out "%DLL%.new"
if errorlevel 1 (
  echo [HATA] Yamalama basarisiz.
  if exist "%DLL%.new" del "%DLL%.new"
  goto :fail
)

copy /y "%DLL%.new" "%DLL%" >nul
if errorlevel 1 (
  echo [HATA] Yamali DLL kopyalanamadi. BMW TOOL kapali mi? Yonetici olarak calistirin.
  del "%DLL%.new"
  goto :fail
)
del "%DLL%.new"
echo Yamali DLL yerine konuldu.
echo.

REM NOT: SKIPHTTP/SKIPACPRO ayari yalnizca Wine/Linux icin gerekliydi; gercek
REM Windows'ta online guncelleme cokmez, bu yuzden burada config degistirilmez.
REM Gerekirse (orn. Wine) elle: powershell -File set_config.ps1 -Ini "...\bmwtool_config.ini"

echo === TAMAMLANDI ===
echo BMW TOOL.exe calistirin. Dil menusunde:
echo   Deutsch  -> uygulanan ceviri ^(%FIELD%^)
echo   English  -> dokunulmamis yerlesik Ingilizce
echo Orijinale donmek icin: BMW_Language.dll.orig dosyasini BMW_Language.dll yapin.
echo.
pause
exit /b 0

:fail
echo.
echo Kurulum yarida kesildi.
echo.
pause
exit /b 1
