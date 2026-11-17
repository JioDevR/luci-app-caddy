'use strict';
'require view';
'require rpc';
'require ui';
'require uci';

var callCaddyStatus = rpc.declare({
	object: 'luci.caddy',
	method: 'status',
	expect: {}
});

var callCaddyBinInfo = rpc.declare({
	object: 'luci.caddy',
	method: 'get_bin_info',
	expect: {}
});

var callCaddyValidate = rpc.declare({
	object: 'luci.caddy',
	method: 'validate_caddyfile',
	expect: {}
});

var callCaddyService = rpc.declare({
	object: 'luci.caddy',
	method: 'service_action',
	params: [ 'action' ],
	expect: {}
});

var callInstallBin = rpc.declare({
	object: 'luci.caddy',
	method: 'install_bin',
	params: [ 'source' ],
	expect: {}
});

var callFreePorts = rpc.declare({
	object: 'luci.caddy',
	method: 'free_ports',
	expect: {}
});

return view.extend({
	load: function() {
		return Promise.all([
			callCaddyStatus().catch(function() { return { running: 0, pid: 0, enabled: 0 }; }),
			callCaddyBinInfo().catch(function() { return { installed: 0, version: 'none', has_cloudflare: 0, arch: 'unknown', path: '', bundled_available: 0 }; }),
			uci.load('caddy'),
			uci.load('uhttpd').catch(function() { return {}; })
		]);
	},

	render: function(data) {
		var status = data[0];
		var binInfo = data[1];

		var isRunning = (status && status.running === 1);
		var isInstalled = (binInfo && binInfo.installed === 1);
		var hasCF = (binInfo && binInfo.has_cloudflare === 1);
		var bundled = (binInfo && binInfo.bundled_available === 1);

		// Badge limpio y estático (sin clase spinning)
		var statusBadge = isRunning
			? E('span', { 'class': 'badge label-success', 'style': 'font-size: 105%; padding: 5px 12px;' },
				'● ' + _('En ejecución') + ' (PID: ' + status.pid + ')')
			: E('span', { 'class': 'badge label-danger', 'style': 'font-size: 105%; padding: 5px 12px;' },
				'■ ' + _('Detenido'));

		var binBadge = isInstalled
			? E('span', { 'class': 'badge label-info', 'style': 'font-size: 105%; margin-left: 8px;' },
				'Caddy ' + (binInfo.version ? binInfo.version.split(' ')[0] : _('Instalado')))
			: E('span', { 'class': 'badge label-warning', 'style': 'font-size: 105%; margin-left: 8px;' },
				_('Binario no instalado'));

		var cfBadge = hasCF
			? E('span', { 'class': 'badge label-success', 'style': 'font-size: 105%; margin-left: 8px;' },
				'✓ ' + _('Módulo Cloudflare Activo'))
			: E('span', { 'class': 'badge label-default', 'style': 'font-size: 105%; margin-left: 8px;' },
				_('Cloudflare no detectado'));

		var enableBadge = (status && status.enabled === 1)
			? E('span', { 'class': 'badge label-success', 'style': 'font-size: 105%; margin-left: 8px;' },
				_('Inicio automático activado'))
			: E('span', { 'class': 'badge label-default', 'style': 'font-size: 105%; margin-left: 8px;' },
				_('Inicio automático desactivado'));

		var proxies = uci.sections('caddy', 'proxy') || [];
		var httpPort = uci.get('caddy', 'general', 'http_port') || '80';
		var httpsPort = uci.get('caddy', 'general', 'https_port') || '443';

		// Detección de puertos de LuCI (uhttpd)
		var uhttpdListenHttp = uci.get('uhttpd', 'main', 'listen_http') || ['8080'];
		var uhttpdListenHttps = uci.get('uhttpd', 'main', 'listen_https') || ['8443'];
		var luciHttpDisplay = Array.isArray(uhttpdListenHttp) ? uhttpdListenHttp.join(', ') : uhttpdListenHttp;
		var luciHttpsDisplay = Array.isArray(uhttpdListenHttps) ? uhttpdListenHttps.join(', ') : uhttpdListenHttps;

		var reloadPage = function(msg, type) {
			if (msg)
				ui.addNotification(null, E('p', {}, msg), type || 'info');
			window.location.reload();
		};

		var btnStart = E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'disabled': isRunning || !isInstalled ? 'disabled' : null,
			'click': ui.createHandlerFn(this, function() {
				ui.showModal(_('Iniciando Caddy...'), [ E('p', { 'class': 'spinning' }, _('Arrancando el servicio...')) ]);
				return callCaddyService('start').then(function() {
					ui.hideModal();
					reloadPage(_('Servicio Caddy iniciado'));
				});
			})
		}, _('Iniciar'));

		var btnStop = E('button', {
			'class': 'btn cbi-button cbi-button-negative',
			'disabled': !isRunning ? 'disabled' : null,
			'click': ui.createHandlerFn(this, function() {
				ui.showModal(_('Deteniendo Caddy...'), [ E('p', { 'class': 'spinning' }, _('Deteniendo el proceso...')) ]);
				return callCaddyService('stop').then(function() {
					ui.hideModal();
					reloadPage(_('Servicio Caddy detenido'));
				});
			})
		}, _('Detener'));

		var btnRestart = E('button', {
			'class': 'btn cbi-button cbi-button-neutral',
			'disabled': !isInstalled ? 'disabled' : null,
			'click': ui.createHandlerFn(this, function() {
				ui.showModal(_('Reiniciando Caddy...'), [ E('p', { 'class': 'spinning' }, _('Reiniciando el servicio...')) ]);
				return callCaddyService('restart').then(function() {
					ui.hideModal();
					reloadPage(_('Servicio Caddy reiniciado con éxito'));
				});
			})
		}, _('Reiniciar'));

		var btnReload = E('button', {
			'class': 'btn cbi-button cbi-button-neutral',
			'disabled': !isRunning ? 'disabled' : null,
			'click': ui.createHandlerFn(this, function() {
				return callCaddyService('reload').then(function() {
					ui.addNotification(null, E('p', _('Configuración recargada sin desconectar clientes')), 'info');
				});
			})
		}, _('Recargar Configuración'));

		var btnValidate = E('button', {
			'class': 'btn cbi-button cbi-button-apply',
			'disabled': !isInstalled ? 'disabled' : null,
			'click': ui.createHandlerFn(this, function() {
				return callCaddyValidate().then(function(res) {
					if (res && res.valid) {
						ui.addNotification(null, E('p', '✓ ' + _('La sintaxis del Caddyfile es 100% válida.')), 'info');
					} else {
						ui.addNotification(null, E('div', [
							E('p', { 'style': 'font-weight: bold; color: red;' }, _('Error en validación de Caddyfile:')),
							E('pre', {}, res ? res.output : _('Error desconocido'))
						]), 'error');
					}
				});
			})
		}, _('Comprobar Sintaxis'));

		var btnInstall = E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'disabled': !bundled ? 'disabled' : null,
			'click': ui.createHandlerFn(this, function() {
				ui.showModal(_('Instalando binario'), [ E('p', { 'class': 'spinning' }, _('Copiando el binario de Caddy incluido en el paquete...')) ]);
				return callInstallBin('bundled').then(function(res) {
					ui.hideModal();
					if (res && res.success) {
						ui.addNotification(null, E('pre', {}, res.message || _('Binario instalado')), 'info');
						window.location.reload();
					} else {
						ui.addNotification(null, E('pre', {}, (res && res.message) || _('Error al instalar')), 'error');
					}
				}).catch(function(err) {
					ui.hideModal();
					ui.addNotification(null, E('p', _('Error: ') + (err.message || err)), 'error');
				});
			})
		}, _('Instalar binario incluido'));

		var btnForceInstall = E('button', {
			'class': 'btn cbi-button cbi-button-reset',
			'disabled': !bundled ? 'disabled' : null,
			'click': ui.createHandlerFn(this, function() {
				if (!confirm(_('Se reemplazará el binario /usr/bin/caddy por el incluido en el paquete. ¿Continuar?')))
					return;
				ui.showModal(_('Reinstalando binario'), [ E('p', { 'class': 'spinning' }, _('Reemplazando el binario de Caddy...')) ]);
				return callInstallBin('force').then(function(res) {
					ui.hideModal();
					if (res && res.success) {
						ui.addNotification(null, E('pre', {}, res.message || _('Binario reinstalado')), 'info');
						window.location.reload();
					} else {
						ui.addNotification(null, E('pre', {}, (res && res.message) || _('Error al instalar')), 'error');
					}
				}).catch(function(err) {
					ui.hideModal();
					ui.addNotification(null, E('p', _('Error: ') + (err.message || err)), 'error');
				});
			})
		}, _('Reinstalar binario (forzado)'));

		var btnFreePorts = E('button', {
			'class': 'btn cbi-button cbi-button-neutral',
			'click': ui.createHandlerFn(this, function() {
				return callFreePorts().then(function(res) {
					var msg = (res && res.message) || _('Puertos procesados');
					ui.addNotification(null, E('p', {}, msg), 'info');
				}).catch(function(err) {
					ui.addNotification(null, E('p', _('Error: ') + (err.message || err)), 'error');
				});
			})
		}, _('Liberar puertos 80/443 (LuCI)'));

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Caddy - Estado y Control')),
			E('div', { 'class': 'cbi-map-descr' },
				_('Monitoriza el estado del servidor web y ejecuta acciones administrativas.')),

			// Sección 1: Diagnóstico en Tiempo Real
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Estado en Tiempo Real')),
				E('div', { 'class': 'cbi-section-node', 'style': 'padding: 15px;' }, [
					E('table', { 'class': 'table', 'style': 'width: 100%;' }, [
						E('tr', { 'class': 'tr' }, [
							E('td', { 'class': 'td', 'style': 'width: 30%; font-weight: bold;' }, _('Estado del Proceso:')),
							E('td', { 'class': 'td' }, [ statusBadge, binBadge, cfBadge, enableBadge ])
						]),
						E('tr', { 'class': 'tr' }, [
							E('td', { 'class': 'td', 'style': 'font-weight: bold;' }, _('Ruta del Binario:')),
							E('td', { 'class': 'td' }, E('code', {}, binInfo.path || '/usr/bin/caddy'))
						]),
						E('tr', { 'class': 'tr' }, [
							E('td', { 'class': 'td', 'style': 'font-weight: bold;' }, _('Arquitectura Detectada:')),
							E('td', { 'class': 'td' }, E('span', { 'class': 'badge' }, binInfo.arch || 'unknown'))
						]),
						E('tr', { 'class': 'tr' }, [
							E('td', { 'class': 'td', 'style': 'font-weight: bold;' }, _('Puertos de Caddy:')),
							E('td', { 'class': 'td' }, [
								E('span', { 'class': 'badge label-default', 'style': 'margin-right: 5px;' }, 'HTTP: ' + httpPort),
								E('span', { 'class': 'badge label-default' }, 'HTTPS: ' + httpsPort)
							])
						]),
						E('tr', { 'class': 'tr' }, [
							E('td', { 'class': 'td', 'style': 'font-weight: bold;' }, _('Puertos de LuCI (uhttpd):')),
							E('td', { 'class': 'td' }, [
								E('span', { 'class': 'badge label-default', 'style': 'margin-right: 5px;' }, 'HTTP: ' + luciHttpDisplay),
								E('span', { 'class': 'badge label-default' }, 'HTTPS: ' + luciHttpsDisplay)
							])
						]),
						E('tr', { 'class': 'tr' }, [
							E('td', { 'class': 'td', 'style': 'font-weight: bold;' }, _('Reverse Proxies Configurados:')),
							E('td', { 'class': 'td' }, E('strong', {}, proxies.length + ' ' + _('reglas registradas')))
						])
					])
				])
			]),

			// Sección 2: Acciones del Servicio
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Acciones del Servicio')),
				E('div', { 'class': 'cbi-section-node', 'style': 'padding: 15px;' }, [
					E('div', { 'style': 'display: flex; flex-wrap: wrap; gap: 8px;' }, [
						btnStart,
						btnStop,
						btnRestart,
						btnReload,
						btnValidate
					])
				])
			]),

			// Sección 3: Mantenimiento
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Mantenimiento')),
				E('div', { 'class': 'cbi-section-node', 'style': 'padding: 15px;' }, [
					E('div', { 'style': 'display: flex; flex-wrap: wrap; gap: 8px;' }, [
						btnInstall,
						btnForceInstall,
						btnFreePorts
					]),
					E('p', { 'class': 'cbi-section-descr', 'style': 'margin-top: 10px;' },
						_('«Instalar binario incluido» copia el Caddy del paquete (x86_64/aarch64 con Cloudflare) si no hay uno instalado. «Liberar puertos» reasigna uhttpd a 8080/8443 si vuelve a ocupar 80/443.'))
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
