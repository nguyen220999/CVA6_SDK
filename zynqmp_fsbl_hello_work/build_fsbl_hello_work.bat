@echo off
setlocal EnableExtensions

rem Build zynqmp_fsbl_hello_work for Cortex-A53 64-bit with Vitis 2024.2.
rem Optional environment variables:
rem   VITIS_ROOT - Vitis installation directory.
rem   BSP_DIR    - Exported standalone_psu_cortexa53_0 BSP directory.

if not defined VITIS_ROOT set "VITIS_ROOT=C:\Xilinx\Vitis\2024.2"
if not defined BSP_DIR set "BSP_DIR=%USERPROFILE%\Downloads\platform_fsbl_hello_work\platform_fsbl_hello_work\export\platform_fsbl_hello_work\sw\standalone_psu_cortexa53_0"

set "FSBL_DIR=%~dp0"
set "SOURCE_DIR=%FSBL_DIR%src"
set "BUILD_DIR=%FSBL_DIR%build-windows"
set "OUTPUT_ELF=%BUILD_DIR%\zynqmp_fsbl_hello_work.elf"

if not exist "%VITIS_ROOT%\settings64.bat" (
    echo ERROR: Vitis environment script was not found:
    echo        %VITIS_ROOT%\settings64.bat
    echo Set VITIS_ROOT to the Vitis 2024.2 installation directory.
    exit /b 1
)

if not exist "%BSP_DIR%\cortexa53_toolchain.cmake" (
    echo ERROR: Cortex-A53 BSP was not found:
    echo        %BSP_DIR%
    echo Set BSP_DIR to the exported standalone_psu_cortexa53_0 directory.
    exit /b 1
)

call "%VITIS_ROOT%\settings64.bat"
if errorlevel 1 goto :error

where cmake >nul 2>&1
if errorlevel 1 (
    echo ERROR: cmake was not found after loading the Vitis environment.
    exit /b 1
)

where ninja >nul 2>&1
if errorlevel 1 (
    echo ERROR: ninja was not found after loading the Vitis environment.
    exit /b 1
)

echo Configuring FSBL...
cmake ^
    -S "%SOURCE_DIR%" ^
    -B "%BUILD_DIR%" ^
    -G Ninja ^
    "-DCMAKE_TOOLCHAIN_FILE=%BSP_DIR%\cortexa53_toolchain.cmake" ^
    "-DCMAKE_MODULE_PATH=%BSP_DIR%" ^
    "-DCMAKE_PREFIX_PATH=%BSP_DIR%" ^
    "-DCMAKE_INCLUDE_PATH=%BSP_DIR%\include" ^
    "-DCMAKE_LIBRARY_PATH=%BSP_DIR%\lib" ^
    "-DCMAKE_SPECS_FILE=%BSP_DIR%\Xilinx.spec" ^
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
if errorlevel 1 goto :error

echo Building FSBL...
cmake --build "%BUILD_DIR%" --parallel
if errorlevel 1 goto :error

if not exist "%OUTPUT_ELF%" (
    echo ERROR: Build completed without producing the expected ELF:
    echo        %OUTPUT_ELF%
    exit /b 1
)

echo.
echo FSBL build completed successfully.
echo Output: %OUTPUT_ELF%

where aarch64-none-elf-size >nul 2>&1
if not errorlevel 1 aarch64-none-elf-size "%OUTPUT_ELF%"

exit /b 0

:error
set "BUILD_ERROR=%ERRORLEVEL%"
echo.
echo ERROR: FSBL build failed with exit code %BUILD_ERROR%.
exit /b %BUILD_ERROR%
