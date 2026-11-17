<div align="center">

# luci-app-caddy

**Interfaz web LuCI para instalar, configurar y gestionar Caddy como servidor web y Reverse Proxy en OpenWrt, con soporte nativo para Cloudflare DNS-01.**

[![OpenWrt](https://img.shields.io/badge/OpenWrt-24.10%2B%20%7C%2025.x%20(apk)-00B5E2?style=flat-square&logo=openwrt&logoColor=white)](#compatibilidad)
[![Caddy](https://img.shields.io/badge/Caddy-v2.11.4%20%2B%20Cloudflare-1F88E5?style=flat-square&logo=caddy&logoColor=white)](#modos-tls)
[![Arquitecturas](https://img.shields.io/badge/Arch-x86__64%20%7C%20aarch64-4CAF50?style=flat-square)](#compatibilidad)
[![Release](https://img.shields.io/github/v/release/JioDevR/luci-app-caddy?style=flat-square&color=orange)](https://github.com/JioDevR/luci-app-caddy/releases)
[![Licencia](https://img.shields.io/badge/Licencia-Apache%202.0-blue?style=flat-square)](#licencia)

[Instalación rápida](#instalación-rápida) · [Características](#características) · [Uso en LuCI](#uso-en-luci) · [Modos TLS](#modos-tls) · [Solución de problemas](#solución-de-problemas) · [Auditoría](AUDITORIA.md)

</div>

---

`luci-app-caddy` integra **Caddy v2.11.4** (compilado con el módulo `dns.providers.cloudflare`) directamente en **LuCI** (`Servicios → Caddy`), permitiendo emitir certificados TLS válidos mediante **Cloudflare DNS-01** incluso detrás de CGNAT o sin abrir los puertos `80`/`443`, además de gestionar reverse proxies y editar el `Caddyfile` con validación previa.

---

## Instalación rápida

Conéctate por SSH al router y ejecuta:

```sh
wget -qO- https://raw.githubusercontent.com/JioDevR/luci-app-caddy/main/install.sh | sh
```

El instalador ([`install.sh`](install.sh)) detecta automáticamente la arquitectura (`x86_64` o `aarch64`), comprueba el espacio disponible en `/tmp`, descarga el `.apk` correspondiente desde [GitHub Releases](https://github.com/JioDevR/luci-app-caddy/releases), verifica su `sha256sum` e instala el paquete.

Para instalar una versión específica:

```sh
wget -qO- https://raw.githubusercontent.com/JioDevR/luci-app-caddy/main/install.sh | VERSION=v1.0.3 sh
```

> [!IMPORTANT]
> **Acceso a LuCI tras instalar:** si los puertos `80` y `443` estaban ocupados por `uhttpd`, el instalador reasigna automáticamente LuCI a **`8080` (HTTP)** y **`8443` (HTTPS)** para dejárselos libres a Caddy. El acceso SSH (puerto `22`) no se modifica.

---

## Características

- **Paquetes ligeros por arquitectura (sin dependencias externas):** builds separados para `x86_64` (~17 MB) y `aarch64` (~15 MB) con Caddy `v2.11.4` + `dns.providers.cloudflare` incluidos, más una variante `all` (~31 MB) para entornos offline.
- **Instalación y puertos automáticos:** detecta la arquitectura, instala `/usr/bin/caddy` (omitiéndolo si ya existe) y libera los puertos `80`/`443` de LuCI automáticamente.
- **Gestión visual de Reverse Proxies:** tabla interactiva con estado activo/inactivo, dominio, upstream, orden, cabeceras de proxy y directivas personalizadas.
- **4 modos TLS por sitio:** Automático (ACME), Cloudflare DNS-01, Certificado interno (CA local) y HTTP plano.
- **Editor de Caddyfile seguro:** valida con `caddy validate` antes de aplicar; un archivo con errores nunca reemplaza la configuración activa.
- **Modo personalizado persistente:** las ediciones manuales del `Caddyfile` sobreviven a reinicios y guardados en otras pestañas.
- **Diagnóstico sin impacto:** `caddy validate` + `caddy adapt` desde la UI sin arrancar procesos ni consumir cuota de Let's Encrypt.
- **Seguridad integrada:** credenciales con permisos `0600` y token de Cloudflare enmascarado (`***`) en UI, RPC y logs.

---

## Compatibilidad y requisitos

### Arquitecturas soportadas

| Arquitectura | Binario incluido | Paquete `.apk` | Estado |
|---|---|---|---|
| `x86_64` / `amd64` | `caddy_linux_amd64_custom` | `luci-app-caddy-x86_64.apk` (~17 MB) | ✅ Verificado en OpenWrt 25.12.6 (QEMU) |
| `aarch64` / `arm64` | `caddy_linux_arm64_custom` | `luci-app-caddy-aarch64.apk` (~15 MB) | ✅ Verificado (138 módulos, `validate`/`adapt` y HTTP bajo `qemu-user`) |
| `armv7` / `armv6` / `mips` | — | — | ❌ No incluido |

### Versiones de OpenWrt

| Versión de OpenWrt | Gestor de paquetes | Soporte |
|---|---|---|
| OpenWrt **25.x** (SNAPSHOT / 25.12+) | `apk` v3 | ✅ Paquetes `.apk` listos para usar |
| OpenWrt **24.10+** (con `apk`) | `apk` v3 | ✅ Paquetes `.apk` listos para usar |
| OpenWrt **23.05 y anteriores** | `opkg` | ⚙️ Compilable vía [`Makefile`](Makefile) con OpenWrt SDK/Buildroot |

### Requisitos del router

- **Dependencia:** `luci-base` (LuCI instalado).
- **Acceso:** SSH como `root`.
- **Espacio libre:** ~25 MB en `/tmp` durante la descarga y ~45–65 MB en flash/overlay para la instalación (el `post-install` limpia el paquete temporal tras copiar el binario).
- **Certificados ACME:** salida a Internet y DNS apuntando al router (o token de Cloudflare para DNS-01).

> [!NOTE]
> Los paquetes `.apk` se declaran como `arch: noarch` para ser aceptados por cualquier subarquitectura `aarch64_*` o `x86_64`, y no están firmados criptográficamente (requieren `--allow-untrusted` en `apk`, aunque su integridad se valida mediante `.sha256`).

---

## Instalación manual, actualización y desinstalación

<details>
<summary><strong>Instalación manual / offline (sin Internet en el router)</strong></summary>

Descarga el paquete de tu arquitectura (`luci-app-caddy-x86_64.apk`, `luci-app-caddy-aarch64.apk` o `luci-app-caddy-all.apk`) desde [Releases](https://github.com/JioDevR/luci-app-caddy/releases) o desde `dist/`.

**1. Copiar al router:**

```sh
# Sustituye <ARCH> por x86_64, aarch64 o all
scp -O dist/luci-app-caddy-<ARCH>.apk root@192.168.1.1:/tmp/
```

> `-O` fuerza el protocolo SCP clásico porque **dropbear** no incluye SFTP. Alternativa sin `scp`:
> ```sh
> ssh root@192.168.1.1 'cat > /tmp/luci-app-caddy-<ARCH>.apk' < dist/luci-app-caddy-<ARCH>.apk
> ```

**2. Instalar:**

```sh
ssh root@192.168.1.1 'apk add --allow-untrusted /tmp/luci-app-caddy-<ARCH>.apk'
```

</details>

<details>
<summary><strong>Actualizar o reinstalar</strong></summary>

* **Con Internet:** vuelve a ejecutar el comando de [Instalación rápida](#instalación-rápida).
* **Manual:**
  ```sh
  scp -O dist/luci-app-caddy-<ARCH>.apk root@192.168.1.1:/tmp/
  ssh root@192.168.1.1 'apk add --allow-untrusted --upgrade /tmp/luci-app-caddy-<ARCH>.apk'
  ```
* **Reinstalar la misma versión** (`apk` omite versiones idénticas, conserva `/etc/config/caddy`):
  ```sh
  ssh root@192.168.1.1 'apk del luci-app-caddy && apk add --allow-untrusted /tmp/luci-app-caddy-<ARCH>.apk'
  ```

Tu archivo `/etc/config/caddy` se conserva entre actualizaciones; si hay cambios por defecto, se guardan en `/etc/config/caddy.apk-new`.

</details>

<details>
<summary><strong>Compilación con OpenWrt Buildroot / SDK (para opkg o imagen propia)</strong></summary>

Copia el proyecto en `package/luci-app-caddy` dentro de tu árbol de OpenWrt y ejecuta:

```sh
make package/luci-app-caddy/compile V=s
```

El [`Makefile`](Makefile) declara `LUCI_DEPENDS:=+caddy`. En este flujo se utiliza el paquete `caddy` oficial de los feeds, por lo que el instalador integrado omite copiar el binario propio si `/usr/bin/caddy` ya está presente.

</details>

### Verificar la instalación

```sh
apk list -I | grep luci-app-caddy
/usr/bin/caddy version
/usr/bin/caddy list-modules | grep cloudflare
ubus call luci.caddy status
```

### Desinstalación

```sh
ssh root@192.168.1.1 'apk del luci-app-caddy'
```

Esto **no** revierte los puertos de LuCI ni borra tus certificados. Si quieres devolver LuCI a `80`/`443` y limpiar datos:

```sh
uci set uhttpd.main.listen_http='0.0.0.0:80'
uci set uhttpd.main.listen_https='0.0.0.0:443'
uci commit uhttpd && /etc/init.d/uhttpd restart

# Opcional: eliminar configuración y certificados de Caddy
rm -rf /etc/caddy /etc/config/caddy
```

---

## Uso en LuCI

Accede a **Servicios → Caddy** desde `http://<IP-DEL-ROUTER>:8080` (o `https://<IP-DEL-ROUTER>:8443`).

### 1. Estado y Control
- Indicadores en tiempo real de **servicio (`procd`)**, **binario**, **módulo Cloudflare** e **inicio automático**.
- Información de ruta del binario, arquitectura, puertos activos de Caddy y LuCI, y número de proxies.
- Acciones de control (**Iniciar**, **Detener**, **Reiniciar**, **Recargar**, **Comprobar Sintaxis**) y mantenimiento (**Instalar/Reinstalar binario**, **Liberar puertos 80/443**).

### 2. Configuración General

| Campo | Descripción |
|---|---|
| **Habilitar Caddy** | Activa o desactiva el inicio automático (`procd` / UCI). |
| **Token de API de Cloudflare** | Token para el desafío DNS-01 (opcional). |
| **Email de administrador** | Correo de contacto para Let's Encrypt / ZeroSSL. |
| **Puerto HTTP / HTTPS** | Puertos de escucha de Caddy (por defecto `80` / `443`). |
| **Nivel de registro** | `DEBUG`, `INFO`, `WARN` o `ERROR`. |
| **Ruta del binario** | Por defecto `/usr/bin/caddy`. |
| **Usar Caddyfile personalizado** | Protege ediciones manuales frente a regeneraciones desde UCI. |

### 3. Reverse Proxies

| Campo | Ejemplo | Notas |
|---|---|---|
| **Activo** | ✔ | Las reglas inactivas se omiten al generar el `Caddyfile`. |
| **Etiqueta** | `Home Assistant` | Nombre descriptivo. |
| **Dominio** | `ha.tudominio.com` | Sin esquema ni rutas. |
| **Upstream** | `192.168.1.100:8123` | `host:puerto`. |
| **Modo TLS** | `Cloudflare DNS-01` | Ver [Modos TLS](#modos-tls). |
| **Pasar headers** | ✘ | Añade `header_up Host {upstream_hostport}` y `X-Real-IP`. |
| **Directivas extra** | `header_up X-Custom val` | Se insertan dentro del bloque `reverse_proxy`. |

Al guardar, se valida el `Caddyfile` generado y se recarga Caddy sin cortar conexiones activas. Si falla la validación, no se sobrescribe la configuración en ejecución.

### 4. Caddyfile
- Editor directo del `/etc/caddy/Caddyfile` activo con indicador de modo (*Gestionado* o *Personalizado*).
- **Probar Configuración:** ejecuta `caddy validate` + `caddy adapt` en frío.
- **Guardar y Aplicar:** valida antes de aplicar; guarda backup previo en `Caddyfile.bak`.
- **Importar Caddyfile a UCI** y **Restaurar generado desde UCI**.

---

## Modos TLS

| Modo | Directiva generada | Cuándo usarlo |
|---|---|---|
| **Automático** | *(por defecto)* | Let's Encrypt/ZeroSSL por HTTP-01 o TLS-ALPN (requiere `80`/`443` abiertos). |
| **Cloudflare DNS-01** | `tls { dns cloudflare <token> }` | Sin abrir puertos, CGNAT o doble NAT. |
| **Certificado interno** | `tls internal` | Servicios LAN con la CA local de Caddy (`/etc/caddy/data/caddy/pki/authorities/local/root.crt`). |
| **Sin TLS (HTTP)** | `http://dominio` | Tráfico interno sin cifrar o detrás de otro proxy. |

<details>
<summary><strong>Ejemplo de Caddyfile generado automáticamente</strong></summary>

```caddyfile
# Generated automatically by luci-app-caddy
{
	acme_dns cloudflare <TOKEN>
	log {
		level INFO
	}
}

# 1. Home Assistant (Cloudflare DNS-01)
ha.tudominio.com {
	tls {
		dns cloudflare <TOKEN>
	}
	reverse_proxy 192.168.1.100:8123
}

# 2. Panel interno (CA local)
panel.lan {
	tls internal
	reverse_proxy 192.168.1.50:8080
}

# 3. NAS sin TLS
http://nas.lan {
	reverse_proxy 192.168.1.60:5000
}
```

</details>

---

## Cloudflare DNS-01

1. En Cloudflare, ve a **My Profile → API Tokens → Create Token**.
2. Selecciona la plantilla **Edit zone DNS** con el permiso `Zone → DNS → Edit` limitado a tu zona.
3. Pega el token generado en **Configuración General**.

El token debe tener al menos 32 caracteres (`A-Za-z0-9_-`). Si es inválido, la UI rechaza el guardado y el generador omite `acme_dns` para no impedir el arranque del resto de sitios.

---

## Caddyfile personalizado

Al guardar desde la pestaña **Caddyfile**, se activa `custom_caddyfile=1` y se guarda una copia en `/etc/caddy/Caddyfile.custom`.

| Acción | ¿Sobrescribe tu Caddyfile manual? |
|---|---|
| `reload` / `restart` o reinicio del router | ❌ No |
| Guardar **Configuración General** | ❌ No |
| Guardar **Reverse Proxies** | ✅ Sí (vuelve a modo gestionado y guarda respaldo en `Caddyfile.custom.bak`) |
| **Restaurar generado desde UCI** | ✅ Sí (acción explícita) |

---

## Referencia técnica: CLI, RPC y Seguridad

### CLI y servicio

```sh
/etc/init.d/caddy start|stop|restart|reload|enable|disable
/etc/init.d/caddy generate              # Regenera Caddyfile desde UCI
/etc/init.d/caddy sync_from_caddyfile   # Importa reglas del Caddyfile a UCI
```

### Llamadas RPC (`ubus`)

```sh
ubus call luci.caddy status
ubus call luci.caddy get_bin_info
ubus call luci.caddy validate_caddyfile
ubus call luci.caddy test_caddy_run
ubus call luci.caddy service_action '{"action":"reload"}'
```

Métodos disponibles en `luci.caddy`: `status`, `get_bin_info`, `validate_caddyfile`, `test_caddy_run`, `get_caddyfile`, `set_caddyfile`, `generate_caddyfile`, `restore_generated`, `sync_general`, `sync_from_caddyfile`, `service_action`, `install_bin`, `free_ports`.

### Seguridad

- `/etc/config/caddy` y `/etc/caddy/Caddyfile` se crean con permisos **`0600`**.
- El token de Cloudflare se enmascara (`***`) en salidas RPC y en `logread`.
- La API de administración de Caddy escucha únicamente en `127.0.0.1:2019`.

<details>
<summary><strong>Estructura del repositorio y ficheros en el router</strong></summary>

```text
luci-app-caddy/
├── bin/                           # Binarios Caddy 2.11.4 + cloudflare
│   ├── caddy_linux_amd64_custom
│   └── caddy_linux_arm64_custom
├── dist/                          # Paquetes generados por build_apk.sh
│   ├── luci-app-caddy-x86_64.apk  (+ .sha256)
│   ├── luci-app-caddy-aarch64.apk (+ .sha256)
│   └── luci-app-caddy-all.apk     (+ .sha256)
├── root/                          # Sistema de ficheros destino en OpenWrt
│   ├── etc/config/caddy
│   ├── etc/init.d/caddy
│   ├── etc/uci-defaults/luci-app-caddy
│   ├── usr/lib/caddy/{caddy-installer.sh,free-ports.sh,generate-caddyfile.sh}
│   ├── usr/libexec/rpcd/luci.caddy
│   ├── usr/share/luci/menu.d/luci-app-caddy.json
│   ├── usr/share/rpcd/acl.d/luci-app-caddy.json
│   └── www/luci-static/resources/view/caddy/{status,general,proxies,caddyfile}.js
├── tools/apk.static               # apk-tools v3 para empaquetado
├── build_apk.sh                   # Script de construcción de .apk
├── install.sh                     # Instalador rápido para OpenWrt
├── Makefile                       # Integración con OpenWrt Buildroot/SDK
├── AUDITORIA.md                   # Informe completo de auditoría y pruebas
└── RELEASE_NOTES.md               # Historial de cambios
```

| Ruta en el router | Descripción |
|---|---|
| `/etc/config/caddy` | Configuración UCI (`0600`) |
| `/etc/caddy/Caddyfile` | Configuración activa de Caddy (`0600`) |
| `/etc/caddy/Caddyfile.custom` / `.bak` | Copias del modo personalizado y backups |
| `/etc/caddy/data` y `/etc/caddy/config` | Certificados ACME y estado interno de Caddy |
| `/usr/bin/caddy` | Binario de Caddy instalado |

</details>

---

## Solución de problemas

| Síntoma | Causa / Solución |
|---|---|
| `apk` rechaza el paquete | Añade `--allow-untrusted` al instalar manualmente. |
| `apk add` no hace nada | Ya tienes la misma versión: usa `--upgrade` o reinstala con `apk del` + `apk add`. |
| `apk upgrade --prune` desinstala la app | Al ser un paquete local fuera de feeds, evita el flag `--prune`. |
| LuCI no abre en `80`/`443` | Se reasignó a **`8080`/`8443`**; si volvió al `80`, usa *Estado → Liberar puertos 80/443*. |
| Caddy no arranca | Ejecuta `ubus call luci.caddy test_caddy_run` y revisa `logread \| grep caddy`. |
| No se emite certificado | Verifica DNS, puertos `80`/`443` abiertos o validez del token Cloudflare DNS-01. |
| `502 Bad Gateway` | El servicio upstream está apagado, el puerto es incorrecto o lo bloquea el firewall. |
| `Access denied` en LuCI | Inicia sesión como `root` o un usuario con ACL `luci-app-caddy`. |

### Limitaciones conocidas

1. La emisión real de certificados contra ACME no se ha probado en laboratorio sin salida a Internet (sí la generación, `validate` y `adapt`).
2. Sólo se incluyen binarios para `x86_64` y `aarch64` (no `armv7`/`mips`).
3. `sync_from_caddyfile` usa parsing heurístico para reglas estándar (`domain`, `reverse_proxy`, `tls`, `header_up`); bloques complejos se conservan mejor en modo personalizado.
4. El `post-install` elimina `/usr/share/caddy/bin` tras instalar `/usr/bin/caddy` para liberar memoria flash.

---

## Desarrollo y pruebas

### Reconstruir los paquetes `.apk`

Requisitos: `bash`, `tools/apk.static` (incluido), `unshare` (para propietario `root:root`) y los binarios en `bin/`.

```sh
./build_apk.sh
```

Para actualizar la versión antes de empaquetar, modifica simultáneamente `PKG_VER` en [`build_apk.sh`](build_apk.sh) y `PKG_VERSION` en [`Makefile`](Makefile).

### Resumen de verificación

| Prueba | Entorno | Resultado |
|---|---|---|
| Instalación limpia y actualización | OpenWrt 25.12.6 `x86_64` (QEMU) | ✅ |
| Proxy HTTP/HTTPS real | OpenWrt 25.12.6 `x86_64` | ✅ `200 OK` |
| UI completa (4 vistas LuCI) | Playwright sobre LuCI real | ✅ |
| Binario ARM64 (138 módulos, `validate`/`adapt`, HTTP) | `qemu-user` (`aarch64`) | ✅ |
| Integridad de paquetes `.apk` | `apk verify` + `adbdump` + `sha256sum` | ✅ |

Consulta el detalle completo en [AUDITORIA.md](AUDITORIA.md).

---

## Licencia

Distribuido bajo **Apache License 2.0** (ver cabecera de [`Makefile`](Makefile)).  
**Caddy** es un proyecto de Stack Holdings GmbH, licenciado bajo Apache License 2.0.
