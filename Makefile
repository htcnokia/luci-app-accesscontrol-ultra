include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Access Control Ultra
LUCI_PKGARCH:=all
PKG_NAME:=luci-app-accesscontrol-ultra
PKG_VERSION:=3.6
PKG_RELEASE:=5

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

