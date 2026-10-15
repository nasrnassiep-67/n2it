<?php
/**
 * N2IT branding for the Roundcube login page (matches the Webuzo logins and voip.n2it.co.za),
 * plus a Cloudflare Turnstile bot check on the login form.
 * Source: /root/webuzo-branding/roundcube-plugin - installed by /root/webuzo-branding/apply.sh
 *
 * Turnstile keys come from turnstile.inc.php (written by apply.sh from /root/n2it-turnstile.env).
 * The check only applies on the hostnames listed on the Cloudflare widget (n2it.co.za, nextel.co.za);
 * webmail opened on a customer's own domain is left as before.
 * Emergency off-switch: touch /root/webuzo-branding/turnstile-disabled and delete plugins/n2it_branding/turnstile.inc.php.
 */
class n2it_branding extends rcube_plugin
{
    public $task = 'login|logout';

    private $ts_site   = '';
    private $ts_secret = '';

    function init()
    {
        $rc = rcmail::get_instance();

        $keys = __DIR__ . '/turnstile.inc.php';
        if (is_readable($keys) && $this->turnstile_host()) {
            $cfg = include $keys;
            if (is_array($cfg)) {
                $this->ts_site   = (string) ($cfg['site'] ?? '');
                $this->ts_secret = (string) ($cfg['secret'] ?? '');
            }
        }
        $this->add_hook('authenticate', [$this, 'authenticate']);

        if ($rc->output->type != 'html') {
            return;
        }
        $rc->config->set('skin_logo', $this->urlbase . 'n2it_logo_login.png');
        $this->include_stylesheet('n2it-login.css');
        $rc->output->add_header('<link rel="icon" href="' . $this->urlbase . 'n2it_favicon.ico">');

        // N2IT services panel beside the card (login kit panel/n2it-services.*, copied in by apply.sh).
        // Appended to #layout-content with the pills; the logo and form (with Turnstile) are never moved.
        if (is_readable(__DIR__ . '/n2it-services.js')) {
            $this->include_stylesheet('n2it-services.css');
            $this->include_script('n2it-services.js');
            $rc->output->add_script(<<<'JS'
(function () {
	var c = document.getElementById('layout-content');
	if (!c || !document.getElementById('login-form') || !window.N2ITServices) return;
	var l = document.getElementById('n2it_app_links');
	if (l) c.appendChild(l);
	var p = N2ITServices.mount(c, 'append'), q = window.matchMedia('(min-width: 1100px)');
	function w() { p.classList.toggle('n2it-svc-wide', q.matches); }
	w();
	if (q.addEventListener) q.addEventListener('change', w); else q.addListener(w);
})();
JS, 'docready');
        }

        if ($this->ts_site) {
            $rc->output->add_header('<script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>');
            $this->add_hook('template_object_loginform', [$this, 'loginform']);
        }

        $rc->output->add_footer(
            '<div id="n2it_app_links"><div class="apps">'
            . '<a href="https://www.n2it.co.za/" title="N2IT Web Hosting"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.9 6h-2.9a15.7 15.7 0 0 0-1.4-3.6A8 8 0 0 1 18.9 8zM12 4c.8 1.2 1.5 2.5 1.9 4h-3.8c.4-1.5 1.1-2.8 1.9-4zM4.3 14a8.2 8.2 0 0 1 0-4h3.4a16.5 16.5 0 0 0 0 4H4.3zm.8 2h2.9c.3 1.3.8 2.5 1.4 3.6A8 8 0 0 1 5.1 16zM8 8H5.1a8 8 0 0 1 4.3-3.6C8.8 5.5 8.3 6.7 8 8zm4 12c-.8-1.2-1.5-2.5-1.9-4h3.8c-.4 1.5-1.1 2.8-1.9 4zm2.3-6H9.7a14.7 14.7 0 0 1 0-4h4.6a14.7 14.7 0 0 1 0 4zm.3 5.6c.6-1.1 1.1-2.3 1.4-3.6h2.9a8 8 0 0 1-4.3 3.6zM16.3 14a16.5 16.5 0 0 0 0-4h3.4a8.2 8.2 0 0 1 0 4h-3.4z"/></svg>Web Hosting</a>'
            . '</div></div>'
        );
    }

    /* Only on hostnames the Turnstile widget is valid for. */
    private function turnstile_host()
    {
        $host = strtolower(preg_replace('/:\d+$/', '', $_SERVER['HTTP_HOST'] ?? ''));
        foreach (['n2it.co.za', 'nextel.co.za'] as $d) {
            if ($host === $d || substr($host, -strlen('.' . $d)) === '.' . $d) {
                return true;
            }
        }
        return false;
    }

    function loginform($args)
    {
        $widget = '<div class="cf-turnstile n2it-turnstile" data-sitekey="' . htmlspecialchars($this->ts_site, ENT_QUOTES) . '" data-theme="light" data-size="flexible"></div>';
        $args['content'] = preg_replace('#</table>#', '</table>' . $widget, $args['content'], 1);
        return $args;
    }

    function authenticate($args)
    {
        // No keys, or a hostname the widget doesn't cover (customers' own domains): unchanged.
        // (Webuzo's config.inc.php sets $_POST['_autologin'] on every login and all requests arrive from
        //  127.0.0.1 via the internal port 2002, so neither can be used to single out "trusted" logins.)
        if (!$this->ts_secret || $this->from_panel()) {
            return $args;
        }
        if (!$this->verify()) {
            $args['abort'] = true;
            $args['valid'] = false;
            $args['error'] = 'Please complete the security check and try again.';
        }
        return $args;
    }

    /*
     * One-click webmail from the Webuzo panel (mail icon / Email Accounts): the browser POSTs to
     * https://<host>:2083/sess<16 chars>/mail/ and nginx keeps that original path in REQUEST_URI
     * (the public :2096 login always arrives as /mail/... via the proxy). Only trusted if a live
     * panel session with that id exists (Webuzo touches /var/webuzo/sessions/sess_<id>... on every
     * panel request), so a made-up /sessXXXX/ path still gets the Turnstile check.
     */
    private function from_panel()
    {
        // getenv(), not $_SERVER: Webuzo's config.inc.php overwrites $_SERVER['REQUEST_URI'] with './'.
        if (!preg_match('#^/sess([0-9a-zA-Z]{16})/mail/#', (string) getenv('REQUEST_URI'), $m)) {
            return false;
        }
        foreach (glob('/var/webuzo/sessions/sess_' . $m[1] . '*') ?: [] as $f) {
            if (strlen(basename($f)) > 21 && time() - (int) @filemtime($f) < 3600) {
                return true;
            }
        }
        return false;
    }

    private function verify()
    {
        $token = isset($_POST['cf-turnstile-response']) ? trim((string) $_POST['cf-turnstile-response']) : '';
        if ($token === '') {
            return false;
        }
        $ip = $_SERVER['HTTP_CF_CONNECTING_IP'] ?? ($_SERVER['REMOTE_ADDR'] ?? '');
        $ch = curl_init('https://challenges.cloudflare.com/turnstile/v0/siteverify');
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => http_build_query(['secret' => $this->ts_secret, 'response' => $token, 'remoteip' => $ip]),
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 8,
        ]);
        $body = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($body === false || $code != 200) {
            // Cloudflare unreachable: don't lock everyone out of webmail.
            rcube::write_log('errors', 'n2it_branding: Turnstile verify unreachable, check skipped');
            return true;
        }
        $res = json_decode($body, true);
        return !empty($res['success']);
    }
}
