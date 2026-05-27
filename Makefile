# ============================================================================
# utils/quicksetup - OpenWrt 25.12.4 纯净版快捷部署向导
#
# 编译方式:
#   1. 将 quicksetup/ 目录复制到 openwrt/package/utils/quicksetup
#   2. 在 openwrt 根目录执行: make menuconfig
#   3. 勾选 Utilities -> quicksetup
#   4. 执行: make package/quicksetup/compile V=s
# ============================================================================

include $(TOPDIR)/rules.mk

PKG_NAME:=quicksetup
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

# 纯脚本包，无需下载源码
PKG_SOURCE:=
PKG_SOURCE_PROTO:=

include $(INCLUDE_DIR)/package.mk

define Package/quicksetup
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Quick Setup Wizard (TUI)
  DEPENDS:=+libnewt +ip-full +bash +coreutils-od
  URL:=
endef

define Package/quicksetup/description
  A lightweight TUI-based quick setup wizard for OpenWrt 25.12.4.
  Features: network card inspection, LAN IP modification,
  disk management with dd interface.
  Built with pure Shell + whiptail, no Luci dependencies.
endef

define Build/Configure
  true
endef

define Build/Compile
  true
endef

define Package/quicksetup/install
  # 主程序
  $(INSTALL_DIR) $(1)/usr/sbin
  $(INSTALL_BIN) ./files/quicksetup.sh $(1)/usr/sbin/quicksetup

  # init.d 服务（开机自启）
  $(INSTALL_DIR) $(1)/etc/init.d
  $(INSTALL_BIN) ./files/quicksetup.init $(1)/etc/init.d/quicksetup

  # profile.d（tty 自动呼出）
  $(INSTALL_DIR) $(1)/etc/profile.d
  $(INSTALL_BIN) ./files/quicksetup.profile $(1)/etc/profile.d/quicksetup.sh

  # UCI defaults
  $(INSTALL_DIR) $(1)/etc/uci-defaults
  $(INSTALL_BIN) ./files/quicksetup.uci-default $(1)/etc/uci-defaults/90-quicksetup
endef

define Package/quicksetup/postinst
#!/bin/sh
# 开机自启
[ -f /etc/init.d/quicksetup ] && {
    chmod 755 /etc/init.d/quicksetup
    /etc/init.d/quicksetup enable 2>/dev/null
}
# 执行 uci-defaults
if [ -z "$${IPKG_INSTROOT}" ] && [ -f /etc/uci-defaults/90-quicksetup ]; then
    . /etc/uci-defaults/90-quicksetup
    rm -f /etc/uci-defaults/90-quicksetup
fi
exit 0
endef

define Package/quicksetup/postrm
#!/bin/sh
# 取消自启
/etc/init.d/quicksetup disable 2>/dev/null
# 清理 profile
rm -f /etc/profile.d/quicksetup.sh
exit 0
endef

$(eval $(call BuildPackage,quicksetup))
