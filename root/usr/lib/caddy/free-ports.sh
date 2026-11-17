#!/bin/sh
#
# free-ports.sh - Libera los puertos 80 y 443 ocupados por LuCI (uhttpd / nginx)
# para que Caddy pueda operar como Reverse Proxy principal en el router.
# Si los puertos alternativos están ocupados, busca automáticamente el siguiente
# puerto disponible hasta encontrar uno libre.
# Si ya están liberados o reasignados, se omite con aviso claro.
#

CHANGED=0
ALREADY_FREE=0
NEW_HTTP_PORT=""
NEW_HTTPS_PORT=""
CURRENT_HTTP_PORT=""
CURRENT_HTTPS_PORT=""
MODE="${1:-}"

# Comprobar si un puerto TCP está en uso (LISTEN) en el sistema
is_port_in_use() {
	local port="$1"
	[ -z "$port" ] && return 1

	# 1. Comprobar /proc/net/tcp y /proc/net/tcp6 (100% nativo kernel Linux, sin dependencias)
	local hex
	hex=$(printf "%04x" "$port" 2>/dev/null)
	if [ -n "$hex" ]; then
		if grep -qiE ":${hex}[[:space:]]+[0-9A-Fa-f:]+[[:space:]]+0A[[:space:]]" /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
			return 0
		fi
	fi

	# 2. Comprobar netstat si está disponible
	if command -v netstat >/dev/null 2>&1; then
		if netstat -lnt 2>/dev/null | grep -qE "[: ]${port}[[:space:]]"; then
			return 0
		fi
	fi

	# 3. Comprobar ss si está disponible
	if command -v ss >/dev/null 2>&1; then
		if ss -lnt 2>/dev/null | grep -qE "[: ]${port}[[:space:]]"; then
			return 0
		fi
	fi

	return 1
}

# Buscar el siguiente puerto libre disponible a partir de un puerto inicial
find_next_free_port() {
	local candidate="$1"
	local exclude="${2:-0}"
	local max_port=65535

	while [ "$candidate" -le "$max_port" ]; do
		# Los puertos 80 y 443 quedan reservados para Caddy
		if [ "$candidate" -ne 80 ] && [ "$candidate" -ne 443 ] && [ "$candidate" -ne "$exclude" ]; then
			if ! is_port_in_use "$candidate"; then
				echo "$candidate"
				return 0
			fi
		fi
		candidate=$((candidate + 1))
	done

	echo "$1"
	return 1
}

# Obtener los puertos actuales en los que escucha LuCI
get_current_luci_ports() {
	local h="" hs=""

	if [ -f /etc/config/uhttpd ]; then
		# Extraer puerto HTTP de uhttpd
		h=$(grep -E "listen_http[[:space:]]" /etc/config/uhttpd 2>/dev/null | sed -n -E 's/.*:([0-9]+).*/\1/p' | head -n 1)
		if [ -z "$h" ]; then
			h=$(grep -E "listen_http[[:space:]]" /etc/config/uhttpd 2>/dev/null | grep -oE '[0-9]+' | tail -n 1)
		fi

		# Extraer puerto HTTPS de uhttpd
		hs=$(grep -E "listen_https[[:space:]]" /etc/config/uhttpd 2>/dev/null | sed -n -E 's/.*:([0-9]+).*/\1/p' | head -n 1)
		if [ -z "$hs" ]; then
			hs=$(grep -E "listen_https[[:space:]]" /etc/config/uhttpd 2>/dev/null | grep -oE '[0-9]+' | tail -n 1)
		fi
	fi

	# Si uhttpd no está presente o no se encontraron puertos, comprobar UCI
	if [ -z "$h" ] && command -v uci >/dev/null 2>&1; then
		local lh
		lh="$(uci -q get uhttpd.main.listen_http 2>/dev/null)"
		h=$(echo "$lh" | sed -n -E 's/.*:([0-9]+).*/\1/p' | head -n 1)
		[ -z "$h" ] && h=$(echo "$lh" | grep -oE '[0-9]+' | tail -n 1)
	fi
	if [ -z "$hs" ] && command -v uci >/dev/null 2>&1; then
		local lhs
		lhs="$(uci -q get uhttpd.main.listen_https 2>/dev/null)"
		hs=$(echo "$lhs" | sed -n -E 's/.*:([0-9]+).*/\1/p' | head -n 1)
		[ -z "$hs" ] && hs=$(echo "$lhs" | grep -oE '[0-9]+' | tail -n 1)
	fi

	CURRENT_HTTP_PORT="${h:-8080}"
	CURRENT_HTTPS_PORT="${hs:-8443}"
}

# Comprobar si uhttpd está ocupando 80 o 443
uhttpd_needs_freeing() {
	[ -f /etc/config/uhttpd ] || return 1
	if grep -qE "(:|['\"])80(['\"[:space:]]|$)" /etc/config/uhttpd || \
	   grep -qE "(:|['\"])443(['\"[:space:]]|$)" /etc/config/uhttpd; then
		return 0
	fi
	return 1
}

# Comprobar si nginx está ocupando 80 o 443
nginx_needs_freeing() {
	if [ -f /etc/config/nginx ] || [ -d /etc/nginx ]; then
		if grep -rqE "([: ]80;|\"80\"|'80')" /etc/nginx/ 2>/dev/null || \
		   grep -rqE "([: ]443;|\"443\"|'443')" /etc/nginx/ 2>/dev/null; then
			return 0
		fi
	fi
	return 1
}

reconfigure_uhttpd() {
	[ -f /etc/config/uhttpd ] || return 0

	uhttpd_needs_freeing || return 0

	CHANGED=1

	# Buscar puertos alternativos libres (si 8080/8443 están ocupados, avanza al siguiente)
	NEW_HTTP_PORT="$(find_next_free_port 8080 0)"
	NEW_HTTPS_PORT="$(find_next_free_port 8443 "$NEW_HTTP_PORT")"

	# Reemplazo infalible y directo en /etc/config/uhttpd (soporta con o sin comillas, con o sin IP)
	sed -i -E "s/(:|['\"])80(['\"[:space:]]|$)/\1${NEW_HTTP_PORT}\2/g" /etc/config/uhttpd
	sed -i -E "s/(:|['\"])443(['\"[:space:]]|$)/\1${NEW_HTTPS_PORT}\2/g" /etc/config/uhttpd

	# Sincronizar UCI si está disponible
	if command -v uci >/dev/null 2>&1; then
		uci commit uhttpd 2>/dev/null || true
	fi

	# Reiniciar uhttpd para aplicar el cambio y liberar puertos inmediatamente
	if [ -x /etc/init.d/uhttpd ]; then
		/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
	fi
}

reconfigure_nginx() {
	if nginx_needs_freeing; then
		local nginx_changed=0

		if grep -rqE "([: ]80;|\"80\"|'80')" /etc/nginx/ 2>/dev/null; then
			[ -z "$NEW_HTTP_PORT" ] && NEW_HTTP_PORT="$(find_next_free_port 8080 0)"
			sed -i -E "s/(:| )80;/\1${NEW_HTTP_PORT};/g" /etc/nginx/conf.d/*.conf /etc/nginx/nginx.conf 2>/dev/null || true
			nginx_changed=1
		fi

		if grep -rqE "([: ]443;|\"443\"|'443')" /etc/nginx/ 2>/dev/null; then
			[ -z "$NEW_HTTPS_PORT" ] && NEW_HTTPS_PORT="$(find_next_free_port 8443 "${NEW_HTTP_PORT:-8080}")"
			sed -i -E "s/(:| )443;/\1${NEW_HTTPS_PORT};/g" /etc/nginx/conf.d/*.conf /etc/nginx/nginx.conf 2>/dev/null || true
			nginx_changed=1
		fi

		if [ "$nginx_changed" -eq 1 ]; then
			CHANGED=1
			if [ -x /etc/init.d/nginx ]; then
				/etc/init.d/nginx restart >/dev/null 2>&1 || true
			fi
		fi
	fi
}

deduplicate_uhttpd() {
	[ -f /etc/config/uhttpd ] || return 0
	local tmp
	tmp=$(mktemp) || return 0
	awk '
	/^([[:space:]]*list[[:space:]]+listen_http[[:space:]])/ {
		if (seen_http[$0]++) next
	}
	/^([[:space:]]*list[[:space:]]+listen_https[[:space:]])/ {
		if (seen_https[$0]++) next
	}
	{ print }
	' /etc/config/uhttpd > "$tmp" && mv -f "$tmp" /etc/config/uhttpd
	rm -f "$tmp" 2>/dev/null || true
}

show_reassigned_notice() {
	get_current_luci_ports
	local p_http="${NEW_HTTP_PORT:-$CURRENT_HTTP_PORT}"
	local p_https="${NEW_HTTPS_PORT:-$CURRENT_HTTPS_PORT}"

	echo "* [AVISO] Puertos de LuCI reasignados a HTTP: $p_http, HTTPS: $p_https para liberar 80 y 443 a Caddy."
}

show_omitted_notice() {
	get_current_luci_ports
	echo "* [OMITIDO] Puertos 80 y 443 ya están libres para Caddy (LuCI activo en HTTP: $CURRENT_HTTP_PORT, HTTPS: $CURRENT_HTTPS_PORT)."
}

show_json() {
	get_current_luci_ports
	local p_http="${NEW_HTTP_PORT:-$CURRENT_HTTP_PORT}"
	local p_https="${NEW_HTTPS_PORT:-$CURRENT_HTTPS_PORT}"
	local ch_bool="false"
	[ "$CHANGED" -eq 1 ] && ch_bool="true"
	local free_bool="false"
	[ "$ALREADY_FREE" -eq 1 ] && free_bool="true"

	cat <<EOF
{"success":true,"changed":$ch_bool,"already_free":$free_bool,"http_port":$p_http,"https_port":$p_https,"message":"Puertos procesados. LuCI disponible en HTTP: $p_http, HTTPS: $p_https"}
EOF
}

# Sanitizar duplicados acumulados en /etc/config/uhttpd
deduplicate_uhttpd

# Evaluar si los servicios web necesitan reasignación
if uhttpd_needs_freeing || nginx_needs_freeing; then
	reconfigure_uhttpd
	reconfigure_nginx
	deduplicate_uhttpd
else
	ALREADY_FREE=1
fi

# Gestión de salida según el modo solicitado
case "$MODE" in
	--quiet|-q)
		# Operación silenciosa
		exit 0
		;;
	--show|-s)
		if [ "$CHANGED" -eq 1 ]; then
			show_reassigned_notice
		else
			show_omitted_notice
		fi
		exit 0
		;;
	--json)
		show_json
		exit 0
		;;
	*)
		# Modo estándar interactivo / script
		if [ "$CHANGED" -eq 1 ]; then
			show_reassigned_notice
		else
			show_omitted_notice
		fi
		exit 0
		;;
esac
