#!/bin/sh
#
# install.sh - Instalador en 1 línea de luci-app-caddy para OpenWrt (apk)
#
# Uso:
#   wget -qO- https://raw.githubusercontent.com/JioDevR/luci-app-caddy/main/install.sh | sh
#
# Variables opcionales:
#   VERSION=v1.0.4   Instala una versión/tag específico (por defecto: latest)
#   REPO=...         Repositorio GitHub (por defecto: JioDevR/luci-app-caddy)
#

set -e

REPO="${REPO:-JioDevR/luci-app-caddy}"
VERSION="${VERSION:-latest}"
TMP_DIR="$(mktemp -d /tmp/luci-app-caddy-install.XXXXXX)"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

log() {
    printf '[luci-app-caddy] %s\n' "$1"
}

err() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

# 1. Comprobar que el router usa apk (OpenWrt 24.x+ / snapshots)
if ! command -v apk >/dev/null 2>&1; then
    if command -v opkg >/dev/null 2>&1; then
        err "Este router usa 'opkg' (.ipk) y este instalador distribuye paquetes '.apk' para OpenWrt con apk-tools. Consulta el Makefile del repositorio para compilar con OpenWrt SDK."
    fi
    err "No se encontró el gestor de paquetes 'apk' en el sistema."
fi

# 2. Detectar arquitectura
RAW_ARCH="$(uname -m)"
case "$RAW_ARCH" in
    x86_64|amd64)
        ARCH="x86_64"
        ;;
    aarch64|arm64)
        ARCH="aarch64"
        ;;
    *)
        err "Arquitectura no soportada: $RAW_ARCH (solo x86_64 y aarch64)."
        ;;
esac

PKG_FILE="luci-app-caddy-${ARCH}.apk"
SHA_FILE="${PKG_FILE}.sha256"

if [ "$VERSION" = "latest" ]; then
    BASE_URL="https://github.com/${REPO}/releases/latest/download"
else
    BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
fi

# 3. Comprobar espacio libre en /tmp (al menos ~25 MB para descarga + extracción)
FREE_KB="$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt 25600 ] 2>/dev/null; then
    FREE_MB=$((FREE_KB / 1024))
    err "Espacio insuficiente en /tmp (${FREE_MB} MB disponibles, se recomiendan al menos 25 MB)."
fi

# 4. Función de descarga compatible con curl, wget (BusyBox/GNU) y uclient-fetch
download_file() {
    local url="$1"
    local dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$dest" "$url"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$dest" "$url"
    else
        err "No se encontró curl, wget ni uclient-fetch para descargar el paquete."
    fi
}

log "Arquitectura detectada: $ARCH ($RAW_ARCH)"
log "Descargando $PKG_FILE desde $BASE_URL..."
download_file "${BASE_URL}/${PKG_FILE}" "${TMP_DIR}/${PKG_FILE}" \
    || err "No se pudo descargar ${PKG_FILE}. Verifica tu conexión o que la release exista."

log "Descargando checksum $SHA_FILE..."
if download_file "${BASE_URL}/${SHA_FILE}" "${TMP_DIR}/${SHA_FILE}"; then
    if command -v sha256sum >/dev/null 2>&1; then
        log "Verificando integridad SHA256..."
        ( cd "$TMP_DIR" && sha256sum -c "$SHA_FILE" ) \
            || err "La verificación SHA256 falló. El archivo descargado está corrupto o incompleto."
    else
        log "Aviso: 'sha256sum' no está disponible, se omite la verificación de hash."
    fi
else
    err "No se pudo descargar ${SHA_FILE}."
fi

# 5. Instalar paquete
log "Instalando ${PKG_FILE}..."
apk add --allow-untrusted "${TMP_DIR}/${PKG_FILE}"

# 6. Mostrar URL de acceso a LuCI
LAN_IP="$(uci -q get network.lan.ipaddr 2>/dev/null | cut -d/ -f1 || true)"
[ -z "$LAN_IP" ] && LAN_IP="<IP-DEL-ROUTER>"

echo ""
log "Instalación completada."
log "Accede a LuCI en:"
log "  http://${LAN_IP}:8080"
log "  https://${LAN_IP}:8443"
