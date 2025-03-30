@echo off

set game_path=src\game
set game_running=false
set exe_name=DanMofu.exe

if not exist build mkdir build
pushd build

FOR /F %%x IN ('tasklist /NH /FI "IMAGENAME eq %exe_name%"') DO IF %%x == %exe_name% set GAME_RUNNING=true

robocopy ..\lib . /s > nul

for %%a in (%*) do set "%%a=1"

set flags="-vet-shadowing"
if "%release%" == "1" (
    echo RELEASE
    set flags=%flags% -o:speed -subsystem:windows 
) else (
    set flags=%flags% -debug -o:none
    rem set flags=%flags% -debug -o:none -use-separate-modules -lld -show-timings
)

REM Reset errorlevel
ver > nul

if not "%only_game%"=="1" (
    echo "Building Platform"
    del %exe_name%
    odin build ..\src\platform_win32 %flags% -out:%exe_name%
)

if %errorlevel%==0 (
    odin build ..\src\game -build-mode=dll -out="Game.dll" %flags%
)

if "%run%" == "1" if %errorlevel%==0 if %game_running% == false (
    %exe_name%
)

popd