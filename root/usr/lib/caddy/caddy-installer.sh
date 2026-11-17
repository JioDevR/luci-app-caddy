#!/bin/sh
#
# caddy-installer.sh - Instalador inteligente de Caddy para OpenWrt
# Detecta arquitectura (x86_64 / aarch64), comprueba si ya existe
# una instalación previa para omitirla, o procede a instalar el binario
# con soporte para Cloudflare DNS Challenge.
#

TARGET_BIN="/usr/bin/caddy"
BUNDLED_DIR="/usr/share/caddy/bin"
BACKUP_DIR="/tmp/caddy_bin"

get_arch() {
	local m
	m="$(uname -m)"
	case "$m" in
		x86_64|amd64) echo "x86_64" ;;
		aarch64|arm64) echo "aarch64" ;;
		armv7*|armv6*) echo "arm" ;;
		mips*|mipsel*) echo "mips" ;;
		*) echo "$m" ;;
	esac
}

find_bundled_binary() {
	local arch="$1"
	local dirs="$BUNDLED_DIR $BACKUP_DIR ./bin /tmp"
	for d in $dirs; do
		if [ "$arch" = "x86_64" ] && [ -f "$d/caddy_linux_amd64_custom" ]; then
			echo "$d/caddy_linux_amd64_custom"
			return 0
		elif [ "$arch" = "aarch64" ] && [ -f "$d/caddy_linux_arm64_custom" ]; then
			echo "$d/caddy_linux_arm64_custom"
			return 0
		fi
	done
	return 1
}

cleanup_bundled_binaries() {
	# Limpieza opcional para liberar memoria flash después de instalar
	if [ -d "$BUNDLED_DIR" ]; then
		rm -rf "$BUNDLED_DIR"
	fi
}

check_status() {
	local installed=0 version="none" has_cf=0 path=""
	local arch
	arch="$(get_arch)"

	if [ -x "$TARGET_BIN" ]; then
		path="$TARGET_BIN"
	else
		path="$(which caddy 2>/dev/null)"
	fi

	if [ -n "$path" ] && [ -x "$path" ]; then
		installed=1
		local ver_out
		ver_out="$("$path" version 2>/dev/null | head -n 1)"
		[ -n "$ver_out" ] && version="$ver_out"
		if "$path" list-modules 2>/dev/null | grep -qi "cloudflare"; then
			has_cf=1
		fi
	fi

	echo "arch=$arch"
	echo "installed=$installed"
	echo "path=$path"
	echo "version=$version"
	echo "has_cloudflare=$has_cf"
}

do_install() {
	local force="$1"
	local arch
	arch="$(get_arch)"

	# 1. Comprobar si Caddy ya está instalado
	if [ -x "$TARGET_BIN" ] || command -v caddy >/dev/null 2>&1; then
		local current_path="$TARGET_BIN"
		[ -x "$current_path" ] || current_path="$(which caddy 2>/dev/null)"
		local cur_ver
		cur_ver="$("$current_path" version 2>/dev/null | head -n 1)"

		if [ "$force" != "--force" ]; then
			echo "[OMITIDO] Caddy ya está instalado en $current_path ($cur_ver). Se omite la instalación."
			# Liberar almacenamiento temporal del paquete si existe
			cleanup_bundled_binaries

			# Asegurar que los puertos 80 y 443 estén liberados para Caddy
			if [ -x /usr/lib/caddy/free-ports.sh ]; then
				/usr/lib/caddy/free-ports.sh --quiet
			fi
			return 0
		else
			echo "[AVISO] Reemplazo forzado solicitado. Actualizando Caddy en $TARGET_BIN..."
		fi
	fi

	# 2. Localizar el binario según la arquitectura detectada
	local src_bin
	src_bin="$(find_bundled_binary "$arch")"

	if [ -z "$src_bin" ] || [ ! -f "$src_bin" ]; then
		echo "[ERROR] No se encontró binario Caddy todo-en-uno compatible para la arquitectura detectada: $arch"
		return 1
	fi

	echo "-> Instalando binario Caddy ($arch) desde $src_bin a $TARGET_BIN..."
	mkdir -p /usr/bin /etc/caddy/data /etc/caddy/config /var/etc/caddy
	cp -f "$src_bin" "$TARGET_BIN"
	chmod 755 "$TARGET_BIN"

	# 3. Validar ejecución
	if "$TARGET_BIN" version >/dev/null 2>&1; then
		local new_ver
		new_ver="$("$TARGET_BIN" version | head -n 1)"
		echo "[EXITO] Caddy ($new_ver) instalado correctamente en $TARGET_BIN."

		# La configuración contiene el token de Cloudflare en claro
		chmod 600 /etc/config/caddy 2>/dev/null || true
		chmod 600 /etc/caddy/Caddyfile 2>/dev/null || true

		# Liberar puertos 80 y 443 ocupados por LuCI
		if [ -x /usr/lib/caddy/free-ports.sh ]; then
			/usr/lib/caddy/free-ports.sh --quiet
		fi

		# Limpiar binarios empaquetados para liberar espacio flash (muy importante en routers)
		cleanup_bundled_binaries
		return 0
	else
		echo "[ERROR] El binario instalado en $TARGET_BIN falló al ejecutarse. Verifique permisos o dependencias."
		return 1
	fi
}

case "$1" in
	--check)
		check_status
		;;
	--install)
		do_install "$2"
		;;
	--force)
		do_install "--force"
		;;
	*)
		echo "Uso: $0 {--check|--install|--force}"
		exit 1
		;;
esac
