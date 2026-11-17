'use strict';
'require view';
'require form';
'require rpc';
'require ui';

var callSyncGeneral = rpc.declare({
	object: 'luci.caddy',
	method: 'sync_general',
	expect: {}
});

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('caddy', _('Caddy - Configuración General'),
			_('Ajustes globales del servidor web y configuración de Cloudflare DNS-01 Challenge para emisión automática de certificados SSL.'));

		s = m.section(form.NamedSection, 'general', 'caddy', _('Parámetros Globales'));
		s.addremove = false;

		// 1. Servicio
		o = s.option(form.Flag, 'enabled', _('Habilitar Caddy'),
			_('Habilita el inicio automático del servicio Caddy en el arranque del sistema.'));
		o.rmempty = false;
		o.default = '0';

		// 2. Cloudflare API Token
		o = s.option(form.Value, 'cloudflare_token', _('Token de API de Cloudflare'),
			_('Token de API de Cloudflare con permisos de edición DNS (Zone.DNS). Permite validar dominios mediante el reto DNS-01 de ACME para obtener certificados SSL válidos incluso sin puertos abiertos o detrás de CGNAT. Déjalo vacío para usar sólo Let\'s Encrypt (HTTP-01).'));
		o.password = true;
		o.placeholder = 'Pon aquí tu API Token de Cloudflare';
		o.validate = function(section_id, value) {
			if (!value)
				return true;
			// Caddy rechaza tokens con comillas, llaves, espacios... y entonces
			// el servicio no arranca. Se valida el formato antes de guardar.
			if (!/^[A-Za-z0-9_-]+$/.test(value))
				return _('El token sólo puede contener letras, números, guiones y guiones bajos (sin comillas, llaves ni espacios)');
			if (value.length < 32)
				return _('El token parece demasiado corto. Copia el token completo desde el panel de Cloudflare.');
			return true;
		};

		// 3. Email
		o = s.option(form.Value, 'email', _('Email de Administrador'),
			_('Correo de contacto para registro en Let\'s Encrypt / ZeroSSL (avisos de expiración o problemas de seguridad).'));
		o.placeholder = 'admin@tudominio.com';
		o.datatype = 'email';

		// 4. Puertos con validación cruzada y rango
		var optHttp = s.option(form.Value, 'http_port', _('Puerto HTTP'),
			_('Puerto en el que Caddy escuchará las conexiones HTTP normales.'));
		optHttp.default = '80';
		optHttp.datatype = 'port';
		optHttp.validate = function(section_id, value) {
			var port = parseInt(value, 10);
			if (isNaN(port) || port < 1 || port > 65535)
				return _('Introduce un puerto válido (1-65535)');
			var httpsVal = optHttps ? optHttps.formvalue(section_id) : null;
			if (httpsVal && parseInt(httpsVal, 10) === port)
				return _('El puerto HTTP no puede ser idéntico al puerto HTTPS');
			return true;
		};

		var optHttps = s.option(form.Value, 'https_port', _('Puerto HTTPS'),
			_('Puerto en el que Caddy escuchará las conexiones HTTPS seguras.'));
		optHttps.default = '443';
		optHttps.datatype = 'port';
		optHttps.validate = function(section_id, value) {
			var port = parseInt(value, 10);
			if (isNaN(port) || port < 1 || port > 65535)
				return _('Introduce un puerto válido (1-65535)');
			var httpVal = optHttp ? optHttp.formvalue(section_id) : null;
			if (httpVal && parseInt(httpVal, 10) === port)
				return _('El puerto HTTPS no puede ser idéntico al puerto HTTP');
			return true;
		};

		// 5. Nivel de Logs
		o = s.option(form.ListValue, 'log_level', _('Nivel de Registro (Log Level)'),
			_('Nivel de detalle de los mensajes que se envían a logd / logread.'));
		o.value('DEBUG', 'DEBUG');
		o.value('INFO', 'INFO (Predeterminado)');
		o.value('WARN', 'WARN');
		o.value('ERROR', 'ERROR');
		o.default = 'INFO';

		// 6. Ruta del Binario
		o = s.option(form.Value, 'bin_path', _('Ruta del Binario Caddy'),
			_('Ubicación del ejecutable de Caddy en el sistema.'));
		o.default = '/usr/bin/caddy';
		o.validate = function(section_id, value) {
			if (!value || !value.startsWith('/'))
				return _('La ruta del binario debe ser una ruta absoluta (ej. /usr/bin/caddy)');
			return true;
		};

		// 7. Modo personalizado del Caddyfile
		o = s.option(form.Flag, 'custom_caddyfile', _('Usar Caddyfile personalizado'),
			_('Si está activo, los cambios guardados en esta página o en Reverse Proxies NO sobrescribirán el contenido de /etc/caddy/Caddyfile. Se activa automáticamente al guardar desde la pestaña Caddyfile.'));
		o.default = '0';
		o.rmempty = false;

		return m.render();
	},

	notifyResult: function(res, fallbackMsg) {
		if (res && res.valid === false) {
			ui.addNotification(null, E('div', [
				E('p', { 'style': 'font-weight: bold; color: red;' }, _('Aviso de validación:')),
				E('pre', {}, res.output || _('Error desconocido'))
			]), 'error');
		}
		else {
			ui.addNotification(null, E('p', _('Configuración general guardada y aplicada')), 'info');
		}
	},

	handleSave: function(ev) {
		var self = this;
		return this.super('handleSave', [ev]).then(function() {
			return callSyncGeneral().then(function(res) {
				self.notifyResult(res);
			}).catch(function(err) {
				ui.addNotification(null, E('p', _('Error al sincronizar con /etc/caddy/Caddyfile: ') + (err.message || err)), 'error');
			});
		});
	}
});
