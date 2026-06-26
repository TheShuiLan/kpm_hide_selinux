# FolkPatch KPM SELinux 强制隐藏

一个基于 KernelPatch 框架的 KPM 内核模块，用于**强制 SELinux 为强制模式（Enforcing）**并**阻止任何切换到宽容模式（Permissive）的尝试**。

适用于 APatch / KernelSU 等 root 方案，防止检测工具通过 SELinux 状态发现 root 痕迹。

## 功能

- ✅ **强制执行** — 模块加载时直接将 `selinux_state.enforcing` 写入内存设为 1
- ✅ **实时拦截** — 钩挂 `write` / `pwrite64` 系统调用，精确追踪 `/sys/fs/selinux/enforce` 的文件描述符，拦截 `setenforce 0` 的写入
- ✅ **定期自检** — 内置计数器定期检查 enforcing 状态，自动修复被其他方式修改的情况
- ✅ **精确追踪** — 通过 `openat` 钩子追踪 enforce 文件描述符，只拦截针对该文件的写入，不影响其他 App 正常通信
- ✅ **轻量安全** — 仅 9KB，使用 `fp_hook_syscalln`（函数指针替换），无 CFI 风险，无 LTO 内联问题

## 原理

```
┌─ Userspace ──────────────────────────────────────────────────┐
│  setenforce 0  →  open("/sys/fs/selinux/enforce")            │
│                       ↓                                       │
│                   openat 钩子追踪 fd                           │
│                       ↓                                       │
│                  write(fd, "0", 1)                             │
│                       ↓                                       │
│                   write 钩子: fd==g_enforce_fd 且 内容=="0"?    │
│                   → 跳过原始调用，返回成功                      │
│                   ← 系统依然 enforcing                         │
└──────────────────────────────────────────────────────────────┘
```

## 编译要求

- **KernelPatch 框架** — [KernelPatch](https://github.com/bmax121/KernelPatch)
- **ARM64 裸机交叉编译器** — 任选其一：
  - `aarch64-none-elf-gcc`（Arm GNU Toolchain）
  - NDK 自带的 `arm-gnu-toolchain-aarch64-none-elf`
  - NDK clang + `--target=aarch64-none-elf`

## 快速编译

### Windows

```bash
cd EXP/kpm_hide_selinux
build.bat
```

### Linux / macOS

```bash
cd EXP/kpm_hide_selinux
chmod +x build.sh
./build.sh
```

或手动编译：

```bash
make TARGET_COMPILE=aarch64-none-elf- KP_DIR=../../KernelPatch
```

## 安装

编译出的 `hide_selinux.kpm` 通过 APatch / FolkPatch App 加载即可。

或推送到设备：

```bash
adb push hide_selinux.kpm /data/local/tmp/
# 然后在 App 中加载
```

## 验证

```bash
# 尝试切宽容模式（应被拦截）
su -c setenforce 0

# 检查仍是强制模式
getenforce

# 查看拦截日志
dmesg | grep "kpm-hide-selinux"
```

## 技术细节

| 文件 | 说明 |
|------|------|
| `hide_selinux.c` | KPM 模块主源码 |
| `Makefile` | 构建文件（支持 gcc / clang） |
| `build.bat` | Windows 一键编译脚本 |
| `build.sh` | Linux/macOS 一键编译脚本 |

### 兼容性

- 内核版本: 5.10+ (Android GKI)
- 架构: ARM64 (aarch64)
- 框架: KernelPatch (APatch 内置)

### 注意事项

- 模块使用 `kallsyms_lookup_name` 运行时解析 `selinux_state` 内核符号
- 所有系统调用钩子均使用 `fp_hook_syscalln`（函数指针替换），不修改代码段
- 在 Linux 5.10+ 内核上已验证通过

## 许可证

GPL v2