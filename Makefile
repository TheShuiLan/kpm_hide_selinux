ifndef KP_DIR
    KP_DIR = ../../KernelPatch
endif

# 使用 NDK 的 clang 编译器（代替 gcc）
# 设置 NDK_DIR 指向 NDK 工具链目录，例如:
#   make NDK_DIR=D:/android-ndk-r26d/toolchains/llvm/prebuilt/windows-x86_64
#
# Windows PowerShell 示例:
#   $env:NDK_DIR="D:\android-ndk-r26d\toolchains\llvm\prebuilt\windows-x86_64"; make
#
# 如果未设置 NDK_DIR，则尝试使用 TARGET_COMPILE（传统 gcc 方式）
ifdef NDK_DIR
    CC = $(NDK_DIR)/bin/aarch64-linux-android34-clang
    LD = $(NDK_DIR)/bin/ld.lld

    # 裸机 ARM64 编译标志（clang）
    # 注意：不使用 --target=aarch64-none-elf 以避免 clang 生成特殊的
    # 裸机目标 ELF 布局。直接用 Android 目标但加 -ffreestanding。
    ARCH_FLAGS := -ffreestanding -nostdlib -nostdinc
    CFLAGS := $(ARCH_FLAGS) -O2 -fno-PIC \
              -Wno-ignored-attributes \
              -Wno-unused-parameter \
              -Wno-pointer-sign \
              -Wno-implicit-function-declaration
else ifdef TARGET_COMPILE
    CC = $(TARGET_COMPILE)gcc
    LD = $(TARGET_COMPILE)ld
    CFLAGS = -O2
else
    ifeq ($(MAKECMDGOALS),clean)
        # clean 目标不需要编译器，直接定义空变量跳过
        CC = echo
        LD = echo
        CFLAGS =
    else
        # 其他目标需要设置
        $(info [*] 提示: 未设置 NDK_DIR 或 TARGET_COMPILE)
        $(info [*] 请使用以下任一方式编译:)
        $(info [*]   1. make NDK_DIR=D:/android-ndk-r26d/toolchains/llvm/prebuilt/windows-x86_64)
        $(info [*]   2. set TARGET_COMPILE=aarch64-none-elf- && make)
        $(error 需要设置 NDK_DIR 或 TARGET_COMPILE)
    endif
endif

INCLUDE_DIRS := . include patch/include linux/include linux/arch/arm64/include linux/tools/arch/arm64/include linux/security/selinux/include

INCLUDE_FLAGS := $(foreach dir,$(INCLUDE_DIRS),-I$(KP_DIR)/kernel/$(dir))

objs := hide_selinux.o

all: hide_selinux.kpm

hide_selinux.kpm: ${objs}
	$(LD) -r -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) $(INCLUDE_FLAGS) -c -o $@ $<

.PHONY: clean
clean:
	-del /f /q *.kpm *.o 2>nul
	-rm -rf *.kpm 2>/dev/null; find . -name "*.o" -delete 2>/dev/null
	@echo 清理完成

.PHONY: push
push: hide_selinux.kpm
	adb push hide_selinux.kpm /data/local/tmp/

.PHONY: load
load: push
	adb shell su -c "cp /data/local/tmp/hide_selinux.kpm /data/adb/modules/kpm_hide_selinux/ && echo '模块已复制到 /data/adb/modules/kpm_hide_selinux/'"