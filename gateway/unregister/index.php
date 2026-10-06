<?php
// POST /push/unregister: the app signs out. Knowing the token is the proof (it never leaves the phone otherwise).
require dirname(__DIR__) . '/common.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') reply(405);
$b = json_body();
$token = strtolower((string)($b['token'] ?? ''));
if (!valid_token($token)) reply(400, ['error' => 'bad request']);
$removed = with_tokens(function (&$data) use ($token) {
	$n = 0;
	foreach ($data as $k => $list) {
		$keep = array_values(array_filter($list, function ($d) use ($token) { return $d['token'] !== $token; }));
		$n += count($list) - count($keep);
		if ($keep) $data[$k] = $keep; else unset($data[$k]);
	}
	return $n;
});
if ($removed) push_log('unregistered ' . substr($token, 0, 8) . '...');
reply(200, ['ok' => true]);
