/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * KPM 模块：隐藏 SELinux 宽容模式
 *
 * 功能：
 *   1. 初始化时强制 SELinux 为强制模式（写内存，无函数调用）
 *   2. 追踪 /sys/fs/selinux/enforce 的文件描述符
 *   3. 仅拦截针对该描述符的写入 "0" 操作（setenforce 0）
 *
 * 参考框架：KernelPatch (KPatch)
 */

#include <compiler.h>
#include <kpmodule.h>
#include <linux/printk.h>
#include <linux/kernel.h>
#include <linux/kallsyms.h>
#include <linux/string.h>
#include <uapi/asm-generic/unistd.h>
#include <linux/uaccess.h>
#include <syscall.h>
#include <kputils.h>

/* ========== 模块元信息 ========== */

KPM_NAME("kpm-hide-selinux");
KPM_VERSION("2.0.0X");
KPM_LICENSE("GPL v2");
KPM_AUTHOR("selux");
KPM_DESCRIPTION("KPM 模块：强制 SELinux 强制模式，追踪 fd 精确拦截 setenforce 0");

/* ========== 全局状态 ========== */

/* selinux_state 全局变量地址 */
static volatile u8 *g_selinux_state = NULL;

/* 被追踪的 /sys/fs/selinux/enforce 的文件描述符，-1 表示未追踪 */
static int g_enforce_fd = -1;

/* ========== 强制执行 SELinux 强制模式 ========== */

static void force_enforcing(void)
{
    u8 val0, val1;

    if (!g_selinux_state) {
        pr_err("kpm-hide-selinux: selinux_state 未找到\n");
        return;
    }

    val0 = g_selinux_state[0];
    val1 = g_selinux_state[1];
    pr_info("kpm-hide-selinux: selinux_state=[%d,%d]\n", val0, val1);

    if (val0 == 0) {
        g_selinux_state[0] = 1;
        pr_info("kpm-hide-selinux: 已设置 enforcing=1 (offset 0)\n");
    } else {
        g_selinux_state[1] = 1;
        pr_info("kpm-hide-selinux: 已设置 enforcing=1 (offset 1)\n");
    }
}

/* ========== openat 钩子：追踪 /sys/fs/selinux/enforce ========== */

static void before_openat(hook_fargs4_t *args, void *udata)
{
    const char __user *filename;
    char buf[256];
    long copied;

    (void)udata;

    args->local.data0 = 0;

    filename = (const char __user *)syscall_argn(args, 1);
    if (!filename) return;

    copied = compat_strncpy_from_user(buf, filename, sizeof(buf));
    if (copied <= 0) return;

    if (strcmp(buf, "/sys/fs/selinux/enforce") == 0) {
        args->local.data0 = 1;
    }
}

static void after_openat(hook_fargs4_t *args, void *udata)
{
    (void)udata;

    if (!args->local.data0) return;

    if (args->ret >= 0) {
        g_enforce_fd = (int)args->ret;
        pr_info("kpm-hide-selinux: 追踪 enforce fd=%d\n", g_enforce_fd);
    }
}

/* ========== close 钩子：清理追踪状态 ========== */

static void before_close(hook_fargs4_t *args, void *udata)
{
    unsigned int fd;
    (void)udata;

    fd = (unsigned int)syscall_argn(args, 0);
    if ((int)fd == g_enforce_fd) {
        pr_info("kpm-hide-selinux: 清理追踪 fd=%d\n", g_enforce_fd);
        g_enforce_fd = -1;
    }
}

/* ========== write 钩子：精确拦截 setenforce 0 ========== */

static void before_write(hook_fargs4_t *args, void *udata)
{
    unsigned int fd;
    const char __user *ubuf;
    long long count;
    char kbuf[4];
    long copied;

    (void)udata;

    fd = (unsigned int)syscall_argn(args, 0);

    /* 仅检查被追踪的描述符 */
    if ((int)fd != g_enforce_fd) return;
    if (fd <= 2) return;

    ubuf = (const char __user *)syscall_argn(args, 1);
    count = (long long)syscall_argn(args, 2);

    if (!ubuf || count < 1 || count > 3) return;

    copied = compat_strncpy_from_user(kbuf, ubuf, sizeof(kbuf));
    if (copied <= 0) return;

    /* 只有写入 "0" 才拦截 */
    if (copied >= 1 && copied <= 3 && kbuf[0] == '0') {
        pr_info("kpm-hide-selinux: 拦截 setenforce 0 (fd=%d)\n", fd);
        args->skip_origin = 1;
        args->ret = 1;
    }
}

/* ========== pwrite64 钩子 ========== */

static void before_pwrite64(hook_fargs4_t *args, void *udata)
{
    unsigned int fd;
    const char __user *ubuf;
    long long count;
    char kbuf[4];
    long copied;

    (void)udata;

    fd = (unsigned int)syscall_argn(args, 0);

    if ((int)fd != g_enforce_fd) return;
    if (fd <= 2) return;

    ubuf = (const char __user *)syscall_argn(args, 1);
    count = (long long)syscall_argn(args, 2);

    if (!ubuf || count < 1 || count > 3) return;

    copied = compat_strncpy_from_user(kbuf, ubuf, sizeof(kbuf));
    if (copied <= 0) return;

    if (copied >= 1 && copied <= 3 && kbuf[0] == '0') {
        pr_info("kpm-hide-selinux: 拦截 setenforce 0 (fd=%d, pwrite64)\n", fd);
        args->skip_origin = 1;
        args->ret = 1;
    }
}

/* ========== 模块初始化 ========== */

static long hide_selinux_init(const char *args, const char *event, void *__user reserved)
{
    hook_err_t err;

    pr_info("kpm-hide-selinux: 初始化 ...\n");

    /* 解析 selinux_state */
    g_selinux_state = (volatile u8 *)kallsyms_lookup_name("selinux_state");
    if (!g_selinux_state) {
        pr_err("kpm-hide-selinux: 未找到 selinux_state\n");
        return 0;
    }
    pr_info("kpm-hide-selinux: selinux_state @ %p\n", g_selinux_state);

    /* 强制执行 */
    force_enforcing();

    /* 挂载 openat：追踪 enforce 文件 */
    err = fp_hook_syscalln(__NR_openat, 4, before_openat, after_openat, 0);
    if (err) pr_err("kpm-hide-selinux: openat 钩子失败: %d\n", err);
    else pr_info("kpm-hide-selinux: openat 钩子成功\n");

    /* 挂载 close：清理追踪 */
    err = fp_hook_syscalln(__NR_close, 1, before_close, 0, 0);
    if (err) pr_err("kpm-hide-selinux: close 钩子失败: %d\n", err);
    else pr_info("kpm-hide-selinux: close 钩子成功\n");

    /* 挂载 write：精确拦截 */
    err = fp_hook_syscalln(__NR_write, 3, before_write, 0, 0);
    if (err) pr_err("kpm-hide-selinux: write 钩子失败: %d\n", err);
    else pr_info("kpm-hide-selinux: write 钩子成功\n");

    /* 挂载 pwrite64 */
    err = fp_hook_syscalln(__NR_pwrite64, 4, before_pwrite64, 0, 0);
    if (err) pr_err("kpm-hide-selinux: pwrite64 钩子失败: %d\n", err);
    else pr_info("kpm-hide-selinux: pwrite64 钩子成功\n");

    pr_info("kpm-hide-selinux: 初始化完成\n");
    return 0;
}

/* ========== 模块控制接口 ========== */

static long hide_selinux_control0(const char *ctl_args, char *__user out_msg, int outlen)
{
    char reply[64];
    int copy_len;

    sprintf(reply, "enforcing=%d fd=%d",
            g_selinux_state ? (int)g_selinux_state[0] : -1,
            g_enforce_fd);

    copy_len = outlen < (int)sizeof(reply) ? outlen : (int)sizeof(reply);
    compat_copy_to_user(out_msg, reply, copy_len);
    return 0;
}

/* ========== 模块退出 ========== */

static long hide_selinux_exit(void *__user reserved)
{
    pr_info("kpm-hide-selinux: 退出 ...\n");

    fp_unhook_syscalln(__NR_openat, before_openat, after_openat);
    fp_unhook_syscalln(__NR_close, before_close, 0);
    fp_unhook_syscalln(__NR_write, before_write, 0);
    fp_unhook_syscalln(__NR_pwrite64, before_pwrite64, 0);

    g_enforce_fd = -1;
    pr_info("kpm-hide-selinux: 已退出\n");
    return 0;
}

/* ========== 模块入口注册 ========== */

KPM_INIT(hide_selinux_init);
KPM_CTL0(hide_selinux_control0);
KPM_EXIT(hide_selinux_exit);