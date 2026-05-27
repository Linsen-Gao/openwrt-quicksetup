#!/bin/sh
# ============================================================================
# quicksetup 自动启动脚本
# 放置于 /etc/profile.d/ 或 /etc/rc.local 中
#
# 工作方式:
#   仅在物理串口终端 (tty1, ttyS0, ttyAMA0) 登录时自动呼出菜单
#   SSH 远程连接不会触发
# ============================================================================

# 仅对 tty 生效（排除 SSH 的 pts）
case "$(tty)" in
    /dev/tty1|/dev/ttyS0|/dev/ttyAMA0|/dev/tty0)
        # 避免循环嵌套调用
        if [ -z "$QUICKSETUP_RUNNING" ]; then
            export QUICKSETUP_RUNNING=1
            quicksetup
        fi
        ;;
esac
