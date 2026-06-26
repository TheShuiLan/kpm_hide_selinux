#!/bin/bash
# ============================================================================
# 一键编译脚本：kpm_hide_selinux 通用编译脚本 (Linux/macOS/Cygwin/WSL)
#
# 用法：
#   ./build.sh              # 自动查找工具链并编译
#   ./build.sh clean        # 清理编译产物
#   ./build.sh push         # 编译并推送到设备
#
# 特点：
#   - 自动查找工具链
#   - 自动定位 KernelPatch 框架目录
#   - 从任意目录运行都能正常工作
#   - 支持跨设备移植
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "[*] kpm_hide_selinux 一键编译脚本"
echo "[*] 脚本目录: ${SCRIPT_DIR}"

# ---- 1. 确定项目根目录 ----
PROJECT_DIR=""
CHECK_DIR="${SCRIPT_DIR}"

while [[ "${CHECK_DIR}" != "" && "${CHECK_DIR}" != "/" ]]; do
    if [[ -d "${CHECK_DIR}/KernelPatch" ]]; then
        PROJECT_DIR="${CHECK_DIR}"
        break
    fi
    CHECK_DIR="$(dirname "${CHECK_DIR}")"
done

if [[ -z "${PROJECT_DIR}" ]]; then
    echo "[!] 错误: 找不到 KernelPatch 目录！"
    echo "[!] 请确保 KernelPatch 在本项目目录下"
    exit 1
fi
echo "[*] 项目目录: ${PROJECT_DIR}"

MODULE_DIR="${PROJECT_DIR}/EXP/kpm_hide_selinux"
KP_DIR="${PROJECT_DIR}/KernelPatch"

if [[ ! -d "${MODULE_DIR}" ]]; then
    echo "[!] 错误: 找不到模块目录 ${MODULE_DIR}"
    exit 1
fi

# ---- 2. 清理 ----
if [[ "$1" == "clean" ]]; then
    echo "[*] 清理中..."
    rm -f "${MODULE_DIR}"/hide_selinux.kpm "${MODULE_DIR}"/hide_selinux.o
    echo "[*] 已清理"
    exit 0
fi

# ---- 3. 自动查找工具链 ----
TARGET_COMPILE="${TARGET_COMPILE:-}"

# 3a. 检查环境变量
if [[ -n "${TARGET_COMPILE}" ]]; then
    echo "[*] 使用环境变量 TARGET_COMPILE=${TARGET_COMPILE}"

# 3b. 检查 arm-gnu-toolchain
elif command -v aarch64-none-elf-gcc &>/dev/null; then
    echo "[*] 在 PATH 中找到 aarch64-none-elf-gcc"
    TARGET_COMPILE="aarch64-none-elf-"

# 3c. 检查 NDK 中的 arm-gnu-toolchain
elif [[ -f "${HOME}/android-ndk-r26d/arm-gnu-toolchain-aarch64-none-elf/bin/aarch64-none-elf-gcc" ]]; then
    echo "[*] 发现 NDK arm-gnu-toolchain"
    TARGET_COMPILE="${HOME}/android-ndk-r26d/arm-gnu-toolchain-aarch64-none-elf/bin/aarch64-none-elf-"

# 3d. 检查常见的 NDK 安装路径
elif [[ -f "/opt/android-ndk-r26d/arm-gnu-toolchain-aarch64-none-elf/bin/aarch64-none-elf-gcc" ]]; then
    echo "[*] 发现 /opt/android-ndk arm-gnu-toolchain"
    TARGET_COMPILE="/opt/android-ndk-r26d/arm-gnu-toolchain-aarch64-none-elf/bin/aarch64-none-elf-"

# 3e. 检查 Android SDK NDK
elif [[ -n "${ANDROID_NDK_HOME}" ]] && [[ -f "${ANDROID_NDK_HOME}/arm-gnu-toolchain-aarch64-none-elf/bin/aarch64-none-elf-gcc" ]]; then
    echo "[*] 发现 ANDROID_NDK_HOME 工具链"
    TARGET_COMPILE="${ANDROID_NDK_HOME}/arm-gnu-toolchain-aarch64-none-elf/bin/aarch64-none-elf-"

else
    echo "[!] 错误: 未找到 ARM64 交叉编译器！"
    echo "[!] 请安装 arm-gnu-toolchain 或设置 TARGET_COMPILE 环境变量"
    echo "[!] 例如: export TARGET_COMPILE=/path/to/aarch64-none-elf-"
    exit 1
fi

# ---- 4. 编译 ----
echo "[*] 编译器: ${TARGET_COMPILE}gcc"
echo "[*] 模块目录: ${MODULE_DIR}"
echo "[*] KernelPatch: ${KP_DIR}"

cd "${MODULE_DIR}" || exit 1

make TARGET_COMPILE="${TARGET_COMPILE}" KP_DIR="${KP_DIR}" 2>&1

if [[ $? -ne 0 ]]; then
    echo "[!] 编译失败！"
    exit 1
fi

echo "[*] ================================"
echo "[*] 编译成功！"
echo "[*] 输出: ${MODULE_DIR}/hide_selinux.kpm"
echo "[*] ================================"

# ---- 5. 可选：推送 ----
if [[ "$1" == "push" ]]; then
    echo "[*] 推送到设备..."
    adb push "${MODULE_DIR}/hide_selinux.kpm" /data/local/tmp/
    if [[ $? -eq 0 ]]; then
        echo "[*] 推送成功: /data/local/tmp/hide_selinux.kpm"
    else
        echo "[!] 推送失败，请检查 adb 连接"
    fi
fi