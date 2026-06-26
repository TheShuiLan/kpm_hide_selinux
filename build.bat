@echo off
REM ============================================================================
REM 一键编译脚本：kpm_hide_selinux 通用编译脚本 (Windows)
REM
REM 用法：
REM   直接把本脚本复制到项目任意位置，双击运行 或 在命令行执行
REM
REM 特点：
REM   - 自动查找工具链 (NDK / arm-gnu-toolchain / 环境变量)
REM   - 自动定位 KernelPatch 框架目录
REM   - 从任意目录运行都能正常工作
REM   - 支持跨设备移植（复制整个项目到其他电脑也能用）
REM
REM 依赖：
REM   1. KernelPatch 框架（应位于脚本所在项目中的 KernelPatch 目录）
REM   2. ARM64 交叉编译器（NDK 或 arm-gnu-toolchain）
REM ============================================================================
setlocal enabledelayedexpansion

echo [*] kpm_hide_selinux 一键编译脚本
echo [*] ================================

REM ---- 1. 确定项目根目录（脚本所在位置的上级目录查找） ----
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM 从脚本目录向上找，直到找到 KernelPatch 目录
set "PROJECT_DIR="
set "CHECK_DIR=%SCRIPT_DIR%"
:find_project
if exist "%CHECK_DIR%\KernelPatch" (
    set "PROJECT_DIR=%CHECK_DIR%"
    goto found_project
)
REM 检查是否到了盘符根目录
if "%CHECK_DIR:~-1%"==":" (
    goto found_project
)
for %%i in ("%CHECK_DIR%") do set "CHECK_DIR=%%~dpi"
if "%CHECK_DIR%"=="" goto found_project
set "CHECK_DIR=%CHECK_DIR:~0,-1%"
goto find_project
:found_project

if "%PROJECT_DIR%"=="" (
    echo [!] 错误: 找不到 KernelPatch 目录！
    echo [!] 请确保 KernelPatch 和本模块在同一项目目录下。
    exit /b 1
)
echo [*] 项目目录: %PROJECT_DIR%

REM ---- 2. 自动查找工具链 ----
set "TOOLCHAIN_DIR="

REM 2a. 检查环境变量
if not "%TARGET_COMPILE%"=="" (
    echo [*] 使用环境变量 TARGET_COMPILE=%TARGET_COMPILE%
    goto found_tc
)

REM 2b. 检查 arm-gnu-toolchain（与 NDK 同目录）
if exist "D:\android-ndk-r26d\arm-gnu-toolchain-aarch64-none-elf\bin\aarch64-none-elf-gcc.exe" (
    set "TOOLCHAIN_DIR=D:\android-ndk-r26d\arm-gnu-toolchain-aarch64-none-elf"
    echo [*] 发现 NDK arm-gnu-toolchain
    goto found_tc
)

REM 2c. 检查 NDK clang
if exist "D:\android-ndk-r26d\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android34-clang.exe" (
    set "TOOLCHAIN_DIR=D:\android-ndk-r26d\toolchains\llvm\prebuilt\windows-x86_64"
    echo [*] 发现 NDK clang (将尝试裸机编译)
    goto found_tc
)

REM 2d. 检查常见的 msys2/cygwin 工具链
if exist "C:\msys64\usr\bin\aarch64-none-elf-gcc.exe" (
    set "TOOLCHAIN_DIR=C:\msys64\usr"
    echo [*] 发现 MSYS2 工具链
    goto found_tc
)

REM 2e. 检查 PATH 中是否有 aarch64-none-elf-gcc
where aarch64-none-elf-gcc >nul 2>nul
if %errorlevel%==0 (
    echo [*] 在 PATH 中找到 aarch64-none-elf-gcc
    set "TARGET_COMPILE=aarch64-none-elf-"
    goto found_tc
)

echo [!] 未找到 ARM64 交叉编译器！
echo [!] 请设置环境变量 TARGET_COMPILE，例如：
echo [!]   set TARGET_COMPILE=D:/android-ndk-r26d/arm-gnu-toolchain-aarch64-none-elf/bin/aarch64-none-elf-
exit /b 1

:found_tc
if not "%TOOLCHAIN_DIR%"=="" (
    if "%TOOLCHAIN_DIR%"=="D:\android-ndk-r26d\toolchains\llvm\prebuilt\windows-x86_64" (
        REM NDK clang 需要特殊处理
        echo [*] 使用 NDK clang 编译...
        set "CC=%TOOLCHAIN_DIR%\bin\aarch64-linux-android34-clang"
        set "ARCH_FLAGS=--target=aarch64-none-elf -ffreestanding -nostdlib -nostdinc"
        set "CFLAGS=!ARCH_FLAGS! -O2 -fno-PIC -Wno-ignored-attributes -Wno-unused-parameter -Wno-pointer-sign"
    ) else (
        set "TARGET_COMPILE=%TOOLCHAIN_DIR%\bin\aarch64-none-elf-"
    )
)

REM ---- 3. 构建 ----
set "MODULE_DIR=%PROJECT_DIR%\EXP\kpm_hide_selinux"
set "KP_DIR=%PROJECT_DIR%\KernelPatch"

if not exist "%MODULE_DIR%" (
    echo [!] 错误: 找不到模块目录 %MODULE_DIR%
    exit /b 1
)

echo [*] 模块目录: %MODULE_DIR%
echo [*] KernelPatch: %KP_DIR%

cd /d "%MODULE_DIR%"

if not "%CC%"=="" (
    REM ---- NDK clang 路径 ----
    echo [*] 编译器: %CC%
    echo [*] 编译中...

    set "INCLUDE_DIRS=. include patch/include linux/include linux/arch/arm64/include linux/tools/arch/arm64/include linux/security/selinux/include"
    set "INCLUDE_FLAGS="
    for %%d in (%INCLUDE_DIRS%) do set "INCLUDE_FLAGS=!INCLUDE_FLAGS! -I%KP_DIR%/kernel/%%d"

    %CC% %CFLAGS% %INCLUDE_FLAGS% -c -o hide_selinux.o hide_selinux.c
    if %errorlevel% neq 0 (
        echo [!] 编译失败！
        exit /b %errorlevel%
    )

    %CC% %CFLAGS% -r -o hide_selinux.kpm hide_selinux.o
    if %errorlevel% neq 0 (
        echo [!] 链接失败！
        exit /b %errorlevel%
    )
) else (
    REM ---- arm-gnu-toolchain gcc ----
    echo [*] 编译器前缀: %TARGET_COMPILE%
    echo [*] 编译中...

    make TARGET_COMPILE=%TARGET_COMPILE% KP_DIR=%KP_DIR%
    if %errorlevel% neq 0 (
        echo [!] 编译失败！
        exit /b %errorlevel%
    )
)

echo [*] ================================
echo [*] 编译成功！
echo [*] 输出: %MODULE_DIR%\hide_selinux.kpm
echo [*] ================================

REM ---- 4. 可选：提示推送 ----
echo.
echo 如果想推送到设备，请执行:
echo   adb push "%MODULE_DIR%\hide_selinux.kpm" /data/local/tmp/

exit /b 0