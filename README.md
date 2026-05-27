# OpenWrt Quicksetup

为 OpenWrt 25.12.4 优化的纯净版 TUI 快捷部署向导，基于 Shell + whiptail，零 Luci 依赖。

## 功能

- **查看网卡** — 动态列出物理网卡名称、MAC 地址、链路状态及 IP
- **修改 LAN IP** — IPv4 格式校验 + 保留地址检测 + 安全确认
- **磁盘快捷操作** — 自动排除 rootfs、安全确认、dd 写入 / 挂载接口预留
- **系统概览** — 主机名、内核、架构、运行时间、内存、磁盘

## 编译集成

```bash
# 复制到 OpenWrt 源码
cp -r quicksetup /path/to/openwrt/package/utils/quicksetup

# 选择编译
cd /path/to/openwrt
make menuconfig
# 勾选: Utilities -> quicksetup

# 编译
make package/quicksetup/compile V=s
```

## 依赖

- `libnewt` (提供 whiptail)
- `ip-full`

## 自动启动

安装后自动启用 init.d 服务，同时通过 `/etc/profile.d/quicksetup.sh` 在物理串口终端 (tty1/ttyS0) 登录时自动呼出菜单。SSH 连接不会触发。

## 手动使用

```bash
quicksetup
```

## License

MIT
