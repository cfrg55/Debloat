@echo off
title Windows Optimizer Launcher
color 0A

cls
echo.
echo =======================================================================
echo   OptimizerWin v8.8 - by CFRG
echo   Creado por CFRG - el negrito del ritmo
echo =======================================================================
echo.

:: ===== CONFIGURACION =====
set "RAW_URL=https://raw.githubusercontent.com/cfrg55/Debloat/refs/heads/main/WindowsOptimizer"
set "LOCAL_SCRIPT=WindowsOptimizer.ps1"
set "TEMP_SCRIPT=%TEMP%\WO.ps1"

:: ===== PASO 1: DESCARGAR SCRIPT DESDE GITHUB =====
echo [1/3] Descargando WindowsOptimizer desde GitHub...
echo.

powershell -Command "& {Invoke-WebRequest -Uri '%RAW_URL%' -OutFile '%LOCAL_SCRIPT%'}" 2>nul

:: Verificar si la descarga fue exitosa
if exist "%LOCAL_SCRIPT%" (
    echo [OK] Descarga completada: %LOCAL_SCRIPT%
    echo.
) else (
    echo [ERROR] No se pudo descargar el script desde GitHub.
    echo Verifica tu conexion a Internet.
    echo.
    pause
    exit /b 1
)

:: ===== PASO 2: EJECUTAR EL SCRIPT =====
echo [2/2] Ejecutando script...
echo.

:: EJECUTAR SIN ELEVACION - EL SCRIPT MISMO PEDIRA ELEVACION
powershell -ExecutionPolicy Bypass -File "%LOCAL_SCRIPT%"

echo.
echo [OK] Ejecucion finalizada.

echo =======================================================================
echo   Gracias por su visita - vuelva pronto
echo =======================================================================

:: Preguntar si quiere eliminar el script local descargado
echo.
set /p "DEL_LOCAL=¿Deseas eliminar el archivo %LOCAL_SCRIPT%? (S/N): "
if /i "%DEL_LOCAL%"=="S" (
    del "%LOCAL_SCRIPT%" /Q 2>nul
    echo [OK] Archivo local eliminado.
) else (
    echo [OK] Archivo local conservado: %LOCAL_SCRIPT%
)

echo.
echo Proceso completado.
echo.
pause