#!/bin/sh

. /lib/functions.sh

CONF_DIR="/etc/caddy"
CADDYFILE="$CONF_DIR/Caddyfile"
CUSTOM_FILE="$CONF_DIR/Caddyfile.custom"
DATA_DIR="/etc/caddy/data"
CONFIG_STORAGE="/etc/caddy/config"
CONFIG_FILE="/etc/config/caddy"

# --force: ignora el modo personalizado y regenera desde UCI (lo usa la
# pestaña Reverse Proxies al guardar). Sin --force se respeta Caddyfile.custom.
FORCE=0
for arg in "$@"; do
	case "$arg" in
		--force|-f) FORCE=1 ;;
	esac
done

mkdir -p "$CONF_DIR" "$DATA_DIR" "$CONFIG_STORAGE"

# Asegurar que los cambios guardados en staging UCI se confirmen
uci -q commit caddy

# Si custom_caddyfile está activo y existe un Caddyfile personalizado, usarlo
config_load caddy 2>/dev/null

custom_caddyfile=0
config_get_bool custom_caddyfile general custom_caddyfile 0
if [ "$custom_caddyfile" -eq 1 ] && [ "$FORCE" -ne 1 ]; then
	if [ -s "$CUSTOM_FILE" ]; then
		cp -f "$CUSTOM_FILE" "$CADDYFILE"
		chmod 600 "$CADDYFILE" 2>/dev/null
		exit 0
	fi
	if [ -s "$CADDYFILE" ]; then
		# Modo personalizado sin copia en Caddyfile.custom (edición manual por
		# SSH): se respeta el fichero actual y no se sobrescribe.
		chmod 600 "$CADDYFILE" 2>/dev/null
		exit 0
	fi
	logger -t caddy "custom_caddyfile=1 pero no existe $CUSTOM_FILE; se genera desde UCI"
fi

http_port="80"
https_port="443"
email=""
cf_token=""
log_level="INFO"

config_get http_port general http_port "80"
config_get https_port general https_port "443"
config_get email general email ""
config_get cf_token general cloudflare_token ""
config_get log_level general log_level "INFO"
[ -z "$log_level" ] && log_level="INFO"

# Validar el formato del token ANTES de escribirlo. Un token mal formado
# (comillas, llaves, espacios, longitud rara) hace que Caddy no arranque y
# además se filtraría en los logs. Caddy lo comprueba localmente, sin red.
cf_token_valid=0
if [ -n "$cf_token" ]; then
	case "$cf_token" in
		*[!A-Za-z0-9_-]*)
			logger -t caddy "Token de Cloudflare con caracteres no válidos; se omite acme_dns (el resto de la configuración se aplica igualmente)"
			cf_token=""
			;;
		*)
			if [ "${#cf_token}" -ge 32 ]; then
				cf_token_valid=1
			else
				logger -t caddy "Token de Cloudflare demasiado corto; se omite acme_dns (el resto de la configuración se aplica igualmente)"
				cf_token=""
			fi
			;;
	esac
fi

TMP_FILE="/tmp/Caddyfile.gen.$$"

# 1. Bloque de opciones globales con acme_dns cloudflare
cat <<EOF > "$TMP_FILE"
# Generated automatically by luci-app-caddy
{
EOF

[ -n "$http_port" ] && [ "$http_port" != "80" ] && echo "	http_port $http_port" >> "$TMP_FILE"
[ -n "$https_port" ] && [ "$https_port" != "443" ] && echo "	https_port $https_port" >> "$TMP_FILE"
[ -n "$email" ] && echo "	email $email" >> "$TMP_FILE"

# Configuración global de ACME DNS Cloudflare Challenge
if [ "$cf_token_valid" -eq 1 ]; then
	echo "	acme_dns cloudflare $cf_token" >> "$TMP_FILE"
fi

cat <<EOF >> "$TMP_FILE"
	log {
		level $log_level
	}
}

EOF

# 2. Bloques de servicios / reverse proxies
RULE_INDEX=1

append_proxy_rule() {
	local cfg="$1"
	local enabled name domain upstream transparent custom_headers tls_mode

	config_get_bool enabled "$cfg" enabled 1
	config_get name "$cfg" name "$cfg"
	config_get domain "$cfg" domain ""
	config_get upstream "$cfg" upstream ""
	config_get_bool transparent "$cfg" transparent 0
	config_get custom_headers "$cfg" custom_headers ""
	config_get tls_mode "$cfg" tls_mode "auto"

	# Ignorar reglas sin dominio o upstream
	[ -z "$domain" ] && return 0
	[ -z "$upstream" ] && return 0

	# Ignorar reglas desactivadas (nunca incluir servicios desactivados en el Caddyfile)
	[ "$enabled" -ne 1 ] && return 0

	# Limpiar prefijo http/https y rutas del dominio
	domain="$(echo "$domain" | sed -E 's|^https?://||; s|/.*$||')"
	# Limpiar upstream
	upstream="$(echo "$upstream" | sed -E 's|^https?://||')"

	# Modo TLS: off desactiva HTTPS usando el esquema http:// en la dirección
	site_addr="$domain"
	case "$tls_mode" in
		off)
			site_addr="http://$domain"
			;;
	esac

	# Comentario enumerado y descriptivo
	echo "# $RULE_INDEX. $name" >> "$TMP_FILE"
	RULE_INDEX=$((RULE_INDEX + 1))

	echo "$site_addr {" >> "$TMP_FILE"

	case "$tls_mode" in
		internal)
			echo "	tls internal" >> "$TMP_FILE"
			;;
		cloudflare)
			if [ "$cf_token_valid" -eq 1 ]; then
				echo "	tls {" >> "$TMP_FILE"
				echo "		dns cloudflare $cf_token" >> "$TMP_FILE"
				echo "	}" >> "$TMP_FILE"
			else
				logger -t caddy "Regla $name: tls_mode=cloudflare sin token válido; se usa HTTPS automático"
			fi
			;;
	esac

	if [ "$transparent" -eq 1 ] || [ -n "$custom_headers" ]; then
		echo "	reverse_proxy $upstream {" >> "$TMP_FILE"
		if [ "$transparent" -eq 1 ]; then
			echo "		header_up Host {upstream_hostport}" >> "$TMP_FILE"
			echo "		header_up X-Real-IP {remote_host}" >> "$TMP_FILE"
		fi
		if [ -n "$custom_headers" ]; then
			# Indentar también las líneas adicionales de directivas
			printf '%s\n' "$custom_headers" | sed 's/^/		/' >> "$TMP_FILE"
		fi
		echo "	}" >> "$TMP_FILE"
	else
		echo "	reverse_proxy $upstream" >> "$TMP_FILE"
	fi

	echo "}" >> "$TMP_FILE"
	echo "" >> "$TMP_FILE"
}

config_foreach append_proxy_rule proxy

# 3. Validar el resultado ANTES de sustituir el Caddyfile activo. Así una
#    configuración inválida (p. ej. un email o un dominio imposible) no deja
#    el servicio sin arrancar en el siguiente reinicio.
BIN="/usr/bin/caddy"
[ -x "$BIN" ] || BIN="$(command -v caddy 2>/dev/null)"

if [ -s "$TMP_FILE" ] && [ -x "$BIN" ]; then
	[ "$cf_token_valid" -eq 1 ] && export CLOUDFLARE_API_TOKEN="$cf_token"
	if ! "$BIN" validate --config "$TMP_FILE" --adapter caddyfile >/tmp/caddy-gen.err 2>&1; then
		err_out="$(cat /tmp/caddy-gen.err 2>/dev/null)"
		[ -n "$cf_token" ] && err_out="$(echo "$err_out" | sed "s|$cf_token|***|g")"
		logger -t caddy "Caddyfile generado NO válido; se conserva el anterior. Detalle: $err_out"
		rm -f "$TMP_FILE" /tmp/caddy-gen.err
		exit 1
	fi
	rm -f /tmp/caddy-gen.err
fi

# 4. Mover atómicamente el archivo final garantizando que no esté vacío
if [ -s "$TMP_FILE" ]; then
	mv -f "$TMP_FILE" "$CADDYFILE"
	chmod 600 "$CADDYFILE" 2>/dev/null
	# Caddyfile y configuración UCI contienen el token de Cloudflare
	chmod 600 "$CONFIG_FILE" 2>/dev/null
	# Normalizar formato (elimina los avisos "Caddyfile input is not formatted")
	if [ -x "$BIN" ]; then
		"$BIN" fmt --overwrite "$CADDYFILE" >/dev/null 2>&1 || true
	fi
else
	rm -f "$TMP_FILE"
fi

exit 0
