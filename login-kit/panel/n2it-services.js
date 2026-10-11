/* N2IT services panel - standalone version for any login page (voip, unifi, Webuzo, ...).
   Same content and look as the panel on cloud.nextel.co.za. Needs n2it-services.css.

   Usage:   N2ITServices.mount(referenceElement, 'after')   // or 'before', 'append', 'prepend'
   It returns the <aside id="n2it_services"> element; laying it out next to the site's login card is
   site-specific CSS (see README.md). Calling mount() again does nothing if the panel already exists.
   To change the services, edit SERVICES_HEAD / SERVICES below - keep every copy of this file in sync. */
(function () {
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
		{ title: 'Hosted Exchange', text: 'Microsoft Exchange mailboxes, calendars and shared contacts, hosted for you',
		  icon: 'M4 5h16v15H4zM4 9h16M8 3v4M16 3v4M8 13h3M8 16h6' },
		{ title: 'Email Hosting', text: 'Business email on your own domain, with webmail and mobile sync',
		  icon: 'M3 6h18v12H3zM3 7l9 6 9-6' },
		{ title: 'Web Hosting', text: 'Website hosting for your domain, with SSL and a control panel',
		  icon: 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18zM3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18' },
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

	function mount(ref, where) {
		var existing = document.getElementById('n2it_services');
		if (existing || !ref) return existing;
		var aside = buildServices();
		if (where === 'before') ref.parentNode.insertBefore(aside, ref);
		else if (where === 'append') ref.appendChild(aside);
		else if (where === 'prepend') ref.insertBefore(aside, ref.firstChild);
		else ref.parentNode.insertBefore(aside, ref.nextSibling);
		document.documentElement.classList.add('n2it-ads');
		return aside;
	}

	window.N2ITServices = { mount: mount, build: buildServices, services: SERVICES, head: SERVICES_HEAD };
})();
