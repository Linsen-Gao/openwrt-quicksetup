#!/bin/sh
# ============================================================================
# quicksetup - OpenWrt 25.12.4 纯净版快捷部署向导
# 依赖: whiptail (libnewt), ip-full, uci, coreutils-stdbuf (可选)
# ============================================================================

VERSION="1.0.0"
TITLE="OpenWrt 快捷部署向导 v${VERSION}"

# ──────────────────────────────────────────────────────────────────────────────
# 颜色 & 样式定义（whiptail 通过 --title 控制，此处仅保留扩展位）
# ──────────────────────────────────────────────────────────────────────────────

# 检测 whiptail 是否可用
check_deps() {
    if ! command -v whiptail >/dev/null 2>&1; then
        echo "[ERROR] whiptail 未安装，请执行: opkg install libnewt 或 apk add newt"
        exit 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# 功能 1: 查看网卡信息
# ──────────────────────────────────────────────────────────────────────────────
view_nics() {
    local output=""
    local sep="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 遍历 /sys/class/net 下所有非 lo 接口
    for iface_path in /sys/class/net/*; do
        local iface
        iface=$(basename "$iface_path")

        # 跳过 loopback
        [ "$iface" = "lo" ] && continue

        # 获取 MAC 地址
        local mac=""
        if [ -f "$iface_path/address" ]; then
            mac=$(cat "$iface_path/address" 2>/dev/null)
        fi
        [ -z "$mac" ] && mac="N/A"

        # 物理链路状态: operstate (up/down/unknown)
        local operstate="unknown"
        if [ -f "$iface_path/operstate" ]; then
            operstate=$(cat "$iface_path/operstate" 2>/dev/null)
        fi

        # 判断是否为物理网卡（排除 bridge/veth/wifi 等虚拟接口）
        local devtype="虚拟"
        if [ -d "$iface_path/device" ]; then
            devtype="物理"
        elif [ -f "$iface_path/type" ]; then
            local iftype
            iftype=$(cat "$iface_path/type" 2>/dev/null)
            case "$iftype" in
                1) devtype="物理" ;;  # ARPHRD_ETHER
            esac
        fi

        # 获取 IP 地址
        local ip_info
        ip_info=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+/\d+' | head -1)
        [ -z "$ip_info" ] && ip_info="未配置"

        # 链路状态显示
        local link_display
        case "$operstate" in
            up)       link_display="UP (已连接)" ;;
            down)     link_display="DOWN (未连接)" ;;
            unknown)  link_display="UNKNOWN" ;;
            *)        link_display="$operstate" ;;
        esac

        output="${output}${sep}\n"
        output="${output}  网卡名称:  ${iface}\n"
        output="${output}  设备类型:  ${devtype}\n"
        output="${output}  MAC 地址:  ${mac}\n"
        output="${output}  链路状态:  ${link_display}\n"
        output="${output}  IPv4 地址: ${ip_info}\n"
    done

    if [ -z "$output" ]; then
        output="未检测到任何网络接口。"
    fi

    whiptail --title "$TITLE" \
             --msgbox "【网卡信息】\n\n${output}${sep}" \
             22 72 --scrolltext
}

# ──────────────────────────────────────────────────────────────────────────────
# 功能 2: 修改 LAN IP
# ──────────────────────────────────────────────────────────────────────────────

# IPv4 格式校验 (支持 CIDR /24 格式，不允许 /0-/32 以外)
validate_ipv4() {
    local ip="$1"

    # 基础正则: x.x.x.x 每段 0-255
    local ip_part='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
    local pattern="^${ip_part}\.${ip_part}\.${ip_part}\.${ip_part}$"

    if echo "$ip" | grep -qE "$pattern"; then
        return 0
    fi

    return 1
}

# 检查是否为保留地址
is_reserved_ip() {
    local ip="$1"
    case "$ip" in
        0.*|127.*|169.254.*|224.*|240.*|255.255.255.255)
            return 0 ;;
    esac
    return 1
}

change_lan_ip() {
    # 获取当前 LAN IP
    local current_ip
    current_ip=$(uci get network.lan.ipaddr 2>/dev/null)

    # 获取当前子网掩码
    local current_netmask
    current_netmask=$(uci get network.lan.netmask 2>/dev/null)
    [ -z "$current_netmask" ] && current_netmask="255.255.255.0"

    whiptail --title "$TITLE" \
             --msgbox "【修改 LAN IP】\n\n当前 LAN IP:  ${current_ip}\n当前子网掩码: ${current_netmask}\n\n提示:\n- 新 IP 必须为合法 IPv4 格式 (如 192.168.2.1)\n- 修改后将自动重启网络服务\n- 建议保持在 192.168.x.1 段" \
             16 64

    # 输入新 IP
    local new_ip
    new_ip=$(whiptail --title "$TITLE" \
                      --inputbox "请输入新的 LAN IP 地址:\n(当前: ${current_ip})" \
                      12 50 "$current_ip" \
                      3>&1 1>&2 2>&3)
    local exit_status=$?

    # 用户取消
    if [ $exit_status -ne 0 ]; then
        return 1
    fi

    # 空值检查
    if [ -z "$new_ip" ]; then
        whiptail --title "$TITLE" --msgbox "错误: IP 地址不能为空！" 8 40
        return 1
    fi

    # IPv4 格式校验
    if ! validate_ipv4 "$new_ip"; then
        whiptail --title "$TITLE" --msgbox "错误: \"${new_ip}\" 不是合法的 IPv4 地址！\n\n请输入格式如: 192.168.1.1" 10 50
        return 1
    fi

    # 保留地址检查
    if is_reserved_ip "$new_ip"; then
        whiptail --title "$TITLE" --msgbox "错误: \"${new_ip}\" 是保留地址，不可使用！" 8 50
        return 1
    fi

    # 与当前 IP 相同
    if [ "$new_ip" = "$current_ip" ]; then
        whiptail --title "$TITLE" --msgbox "新 IP 与当前 IP 相同，无需修改。" 8 40
        return 0
    fi

    # 二次确认
    if ! whiptail --title "$TITLE" \
                  --yesno "确认将 LAN IP 修改为:\n\n  ${new_ip}\n\n修改后网络将重启，你可能需要更换连接地址。" \
                  12 50; then
        return 1
    fi

    # 执行修改
    uci set network.lan.ipaddr="$new_ip"
    uci commit network

    whiptail --title "$TITLE" \
             --msgbox "LAN IP 已修改为 ${new_ip}\n\n正在重启网络服务...\n\n请使用新地址重新连接。" \
             12 50

    # 后台重启网络（避免阻塞 TTY）
    /etc/init.d/network restart >/dev/null 2>&1 &

    return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# 功能 3: 磁盘快捷写入（核心还原）
# ──────────────────────────────────────────────────────────────────────────────

# 获取 rootfs 所在磁盘（排除）
get_root_disk() {
    local root_dev
    # 通过 /proc/mounts 获取 rootfs 设备
    root_dev=$(awk '$2 == "/" {print $1}' /proc/mounts 2>/dev/null)

    if [ -z "$root_dev" ]; then
        echo ""
        return
    fi

    # 去除分区号, 如 /dev/sda1 -> /dev/sda
    echo "$root_dev" | sed -E 's/p?[0-9]+$//'
}

# 获取所有物理块设备列表（排除 rootfs 所在盘、loop、ram 等）
list_target_disks() {
    local root_disk
    root_disk=$(get_root_disk)

    # 使用 lsblk 或手动检测
    if command -v lsblk >/dev/null 2>&1; then
        lsblk -dn -o NAME,TYPE,SIZE,MODEL 2>/dev/null | \
        while read -r name type size model; do
            [ "$type" != "disk" ] && continue
            local dev="/dev/${name}"
            [ "$dev" = "$root_disk" ] && continue
            echo "${dev} ${size} ${model}"
        done
    else
        # 回退: 扫描 /sys/block
        for bdev in /sys/block/*; do
            local name
            name=$(basename "$bdev")

            # 跳过非物理设备
            case "$name" in
                loop*|ram*|dm-*|zram*) continue ;;
            esac

            local dev="/dev/${name}"
            [ "$dev" = "$root_disk" ] && continue

            # 确认是块设备
            [ ! -b "$dev" ] && continue

            # 获取容量 (以人类可读单位)
            local size_sectors
            size_sectors=$(cat "$bdev/size" 2>/dev/null || echo 0)
            local size_gb=$(( size_sectors * 512 / 1024 / 1024 / 1024 ))
            local size_human="${size_gb}GB"

            # 尝试读取 model
            local model=""
            if [ -f "$bdev/device/model" ]; then
                model=$(cat "$bdev/device/model" 2>/dev/null | sed 's/ *$//')
            fi

            echo "${dev} ${size_human} ${model}"
        done
    fi
}

# 显示磁盘列表并选择
select_disk() {
    local disks
    disks=$(list_target_disks)

    if [ -z "$disks" ]; then
        whiptail --title "$TITLE" --msgbox "未检测到可用的目标磁盘。\n\n可能原因:\n- 系统仅有一块盘（rootfs 所在盘不可选）\n- 未安装 lsblk 工具" 12 50
        return 1
    fi

    # 构建 whiptail --menu 参数
    local menu_items=""
    local count=0

    while IFS= read -r line; do
        local dev size model
        dev=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        model=$(echo "$line" | cut -d' ' -f3-)
        [ -z "$model" ] && model="(未知型号)"

        menu_items="${menu_items} ${dev} \"${size}  ${model}\""
        count=$((count + 1))
    done <<< "$disks"

    if [ "$count" -eq 0 ]; then
        whiptail --title "$TITLE" --msgbox "没有可选的目标磁盘。" 8 40
        return 1
    fi

    # 弹出选择菜单
    local selected_disk
    selected_disk=$(eval whiptail --title \"$TITLE\" \
                                  --menu \"请选择目标磁盘:\" \
                                  18 68 8 \
                                  $menu_items \
                                  3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$selected_disk" ]; then
        return 1
    fi

    echo "$selected_disk"
    return 0
}

# 安全确认框
confirm_disk_operation() {
    local disk="$1"

    # 获取磁盘详细信息
    local disk_size disk_model
    if command -v lsblk >/dev/null 2>&1; then
        disk_size=$(lsblk -dn -o SIZE "$disk" 2>/dev/null)
        disk_model=$(lsblk -dn -o MODEL "$disk" 2>/dev/null)
    else
        disk_size="(未知)"
        disk_model="(未知)"
    fi

    # 获取分区信息
    local partitions
    partitions=$(lsblk -ln -o NAME,SIZE,MOUNTPOINT "$disk" 2>/dev/null | \
                 grep -v "^$(basename "$disk") " | \
                 awk '{printf "  /dev/%s  %s  %s\n", $1, $2, ($3!="" ? "挂载:"$3 : "未挂载")}')
    [ -z "$partitionss" ] && partitions="  (无分区)"

    # 危险警告
    whiptail --title "$TITLE" \
             --defaultno \
             --yesno "⚠️  危险操作警告  ⚠️\n\n目标磁盘:  ${disk}\n磁盘容量:  ${disk_size}\n磁盘型号:  ${disk_model}\n\n当前分区:\n${partitions}\n━━━━━━━━━━━━━━━━━━━━━━━━━\n\n此操作将擦除该磁盘上的所有数据！\n请确保你已备份重要文件。\n\n确认要继续吗？" \
             22 68

    return $?
}

# dd 写入接口（标准函数，可被其他脚本调用）
do_disk_write() {
    local disk="$1"
    local image_path="$2"

    # 参数校验
    if [ -z "$disk" ] || [ ! -b "$disk" ]; then
        echo "[ERROR] 无效的磁盘设备: $disk" >&2
        return 1
    fi

    if [ -z "$image_path" ] || [ ! -f "$image_path" ]; then
        echo "[ERROR] 镜像文件不存在: $image_path" >&2
        return 1
    fi

    # 卸载该磁盘所有分区
    for part in $(lsblk -ln -o MOUNTPOINT "$disk" 2>/dev/null | grep -v '^$'); do
        umount "$part" 2>/dev/null
    done

    # 执行 dd 写入
    echo "[INFO] 开始写入: $image_path -> $disk"
    dd if="$image_path" of="$disk" bs=4M status=progress oflag=sync
    local ret=$?

    if [ $ret -eq 0 ]; then
        sync
        echo "[INFO] 写入完成。"
    else
        echo "[ERROR] 写入失败，返回码: $ret" >&2
    fi

    return $ret
}

# 磁盘挂载接口（标准函数）
do_disk_mount() {
    local disk="$1"
    local mount_point="$2"

    if [ -z "$disk" ] || [ ! -b "$disk" ]; then
        echo "[ERROR] 无效的磁盘设备: $disk" >&2
        return 1
    fi

    if [ -z "$mount_point" ]; then
        mount_point="/mnt/$(basename "$disk")"
    fi

    mkdir -p "$mount_point"

    # 尝试挂载第一个分区，若无分区则挂载整个设备
    local first_part
    first_part=$(lsblk -ln -o NAME "$disk" 2>/dev/null | sed -n '2p')
    local target="$disk"
    [ -n "$first_part" ] && target="/dev/${first_part}"

    mount "$target" "$mount_point" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "[INFO] 已将 ${target} 挂载到 ${mount_point}"
        return 0
    else
        echo "[WARN] 无法自动挂载，可能需要先格式化。" >&2
        return 1
    fi
}

# 磁盘操作子菜单
disk_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "$TITLE" \
                          --menu "【磁盘快捷操作】\n\n请选择操作:" \
                          16 58 4 \
                          "1" "查看可用磁盘列表" \
                          "2" "一键写入镜像 (dd)" \
                          "3" "挂载磁盘到 /mnt" \
                          "0" "返回主菜单" \
                          3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            1)
                # 查看磁盘列表
                local disk_info
                disk_info=$(list_target_disks)
                if [ -z "$disk_info" ]; then
                    whiptail --title "$TITLE" --msgbox "未检测到可用目标磁盘。" 8 40
                else
                    whiptail --title "$TITLE" \
                             --msgbox "可用目标磁盘:\n\n${disk_info}" \
                             16 68 --scrolltext
                fi
                ;;
            2)
                # 选择磁盘
                local disk
                disk=$(select_disk) || continue

                # 安全确认
                confirm_disk_operation "$disk" || continue

                # 输入镜像路径
                local img_path
                img_path=$(whiptail --title "$TITLE" \
                                    --inputbox "请输入镜像文件路径:\n(支持 .img / .img.gz / .iso)" \
                                    12 58 "/tmp/firmware.img" \
                                    3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && continue

                if [ ! -f "$img_path" ]; then
                    whiptail --title "$TITLE" --msgbox "文件不存在: ${img_path}" 8 50
                    continue
                fi

                # 最终确认
                if whiptail --title "$TITLE" \
                            --defaultno \
                            --yesno "最终确认:\n\n  写入: ${img_path}\n  到:   ${disk}\n\n此操作不可逆！\n按 [是] 开始写入。" \
                            14 58; then

                    whiptail --title "$TITLE" \
                             --msgbox "即将开始写入。\n\n请通过串口或 SSH 另开终端执行:\n\n  dd if=${img_path} of=${disk} bs=4M status=progress oflag=sync\n\n当前 TUI 仅为接口预留，实际写入建议在独立终端执行。" \
                             16 68
                fi
                ;;
            3)
                # 选择磁盘并挂载
                local disk
                disk=$(select_disk) || continue

                local mount_result
                mount_result=$(do_disk_mount "$disk" 2>&1)

                whiptail --title "$TITLE" \
                         --msgbox "${mount_result}" \
                         10 58
                ;;
            0|*)
                return 0
                ;;
        esac
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# 主菜单
# ──────────────────────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "$TITLE" \
                          --menu "请选择要执行的操作:" \
                          18 58 6 \
                          "1" "查看网卡信息" \
                          "2" "修改 LAN IP" \
                          "3" "磁盘快捷操作" \
                          "4" "系统状态概览" \
                          "5" "重启系统" \
                          "0" "退出向导" \
                          3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then
            # ESC 或 Ctrl+C 也退出
            break
        fi

        case "$choice" in
            1) view_nics       ;;
            2) change_lan_ip   ;;
            3) disk_menu       ;;
            4) system_overview ;;
            5) reboot_system   ;;
            0)
                whiptail --title "$TITLE" --msgbox "已退出快捷部署向导。\n\n如需再次运行，请执行:\n  quicksetup" 9 48
                break
                ;;
            *)
                whiptail --title "$TITLE" --msgbox "未知选项。" 7 30
                ;;
        esac
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# 系统状态概览
# ──────────────────────────────────────────────────────────────────────────────
system_overview() {
    local info=""

    # 主机名
    local hostname
    hostname=$(uci get system.@system[0].hostname 2>/dev/null || hostname)
    info="${info}主机名:    ${hostname}\n"

    # 内核版本
    local kernel
    kernel=$(uname -r)
    info="${info}内核版本:  ${kernel}\n"

    # 系统架构
    local arch
    arch=$(uname -m)
    info="${info}系统架构:  ${arch}\n"

    # 运行时间
    local uptime_str
    uptime_str=$(uptime 2>/dev/null | sed 's/.*up /up /' | sed 's/,.*user.*//')
    info="${info}运行时间:  ${uptime_str}\n"

    # 内存使用
    local mem_info
    mem_info=$(free -h 2>/dev/null | awk '/^Mem:/ {printf "已用 %s / 共 %s", $3, $2}')
    [ -n "$mem_info" ] && info="${info}内存使用:  ${mem_info}\n"

    # 磁盘使用
    local disk_info
    disk_info=$(df -h 2>/dev/null | awk '$6 == "/" {printf "已用 %s / 共 %s (%s)", $3, $2, $5}')
    [ -n "$disk_info" ] && info="${info}根分区:    ${disk_info}\n"

    # LAN IP
    local lan_ip
    lan_ip=$(uci get network.lan.ipaddr 2>/dev/null)
    info="${info}LAN IP:    ${lan_ip}\n"

    whiptail --title "$TITLE" \
             --msgbox "【系统状态概览】\n\n${info}" \
             18 58
}

# ──────────────────────────────────────────────────────────────────────────────
# 重启系统
# ──────────────────────────────────────────────────────────────────────────────
reboot_system() {
    if whiptail --title "$TITLE" \
                --yesno "确认要重启系统吗？\n\n所有未保存的更改将丢失。" \
                10 48; then
        whiptail --title "$TITLE" --msgbox "系统即将重启..." 6 30
        reboot
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# 入口
# ──────────────────────────────────────────────────────────────────────────────
main() {
    check_deps
    main_menu
}

# 允许被其他脚本 source 引用函数
if [ "$(basename "$0")" = "quicksetup" ] || [ "$(basename "$0")" = "quicksetup.sh" ]; then
    main "$@"
fi
