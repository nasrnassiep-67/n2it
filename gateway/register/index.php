<?php
// POST /push/register: the iPhone app stores its VoIP push token for an extension.
// Only accepted with the extension's SIP password, and failed attempts are rate limited.
require dirname(__DIR__) . '/common.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') reply(405);
$ip = $_SERVER['REMOTE_ADDR'] ?? '';
$b = json_body();
$domain = tenant_domain($b['tenant'] ?? '');
$user = (string)($b['user'] ?? '');
$token = strtolower((string)($b['token'] ?? ''));
if (!$domain || !valid_user($user) || !valid_token($token) || !is_string($b['password'] ?? null)) reply(400, ['error' => 'bad request']);

// 10 failed attempts per hour per IP, 20 per extension: stops password guessing through this endpoint.
if (!rate_ok("fail-ip:$ip", 10, false) || !rate_ok("fail-ext:$user@$domain", 20, false)) {
	push_log("register rate limited $user@$domain from $ip");
	reply(429, ['error' => 'too many attempts']);
}

try {
	$q = db()->prepare("SELECT e.password FROM v_extensions e JOIN v_domains d USING (domain_uuid)
		WHERE d.domain_name = ? AND d.domain_enabled = 'true' AND e.extension = ? AND e.enabled = 'true'");
	$q->execute([$domain, $user]);
	$row = $q->fetch(PDO::FETCH_ASSOC);
} catch (PDOException $e) {
	push_log('db error: ' . $e->getMessage());
	reply(503, ['error' => 'unavailable']);
}
if (!$row || !hash_equals((string)$row['password'], $b['password'])) {
	rate_ok("fail-ip:$ip", 10); rate_ok("fail-ext:$user@$domain", 20);
	push_log("register refused $user@$domain from $ip");
	reply(401, ['error' => 'wrong extension or password']);
}

$device = [
	'token' => $token,
	'sandbox' => !empty($b['sandbox']),
	'bundle' => preg_replace('/[^A-Za-z0-9.-]/', '', (string)($b['bundle'] ?? '')),
	'updated' => date('c'),
];
with_tokens(function (&$data) use ($user, $domain, $token, $device) {
	foreach ($data as $k => $list) {                   // a phone signs in to one extension at a time
		$data[$k] = array_values(array_filter($list, function ($d) use ($token) { return $d['token'] !== $token; }));
		if (!$data[$k]) unset($data[$k]);
	}
	$data["$user@$domain"][] = $device;
	$data["$user@$domain"] = array_slice($data["$user@$domain"], -MAX_DEVICES);
});
push_log("registered $user@$domain " . substr($token, 0, 8) . '... ' . ($device['sandbox'] ? 'sandbox' : 'production'));
reply(200, ['ok' => true]);
