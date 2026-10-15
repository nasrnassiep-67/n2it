# N2IT branding

## webuzo/
Branded logins for Webuzo panels (2083 user, 2087 admin) and Roundcube webmail (2096), with Cloudflare Turnstile.

- Install on a server: copy this folder to `/root/webuzo-branding/` and run `./apply.sh` as root (`./apply.sh --revert` restores stock files, which it saves on first run in `stock-backup/` - that folder is server-specific and not kept in git).
- Turnstile keys are read from `/root/n2it-turnstile.env` (`TURNSTILE_SITE=...`, `TURNSTILE_SECRET=...`, mode 600) - never commit them.
- Webuzo updates can overwrite the files; on cpl-jhb a daily cron re-runs `apply.sh`.

## website-theme/n2it/
WordPress block child theme of Twenty Twenty-Five used on www.n2it.co.za (2026-10 redesign: Stitch layout, hairline grids, animated isometric scenes in `assets/img/scenes/`).

- Install: copy `n2it/` to `wp-content/themes/` (Twenty Twenty-Five must be installed) and activate.
- Forms (`[n2it_form type="contact|ticket"]`) and Turnstile need the constants `N2IT_TURNSTILE_SITE` / `N2IT_TURNSTILE_SECRET` in `wp-config.php`; without them Turnstile is off.
- Page content (homepage etc.) lives in the WordPress database, not in this theme.
