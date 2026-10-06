#!/bin/bash
# Turn the iPhone push wake-up on (or off) for one n2it extension, by giving it a dial string that runs
# n2it_push_wake.lua before FreeSWITCH looks up where to ring it.
#   enable-push.sh 1002          turn on
#   enable-push.sh 1002 off      back to the domain's normal dial string (empty per-extension value)
# Run as root on the voip server. Backs up the old value to /root/voip/backup/.
set -euo pipefail
EXT=${1:?usage: enable-push.sh <extension> [off]}
DOMAIN=${DOMAIN:-n2it.voip.n2it.co.za}
[[ $EXT =~ ^[0-9]{2,10}$ ]] || { echo "bad extension"; exit 1; }
[[ $DOMAIN =~ ^[a-z0-9-]+\.voip\.n2it\.co\.za$ ]] || { echo "bad domain"; exit 1; }
DS='{sip_invite_domain=${domain_name},leg_timeout=${call_timeout},presence_id=${dialed_user}@${dialed_domain}}${lua(n2it_push_wake.lua user=${dialed_user} domain=${dialed_domain} number=${caller_id_number} name=${url_encode(${caller_id_name})})}${sofia_contact(*/${dialed_user}@${dialed_domain})}'
[ "${2:-}" = off ] && DS=''
sql() { cd /tmp && sudo -u postgres psql -d fusionpbx -v ON_ERROR_STOP=1 -At "$@"; }

OLD=$(sql -c "select coalesce(e.dial_string,'') from v_extensions e join v_domains d using(domain_uuid) where d.domain_name='$DOMAIN' and e.extension='$EXT'")
mkdir -p /root/voip/backup
printf '%s\n' "$OLD" > "/root/voip/backup/dial_string.$EXT@$DOMAIN.$(date +%Y%m%d-%H%M%S)"
sql -c "update v_extensions e set dial_string=nullif(\$q\$$DS\$q\$,''), update_date=now() from v_domains d
        where d.domain_uuid=e.domain_uuid and d.domain_name='$DOMAIN' and e.extension='$EXT' returning e.extension" \
  | grep -qx "$EXT" || { echo "extension $EXT@$DOMAIN not found"; exit 1; }
rm -f /var/cache/fusionpbx/directory."$EXT@$DOMAIN"*
echo "dial string for $EXT@$DOMAIN now:"
fs_cli -x "user_data $EXT@$DOMAIN param dial-string"
