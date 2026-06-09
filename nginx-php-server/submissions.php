<?php
/**
 * Workshop Submission API
 * Returns JSON data about all team submissions
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Cache-Control: no-cache, no-store, must-revalidate');

// ── Configuration ──────────────────────────────────────────────────────────
define('TEAMS_COUNT', 25);
define('SUBMISSIONS_DIR', '/var/workshop/submissions'); // symlink target
define('RECENT_THRESHOLD', 300); // 5 minutes in seconds

// ── Helpers ────────────────────────────────────────────────────────────────

function formatBytes(int $bytes): string {
    if ($bytes === 0) return '0 B';
    $units = ['B', 'KB', 'MB', 'GB'];
    $i = (int) floor(log($bytes, 1024));
    return round($bytes / pow(1024, $i), 1) . ' ' . $units[$i];
}

function teamName(int $n): string {
    return 'team' . str_pad($n, 2, '0', STR_PAD_LEFT);
}

// ── Scan submissions ───────────────────────────────────────────────────────

$allFiles   = [];
$teamCounts = [];
$errors     = [];
$now        = time();

for ($i = 1; $i <= TEAMS_COUNT; $i++) {
    $team    = teamName($i);
    $dir     = SUBMISSIONS_DIR . '/' . $team;
    $count   = 0;

    if (!is_dir($dir)) {
        $teamCounts[$team] = 0;
        continue;
    }

    $items = scandir($dir);
    if ($items === false) {
        $errors[] = "Cannot read $team submissions";
        $teamCounts[$team] = 0;
        continue;
    }

    foreach ($items as $file) {
        if ($file === '.' || $file === '..') continue;

        $path  = $dir . '/' . $file;
        if (!is_file($path)) continue;

        $mtime = filemtime($path);
        $size  = filesize($path);
        $count++;

        $allFiles[] = [
            'team'      => $team,
            'filename'  => $file,
            'size'      => $size,
            'size_fmt'  => formatBytes($size),
            'mtime'     => $mtime,
            'mtime_fmt' => date('H:i:s', $mtime),
            'date_fmt'  => date('Y-m-d', $mtime),
            'recent'    => ($now - $mtime) < RECENT_THRESHOLD,
        ];
    }

    $teamCounts[$team] = $count;
}

// Sort all files newest first
usort($allFiles, fn($a, $b) => $b['mtime'] - $a['mtime']);

// Build leaderboard (sorted by count desc)
$leaderboard = $teamCounts;
arsort($leaderboard);
$leaderboard = array_map(
    fn($team, $count) => ['team' => $team, 'count' => $count],
    array_keys($leaderboard),
    array_values($leaderboard)
);

// ── Response ───────────────────────────────────────────────────────────────

echo json_encode([
    'ok'           => true,
    'timestamp'    => $now,
    'time_fmt'     => date('Y-m-d H:i:s'),
    'total'        => count($allFiles),
    'team_counts'  => $teamCounts,
    'leaderboard'  => $leaderboard,
    'latest'       => array_slice($allFiles, 0, 50),
    'all_files'    => $allFiles,    // used by CSV export
    'errors'       => $errors,
], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
