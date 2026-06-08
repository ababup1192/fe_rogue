@echo off
REM ============================================================================
REM  fe_rogue を Windows の .exe（JRE 同梱・ダブルクリック起動）にパッケージする。
REM  Windows 上でのみ実行可能（jpackage はターゲット OS でしか動かない）。
REM
REM  前提:
REM    - JDK 21 以上（jpackage / jar / java が PATH にあること）
REM    - このリポジトリ一式（bin\flix.jar, lib\external\ のネイティブ jar を含む）
REM
REM  使い方:  examples\fe_rogue\ で  scripts\package-windows-exe.bat
REM  出力:    examples\fe_rogue\dist\fe_rogue\fe_rogue.exe  (portable app-image)
REM
REM  ※ インストーラ形式（単一 .exe / .msi）が欲しい場合は最後の --type を
REM     exe / msi に変える（WiX Toolset のインストールが必要）。
REM ============================================================================
setlocal
cd /d "%~dp0\.."
set HERE=%CD%

echo ==^> build-fatjar
call java -jar "%HERE%\..\..\bin\flix.jar" build-fatjar || goto :err

echo ==^> merge natives into one self-contained jar
rmdir /s /q "%HERE%\build\selfcontained" 2>nul
mkdir "%HERE%\build\selfcontained"
pushd "%HERE%\build\selfcontained"
jar xf "%HERE%\artifact\fe_rogue.jar" || goto :err
for %%j in ("%HERE%\lib\external\lwjgl-*-natives-*.jar") do jar xf "%%j" || goto :err
jar --create --file "%HERE%\artifact\fe_rogue-all.jar" --main-class Main . || goto :err
popd
rmdir /s /q "%HERE%\build\selfcontained" 2>nul

echo ==^> stage app input
set STAGE=%HERE%\build\jpackage-input
rmdir /s /q "%STAGE%" 2>nul
mkdir "%STAGE%\src\scenes"
copy /y "%HERE%\artifact\fe_rogue-all.jar" "%STAGE%\" >nul
copy /y "%HERE%\project.json" "%STAGE%\" >nul
xcopy /e /i /y "%HERE%\assets" "%STAGE%\assets" >nul
xcopy /e /i /y "%HERE%\resources" "%STAGE%\resources" >nul
copy /y "%HERE%\src\scenes\*.scene.json" "%STAGE%\src\scenes\" >nul

echo ==^> jpackage (.exe / app-image)
rmdir /s /q "%HERE%\dist\fe_rogue" 2>nul
REM $APPDIR は jpackage が実行時に展開するマクロ。Windows では -XstartOnFirstThread 不要
REM （ensureMainThread が macOS 以外では何もしないため）。
jpackage ^
  --type app-image ^
  --name fe_rogue ^
  --app-version 1.0.0 ^
  --input "%STAGE%" ^
  --main-jar fe_rogue-all.jar ^
  --main-class Main ^
  --java-options "-DprojectPath=$APPDIR" ^
  --dest "%HERE%\dist" || goto :err

echo.
echo ==^> done: dist\fe_rogue\fe_rogue.exe を実行
goto :eof

:err
echo.
echo [ERROR] パッケージ作成に失敗しました。上のログを確認してください。
exit /b 1
