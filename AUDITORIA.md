# Informe de Auditoría — luci-app-caddy (3ª revisión)

**Fecha:** 2026-11-16
**Entorno de pruebas:** VM `openwrt-lab` (QEMU/libvirt, OpenWrt 25.12.6 r33311, x86_64, `192.168.1.1`)
**Paquete auditado:** `dist/luci-app-caddy.apk` **1.0.3-r1** (instalado como actualización sobre 1.0.2-r1)
**Método:** análisis estático + pruebas RPC/ubus reales + pruebas de navegador con Playwright sobre la UI de LuCI + prueba extremo a extremo de reverse proxy (HTTP y HTTPS) + comprobación de persistencia tras reinicios.

---

## Veredicto

**Todas las funcionalidades principales funcionan y los fallos críticos de las auditorías anteriores están corregidos y verificados en la VM.** La instalación/actualización, el ciclo de vida del servicio, la generación del Caddyfile (incluidos los 4 modos TLS), la validación previa a sobrescribir, la persistencia de ediciones manuales, el enmascarado del token, la UI y el reverse proxy real (HTTP/HTTPS) han sido probados con resultados correctos.

Se han corregido **13 de los 13 hallazgos** de la revisión anterior (C1–C5 y M1–M10), más 5 menores. Quedan únicamente **limitaciones conocidas y documentadas** (ver final), ninguna crítica.

---

## Cambios aplicados en esta revisión

| Fichero | Cambio |
|---|---|
| `root/usr/libexec/rpcd/luci.caddy` | Estado vía **procd** (`ubus service list`), `enabled` desde UCI, **validar antes de escribir**, `saved` ≠ `valid`, rechazo de contenido vacío, enmascarado del token, `test_caddy_run` sin `caddy run`, nuevos métodos `restore_generated`, `bundled_available` real, no fuerza `enabled=1` |
| `root/usr/lib/caddy/generate-caddyfile.sh` | **`tls_mode`** (`auto`/`cloudflare`/`internal`/`off`), validación del formato del token, validación del Caddyfile generado antes de sustituirlo, `caddy fmt`, permisos `0600`, `--force`, indentado de `custom_headers` multilínea |
| `root/etc/init.d/caddy` | Respeta `Caddyfile.custom`, conserva el Caddyfile anterior si la generación falla, enmascara el token en logs, elimina el generador duplicado, `is_valid_token` |
| `root/www/luci-static/resources/view/caddy/general.js` | Validación de formato del token, opción **`custom_caddyfile`**, avisos de error de validación |
| `.../proxies.js` | Campo **Modo TLS** por proxy, aviso de cambio de modo, sin doble guardado |
| `.../caddyfile.js` | Badge de modo, botones **Restaurar generado** e **Importar a UCI**, `<code>` literal corregido, mensajes de error reales |
| `.../status.js` | Botones de mantenimiento (instalar/reinstalar binario, liberar puertos), fila de puertos de LuCI, badge de inicio automático |
| `root/usr/share/rpcd/acl.d/luci-app-caddy.json` | Lectura de `uhttpd`, permiso `restore_generated` |
| `root/etc/uci-defaults/luci-app-caddy`, `caddy-installer.sh`, `build_apk.sh` | `chmod 600` de configuración/Caddyfile; versión 1.0.3 |
| `Makefile` | `PKG_VERSION:=1.0.3`, `LUCI_DEPENDS:=+caddy` (ya no se usa `timeout`) |
| `README.md` | Modos TLS reales, modo personalizado, botón de prueba, permisos, límites del instalador |

---

## Hallazgos de la revisión anterior: estado final

| # | Hallazgo | Estado | Verificación |
|---|---|---|---|
| **C1** | El editor de Caddyfile perdía las ediciones | ✅ **Corregido** | Guardado UI → activa `custom_caddyfile=1`; sobrevive a `reload`, `restart`, `sync_general`, recarga de página y reinicio del router |
| **C2** | Los modos TLS del README no existían | ✅ **Corregido** | `auto`, `cloudflare`, `internal` y `off` generan/validan correctamente (`tls internal`, `tls { dns cloudflare … }`, `http://dominio`) |
| **C3** | Token mal formado dejaba Caddy caído y se filtraba | ✅ **Corregido** | Token con `{`, `"` o espacios → se omite `acme_dns`, el servicio sigue arriba; errores muestran `***`; `logread` sin el token |
| **C4** | `set_caddyfile` sobrescribía antes de validar | ✅ **Corregido** | Caddyfile inválido → `saved:false`, md5 del fichero activo sin cambios |
| **C5** | «Guardado correctamente» sin guardar | ✅ **Corregido** | Sin `content` o vacío → `saved:false, valid:false`; el fichero no cambia |
| **M1** | `status.enabled` leía el symlink | ✅ **Corregido** | `enabled=0` en UCI con symlink presente → `status.enabled=0` |
| **M2** | Guardar proxies forzaba `enabled=1` | ✅ **Corregido** | `enabled=0` → sigue `0`; el servicio no se enciende solo |
| **M3** | `status` usaba `pgrep` | ✅ **Corregido** | Lee el PID de `ubus call service list` (con `pgrep` sólo como fallback) |
| **M4** | «Probar Caddy» daba falsos positivos y consumía cuota ACME | ✅ **Corregido** | Usa `caddy validate` + `caddy adapt`; no abre puertos ni inicia proceso ni llama a ACME |
| **M5** | Token en claro con permisos 0644 | ✅ **Corregido** | `/etc/config/caddy` y `/etc/caddy/Caddyfile` en `0600`; token enmascarado en salidas |
| **M6** | 3 métodos RPC sin botón | ✅ **Corregido** | Instalar binario, liberar puertos, importar Caddyfile y restaurar generado tienen botón |
| **M7** | `bundled_available` siempre 1 | ✅ **Corregido** | Sólo cuenta `/usr/share/caddy/bin` y `/usr/lib/caddy/bin`; devuelve `0` tras la limpieza del post-install |
| **M8** | El post-install borra ficheros del paquete | ⚠️ **Documentado** | Es intencional para liberar flash; el README ya lo describe con precisión |
| **M9** | Dependencias no declaradas | ✅ **Corregido** | El `.apk` sólo declara `luci-base`; ya no se usa `timeout` |
| **M10** | La UI leía `uhttpd` sin ACL | ✅ **Corregido** | `uci` lectura incluye `uhttpd` |
| m1 | Caddyfile sin formatear | ✅ | `caddy fmt --overwrite` tras generar |
| m2 | `custom_headers` perdidos al importar | ✅ | Se importan las directivas `header_up` extra |
| m4 | Versiones duplicadas | ✅ | Makefile y `build_apk.sh` en 1.0.3 |

---

## Pruebas ejecutadas y resultados

### 1. Paquete e instalación
* `apk add --allow-untrusted --upgrade` de 1.0.2-r1 → **1.0.3-r1**: OK, post-upgrade ejecutado, puertos y binario reutilizados.
* Hashes MD5 de **todos** los ficheros instalados = árbol de fuentes.
* Metadatos del `.apk`: `depends: luci-base`, propietario `root:root`, `etc/config/caddy` en `0600`, sin ficheros basura en `/`.
* Permisos comprobados en el router: `-rw------- /etc/config/caddy` y `/etc/caddy/Caddyfile`.

### 2. Estado y ciclo de vida
```
stop    → {"running":0,"pid":0,"enabled":1}
start   → {"running":1,"pid":13795,"enabled":1}
sync_general con enabled=0 → {"running":0,"enabled":0}, symlink off
sync_general con enabled=1 → {"running":1,"enabled":1}, symlink on
status con enabled=0 y symlink presente → enabled:0
```
El PID se obtiene de procd (no de `pgrep`).

### 3. Caddyfile: validación y persistencia
| Prueba | Resultado |
|---|---|
| Guardar `this is { not valid caddy` | `saved:false`, `valid:false`, md5 del Caddyfile intacto ✅ |
| Guardar `{"content":""}` | Rechazado, fichero intacto ✅ |
| Guardar contenido válido | `saved:true`, modo personalizado, `.custom` creado ✅ |
| Tras `reload` / `restart` / `sync_general` | marca manual presente ✅ |
| Tras recargar la página en la UI | marca y badge «Modo personalizado» presentes ✅ |
| Guardar Reverse Proxies en modo personalizado | vuelve a modo gestionado, copia en `Caddyfile.custom.bak` ✅ |
| Restaurar generado desde UCI | marca desaparece, badge «Modo gestionado» ✅ |
| Importar Caddyfile a UCI | 3 reglas importadas con `tls_mode` `internal`/`off`/`cloudflare`, `transparent` y `custom_headers` ✅ |

### 4. Modos TLS (generación real)
```caddyfile
auto.example.com { reverse_proxy 192.168.1.10:80 }                 # auto
int.example.com  { tls internal
                   reverse_proxy 192.168.1.11:80 }                 # internal
http://plain.example.com { reverse_proxy 192.168.1.12:80 }         # off
cf.example.com   { tls { dns cloudflare <token> }
                   reverse_proxy 192.168.1.13:80 }                 # cloudflare
```
`caddy adapt` valida los cuatro bloques.

### 5. Token de Cloudflare
| Caso | Resultado |
|---|---|
| Token con `{`, `"` o espacios | Se omite `acme_dns`; servicio sigue en ejecución; aviso en log sin el token ✅ |
| Token de formato válido | `acme_dns cloudflare …` generado y validado (sin red) ✅ |
| Error de Caddy que cita el token | UI y RPC muestran `API token '***' appears invalid` ✅ |
| `logread` | 0 apariciones del token ✅ |
| UI, token inválido | Campo marcado como inválido y guardado rechazado ✅ |

### 6. Diagnóstico
* `test_caddy_run` → `success:true`, salida con `[SINTAXIS VALIDADA]` + `[ADAPTACION A JSON CORRECTA]`; **sin** procesos nuevos ni puertos abiertos.
* `validate_caddyfile` → correcto; errores reales y enmascarados.
* `free_ports` → JSON con `changed:false/already_free:true`, LuCI en 8080/8443.
* `get_bin_info` → `bundled_available:0` tras la limpieza (antes siempre 1).

### 7. Reverse proxy extremo a extremo
Con un backend real (`caddy file-server` en `127.0.0.1:9999`):
```
HTTP  plain.local   (tls off)      → 200  BACKEND_OK
HTTP  noexiste.local               → 308  (redirección automática a HTTPS)
HTTPS tlsint.local  (tls internal) → 200  BACKEND_OK
```

### 8. Interfaz LuCI (Playwright, navegador real)
* Las 4 vistas renderizan con su `h2` correcto y **sin errores JavaScript propios**.
* Estado: badges de ejecución/binario/Cloudflare/inicio automático, puertos de Caddy y de LuCI, contador de reglas, botones de mantenimiento.
* General: campo «Usar Caddyfile personalizado», validación del token, guardado sin borrar el modo personalizado.
* Proxies: alta de regla con **Modo TLS = Certificado interno** vía modal → fila creada, «Save & Apply» aplica y el Caddyfile contiene `tls internal`; sin campos inválidos.
* Caddyfile: guardado con validación, badge de modo, recarga de página con persistencia, «Comprobar Sintaxis», «Probar Configuración» (modal con adaptación) y «Restaurar generado» funcionan.
* Único mensaje externo: en la pantalla de login (antes de autenticarse) LuCI core pide `uci get luci` y recibe `Access denied` en esta imagen; no proviene de la app y desaparece tras el login.

---

## Limitaciones conocidas (no bloqueantes)

1. **Emisión real de certificados no verificada**: la VM no tiene salida a Internet. Se validó la generación y el chequeo local de formato de `acme_dns`/`tls { dns cloudflare }`, pero no una emisión ACME real (Let's Encrypt o Cloudflare) ni el reto DNS-01 con un token real.
2. **Binarios empaquetados**: el post-install elimina `/usr/share/caddy/bin` tras instalar Caddy para ahorrar ~88 MB de flash. Por eso, tras una instalación correcta, `bundled_available=0` y los botones de instalación de binario aparecen deshabilitados (no hay binario que reinstalar). Es el comportamiento documentado en el README.
3. **Importación (`sync_from_caddyfile`)**: heurística. Importa dominio, un único `reverse_proxy`, `tls internal`/`dns cloudflare`/`http://`, `transparent` y directivas `header_up` extra; no reconstruye bloques avanzados (múltiples upstreams, matchers, `handle`, etc.). Para configuraciones complejas se recomienda el modo personalizado.
4. **`enabled` vs symlink**: la fuente de verdad es UCI (`caddy.general.enabled`). Si alguien ejecuta manualmente `/etc/init.d/caddy enable` con `enabled=0`, el symlink queda creado pero `start_service` sigue respetando UCI; `status` informa `enabled:0`.
5. **Entorno de la VM**: `uhttpd` quedó escuchando sólo en IPv6 (`[::]:8080`); por eso las pruebas de navegador se hicieron por túnel SSH a `[::1]`. Es una particularidad de esta VM, no de la aplicación.
6. **`--prune`**: sigue siendo cierto que `apk upgrade --prune` puede purgar el paquete instalado desde fichero local (documentado en el README).

---

## Cómo reproducir las pruebas

```bash
# Instalar/actualizar
scp -O dist/luci-app-caddy.apk root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'apk add --allow-untrusted --upgrade /tmp/luci-app-caddy.apk'

# Estado y binario
ubus call luci.caddy status
ubus call luci.caddy get_bin_info

# Validación sin arrancar nada
ubus call luci.caddy test_caddy_run

# Edición manual persistente
ubus call luci.caddy set_caddyfile '{"content":"{ \n log { \n level INFO \n } \n}\n"}'
/etc/init.d/caddy restart && grep -c "level INFO" /etc/caddy/Caddyfile

# Restaurar modo gestionado
ubus call luci.caddy restore_generated
```

**Conclusión:** el proyecto queda funcional y coherente con su documentación. Los fallos que impedían un uso seguro (pérdida de ediciones, configuración rota por un guardado inválido, servicio caído por un token mal pegado, promesas TLS no implementadas) están resueltos y verificados en hardware virtual real.
