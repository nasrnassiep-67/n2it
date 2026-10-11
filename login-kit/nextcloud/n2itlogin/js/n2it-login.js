/* N2IT login card for Nextcloud (matches voip.n2it.co.za, unifi.n2it.co.za and the Webuzo panel).
   Source: /root/nextcloud-branding/n2itlogin - edit there, then re-run /root/nextcloud-branding/install-app.sh

   Nextcloud renders the login form with Vue, so this waits for .login-box and then adds the colour logo,
   the Cloudflare Turnstile widget and the app-link pills. n2it-login.css does the styling. */
(function () {
	var LINKS = [
		{ id: 'n2it_voip', href: 'https://voip.n2it.co.za/', title: 'N2IT VoIP', label: 'VoIP',
		  path: 'M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2a1 1 0 0 1 1-.25c1.1.37 2.3.57 3.6.57a1 1 0 0 1 1 1V20a1 1 0 0 1-1 1A17 17 0 0 1 3 4a1 1 0 0 1 1-1h3.5a1 1 0 0 1 1 1c0 1.3.2 2.5.57 3.6a1 1 0 0 1-.25 1l-2.2 2.2z' },
		{ id: 'n2it_webmail', href: 'https://cpl-jhb.nextel.co.za:2096/', title: 'N2IT Webmail', label: 'Email',
		  path: 'M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 4.2-8 5-8-5V6l8 5 8-5v2.2z' },
		{ id: 'n2it_hosting', href: 'https://www.n2it.co.za/', title: 'N2IT Web Hosting', label: 'Web Hosting',
		  path: 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.9 6h-2.9a15.7 15.7 0 0 0-1.4-3.6A8 8 0 0 1 18.9 8zM12 4c.8 1.2 1.5 2.5 1.9 4h-3.8c.4-1.5 1.1-2.8 1.9-4zM4.3 14a8.2 8.2 0 0 1 0-4h3.4a16.5 16.5 0 0 0 0 4H4.3zm.8 2h2.9c.3 1.3.8 2.5 1.4 3.6A8 8 0 0 1 5.1 16zM8 8H5.1a8 8 0 0 1 4.3-3.6C8.8 5.5 8.3 6.7 8 8zm4 12c-.8-1.2-1.5-2.5-1.9-4h3.8c-.4 1.5-1.1 2.8-1.9 4zm2.3-6H9.7a14.7 14.7 0 0 1 0-4h4.6a14.7 14.7 0 0 1 0 4zm.3 5.6c.6-1.1 1.1-2.3 1.4-3.6h2.9a8 8 0 0 1-4.3 3.6zM16.3 14a16.5 16.5 0 0 0 0-4h3.4a8.2 8.2 0 0 1 0 4h-3.4z' }
	];

	/* Cloudflare Turnstile (pre-clearance mode, same widget as unifi.n2it.co.za). Solving it sets Cloudflare's
	   cf_clearance cookie. Only on the public names: LAN logins by IP don't pass Cloudflare. Empty = no widget. */
	var TURNSTILE_SITEKEY = '0x4AAAAAAFSLraJVe15YiVwR';
	var TURNSTILE_HOSTS = ['cloud.nextel.co.za', 'cloud.n2it.co.za'];
	var tsOn = !!TURNSTILE_SITEKEY && TURNSTILE_HOSTS.indexOf(location.hostname) !== -1;
	var tsPassed = false;
	var tsBroken = false;   // widget failed to load (e.g. hostname not on the widget) - don't lock people out

	/* Services panel: beside the card on wide screens, a compact grid under it on phones.
	   SERVICES_LIVE = false shows it only with ?n2it_preview=1 on the login URL. */
	var SERVICES_LIVE = true;
	var SERVICES_ON = SERVICES_LIVE || /[?&]n2it_preview=1(&|$)/.test(location.search);
	var SERVICES_HEAD = {
		kicker: 'N2IT Services',
		title: 'Your complete IT & communications partner',
		text: 'Design, installation and support – from the cable in the wall to the cloud.',
		badges: ['Resellers welcome', 'End-user support'],
		cta: 'Talk to N2IT', ctaHref: 'https://www.n2it.co.za/'
	};
	var SERVICES = [
		{ title: 'VoIP & Hosted PBX', text: 'Multi-tenant cloud PBX on desk phones, desktop PCs and mobile phones',
		  icon: 'M5 4h3l2 5-2.5 1.5a11 11 0 0 0 6 6L15 14l5 2v3a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z' },
		{ title: 'Fibre & Wireless Broadband', text: 'Fibre to the business (FTTB) and to the home (FTTH), plus wireless broadband',
		  icon: 'M3 11l9-7 9 7M5 9.5V20h14V9.5M9.5 20v-5h5v5' },
		{ title: 'LTE Data', text: 'LTE data connectivity \u2013 primary, failover or on the move',
		  icon: 'M5 20v-3M10 20v-7M15 20V9M20 20V5' },
		{ title: 'Fibre Splicing & Backbones', text: 'Fibre backbone networks designed, spliced and maintained',
		  icon: 'M2 12h6M2 7c3.5 0 4 5 6 5M2 17c3.5 0 4-5 6-5M8 12h3M11 10h4v4h-4zM15 12h7' },
		{ title: 'Point-to-Point Wireless', text: 'High-speed wireless links between buildings and sites',
		  icon: 'M5 21V10M3 10h4M19 21V10M17 10h4M7.5 6.5c3-2.5 6-2.5 9 0M9.5 9.5c1.5-1.2 3.5-1.2 5 0' },
		{ title: 'Wi-Fi Installations', text: 'Home and business Wi-Fi, planned and installed for full coverage',
		  icon: 'M2 8.5a15 15 0 0 1 20 0M5 12a10.5 10.5 0 0 1 14 0M8.5 15.5a5.5 5.5 0 0 1 7 0M12 19h.01' },
		{ title: 'Cat6 & Cat7 Cabling', text: 'Structured LAN cabling for offices, sites and campuses',
		  icon: 'M6 3h12v11H6zM9 14v3h6v-3M12 17v4M9 6v3M11 6v3M13 6v3M15 6v3' },
		{ title: 'Professional CCTV', text: 'Dahua, Hikvision and HiLook surveillance systems',
		  icon: 'M2 9l14-4 2 6-14 4zM16 9l4-1v4l-4 1M7 13.5l1 3.5M4 17h6' },
		{ title: 'Server Installation & Support', text: 'Linux, macOS and Windows Server, installed and supported',
		  icon: 'M4 4h16v6H4zM4 14h16v6H4zM8 7h.01M8 17h.01M12 7h4M12 17h4' },
		{ title: 'Hosted Cloud Servers', text: 'From your own hardware to our cloud – fully VPN’d and secure',
		  icon: 'M7 18h10a4 4 0 0 0 .5-8A6 6 0 0 0 6 9a4.5 4.5 0 0 0 1 9zM10 13.5h4v3h-4zM11 13.5v-1a1 1 0 0 1 2 0v1' },
		{ title: 'Sophos XGS Firewalls', text: 'Installed and managed by Sophos specialists since the Astaro UTM 9 days',
		  icon: 'M3 5h18v14H3zM3 9.7h18M3 14.3h18M9 5v4.7M15 5v4.7M6 9.7v4.6M12 9.7v4.6M18 9.7v4.6M9 14.3V19M15 14.3V19' },
		{ title: 'Kaspersky Anti-Virus', text: 'Endpoint protection for desktops and servers',
		  icon: 'M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6zM8.5 12l2.5 2.5 4.5-5' }
	];

	function svgIcon(d) {
		return '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="' + d + '"/></svg>';
	}

	function buildServices() {
		var aside = document.createElement('aside');
		aside.id = 'n2it_services';
		aside.setAttribute('aria-label', SERVICES_HEAD.kicker);
		var html = '<div class="n2it-svc-kicker"></div><h2 class="n2it-svc-title"></h2><p class="n2it-svc-text"></p><ul class="n2it-svc-badges"></ul><ul class="n2it-svc-grid">';
		SERVICES.forEach(function () { html += '<li><span class="n2it-svc-icon"></span><span class="n2it-svc-body"><strong></strong><span></span></span></li>'; });
		html += '</ul><a class="n2it-svc-cta" target="_blank" rel="noopener"></a>';
		aside.innerHTML = html;
		aside.querySelector('.n2it-svc-kicker').textContent = SERVICES_HEAD.kicker;
		aside.querySelector('.n2it-svc-title').textContent = SERVICES_HEAD.title;
		aside.querySelector('.n2it-svc-text').textContent = SERVICES_HEAD.text;
		var badges = aside.querySelector('.n2it-svc-badges');
		SERVICES_HEAD.badges.forEach(function (b) {
			var li = document.createElement('li');
			li.innerHTML = svgIcon('M5 12.5l4.5 4.5L19 7.5');
			li.appendChild(document.createTextNode(b));
			badges.appendChild(li);
		});
		var cta = aside.querySelector('.n2it-svc-cta');
		cta.textContent = SERVICES_HEAD.cta + ' →';
		cta.href = SERVICES_HEAD.ctaHref;
		Array.prototype.forEach.call(aside.querySelectorAll('.n2it-svc-grid li'), function (li, i) {
			li.querySelector('.n2it-svc-icon').innerHTML = svgIcon(SERVICES[i].icon);
			li.querySelector('strong').textContent = SERVICES[i].title;
			li.querySelector('.n2it-svc-body > span').textContent = SERVICES[i].text;
		});
		return aside;
	}

	function services() {
		if (!SERVICES_ON || document.getElementById('n2it_services')) return;
		/* Placed next to .wrapper as a child of <body>, outside Nextcloud's own login containers */
		var wrapper = document.querySelector('body > .wrapper');
		if (!wrapper) return;
		document.body.classList.add('n2it-ads');
		wrapper.parentNode.insertBefore(buildServices(), wrapper.nextSibling);
	}

	var LOGO = (window.OC && OC.filePath ? OC.filePath('n2itlogin', 'img', 'n2it-logo.png') : '/apps/n2itlogin/img/n2it-logo.png');

	function buildLinks() {
		var wrap = document.createElement('div');
		wrap.id = 'n2it_app_links';
		var apps = document.createElement('div');
		apps.className = 'apps';
		LINKS.forEach(function (l) {
			var a = document.createElement('a');
			a.id = l.id; a.href = l.href; a.title = l.title; a.target = '_blank'; a.rel = 'noopener';
			a.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="' + l.path + '"/></svg>';
			a.appendChild(document.createTextNode(l.label));
			apps.appendChild(a);
		});
		wrap.appendChild(apps);
		return wrap;
	}

	/* Turnstile goes just above the Log in button; the script is loaded once and the widget rendered explicitly */
	function turnstile(form) {
		if (!tsOn || form.querySelector('.n2it-turnstile')) return;
		var button = form.querySelector('button[type="submit"]');
		if (!button) return;
		var anchor = button;
		while (anchor.parentElement && anchor.parentElement !== form && anchor.parentElement.tagName !== 'FIELDSET') anchor = anchor.parentElement;
		var box = document.createElement('div');
		box.className = 'n2it-turnstile';
		box.innerHTML = '<div class="n2it-ts-widget"></div><div class="n2it-ts-hint" hidden>Please complete the security check first.</div>';
		anchor.parentElement.insertBefore(box, anchor);
		tsPassed = false;

		function render() {
			window.turnstile.render(box.querySelector('.n2it-ts-widget'), {
				sitekey: TURNSTILE_SITEKEY,
				theme: 'light',
				size: 'flexible',
				callback: function () { tsPassed = true; box.querySelector('.n2it-ts-hint').hidden = true; },
				'expired-callback': function () { tsPassed = false; },
				'error-callback': function () { tsBroken = true; }
			});
		}
		if (window.turnstile) return render();
		window.n2itTurnstileReady = render;
		if (!document.getElementById('n2it-ts-api')) {
			var s = document.createElement('script');
			s.id = 'n2it-ts-api';
			s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=n2itTurnstileReady';
			s.async = true;
			s.onerror = function () { tsBroken = true; };
			document.head.appendChild(s);
		}
	}

	/* Hold the login until the check has passed (capture phase, so it runs before Vue's own submit handler) */
	document.addEventListener('submit', function (e) {
		if (!tsOn || tsPassed || tsBroken || !e.target.classList || !e.target.classList.contains('login-form')) return;
		e.preventDefault();
		e.stopImmediatePropagation();
		var hint = e.target.querySelector('.n2it-ts-hint');
		if (hint) hint.hidden = false;
	}, true);

	function apply() {
		var card = document.querySelector('.guest-box.login-box');
		if (!card) return;
		services();

		if (!card.querySelector('.n2it-logo')) {
			var logo = document.createElement('div');
			logo.className = 'n2it-logo';
			logo.innerHTML = '<img alt="N2IT">';
			logo.firstChild.src = LOGO;
			card.insertBefore(logo, card.firstChild);
		}

		var form = card.querySelector('form.login-form');
		if (form) turnstile(form);

		var links = document.getElementById('n2it_app_links') || buildLinks();
		if (links.parentElement !== card || card.lastElementChild !== links) card.appendChild(links);
	}

	var queued = false;
	function schedule() {
		if (queued) return;
		queued = true;
		requestAnimationFrame(function () { queued = false; apply(); });
	}

	function start() {
		apply();
		new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true });
	}

	if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();
