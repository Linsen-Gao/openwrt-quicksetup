# ============================================================================
# utils/quicksetup - OpenWrt 25.12.4 纯净版快捷部署向导
# ============================================================================

include $(TOPDIR)/rules.mk

PKG_NAME:=quicksetup
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/quicksetup
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Quick Setup Wizard (TUI)
  DEPENDS:=+libnewt +ip-full +bash
endef

define Package/quicksetup/description
  A lightweight TUI-based quick setup wizard for OpenWrt 25.12.4.
endef

define Build/Configure
	true
endef

define Build/Compile
	true
endef

define Package/quicksetup/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/quicksetup.sh $(1)/usr/sbin/quicksetup

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/quicksetup.init $(1)/etc/init.d/quicksetup

	$(INSTALL_DIR) $(1)/etc/profile.d
	$(INSTALL_BIN) ./files/quicksetup.profile $(1)/etc/profile.d/quicksetup.sh

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/quicksetup.uci-default $(1)/etc/uci-defaults/90-quicksetup
endef

$(eval $(call BuildPackage,quicksetup))
