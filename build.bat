@echo off

set game_path=src\game

if not exist build mkdir build
pushd build

robocopy ..\lib . /s > nul

for %%a in (%*) do set "%%a=1"

set exeName=DanMofu

set flags=""

if "%release%" == "1" (
    echo RELEASE
    set flags=%flags% -o:speed -subsystem:windows 
) else (
    set flags=%flags% -debug -o:none -use-separate-modules -lld
)

if not "%only_game%"=="1" (
    echo "Building Platform"
    del %exeName%.exe
    odin build ..\src\platform_win32 %flags% -out:%exeName%.exe 
)

odin build ..\src\game -build-mode=dll -out="Game.dll" %flags%

if "%run%" == "1" if %errorlevel% == 0 (
    %exeName%.exe
)

popd