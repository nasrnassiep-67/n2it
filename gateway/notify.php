<?php
// POST /push/notify.php (127.0.0.1 only): FreeSWITCH asks us to wake an extension's iPhones before ringing it.
// Form fields: user, domain, number, name. Answers {"devices": n, "sent": m}; FreeSWITCH waits only when sent > 0.
require __DIR__ . '/common.php';

if (($_SERVER['REMOTE_ADDR'] ?? '') !== '127.0.0.1') reply(403);
if ($_SERVER['REQUEST_METHOD'] !== 'POST') reply(405);
$user = (string)($_POST['user'] ?? '');
$domain = strtolower((string)($_POST['domain'] ?? ''));
if (!valid_user($user) || !preg_match('/^[a-z0-9-]+\.' . preg_quote(BASE_DOMAIN, '/') . '$/', $domain)) reply(400);

$devices = read_tokens()["$user@$domain"] ?? [];
if (!$devices) reply(200, ['devices' => 0, 'sent' => 0]);

$c = config();
if (empty($c['team_id']) || empty($c['key_id']) || empty($c['key_file']) || !is_readable($c['key_file'])) {
	push_log("not configured: no APNs key, $user@$domain not pushed");
	reply(200, ['devices' => count($devices), 'sent' => 0, 'error' => 'APNs key not configured']);
}

$number = substr(preg_replace('/[^0-9+*#]/', '', (string)($_POST['number'] ?? '')), 0, 32);
$name = mb_substr(trim(preg_replace('/[\x00-\x1f\x7f]/', '', (string)($_POST['name'] ?? ''))), 0, 60);
$caller = ($name !== '' && $name !== $number) ? $name : ($number !== '' ? $number : 'Unknown');
$payload = json_encode(['caller' => $caller, 'number' => $number, 'callee' => $user]);

try {
	$jwt = apns_jwt($c);
} catch (Exception $e) {
	push_log('APNs key error: ' . $e->getMessage());
	reply(200, ['devices' => count($devices), 'sent' => 0, 'error' => 'APNs key unusable']);
}

// One HTTP/2 request per device, in parallel, 3 s at most.
$mh = curl_multi_init();
$handles = [];
foreach ($devices as $d) {
	$host = $d['sandbox'] ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
	$topic = ($c['bundle_id'] ?? ($d['bundle'] ?: 'za.co.n2it.softphone')) . '.voip';
	$ch = curl_init("$host/3/device/{$d['token']}");
	curl_setopt_array($ch, [
		CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_2_0,
		CURLOPT_POST => true,
		CURLOPT_POSTFIELDS => $payload,
		CURLOPT_HTTPHEADER => ["authorization: bearer $jwt", "apns-topic: $topic", 'apns-push-type: voip',
			'apns-priority: 10', 'apns-expiration: 0', 'content-type: application/json'],
		CURLOPT_RETURNTRANSFER => true,
		CURLOPT_TIMEOUT => 3,
	]);
	curl_multi_add_handle($mh, $ch);
	$handles[] = [$ch, $d];
}
do { $status = curl_multi_exec($mh, $running); if ($running) curl_multi_select($mh, 0.2); } while ($running && $status === CURLM_OK);

$sent = 0; $dead = [];
foreach ($handles as [$ch, $d]) {
	$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
	$reason = json_decode((string)curl_multi_getcontent($ch), true)['reason'] ?? curl_error($ch);
	if ($code === 200) $sent++;
	else {
		push_log("APNs $code $reason for $user@$domain " . substr($d['token'], 0, 8) . '...');
		if ($code === 410 || in_array($reason, ['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic'], true)) $dead[] = $d['token'];
	}
	curl_multi_remove_handle($mh, $ch); curl_close($ch);
}
curl_multi_close($mh);
if ($dead) {
	with_tokens(function (&$data) use ($user, $domain, $dead) {
		$k = "$user@$domain";
		$data[$k] = array_values(array_filter($data[$k] ?? [], function ($d) use ($dead) { return !in_array($d['token'], $dead, true); }));
		if (!$data[$k]) unset($data[$k]);
	});
}
push_log("notify $user@$domain caller=$number: $sent/" . count($devices) . ' sent');
reply(200, ['devices' => count($devices), 'sent' => $sent]);

// APNs provider token (ES256 JWT). Apple allows a new one at most every 20 min and accepts it for 60 min,
// so it is cached for 40 min.
function apns_jwt($c) {
	$cache = PUSH_DATA . '/jwt.json';
	$j = is_file($cache) ? json_decode(file_get_contents($cache), true) : null;
	if ($j && $j['key_id'] === $c['key_id'] && $j['at'] > time() - 2400) return $j['jwt'];
	$b64 = function ($s) { return rtrim(strtr(base64_encode($s), '+/', '-_'), '='); };
	$input = $b64(json_encode(['alg' => 'ES256', 'kid' => $c['key_id']])) . '.' . $b64(json_encode(['iss' => $c['team_id'], 'iat' => time()]));
	$key = openssl_pkey_get_private(file_get_contents($c['key_file']));
	if (!$key || !openssl_sign($input, $der, $key, OPENSSL_ALGO_SHA256)) throw new Exception('cannot sign with ' . $c['key_file']);
	$jwt = $input . '.' . $b64(der_to_raw($der));
	file_put_contents($cache, json_encode(['jwt' => $jwt, 'key_id' => $c['key_id'], 'at' => time()]), LOCK_EX);
	return $jwt;
}

// OpenSSL gives an ASN.1 DER ECDSA signature; JWT wants r||s, 32 bytes each.
function der_to_raw($der) {
	$pos = 2 + (ord($der[1]) & 0x80 ? (ord($der[1]) & 0x7f) : 0);
	$out = '';
	for ($i = 0; $i < 2; $i++) {
		$len = ord($der[$pos + 1]);
		$int = ltrim(substr($der, $pos + 2, $len), "\x00");
		$out .= str_pad($int, 32, "\x00", STR_PAD_LEFT);
		$pos += 2 + $len;
	}
	return $out;
}
