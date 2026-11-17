#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_NAME="luci-app-caddy"
PKG_VER="1.0.3"
PKG_REL="1"
DIST_DIR="$DIR/dist"
APK_TOOL="$DIR/tools/apk.static"

if [ ! -x "$APK_TOOL" ]; then
    if command -v apk >/dev/null 2>&1; then
        APK_TOOL="apk"
    else
        echo "ERROR: No se encontró apk.static ni apk en el sistema."
        exit 1
    fi
fi

# Limpiar paquetes anteriores en dist/
mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR"/*.apk

echo "=========================================================="
echo "  Construyendo APK nativo para OpenWrt (apk-tools v3 / OpenWrt 24.x+)"
echo "  (Soporte ARM64 + x86_64 + Cloudflare Challenge + Auto-Check)"
echo "=========================================================="

# -----------------------------------------------------------------------------
# Ejecuta un comando viendo el sistema de ficheros como si fuéramos root.
#
# apk-tools v3 guarda en el paquete el PROPIETARIO (usuario/grupo) por NOMBRE,
# no por UID. Ese nombre se resuelve contra el /etc/passwd del sistema
# DESTINO al instalar. Si construimos el paquete como usuario normal
# (p.ej. "jiodev"), el paquete queda con owner="jiodev" y al instalarlo en
# el router (donde ese usuario no existe) apk le asigna uid/gid 65534
# (nobody:nogroup) a /etc/config/caddy, /etc/init.d/caddy, etc.
#
# Ejecutando el empaquetado dentro de un user namespace donde nuestro UID se
# mapea a 0, stat() devuelve uid 0 y apk registra correctamente root:root.
# No requiere privilegios reales: el paquete queda bien aunque el árbol de
# build siga siendo propiedad del usuario de compilación.
# -----------------------------------------------------------------------------
run_packaging() {
    if [ "$(id -u)" = "0" ]; then
        "$@"
        return 0
    fi
    if command -v unshare >/dev/null 2>&1 && unshare -Ur true >/dev/null 2>&1; then
        unshare -Ur "$@"
        return $?
    fi
    echo "AVISO: no se pudo forzar propietario root:root (unshare no disponible)." >&2
    echo "       El paquete se generará con el propietario del usuario actual." >&2
    "$@"
}

build_apk() {
    local out_name="$1"
    local variant="$2"
    local arch="${3:-noarch}"
    local build_tmp
    build_tmp="$(mktemp -d)"

    echo "-> Preparando archivos para $out_name ($arch)..."

    # Copiar contenido raíz
    cp -r "$DIR/root/"* "$build_tmp/"

    # Integración de binarios según la variante
    mkdir -p "$build_tmp/usr/share/caddy/bin"
    if [ "$variant" = "all-in-one" ]; then
        if [ -f "$DIR/bin/caddy_linux_amd64_custom" ]; then
            echo "   [+] Integrando binario x86_64..."
            cp -f "$DIR/bin/caddy_linux_amd64_custom" "$build_tmp/usr/share/caddy/bin/"
            chmod 755 "$build_tmp/usr/share/caddy/bin/caddy_linux_amd64_custom"
        fi
        if [ -f "$DIR/bin/caddy_linux_arm64_custom" ]; then
            echo "   [+] Integrando binario aarch64 (arm64)..."
            cp -f "$DIR/bin/caddy_linux_arm64_custom" "$build_tmp/usr/share/caddy/bin/"
            chmod 755 "$build_tmp/usr/share/caddy/bin/caddy_linux_arm64_custom"
        fi
    elif [ "$variant" = "amd64" ] && [ -f "$DIR/bin/caddy_linux_amd64_custom" ]; then
        cp -f "$DIR/bin/caddy_linux_amd64_custom" "$build_tmp/usr/share/caddy/bin/"
        chmod 755 "$build_tmp/usr/share/caddy/bin/caddy_linux_amd64_custom"
    elif [ "$variant" = "arm64" ] && [ -f "$DIR/bin/caddy_linux_arm64_custom" ]; then
        cp -f "$DIR/bin/caddy_linux_arm64_custom" "$build_tmp/usr/share/caddy/bin/"
        chmod 755 "$build_tmp/usr/share/caddy/bin/caddy_linux_arm64_custom"
    fi

    # Permisos estándar de OpenWrt
    chmod 755 "$build_tmp/etc/init.d/caddy"
    chmod 755 "$build_tmp/usr/libexec/rpcd/luci.caddy"
    chmod 755 "$build_tmp/usr/lib/caddy/caddy-installer.sh"
    chmod 755 "$build_tmp/usr/lib/caddy/generate-caddyfile.sh"
    chmod 600 "$build_tmp/etc/config/caddy"

    # Script post-install.
    # IMPORTANTE: el script debe vivir FUERA del árbol que se empaqueta.
    # Si se creara dentro de $build_tmp, "apk mkpkg --files" lo incluiría
    # como un fichero normal y se instalaría en "/" del router (archivo
    # basura /.post-install).
    local postinst_file
    postinst_file="$(mktemp "${TMPDIR:-/tmp}/luci-app-caddy-postinst.XXXXXX")"
    cat <<'EOF' > "$postinst_file"
#!/bin/sh

# 0. Limpiar regla de ejemplo obsoleta si existe en UCI
if [ -f /etc/config/caddy ]; then
    count="$(uci -q show caddy 2>/dev/null | grep -c '=proxy$')"
    i=$((count - 1))
    while [ "$i" -ge 0 ]; do
        d="$(uci -q get "caddy.@proxy[$i].domain" 2>/dev/null)"
        n="$(uci -q get "caddy.@proxy[$i].name" 2>/dev/null)"
        if [ "$d" = "ejemplo.tudominio.com" ] || [ "$n" = "ejemplo-web" ]; then
            uci -q delete "caddy.@proxy[$i]"
        fi
        i=$((i - 1))
    done
    uci -q commit caddy 2>/dev/null || true
fi

# 1. Comprobar y liberar puertos 80 y 443 ocupados por LuCI (uhttpd/nginx)
if [ -x /usr/lib/caddy/free-ports.sh ]; then
    /usr/lib/caddy/free-ports.sh
fi

# 2. Ejecutar el instalador inteligente todo-en-uno
if [ -x /usr/lib/caddy/caddy-installer.sh ]; then
    /usr/lib/caddy/caddy-installer.sh --install
fi

# 3. Generar Caddyfile en /etc/caddy/Caddyfile y habilitar servicio
if [ -x /usr/lib/caddy/generate-caddyfile.sh ]; then
    /usr/lib/caddy/generate-caddyfile.sh
fi
if [ -f /etc/init.d/caddy ]; then
    # "reload" es el verbo válido de rc.common (reload_service es una función
    # interna del init script, no un comando: imprimía la ayuda y no hacía nada)
    /etc/init.d/caddy reload >/dev/null 2>&1 || true
    [ "$(uci -q get caddy.general.enabled 2>/dev/null)" = "1" ] && /etc/init.d/caddy enable
fi

# 4. Registrar caddy en ucitrack para integración con LuCI Save & Apply
if command -v uci >/dev/null 2>&1; then
    uci -q delete ucitrack.caddy 2>/dev/null || true
    uci -q set ucitrack.caddy=caddy
    uci -q set ucitrack.caddy.init='caddy'
    uci -q commit ucitrack 2>/dev/null || true
fi

# 5. Permisos: la configuración contiene el token de Cloudflare en claro
chmod 600 /etc/config/caddy 2>/dev/null || true
chmod 600 /etc/caddy/Caddyfile 2>/dev/null || true

# 6. Recargar RPCD y LuCI
/etc/init.d/rpcd restart >/dev/null 2>&1 || true

exit 0
EOF
    chmod 755 "$postinst_file"

    echo "   [+] Empaquetando formato nativo APK con apk mkpkg..."
    run_packaging "$APK_TOOL" mkpkg \
        --info "name:$PKG_NAME" \
        --info "version:${PKG_VER}-r${PKG_REL}" \
        --info "arch:$arch" \
        --info "description:LuCI interface for Caddy reverse proxy with Cloudflare DNS challenge" \
        --info "depends:luci-base" \
        --script "post-install:$postinst_file" \
        --script "post-upgrade:$postinst_file" \
        --files "$build_tmp" \
        -o "$DIST_DIR/$out_name"

    # Eliminar archivo temporal del script (ya está embebido en el paquete)
    rm -f "$postinst_file"

    # Verificación de integridad con apk-tools
    "$APK_TOOL" verify --allow-untrusted "$DIST_DIR/$out_name" >/dev/null 2>&1
    echo "   [OK] Verificado: $DIST_DIR/$out_name"

    # Comprobaciones del contenido del paquete
    verify_package "$DIST_DIR/$out_name"

    rm -rf "$build_tmp"
}

# Comprueba que el paquete no contenga ficheros basura en la raíz (por ejemplo
# el script post-install) y que todos los ficheros pertenezcan a root:root.
verify_package() {
    local pkg="$1"
    local dump
    dump="$("$APK_TOOL" adbdump "$pkg" 2>/dev/null)"

    if printf '%s' "$dump" | grep -qE '^\s+- name: \.[a-zA-Z]'; then
        echo "   [ERROR] El paquete contiene ficheros ocultos en la raíz:" >&2
        printf '%s' "$dump" | grep -E '^\s+- name: \.[a-zA-Z]' >&2
        exit 1
    fi

    local bad_owner
    bad_owner="$(printf '%s' "$dump" | grep -E '^\s+user:' | grep -v 'user: root' | sort -u)"
    if [ -n "$bad_owner" ]; then
        echo "   [ERROR] Propietario incorrecto en el paquete: $bad_owner" >&2
        exit 1
    fi
    echo "   [OK] Contenido: sin ficheros basura y propiedad root:root"
}

# Paquete Todo-en-Uno (Contiene binarios x86_64 y ARM64 con detección automática)
build_apk "luci-app-caddy.apk" "all-in-one" "noarch"

echo ""
echo "=== Paquetes generados con éxito en dist/ ==="
ls -lh "$DIST_DIR"
