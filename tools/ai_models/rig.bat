@echo off
rem Rig + animate an existing GLB with Blender (no AI needed).
rem Usage: tools\ai_models\rig.bat models\Tomato.glb [--no-remesh] [--faces 5000]
rem Writes models\Tomato_rigged.glb next to the input.
call "%~dp0generate.bat" --rig-file %*
exit /b %ERRORLEVEL%
