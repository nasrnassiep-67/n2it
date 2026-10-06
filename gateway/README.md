# N2IT push gateway (runs on the PBX)

Wakes the iPhone app with a VoIP push when its extension is called, so iOS can keep the app suspended.
Replaces the earlier Node prototype. PHP on the PBX's existing nginx/PHP-FPM, no extra services.

| Piece | On the PBX | What it does |
|---|---|---|
| `register/index.php` | `/var/www/fusionpbx/push/register/` = `POST https://voip.n2it.co.za/push/register` | App stores its PushKit token. JSON `{tenant,user,password,token,bundle,sandbox}`; the SIP password is checked against FusionPBX; failed attempts limited to 10/h per IP and 20/h per extension. |
| `unregister/index.php` | `POST https://voip.n2it.co.za/push/unregister` | App signs out. JSON `{token}` (tenant/user ignored). |
| `notify.php` | `POST http://127.0.0.1/push/notify.php` (localhost only) | Sends the VoIP push (APNs HTTP/2, ES256 JWT cached 40 min). Payload `{"caller","number","callee"}`. Drops tokens Apple reports dead. |
| `n2it_push_wake.lua` | `/usr/share/freeswitch/scripts/` | Runs inside the extension's dial string before `${sofia_contact()}`: asks notify.php to push, then waits up to 8 s for the extension's registration to be new or refreshed, so the woken iPhone rings. Never writes into the dial string; errors ring as normal. Works for direct calls, ring groups, queues and transfers. |
| `enable-push.sh` | `/root/voip/n2it-app/push/` | Turns the wake step on/off per extension (`enable-push.sh 1002`, `enable-push.sh 1002 off`). |
| `config.php.example` | `/etc/n2it-push/config.php` (root:www-data 640) | APNs Team ID, Key ID, path of the `.p8` key (`/etc/n2it-push/AuthKey.p8`). Nothing is pushed until filled in. |

Data: `/var/lib/n2it-push/tokens.json` (www-data only). Logs: `grep n2it-push /var/log/nginx/error.log`,
FreeSWITCH log lines `[n2it_push]`.

`/push/register` (no `.php`) reaches PHP through FusionPBX's public router (`/push/register` ->
`push/register/index.php`), so nginx needs no change. A FusionPBX router change could break that: test
`curl -X POST https://voip.n2it.co.za/push/register -d '{}'` (expect 400 JSON) after upgrades.

## App side (iOS)
- `PUSH_GATEWAY_HOST = voip.n2it.co.za/push` (the app calls `https://$(PUSH_GATEWAY_HOST)/register`).
- `sandbox` = true for Xcode/debug builds (development APNs), false for Ad Hoc (production). Matches `aps-environment`.
- On push: report to CallKit at once, then `refreshRegisters()`; the PBX waits for that REGISTER, then sends the INVITE.
