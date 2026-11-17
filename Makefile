#
# Copyright (C) 2026 OpenWrt.org
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for Caddy Web Server & Reverse Proxy with Cloudflare DNS
# NOTA: esta dependencia aplica al paquete compilado con el buildroot de
# OpenWrt (make package/luci-app-caddy/compile). El paquete .apk que genera
# ./build_apk.sh es autónomo: incluye sus propios binarios de Caddy
# (x86_64 + aarch64, con dns.providers.cloudflare) y NO depende del paquete
# "caddy" de los repos, para poder instalarse sin acceso a Internet.
# En el flujo del buildroot, "+caddy" instala el Caddy del repos oficial, por
# lo que caddy-installer.sh omitirá la instalación del binario propio.
LUCI_DEPENDS:=+caddy
LUCI_PKGARCH:=all
PKG_VERSION:=1.0.3
PKG_RELEASE:=1

define Package/luci-app-caddy/conffiles
/etc/config/caddy
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
