'use strict';
'require view';
'require form';
'require rpc';
'require ui';
'require uci';

var callGenerateCaddyfile = rpc.declare({
	object: 'luci.caddy',
	method: 'generate_caddyfile',
	expect: {}
});

return view.extend({
	load: function() {
		return uci.load('caddy');
	},

	render: function() {
		var m, s, o;

		m = new form.Map('caddy', _('Caddy - Reverse Proxies'),
			_('Configura y administra tus proxies inversos hacia servicios internos (NAS, Home Assistant, Proxmox, AdGuard, etc.). Al guardar y aplicar, los cambios se reflejan inmediatamente en <code>/etc/caddy/Caddyfile</code>, se valida la sintaxis y se recarga Caddy.'));

		s = m.section(form.GridSection, 'proxy', _('Reglas de Reverse Proxy'));
		s.addremove = true;
		s.anonymous = true;
		s.sortable = true;

		// 1. Activo
		o = s.option(form.Flag, 'enabled', _('Activo'));
		o.default = '1';
		o.editable = true;
		o.width = '60px';

		// 2. Nombre / Etiqueta
		o = s.option(form.Value, 'name', _('Etiqueta / Nombre'));
		o.placeholder = 'ej. Home Assistant';
		o.width = '180px';

		// 3. Dominio
		o = s.option(form.Value, 'domain', _('Dominio / Subdominio'));
		o.placeholder = 'app.tudominio.com';
		o.rmempty = false;
		o.width = '180px';
		o.validate = function(section_id, value) {
			if (!value || value.trim() === '')
				return _('El dominio es obligatorio');
			if (/^https?:\/\//i.test(value))
				return _('Introduce únicamente el dominio/subdominio sin protocolo (ej. app.tudominio.com)');
			if (/[/\s]/.test(value))
				return _('El dominio no debe contener rutas (/) ni espacios');
			return true;
		};

		// 4. Upstream
		o = s.option(form.Value, 'upstream', _('Destino Upstream (IP:Puerto)'));
		o.placeholder = '192.168.1.100:8123';
		o.rmempty = false;
		o.width = '180px';
		o.validate = function(section_id, value) {
			if (!value || value.trim() === '')
				return _('El destino upstream es obligatorio');
			if (/\s/.test(value))
				return _('El upstream no debe contener espacios');
			if (/^https?:\/\//i.test(value))
				return _('No incluyas http:// ni https:// en el upstream. Usa solo host:puerto (ej. 192.168.1.100:8123)');
			return true;
		};

		// 5. Modo TLS por sitio
		o = s.option(form.ListValue, 'tls_mode', _('Modo TLS'));
		o.value('auto', _('Automático (HTTPS de Caddy)'));
		o.value('cloudflare', _('Cloudflare DNS-01 (por sitio)'));
		o.value('internal', _('Certificado interno (autofirmado)'));
		o.value('off', _('Sin TLS (sólo HTTP)'));
		o.default = 'auto';
		o.width = '180px';
		o.validate = function(section_id, value) {
			if (value === 'cloudflare') {
				var token = uci.get('caddy', 'general', 'cloudflare_token');
				if (!token)
					return _('Para el modo Cloudflare DNS-01 necesitas configurar el Token de API en Configuración General');
			}
			return true;
		};

		// 6. Opciones avanzadas en modal
		o = s.option(form.Flag, 'transparent', _('Pasar Headers de Proxy (Host, X-Real-IP)'));
		o.default = '0';
		o.modalonly = true;

		o = s.option(form.TextValue, 'custom_headers', _('Directivas Adicionales de Caddyfile'));
		o.rows = 5;
		o.placeholder = '# Directivas de Caddyfile adicionales dentro de reverse_proxy\n# header_up Host {upstream_hostport}';
		o.modalonly = true;

		return m.render();
	},

	handleSave: function(ev) {
		var customBefore = (uci.get('caddy', 'general', 'custom_caddyfile') === '1');

		return this.super('handleSave', [ev]).then(function() {
			return callGenerateCaddyfile().then(function(res) {
				if (res && res.valid) {
					var msg = '✓ ' + _('Configuración guardada y /etc/caddy/Caddyfile actualizado.');
					if (customBefore)
						msg += ' ' + _('Se desactivó el modo Caddyfile personalizado (copia en Caddyfile.custom.bak).');
					ui.addNotification(null, E('p', {}, msg), 'info');
				} else {
					ui.addNotification(null, E('div', [
						E('p', { 'style': 'font-weight: bold; color: red;' }, _('La configuración NO se ha aplicado:')),
						E('pre', {}, (res && res.output) || _('Error'))
					]), 'error');
				}
			});
		});
	}
});
