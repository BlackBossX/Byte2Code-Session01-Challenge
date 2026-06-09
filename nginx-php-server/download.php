<?php
/**
 * Secure file download handler
 * Validates team + filename before serving the file
 */

define('TEAMS_COUNT', 25);
define('SUBMISSIONS_DIR', '/var/workshop/submissions');

function teamName(int $n): string {
    return 'team' . str_pad($n, 2, '0', STR_PAD_LEFT);
}

// ── Validate inputs ────────────────────────────────────────────────────────

$team     = $_GET['team']     ?? '';
$filename = $_GET['filename'] ?? '';

// Whitelist team names
$validTeams = [];
for ($i = 1; $i <= TEAMS_COUNT; $i++) {
    $validTeams[] = teamName($i);
}

if (!in_array($team, $validTeams, true)) {
    http_response_code(400);
    die(json_encode(['error' => 'Invalid team']));
}

// Sanitize filename: no path traversal, no hidden files
$filename = basename($filename);
if ($filename === '' || $filename[0] === '.') {
    http_response_code(400);
    die(json_encode(['error' => 'Invalid filename']));
}

$path = SUBMISSIONS_DIR . '/' . $team . '/' . $filename;

// Resolve realpath and confirm it stays inside submissions dir
$real = realpath($path);
$base = realpath(SUBMISSIONS_DIR);

if ($real === false || strpos($real, $base . '/') !== 0) {
    http_response_code(403);
    die(json_encode(['error' => 'Access denied']));
}

if (!is_file($real)) {
    http_response_code(404);
    die(json_encode(['error' => 'File not found']));
}

// ── Serve file ─────────────────────────────────────────────────────────────

$mime = mime_content_type($real) ?: 'application/octet-stream';
$size = filesize($real);
$safe = rawurlencode($filename);

header('Content-Type: ' . $mime);
header('Content-Disposition: attachment; filename="' . $safe . '"');
header('Content-Length: ' . $size);
header('Cache-Control: no-cache');
header('X-Content-Type-Options: nosniff');

readfile($real);
