'use strict';
'require view';
'require rpc';
'require ui';

var callCaddyfile = rpc.declare({
	object: 'luci.caddy',
	method: 'get_caddyfile',
	expect: {}
});

var callSetCaddyfile = rpc.declare({
	object: 'luci.caddy',
	method: 'set_caddyfile',
	params: [ 'content' ],
	expect: {}
});

var callCaddyValidate = rpc.declare({
	object: 'luci.caddy',
	method: 'validate_caddyfile',
	expect: {}
});

var callTestCaddyRun = rpc.declare({
	object: 'luci.caddy',
	method: 'test_caddy_run',
	expect: {}
});

var callRestoreGenerated = rpc.declare({
	object: 'luci.caddy',
	method: 'restore_generated',
	expect: {}
});

var callSyncFromCaddyfile = rpc.declare({
	object: 'luci.caddy',
	method: 'sync_from_caddyfile',
	expect: {}
});

function showTestModal() {
	ui.showModal(_('Validando Caddyfile'), [
		E('p', { 'class': 'spinning' }, _('Ejecutando caddy validate y caddy adapt (sin arrancar el servicio ni contactar con ACME)...'))
	]);
	return callTestCaddyRun().then(function(res) {
		ui.showModal(_('Resultado de la validación'), [
			E('div', { 'style': 'margin-bottom: 12px;' }, [
				res.success
					? E('span', { 'class': 'badge', 'style': 'background:#27ae60; color:#fff; font-size:1em; padding:4px 10px; border-radius:4px; font-weight:bold;' }, '✓ ' + _('Configuración válida'))
					: E('span', { 'class': 'badge', 'style': 'background:#e74c3c; color:#fff; font-size:1em; padding:4px 10px; border-radius:4px; font-weight:bold;' }, '✗ ' + _('Error detectado'))
			]),
			E('pre', {
				'style': 'max-height: 420px; overflow-y: auto; background: #181818; color: #38ef7d; padding: 14px; border-radius: 6px; font-family: monospace; font-size: 0.9em; white-space: pre-wrap; word-break: break-word;'
			}, res.output || _('Sin salida')),
			E('div', { 'class': 'right', 'style': 'margin-top: 15px;' }, [
				E('button', {
					'class': 'btn cbi-button-action',
					'click': ui.hideModal
				}, _('Cerrar'))
			])
		]);
	}).catch(function(err) {
		ui.hideModal();
		ui.addNotification(null, E('p', _('Error al validar Caddy: ') + (err.message || err)), 'error');
	});
}

return view.extend({
	load: function() {
		return callCaddyfile().catch(function() {
			return { content: '# Error al leer /etc/caddy/Caddyfile', custom: 0 };
		});
	},

	render: function(data) {
		var content = data ? data.content : '';
		var customMode = !!(data && data.custom === 1);
		var self = this;

		var modeBadge = E('span', {
			'id': 'caddyfile_mode_badge',
			'class': customMode ? 'badge label-warning' : 'badge label-info',
			'style': 'font-size: 100%; padding: 4px 10px;'
		}, customMode
			? _('Modo personalizado: las ediciones no se sobrescriben')
			: _('Modo gestionado por LuCI (regenerado desde UCI)'));

		var textArea = E('textarea', {
			'id': 'caddyfile_content',
			'rows': 24,
			'spellcheck': 'false',
			'style': 'width: 100%; box-sizing: border-box; background: var(--background-color-low, #181818); color: #38ef7d; padding: 16px; border-radius: 6px; font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, Courier, monospace; font-size: 0.95em; line-height: 1.5; border: 1px solid var(--border-color-medium, #333); tab-size: 4; -moz-tab-size: 4;'
		}, content || '');

		var btnSave = E('button', {
			'class': 'btn cbi-button-save',
			'style': 'padding: 8px 18px;',
			'click': ui.createHandlerFn(this, function() {
				var text = document.getElementById('caddyfile_content').value;
				if (!text || !text.trim()) {
					ui.addNotification(null, E('p', _('El archivo Caddyfile no puede estar completamente vacío.')), 'error');
					return;
				}
				ui.showModal(_('Guardando'), [
					E('p', { 'class': 'spinning' }, _('Validando y aplicando la configuración en /etc/caddy/Caddyfile...'))
				]);
				return callSetCaddyfile(text).then(function(res) {
					ui.hideModal();
					if (res && res.saved && res.valid) {
						customMode = true;
						var badge = document.getElementById('caddyfile_mode_badge');
						if (badge) {
							badge.className = 'badge label-warning';
							badge.textContent = _('Modo personalizado: las ediciones no se sobrescriben');
						}
						ui.addNotification(null, E('p', '✓ ' + _('Caddyfile guardado y aplicado. Modo personalizado activado: pulsa «Restaurar generado» para volver a la gestión por UCI.')), 'info');
					} else {
						ui.addNotification(null, E('div', [
							E('p', { 'style': 'font-weight: bold; color: red;' }, _('Caddyfile NO guardado (configuración inválida). El archivo activo no se ha modificado:')),
							E('pre', {}, (res && res.output) || _('Error de sintaxis'))
						]), 'error');
					}
				}).catch(function(err) {
					ui.hideModal();
					ui.addNotification(null, E('p', _('Error al guardar: ') + (err.message || err)), 'error');
				});
			})
		}, _('Guardar y Aplicar'));

		var btnValidate = E('button', {
			'class': 'btn cbi-button-action',
			'style': 'padding: 8px 18px; margin-left: 10px;',
			'click': ui.createHandlerFn(this, function() {
				return callCaddyValidate().then(function(res) {
					if (res && res.valid) {
						ui.addNotification(null, E('p', '✓ ' + _('La sintaxis del Caddyfile en disco es completamente válida.')), 'info');
					} else {
						ui.addNotification(null, E('div', [
							E('p', { 'style': 'font-weight: bold; color: red;' }, _('Error de sintaxis en Caddyfile:')),
							E('pre', {}, (res && res.output) || _('Error desconocido'))
						]), 'error');
					}
				});
			})
		}, _('Comprobar Sintaxis'));

		var btnTest = E('button', {
			'class': 'btn cbi-button-action',
			'style': 'padding: 8px 18px; margin-left: 10px; font-weight: bold;',
			'click': function(ev) {
				ev.preventDefault();
				showTestModal();
			}
		}, '▶ ' + _('Probar Configuración'));

		var btnRefresh = E('button', {
			'class': 'btn cbi-button-reset',
			'style': 'padding: 8px 18px; margin-left: 10px;',
			'click': ui.createHandlerFn(this, function() {
				return callCaddyfile().then(function(res) {
					var el = document.getElementById('caddyfile_content');
					if (el && res) {
						el.value = res.content || '';
						ui.addNotification(null, E('p', _('Contenido recargado desde /etc/caddy/Caddyfile')), 'info');
					}
				});
			})
		}, _('Recargar desde Disco'));

		var btnRestore = E('button', {
			'class': 'btn cbi-button-negative',
			'style': 'padding: 8px 18px; margin-left: 10px;',
			'click': ui.createHandlerFn(this, function() {
				if (!confirm(_('Se descartará la edición manual y el Caddyfile se regenerará desde la configuración UCI (Reverse Proxies). ¿Continuar?')))
					return;
				ui.showModal(_('Restaurando'), [
					E('p', { 'class': 'spinning' }, _('Regenerando /etc/caddy/Caddyfile desde UCI...'))
				]);
				return callRestoreGenerated().then(function(res) {
					ui.hideModal();
					if (res && res.valid) {
						ui.addNotification(null, E('p', _('Caddyfile restaurado desde UCI.')), 'info');
						window.location.reload();
					} else {
						ui.addNotification(null, E('p', (res && res.output) || _('No se pudo restaurar')), 'error');
					}
				}).catch(function(err) {
					ui.hideModal();
					ui.addNotification(null, E('p', _('Error: ') + (err.message || err)), 'error');
				});
			})
		}, _('Restaurar generado desde UCI'));

		var btnImport = E('button', {
			'class': 'btn cbi-button-action',
			'style': 'padding: 8px 18px; margin-left: 10px;',
			'click': ui.createHandlerFn(this, function() {
				if (!confirm(_('Se reemplazarán las reglas de Reverse Proxies actuales por las que se puedan leer del Caddyfile en disco. ¿Continuar?')))
					return;
				return callSyncFromCaddyfile().then(function() {
					ui.addNotification(null, E('p', _('Reglas importadas a la configuración UCI. Revisa la pestaña Reverse Proxies.')), 'info');
				}).catch(function(err) {
					ui.addNotification(null, E('p', _('Error al importar: ') + (err.message || err)), 'error');
				});
			})
		}, _('Importar Caddyfile a UCI'));

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Caddy - Editor Directo de Caddyfile')),
			E('div', { 'class': 'cbi-map-descr' },
				_('Edita directamente el archivo activo /etc/caddy/Caddyfile. Al guardar se valida antes de sustituirlo; si es inválido, el archivo activo no se modifica.')),

			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; flex-wrap: wrap; gap: 10px;' }, [
					E('div', {}, [
						E('span', { 'style': 'color: #888; font-size: 0.95em;' }, _('Archivo activo: /etc/caddy/Caddyfile ')),
						modeBadge,
						E('div', { 'style': 'color: #888; font-size: 0.85em; margin-top: 6px;' },
							_('En modo personalizado, guardar otras pestañas o reiniciar el router NO borra estos cambios. Guardar Reverse Proxies fuerza la vuelta al modo gestionado por UCI.'))
					]),
					E('div', {}, [ btnSave, btnTest, btnValidate, btnRefresh, btnRestore, btnImport ])
				]),
				textArea
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
