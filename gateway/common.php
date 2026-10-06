<?php
// N2IT push gateway (iPhone VoIP pushes through Apple's APNs). Shared helpers.
// Source: /root/voip/n2it-app/push/, installed to /var/www/fusionpbx/push/ (reached through FusionPBX's
// public router: /push/register -> push/register/index.php). Notes: /root/voip/HANDOVER.md.
//
//   POST /push/register    {tenant,user,password,token,bundle,sandbox}  from the app; SIP password checked
//   POST /push/unregister  {tenant,user,token}                          from the app on sign-out
//   POST /push/notify.php  user, domain, number, name                   from FreeSWITCH, 127.0.0.1 only

date_default_timezone_set('Africa/Johannesburg');

const PUSH_DATA = '/var/lib/n2it-push';               // tokens.json, jwt.json, rate/ (www-data only)
const PUSH_CONFIG = '/etc/n2it-push/config.php';       // APNs team/key ids + .p8 path (owner fills in)
const BASE_DOMAIN = 'voip.n2it.co.za';
const MAX_DEVICES = 5;                                 // per extension

function reply($code, $body = []) {
	http_response_code($code);
	header('Content-Type: application/json');
	header('Cache-Control: no-store');
	echo json_encode($body);
	exit;
}

function push_log($msg) { error_log('n2it-push: ' . $msg); }

function json_body() {
	$b = json_decode(file_get_contents('php://input', false, null, 0, 16384), true);
	return is_array($b) ? $b : [];
}

function config() {
	static $c = null;
	if ($c === null) $c = is_file(PUSH_CONFIG) ? (include PUSH_CONFIG) : [];
	return is_array($c) ? $c : [];
}

// Validated company domain from the app's tenant field, or null.
function tenant_domain($tenant) {
	$t = strtolower(trim((string)$tenant));
	return preg_match('/^[a-z0-9][a-z0-9-]{0,39}$/', $t) ? $t . '.' . BASE_DOMAIN : null;
}

function valid_user($u) { return is_string($u) && preg_match('/^\d{2,10}$/', $u); }
function valid_token($t) { return is_string($t) && preg_match('/^[0-9a-f]{64,200}$/', $t); }

// At most $limit events per hour per key; $count=false only checks.
function rate_ok($key, $limit, $count = true) {
	$file = PUSH_DATA . '/rate/' . hash('sha256', $key) . '.json';
	$now = time();
	$hits = is_file($file) ? (json_decode(@file_get_contents($file), true) ?: []) : [];
	$hits = array_values(array_filter($hits, function ($t) use ($now) { return $t > $now - 3600; }));
	if (count($hits) >= $limit) return false;
	if ($count) { $hits[] = $now; file_put_contents($file, json_encode($hits), LOCK_EX); }
	return true;
}

// FusionPBX's own database settings.
function db() {
	$cfg = [];
	foreach (file('/etc/fusionpbx/config.conf', FILE_IGNORE_NEW_LINES) ?: [] as $line) {
		if (preg_match('/^\s*([\w.]+)\s*=\s*(.*?)\s*$/', $line, $m)) $cfg[$m[1]] = $m[2];
	}
	return new PDO(sprintf('pgsql:host=%s;port=%s;dbname=%s;sslmode=%s', $cfg['database.0.host'] ?? '127.0.0.1',
		$cfg['database.0.port'] ?? '5432', $cfg['database.0.name'] ?? 'fusionpbx', $cfg['database.0.sslmode'] ?? 'prefer'),
		$cfg['database.0.username'] ?? 'fusionpbx', $cfg['database.0.password'] ?? '',
		[PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
}

// Token store: { "<user>@<domain>": [ {token, sandbox, bundle, updated}, ... ] }, updated under an exclusive lock.
function with_tokens(callable $fn) {
	$fh = fopen(PUSH_DATA . '/tokens.json', 'c+');
	flock($fh, LOCK_EX);
	$data = json_decode(stream_get_contents($fh), true) ?: [];
	$result = $fn($data);
	ftruncate($fh, 0); rewind($fh);
	fwrite($fh, json_encode($data, JSON_PRETTY_PRINT));
	fflush($fh); flock($fh, LOCK_UN); fclose($fh);
	return $result;
}

function read_tokens() {
	$f = PUSH_DATA . '/tokens.json';
	return is_file($f) ? (json_decode(file_get_contents($f), true) ?: []) : [];
}
