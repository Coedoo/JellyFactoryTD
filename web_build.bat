@echo off

if not exist build_web mkdir build_web

robocopy .\wasm_stuff .\build_web /s > nul
robocopy .\assets .\build_web\assets\ /s > nul

for %%a in (%*) do set "%%a=1"

set flags="-vet-shadowing"
if "%release%" == "1" (
    echo RELEASE
    set flags=%flags% -o:speed -subsystem:windows 
) else (
    set flags=%flags% -debug -o:none
    rem set flags=%flags% -debug -o:none -use-separate-modules -lld -show-timings
)

call odin build src\platform_wasm %flags% -out:build_web\index.wasm -target:js_wasm32 -extra-linker-flags:" --export-dynamic" -show-system-calls
