# luci-app-caddy

Interfaz web (**LuCI**) para instalar, configurar y controlar **Caddy v2.11.4** como servidor web y **reverse proxy** en OpenWrt, con soporte nativo de **Cloudflare DNS-01** para emitir certificados válidos sin abrir los puertos 80/443.

**Versión:** `1.0.3-r1` · **Caddy:** `2.11.4` (`dns.providers.cloudflare` incluido) · **Arquitecturas:** `x86_64` y `aarch64` · **Paquete:** `.apk` (apk-tools v3)

---

## Índice

1. [Características](#características)
2. [Compatibilidad](#compatibilidad)
3. [Contenido del proyecto](#contenido-del-proyecto)
4. [Requisitos](#requisitos)
5. [Instalación](#instalación)
6. [Uso en LuCI](#uso-en-luci)
7. [Modos TLS](#modos-tls)
8. [Cloudflare DNS-01](#cloudflare-dns-01)
9. [Caddyfile personalizado](#caddyfile-personalizado)
10. [Uso avanzado: CLI y RPC](#uso-avanzado-cli-y-rpc)
11. [Seguridad](#seguridad)
12. [Solución de problemas](#solución-de-problemas)
13. [Desinstalación](#desinstalación)
14. [Desarrollo y compilación](#desarrollo-y-compilación)
15. [Pruebas de compatibilidad](#pruebas-de-compatibilidad)
16. [Limitaciones conocidas](#limitaciones-conocidas)
17. [Licencia](#licencia)

---

## Características

- **Paquete todo-en-uno sin dependencias de Internet**: incluye los binarios de Caddy para `x86_64` y `aarch64` con el plugin `dns.providers.cloudflare`.
- **Detección automática de arquitectura** en el post-install: copia el binario correcto a `/usr/bin/caddy` y omite la instalación si ya existe.
- **Liberación automática de los puertos 80/443**: reasigna LuCI (`uhttpd`) a 8080/8443 si es necesario, sin afectar a SSH.
- **Gestión de reverse proxies** desde una tabla: etiqueta, dominio, upstream, activo/inactivo, orden, headers de proxy y directivas extra.
- **4 modos TLS por proxy**: automático, Cloudflare DNS-01 por sitio, certificado interno y sin TLS.
- **Edición directa del Caddyfile** con validación previa: un archivo inválido nunca sustituye al que está funcionando.
- **Modo personalizado persistente**: las ediciones manuales sobreviven a guardados de otras pestañas y a reinicios del router.
- **Diagnóstico seguro**: `caddy validate` + `caddy adapt` sin arrancar procesos, abrir puertos ni consumir cuota de Let's Encrypt.
- **Estado real del servicio** desde `procd` (PID, habilitado, versión y módulos del binario).
- **Token de Cloudflare protegido** (`0600` en disco y `***` en logs/UI).
- **Mantenimiento desde la UI**: instalar/reinstalar binario, liberar puertos, importar el Caddyfile a UCI y restaurar la configuración generada.

---

## Compatibilidad

### Arquitecturas

| Arquitectura | Binario incluido | Estado |
|---|---|---|
| `x86_64` / `amd64` | `caddy_linux_amd64_custom` | ✅ Verificado en OpenWrt 25.12.6 (QEMU/x86_64) |
| `aarch64` / `arm64` | `caddy_linux_arm64_custom` | ✅ Verificado (versión, 138 módulos, `validate`/`adapt` y HTTP real bajo qemu-user) |
| `armv7` / `armv6` (32 bits) | — | ❌ No incluido |
| `mips` / `mipsel` | — | ❌ No incluido |

El paquete se declara **`arch: noarch`**, por lo que `apk` lo acepta en cualquier router. El instalador decide qué binario copiar según `uname -m`. En arquitecturas no soportadas aborta con un error explícito, sin dejar el servicio a medias.

### Versiones de OpenWrt

| Versión | Gestor | Soporte del `.apk` de `dist/` |
|---|---|---|
| OpenWrt 25.x (SNAPSHOT / 25.12+) | `apk` v3 | ✅ |
| OpenWrt 24.10+ | `apk` v3 | ✅ |
| OpenWrt 23.05 y anteriores | `opkg` | ❌ Usa el `Makefile` con el buildroot |

> El `.apk` **no está firmado**. La instalación requiere `--allow-untrusted`.

---

## Contenido del proyecto

```text
luci-app-caddy/
├── bin/
│   ├── caddy_linux_amd64_custom   # Caddy 2.11.4 + cloudflare (x86_64)
│   └── caddy_linux_arm64_custom   # Caddy 2.11.4 + cloudflare (aarch64)
├── dist/
│   ├── luci-app-caddy.apk         # Paquete final
│   └── luci-app-caddy.apk.sha256  # Checksum
├── root/                          # Árbol que se instala en el router
│   ├── etc/config/caddy           # Configuración UCI por defecto
│   ├── etc/init.d/caddy           # Servicio procd
│   ├── etc/uci-defaults/luci-app-caddy
│   ├── usr/lib/caddy/
│   │   ├── caddy-installer.sh     # Instalación del binario
│   │   ├── free-ports.sh          # Reasignación de puertos de LuCI
│   │   └── generate-caddyfile.sh  # Generador del Caddyfile
│   ├── usr/libexec/rpcd/luci.caddy
│   ├── usr/share/rpcd/acl.d/luci-app-caddy.json
│   ├── usr/share/luci/menu.d/luci-app-caddy.json
│   └── www/luci-static/resources/view/caddy/
│       ├── status.js
│       ├── general.js
│       ├── proxies.js
│       └── caddyfile.js
├── tools/apk.static               # apk-tools para empaquetar
├── build_apk.sh                   # Script de empaquetado
├── Makefile                       # Integración con el buildroot de OpenWrt
├── AUDITORIA.md                   # Informe de auditoría y pruebas
└── README.md
```

### Ficheros en el router

| Ruta | Contenido |
|---|---|
| `/etc/config/caddy` | Configuración UCI (`general` + secciones `proxy`) — `0600` |
| `/etc/caddy/Caddyfile` | Configuración activa de Caddy — `0600` |
| `/etc/caddy/Caddyfile.custom` | Copia del Caddyfile en modo personalizado |
| `/etc/caddy/Caddyfile.bak` | Copia previa a cada guardado desde la UI |
| `/etc/caddy/Caddyfile.custom.bak` | Copia al salir del modo personalizado |
| `/etc/caddy/data` | Certificados y estado de Caddy (`XDG_DATA_HOME`) |
| `/etc/caddy/config` | Configuración interna de Caddy (`XDG_CONFIG_HOME`) |
| `/usr/bin/caddy` | Binario instalado |
| `/usr/lib/caddy/*.sh` | Scripts de instalación, puertos y generación |

---

## Requisitos

- Router con **OpenWrt 24.10+ / 25.x** y `apk-tools` v3.
- **LuCI** instalado (`luci-base`). Es la única dependencia declarada.
- Acceso **SSH** como `root`.
- **Espacio libre**: ~90 MB durante la instalación (se extraen los dos binarios). Tras el post-install se conserva sólo el binario de la arquitectura del router (~43–46 MB) y se elimina el directorio empaquetado.
- Para emitir certificados: conectividad a Internet y DNS del dominio apuntando al router (o token de Cloudflare para DNS-01).

---

## Instalación

### 1. Copiar el paquete

```bash
scp -O dist/luci-app-caddy.apk root@192.168.1.1:/tmp/
```

> `-O` fuerza el protocolo SCP clásico porque **dropbear** (SSH de OpenWrt) no incluye SFTP.
> Alternativa sin `scp`:
> ```bash
> ssh root@192.168.1.1 'cat > /tmp/luci-app-caddy.apk' < dist/luci-app-caddy.apk
> ```

### 2. Instalar

```bash
ssh root@192.168.1.1 'apk add --allow-untrusted /tmp/luci-app-caddy.apk'
```

Salida esperada (resumida):

```text
(1/1) Installing luci-app-caddy (1.0.3-r1)
  Executing luci-app-caddy-1.0.3-r1.post-install
  * [AVISO] Puertos de LuCI reasignados a HTTP: 8080, HTTPS: 8443 ...
  * [EXITO] Caddy (v2.11.4 ...) instalado correctamente en /usr/bin/caddy.
OK: ...
```

### 3. Acceder a LuCI

Tras la instalación, LuCI pasa a:

- `http://<IP-DEL-ROUTER>:8080`
- `https://<IP-DEL-ROUTER>:8443`

El acceso SSH (puerto 22) no cambia. Si LuCI ya estaba en 8080/8443, no se toca nada.

### Actualizar

```bash
scp -O dist/luci-app-caddy.apk root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'apk add --allow-untrusted --upgrade /tmp/luci-app-caddy.apk'
```

- Tu `/etc/config/caddy` se conserva (conffile); la versión nueva se deja en `/etc/config/caddy.apk-new` para revisar.
- El binario de Caddy **no se reemplaza** si ya existe.
- El Caddyfile se regenera salvo que estés en modo personalizado.

### Reinstalar la misma versión

`apk` no reinstala una versión idéntica. Opciones:

```bash
# Reinstalación limpia (conserva /etc/config/caddy)
ssh root@192.168.1.1 'apk del luci-app-caddy && apk add --allow-untrusted /tmp/luci-app-caddy.apk'
```

### Verificar la instalación

```bash
apk list -I | grep luci-app-caddy
/usr/bin/caddy version
/usr/bin/caddy list-modules | grep cloudflare
ls -l /etc/config/caddy
ubus call luci.caddy status
```

### ¿Qué hace el post-install?

1. Limpia reglas de ejemplo obsoletas de UCI.
2. Comprueba y libera los puertos 80/443 ocupados por `uhttpd`/`nginx`.
3. Instala el binario de Caddy de la arquitectura detectada (si no existe).
4. Genera `/etc/caddy/Caddyfile` y registra el servicio en `ucitrack`.
5. Ajusta permisos `0600` y recarga `rpcd`.

### Instalación con buildroot (opcional)

Para OpenWrt 23.05 (`opkg`) o para integrarlo en una imagen propia, copia el proyecto en `package/luci-app-caddy` y compila:

```bash
make package/luci-app-caddy/compile V=s
```

Dependencias del Makefile: `+caddy`. En este flujo se usa el Caddy del repositorio oficial; el instalador propio se omite si ya existe `/usr/bin/caddy`.

---

## Uso en LuCI

**Servicios → Caddy**

### 1. Estado y Control

- Badges de **servicio**, **binario**, **módulo Cloudflare** e **inicio automático**.
- Ruta del binario, arquitectura, puertos de Caddy y puertos de LuCI.
- Número de proxies configurados.
- Acciones: **Iniciar**, **Detener**, **Reiniciar**, **Recargar** y **Comprobar Sintaxis**.
- Mantenimiento: **Instalar binario incluido**, **Reinstalar binario (forzado)** y **Liberar puertos 80/443**.

### 2. Configuración General

| Campo | Descripción |
|---|---|
| Habilitar Caddy | Inicio automático (fuente de verdad: UCI) |
| Token de API de Cloudflare | Opcional; activa DNS-01 |
| Email de administrador | Contacto ACME (Let's Encrypt / ZeroSSL) |
| Puerto HTTP / HTTPS | Puertos de escucha de Caddy (por defecto 80/443) |
| Nivel de registro | DEBUG / INFO / WARN / ERROR |
| Ruta del binario | Por defecto `/usr/bin/caddy` |
| Usar Caddyfile personalizado | Protege las ediciones manuales del Caddyfile |

> Guardar esta pestaña regenera el Caddyfile desde UCI, **salvo** en modo personalizado.

### 3. Reverse Proxies

Tabla de reglas (añadir, editar, activar/desactivar y ordenar):

| Campo | Ejemplo | Notas |
|---|---|---|
| Activo | ✔ | Las reglas desactivadas no se escriben |
| Etiqueta / Nombre | `Home Assistant` | Sólo informativo |
| Dominio / Subdominio | `ha.tudominio.com` | Sin `http://` ni rutas |
| Destino Upstream | `192.168.1.100:8123` | `host:puerto`, sin esquema |
| Modo TLS | `Automático` | Ver [Modos TLS](#modos-tls) |
| Pasar headers | ✘ | Añade `header_up Host {upstream_hostport}` y `X-Real-IP` |
| Directivas adicionales | `header_up X-Custom valor` | Se insertan dentro de `reverse_proxy` |

Al guardar se valida el Caddyfile generado y se recarga Caddy en caliente. Si la validación falla, **no se aplica** y se muestra el error.

### 4. Caddyfile

- Editor del archivo activo con indicador de modo (gestionado o personalizado).
- **Guardar y Aplicar**: valida primero; si es inválido, el archivo activo no se modifica.
- **Probar Configuración**: `validate` + `adapt` (sin arrancar Caddy ni contactar con ACME).
- **Comprobar Sintaxis** sobre el archivo en disco.
- **Recargar desde Disco**, **Restaurar generado desde UCI** e **Importar Caddyfile a UCI**.

---

## Modos TLS

| Modo | Caddyfile generado | Cuándo usarlo |
|---|---|---|
| **Automático** | *(sin directiva)* | Let's Encrypt/ZeroSSL por HTTP-01 o TLS-ALPN. Requiere 80/443 accesibles |
| **Cloudflare DNS-01 (por sitio)** | `tls { dns cloudflare <token> }` | Sin puertos abiertos, CGNAT o doble NAT. Requiere token |
| **Certificado interno** | `tls internal` | Red local, sin dominio público. CA local de Caddy |
| **Sin TLS (sólo HTTP)** | Dirección `http://dominio` | Servicios internos o detrás de otro proxy TLS |

Ejemplo generado:

```caddyfile
# Generated automatically by luci-app-caddy
{
	acme_dns cloudflare <TOKEN>
	log {
		level INFO
	}
}

# 1. Home Assistant (Cloudflare)
ha.tudominio.com {
	tls {
		dns cloudflare <TOKEN>
	}
	reverse_proxy 192.168.1.100:8123
}

# 2. Panel interno (autofirmado)
panel.lan {
	tls internal
	reverse_proxy 192.168.1.50:8080
}

# 3. NAS sin TLS
http://nas.lan {
	reverse_proxy 192.168.1.60:5000
}
```

> El certificado interno lo emite la CA local de Caddy; para que los clientes lo acepten hay que confiar en esa CA (`/etc/caddy/data/caddy/pki/authorities/local/root.crt`).

---

## Cloudflare DNS-01

1. En Cloudflare: **My Profile → API Tokens → Create Token**.
2. Usa la plantilla **Edit zone DNS** con:
   - `Zone → DNS → Edit`
   - Zona: el dominio concreto (recomendado).
3. Copia el token (sólo se muestra una vez) y pégalo en **Configuración General**.

El token debe contener únicamente letras, números, `-` y `_` (≥ 32 caracteres). Si el formato es inválido:

- la UI rechaza el guardado;
- el generador omite `acme_dns` y el resto de la configuración se aplica igualmente;
- el token nunca aparece en `logread` ni en los mensajes de error (`***`).

---

## Caddyfile personalizado

Al guardar desde la pestaña **Caddyfile** se activa `custom_caddyfile=1` y el contenido se copia a `Caddyfile.custom`.

Con el modo activo:

| Acción | ¿Sobrescribe tu Caddyfile? |
|---|---|
| `reload` / `restart` del servicio | No |
| Reinicio del router | No |
| Guardar **Configuración General** | No |
| Guardar **Reverse Proxies** | Sí: vuelve al modo gestionado (copia previa en `Caddyfile.custom.bak`) |
| **Restaurar generado desde UCI** | Sí, de forma explícita |

Para volver a la gestión por UCI sin perder la copia, usa **Restaurar generado desde UCI** o desactiva el flag en *Configuración General*.

---

## Uso avanzado: CLI y RPC

### Servicio

```bash
/etc/init.d/caddy start|stop|restart|reload|enable|disable
/etc/init.d/caddy generate              # regenera desde UCI
/etc/init.d/caddy sync_from_caddyfile   # importa reglas del Caddyfile a UCI
```

### Estado y validación

```bash
ubus call luci.caddy status
ubus call luci.caddy get_bin_info
ubus call luci.caddy validate_caddyfile
ubus call luci.caddy test_caddy_run     # validate + adapt, sin arrancar nada
```

### Métodos RPC disponibles

`status`, `get_bin_info`, `validate_caddyfile`, `test_caddy_run`, `get_caddyfile`, `set_caddyfile`, `generate_caddyfile`, `restore_generated`, `sync_general`, `sync_from_caddyfile`, `service_action`, `install_bin`, `free_ports`.

### Ejemplos

```bash
# Guardar un Caddyfile manual (se valida antes)
ubus call luci.caddy set_caddyfile '{"content":"{\n\tlog {\n\t\tlevel INFO\n\t}\n}\n"}'

# Volver a la configuración generada desde UCI
ubus call luci.caddy restore_generated

# Recargar sin cortar conexiones
ubus call luci.caddy service_action '{"action":"reload"}'
```

### Caddy

Caddy guarda certificados en `/etc/caddy/data` y expone su API de administración en `127.0.0.1:2019`.

---

## Seguridad

- `/etc/config/caddy` y `/etc/caddy/Caddyfile` se guardan con permisos **`0600`** (contienen el token).
- El token se enmascara como `***` en cualquier salida RPC o log.
- Un token mal formado **no impide arrancar** Caddy.
- La API de administración de Caddy escucha sólo en `127.0.0.1:2019`.
- El `.apk` es local y no está firmado; `--allow-untrusted` es obligatorio.
- Caddy queda expuesto a Internet en 80/443: mantén el router actualizado y revisa las reglas.

---

## Solución de problemas

| Síntoma | Causa / solución |
|---|---|
| `apk` rechaza el paquete | Falta `--allow-untrusted` |
| `apk add` no hace nada | Misma versión instalada: usa `--upgrade` o desinstala/reinstala |
| `apk upgrade --prune` desinstala la app | El paquete no pertenece a un repositorio: no uses `--prune` |
| No abre LuCI en el 80/443 | LuCI se movió a **8080/8443**; revisa el aviso del post-install |
| LuCI vuelve a ocupar 80/443 | Estado → **Liberar puertos 80/443 (LuCI)** |
| Caddy no arranca | `ubus call luci.caddy test_caddy_run` y `logread \| grep caddy` |
| Error de token de Cloudflare | Revisa formato en *Configuración General*; el generador lo omite si es inválido |
| No se emite certificado | DNS del dominio, 80/443 accesibles, email/token correctos o usa DNS-01 |
| `502 Bad Gateway` | Upstream apagado, IP/puerto incorrectos o firewall |
| Los cambios manuales del Caddyfile desaparecen | Se guardó *Reverse Proxies* (vuelve a modo gestionado); revisa `Caddyfile.custom.bak` |
| `armv7`/`mips` no soportado | Instala el Caddy oficial con `dns-cloudflare` o compila el tuyo |
| UI muestra `Access denied` | Usuario sin ACL `luci-app-caddy`; usa un usuario del grupo adecuado |

---

## Desinstalación

```bash
ssh root@192.168.1.1 'apk del luci-app-caddy'
```

Esto **no** restaura los puertos de LuCI. Para volver a 80/443:

```bash
uci set uhttpd.main.listen_http='0.0.0.0:80'
uci set uhttpd.main.listen_https='0.0.0.0:443'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

Opcionalmente elimina los datos de Caddy:

```bash
rm -rf /etc/caddy /etc/config/caddy
```

---

## Desarrollo y compilación

### Reconstruir el `.apk`

Requisitos: `bash`, `tools/apk.static` (incluido), `unshare` para forzar propietario `root:root`, y los binarios en `bin/`.

```bash
./build_apk.sh
```

El script:

1. Copia `root/` a un directorio temporal.
2. Integra los binarios `x86_64` y `aarch64`.
3. Aplica permisos (`0755` scripts/binarios, `0600` configuración).
4. Genera el post-install/post-upgrade.
5. Empaqueta con `apk mkpkg` y verifica contenido/propietarios.

Salida: `dist/luci-app-caddy.apk` y `dist/luci-app-caddy.apk.sha256`.

### Actualizar la versión

Cambia **a la vez**:

- `PKG_VER` en `build_apk.sh`
- `PKG_VERSION` en `Makefile`

### Estructura de la UI

Cada vista es un módulo ES6 de LuCI (`view.extend`). Los RPC se declaran con `rpc.declare({ object: 'luci.caddy', ... })` y el ACL vive en `usr/share/rpcd/acl.d/luci-app-caddy.json`.

---

## Pruebas de compatibilidad

| Prueba | Entorno | Resultado |
|---|---|---|
| Instalación limpia y actualización | OpenWrt 25.12.6 x86_64 (QEMU) | ✅ |
| Caddy en ejecución y proxy HTTP/HTTPS real | OpenWrt 25.12.6 x86_64 | ✅ 200 `BACKEND_OK` |
| UI completa (4 vistas, alta de proxy, guardado, restauración) | Playwright sobre LuCI real | ✅ |
| Binario ARM64: `version` | qemu-user 11.1.3 (aarch64) | ✅ `v2.11.4` |
| Binario ARM64: módulos | qemu-user 11.1.3 | ✅ 138 módulos, `dns.providers.cloudflare` |
| Binario ARM64: `validate`/`adapt` | qemu-user 11.1.3 | ✅ |
| Binario ARM64: servidor HTTP real | qemu-user 11.1.3 | ✅ `ARM64_OK` |
| Contenido del `.apk` = fuentes | SHA-256 por fichero | ✅ |

El informe detallado está en [AUDITORIA.md](AUDITORIA.md).

---

## Limitaciones conocidas

1. **Emisión real de certificados** no se ha probado en laboratorio (sin salida a Internet); sí la generación y validación local de `acme_dns`/`tls { dns cloudflare }`.
2. **Sólo `x86_64` y `aarch64`**: no hay binarios para ARM de 32 bits ni MIPS.
3. **Importación desde Caddyfile** (`sync_from_caddyfile`) es heurística: cubre dominio, upstream único, `tls internal`/`dns cloudflare`/`http://`, `transparent` y `header_up` extra; no reconstruye configuraciones avanzadas.
4. **Binarios empaquetados**: el post-install elimina `/usr/share/caddy/bin` para ahorrar flash; tras una instalación correcta los botones de instalación de binario quedan deshabilitados.
5. **Certificado interno**: los clientes deben confiar manualmente en la CA local de Caddy.
6. **`apk upgrade --prune`** puede purgar el paquete si se instaló desde un fichero local.

---

## Licencia

Apache License 2.0, según la cabecera del `Makefile`.

Caddy es un proyecto de Stack Holdings GmbH, distribuido bajo Apache License 2.0.
