#!/bin/bash
# N2IT branding for the Webuzo login pages (enduser :2083 and admin :2087).
# Safe to re-run: files that already carry the N2IT-BRANDING marker are left alone,
# so a daily cron puts the branding back after a Webuzo update overwrites the templates.
#   apply.sh           apply (or re-apply) the branding
#   apply.sh --revert  restore the stock templates from the newest backup
set -euo pipefail

BASE=/root/webuzo-branding
WEB=${WEB:-/usr/local/webuzo/web}
LOG=${LOG:-/var/log/webuzo-n2it-branding.log}

if [ "${1:-}" = "--revert" ]; then
    for t in enduser admin; do
        bak=$(ls -1t "$BASE"/stock-backup/$t-login_theme.php.2* 2>/dev/null | head -1)
        [ -n "$bak" ] || { echo "no backup for $t"; continue; }
        cp -p "$bak" "$WEB/$t/themes/default/login_theme.php"
        echo "$t: restored $bak"
    done
    sed -i '/N2IT-BRANDING/d' /var/webuzo-data/roundcube/config/config.inc.php && echo "roundcube: plugin disabled"
    exit 0
fi

for t in enduser admin; do
    dir="$WEB/$t/themes/default"
    php="$dir/login_theme.php"

    # Assets (always refreshed, so edits in $BASE/assets take effect on re-run)
    install -m 644 "$BASE/assets/n2it_logo_login.png" "$dir/images/n2it_logo_login.png"
    install -m 644 "$BASE/assets/n2it_favicon.ico"    "$dir/images/n2it_favicon.ico"
    install -m 644 "$BASE/assets/n2it-login.css"      "$dir/css/n2it-login.css"
    install -m 644 "$BASE/assets/n2it-login-art.svg" "$BASE/assets/n2it-login-pattern.svg" "$dir/images/"

    grep -q "N2IT-BRANDING" "$php" && continue

    cp -p "$php" "$BASE/stock-backup/$t-login_theme.php.$(date +%Y%m%d-%H%M%S)"
    tmp=$(mktemp)
    python3 - "$php" "$tmp" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, newline='').read()
n = 0

# 1. Logo: use the N2IT login logo (after Webuzo's own logo_url override)
s, c = re.subn(r"(\$logo_src = \$globals\['logo_url'\];\s*\}\s*\n)",
               r"\1$logo_src = $theme['images'].'n2it_logo_login.png'; // N2IT-BRANDING\n", s, count=1)
n += c

# 2. Favicon
s, c = re.subn(r"(<link rel=\"shortcut icon\" href=\"'\.\$theme\['images'\]\.')favicon\.ico", r"\1n2it_favicon.ico", s, count=1)
n += c

# 3. Extra stylesheet after login.css
s, c = re.subn(r"(<link rel=\"stylesheet\" type=\"text/css\" href=\"'\.\$theme\['url'\]\.'/css/login\.css\?'\.\$globals\['version'\]\.'\" />)",
               r"""\1
	<link rel="stylesheet" type="text/css" href="'.$theme['url'].'/css/n2it-login.css?'.@filemtime(dirname(__FILE__).'/css/n2it-login.css').'" /><!-- N2IT-BRANDING -->""", s, count=1)
n += c

# 4. Email / Web Hosting pills, just before trail.js in login_footer()
pills = '''<!-- N2IT-BRANDING: app links -->
		<div id="n2it_app_links"><div class="apps">
			<a id="n2it_webmail" href="https://cpl-jhb.nextel.co.za:2096/" title="N2IT Webmail"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 4.2-8 5-8-5V6l8 5 8-5v2.2z"/></svg>Email</a>
			<a href="https://www.n2it.co.za/" title="N2IT Web Hosting"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.9 6h-2.9a15.7 15.7 0 0 0-1.4-3.6A8 8 0 0 1 18.9 8zM12 4c.8 1.2 1.5 2.5 1.9 4h-3.8c.4-1.5 1.1-2.8 1.9-4zM4.3 14a8.2 8.2 0 0 1 0-4h3.4a16.5 16.5 0 0 0 0 4H4.3zm.8 2h2.9c.3 1.3.8 2.5 1.4 3.6A8 8 0 0 1 5.1 16zM8 8H5.1a8 8 0 0 1 4.3-3.6C8.8 5.5 8.3 6.7 8 8zm4 12c-.8-1.2-1.5-2.5-1.9-4h3.8c-.4 1.5-1.1 2.8-1.9 4zm2.3-6H9.7a14.7 14.7 0 0 1 0-4h4.6a14.7 14.7 0 0 1 0 4zm.3 5.6c.6-1.1 1.1-2.3 1.4-3.6h2.9a8 8 0 0 1-4.3 3.6zM16.3 14a16.5 16.5 0 0 0 0-4h3.4a8.2 8.2 0 0 1 0 4h-3.4z"/></svg>Web Hosting</a>
		</div></div>
		<script>(function(){var a=document.getElementById("n2it_webmail");if(a&&location.hostname)a.href="https://"+location.hostname+":2096/";})();</script>
		'''
s, c = re.subn(r"(\n([ \t]*)<script src=\"'\.\$theme\['url'\]\.'/js/trail\.js)", "\n\t\t" + pills.replace('\\', '\\\\') + r"\1", s, count=1)
n += c

if n != 4:
    sys.exit("only %d of 4 patch points matched in %s - Webuzo template changed, not patching" % (n, src))
open(dst, 'w', newline='').write(s)
PY
    if /usr/local/emps/bin/php -l "$tmp" >/dev/null; then
        cat "$tmp" > "$php"
        echo "$(date '+%F %T') $t: branding applied" | tee -a "$LOG"
    else
        echo "$(date '+%F %T') $t: PHP syntax check failed, stock template kept" | tee -a "$LOG"
        rm -f "$tmp"; exit 1
    fi
    rm -f "$tmp"
done

# ---- N2IT services panel beside the main login card (from the login kit) ----
# Source of truth: /root/n2it-login-kit (git, branch login-kit). To change the services: git pull there, re-run this.
KIT=${KIT:-/root/n2it-login-kit/login-kit/panel}
for t in enduser admin; do
    dir="$WEB/$t/themes/default"
    php="$dir/login_theme.php"
    for f in n2it-services.js n2it-services.css; do
        src="$KIT/$f"; [ -f "$src" ] || src="$BASE/assets/$f"
        [ -f "$src" ] || continue 2
        case $f in *.js) dst="$dir/js/$f" ;; *) dst="$dir/css/$f" ;; esac
        install -m 644 "$src" "$dst"
    done
    grep -q "N2IT-SERVICES" "$php" && continue
    grep -q "N2IT-BRANDING" "$php" || continue
    tmp=$(mktemp)
    python3 - "$php" "$tmp" <<'PY3' || : > "$tmp"
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, newline='').read()
n = 0
# stylesheet after our n2it-login.css link (cache-busted by file mtime)
s, c = re.subn(r"""(/css/n2it-login\.css'\)\.'" /><!-- N2IT-BRANDING -->)""",
               lambda m: m.group(1) + """\n\t<link rel="stylesheet" type="text/css" href="'.$theme['url'].'/css/n2it-services.css?'.@filemtime(dirname(__FILE__).'/css/n2it-services.css').'" /><!-- N2IT-SERVICES -->""", s, count=1)
n += c
# panel script + mount, just before trail.js in login_footer(); only on the main login form (button name=login)
mount = ('<script src="\'.$theme[\'url\'].\'/js/n2it-services.js?\'.@filemtime(dirname(__FILE__).\'/js/n2it-services.js\').\'"></script><!-- N2IT-SERVICES -->\n'
         '\t\t<script>(function(){var b=document.querySelector("form[name=loginform] button[name=login]");'
         'if(!b||!window.N2ITServices)return;var c=b.closest(".container");if(!c)return;'
         'var l=document.getElementById("n2it_app_links");if(l)c.appendChild(l);'
         'var p=N2ITServices.mount(c,"append");var q=window.matchMedia("(min-width: 1100px)");'
         'function w(){p.classList.toggle("n2it-svc-wide",q.matches);}w();'
         'if(q.addEventListener)q.addEventListener("change",w);else q.addListener(w);})();</script>\n')
s, c = re.subn(r"(\n([ \t]*)<script src=\"'\.\$theme\['url'\]\.'/js/trail\.js)", lambda m: "\n\t\t" + mount + m.group(1), s, count=1)
n += c
if n != 2:
    sys.exit("services: only %d of 2 patch points matched in %s" % (n, src))
open(dst, 'w', newline='').write(s)
PY3
    if [ -s "$tmp" ] && /usr/local/emps/bin/php -l "$tmp" >/dev/null; then
        cp -p "$php" "$BASE/stock-backup/$t-login_theme.php.pre-services.$(date +%Y%m%d-%H%M%S)"
        cat "$tmp" > "$php"
        echo "$(date '+%F %T') $t: services panel added" | tee -a "$LOG"
    else
        echo "$(date '+%F %T') $t: services panel patch failed, template unchanged" | tee -a "$LOG"
    fi
    rm -f "$tmp"
done

# Roundcube webmail login (:2096): n2it_branding plugin, enabled by one line after the plugins array
RC=${RC:-/var/webuzo-data/roundcube}
RCCONF="$RC/config/config.inc.php"
if [ -f "$RCCONF" ]; then
    mkdir -p "$RC/plugins/n2it_branding"
    install -m 644 "$BASE"/roundcube-plugin/n2it_branding/* "$RC/plugins/n2it_branding/"
    # Static files are served from public_html/plugins (a copy without the PHP)
    mkdir -p "$RC/public_html/plugins/n2it_branding"
    install -m 644 "$BASE"/roundcube-plugin/n2it_branding/*.{css,png,ico,svg} "$RC/public_html/plugins/n2it_branding/"
    # Services panel from the login kit (the plugin only shows it when n2it-services.js is present)
    for f in n2it-services.js n2it-services.css; do
        src="$KIT/$f"; [ -f "$src" ] || src="$BASE/assets/$f"
        [ -f "$src" ] || continue
        install -m 644 "$src" "$RC/plugins/n2it_branding/$f"
        install -m 644 "$src" "$RC/public_html/plugins/n2it_branding/$f"
    done
    # Turnstile keys for the webmail login (from /root/n2it-turnstile.env); delete this file to switch the check off
    if [ -r /root/n2it-turnstile.env ] && [ ! -e "$BASE/turnstile-disabled" ]; then
        ( . /root/n2it-turnstile.env
          printf "<?php\nreturn ['site' => '%s', 'secret' => '%s'];\n" "$TURNSTILE_SITE" "$TURNSTILE_SECRET" ) > "$RC/plugins/n2it_branding/turnstile.inc.php"
        chmod 640 "$RC/plugins/n2it_branding/turnstile.inc.php"
    else
        rm -f "$RC/plugins/n2it_branding/turnstile.inc.php"
    fi
    chown -R --reference="$RC/plugins/webuzo" "$RC/plugins/n2it_branding" "$RC/public_html/plugins/n2it_branding"
    if ! grep -q "N2IT-BRANDING" "$RCCONF"; then
        cp -p "$RCCONF" "$BASE/stock-backup/roundcube-config.inc.php.$(date +%Y%m%d-%H%M%S)"
        tmp=$(mktemp)
        awk '{print} /^\$config\[.plugins.\] = array\(/ && !done {print "$config['"'"'plugins'"'"'][] = '"'"'n2it_branding'"'"'; // N2IT-BRANDING"; done=1}' "$RCCONF" > "$tmp"
        if grep -q "N2IT-BRANDING" "$tmp" && /usr/local/emps/bin/php -l "$tmp" >/dev/null; then
            cat "$tmp" > "$RCCONF"
            echo "$(date '+%F %T') roundcube: branding plugin enabled" | tee -a "$LOG"
        else
            echo "$(date '+%F %T') roundcube: plugins line not found or syntax check failed, config not changed" | tee -a "$LOG"
        fi
        rm -f "$tmp"
    fi
fi

# ---- Turnstile bot check on the panel logins (:2083 / :2087) ----
# Keys file read by /usr/local/webuzo-n2it/turnstile-prepend.php; delete it (or touch $BASE/turnstile-disabled) to switch off.
TSKEYS=/usr/local/webuzo-n2it/turnstile-keys.php
if [ -r /root/n2it-turnstile.env ] && [ ! -e "$BASE/turnstile-disabled" ] && [ -d /usr/local/webuzo-n2it ]; then
    ( . /root/n2it-turnstile.env
      printf "<?php\nreturn ['site' => '%s', 'secret' => '%s'];\n" "$TURNSTILE_SITE" "$TURNSTILE_SECRET" ) > "$TSKEYS"
    chmod 600 "$TSKEYS"
    TS_SITE=$(. /root/n2it-turnstile.env; echo "$TURNSTILE_SITE")
    for t in enduser admin; do
        php="$WEB/$t/themes/default/login_theme.php"
        grep -q "N2IT-TURNSTILE" "$php" && continue
        grep -q "N2IT-BRANDING" "$php" || continue
        tmp=$(mktemp)
        python3 - "$php" "$tmp" "$TS_SITE" <<'PY2'
import re, sys
src, dst, site = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src, newline='').read()
n = 0
# script tag right after our stylesheet line in login_header()
s, c = re.subn(r'(<!-- N2IT-BRANDING -->)', r'\1\n\t<script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script><!-- N2IT-TURNSTILE -->', s, count=1)
n += c
# widget (+ message after a refused attempt) just above the Login button in login_theme()
widget = ('<div class="n2it-turnstile" style="margin:4px 0 16px">\'.(!empty($_GET[\'n2it_ts\']) ? \'<p style="color:#c0392b;font-size:13px;margin:0 0 8px">Please complete the security check and try again.</p>\' : \'\').\''
          '<div class="cf-turnstile" data-sitekey="' + site + '" data-theme="light" data-size="flexible"></div></div><!-- N2IT-TURNSTILE -->\n\t\t\t\t\t\t')
s, c = re.subn(r'(<div class="form-group d-grid gap-2 mx-auto">\s*<button type="submit" name="login")', lambda m: widget + m.group(1), s, count=1)
n += c
if n != 2:
    sys.exit("turnstile: only %d of 2 patch points matched in %s" % (n, src))
open(dst, 'w', newline='').write(s)
PY2
        if [ -s "$tmp" ] && /usr/local/emps/bin/php -l "$tmp" >/dev/null; then
            cp -p "$php" "$BASE/stock-backup/$t-login_theme.php.pre-turnstile.$(date +%Y%m%d-%H%M%S)"
            cat "$tmp" > "$php"
            echo "$(date '+%F %T') $t: turnstile widget added" | tee -a "$LOG"
        else
            echo "$(date '+%F %T') $t: turnstile patch failed, template unchanged" | tee -a "$LOG"
        fi
        rm -f "$tmp"
    done
    # Make sure the pre-login check is still hooked in (a Webuzo/EMPS update could remove php.d files)
    INI=/usr/local/emps/etc/php.d/zz-n2it-turnstile.ini
    if [ ! -f "$INI" ]; then
        printf '; N2IT: Turnstile check before Webuzo panel logins - see /usr/local/webuzo-n2it/turnstile-prepend.php\nauto_prepend_file = /usr/local/webuzo-n2it/turnstile-prepend.php\n' > "$INI"
        echo "$(date '+%F %T') panel turnstile ini restored - EMPS php-fpm needs a reload (kill -USR2 of its master)" | tee -a "$LOG"
    fi
else
    rm -f "$TSKEYS"
fi
