#!/usr/bin/env python3
"""
Workshop Submission Dashboard Server
====================================
Run this on the machine that has the submission folders.
Access from any other computer via:  http://<this-machine-ip>:8080

Usage:
    python3 server.py

Options (edit the CONFIG block below):
    HOST        - listen address (0.0.0.0 = all interfaces)
    PORT        - port to serve on (default 8080)
    TEAMS       - list of team folder names to scan
    SUB_PATH    - path pattern for each team's submission folder
                  use {team} as placeholder, e.g. "/home/{team}/submissions"
"""

import http.server
import json
import os
import time
import mimetypes
import urllib.parse
from pathlib import Path
from datetime import datetime

# ─────────────────────────── CONFIG ──────────────────────────────────────────
HOST      = "0.0.0.0"          # listen on all network interfaces
PORT      = 8080

# Submission folder for each team.
# {team} is replaced with the team name, e.g.  /home/team01/submissions
SUB_PATH  = "/home/{team}/submissions"

# Teams to scan  –  edit this list to match your actual team accounts
TEAMS = [f"team{str(i).zfill(2)}" for i in range(1, 26)]  # team01 … team25

# A file is "recent" if submitted in the last N seconds
RECENT_THRESHOLD = 300   # 5 minutes
# ─────────────────────────────────────────────────────────────────────────────


SCRIPT_DIR  = Path(__file__).parent          # .../python-server/
REPO_ROOT   = SCRIPT_DIR.parent              # .../submission dashboard/


def fmt_bytes(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def scan_submissions():
    all_files   = []
    team_counts = {}
    errors      = []
    now         = time.time()

    for team in TEAMS:
        folder = SUB_PATH.replace("{team}", team)
        if not os.path.isdir(folder):
            team_counts[team] = 0
            continue
        try:
            entries = os.scandir(folder)
        except PermissionError:
            errors.append(f"Cannot read {team} submissions (permission denied)")
            team_counts[team] = 0
            continue

        count = 0
        for entry in entries:
            if not entry.is_file(follow_symlinks=False):
                continue
            try:
                stat  = entry.stat()
                mtime = stat.st_mtime
                size  = stat.st_size
            except OSError:
                continue
            count += 1
            all_files.append({
                "team":      team,
                "filename":  entry.name,
                "size":      size,
                "size_fmt":  fmt_bytes(size),
                "mtime":     mtime,
                "mtime_fmt": datetime.fromtimestamp(mtime).strftime("%H:%M:%S"),
                "date_fmt":  datetime.fromtimestamp(mtime).strftime("%Y-%m-%d"),
                "recent":    (now - mtime) < RECENT_THRESHOLD,
            })
        team_counts[team] = count

    # sort newest first
    all_files.sort(key=lambda f: f["mtime"], reverse=True)

    # leaderboard
    leaderboard = sorted(
        [{"team": t, "count": c} for t, c in team_counts.items()],
        key=lambda x: x["count"], reverse=True
    )

    return {
        "ok":          True,
        "timestamp":   now,
        "time_fmt":    datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "total":       len(all_files),
        "team_counts": team_counts,
        "leaderboard": leaderboard,
        "latest":      all_files[:50],
        "all_files":   all_files,
        "errors":      errors,
    }


class Handler(http.server.BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        print(f"  {self.address_string()} → {fmt % args}")

    def send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path: Path):
        mime, _ = mimetypes.guess_type(str(path))
        mime = mime or "application/octet-stream"
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_404(self):
        self.send_response(404)
        self.end_headers()
        self.wfile.write(b"Not found")

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path   = parsed.path.rstrip("/") or "/"
        query  = urllib.parse.parse_qs(parsed.query)

        # ── API: submissions ──────────────────────────────────────────────
        if path == "/api/submissions":
            self.send_json(scan_submissions())
            return

        # ── API: download a file ──────────────────────────────────────────
        if path == "/api/download":
            team     = query.get("team",     [""])[0]
            filename = query.get("filename", [""])[0]

            # security: no path traversal
            if not team or not filename or ".." in team or ".." in filename:
                self.send_json({"ok": False, "error": "Bad request"}, 400)
                return

            file_path = Path(SUB_PATH.replace("{team}", team)) / filename
            if not file_path.is_file():
                self.send_404()
                return

            data = file_path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition",
                             f'attachment; filename="{filename}"')
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        # ── Static files ──────────────────────────────────────────────────
        if path == "/" or path == "/index.html":
            file_path = SCRIPT_DIR / "index.html"
        else:
            # First look in python-server/ dir, then fall back to repo root
            local_path = SCRIPT_DIR / path.lstrip("/")
            repo_path  = REPO_ROOT  / path.lstrip("/")
            if local_path.is_file():
                file_path = local_path
            elif repo_path.is_file():
                file_path = repo_path
            else:
                file_path = local_path  # will trigger 404 below

        if file_path.is_file():
            self.send_file(file_path)
        else:
            self.send_404()


def main():
    import socket
    # Find a local non-loopback IP to show the user
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        local_ip = "YOUR_IP"

    server = http.server.HTTPServer((HOST, PORT), Handler)

    print()
    print("╔══════════════════════════════════════════════════╗")
    print("║   Workshop Dashboard — running                   ║")
    print("╠══════════════════════════════════════════════════╣")
    print(f"║  Local:    http://localhost:{PORT}                  ║")
    print(f"║  Network:  http://{local_ip}:{PORT}            ║")
    print("╠══════════════════════════════════════════════════╣")
    print("║  Open the Network URL on any other computer      ║")
    print("║  Press Ctrl+C to stop                            ║")
    print("╚══════════════════════════════════════════════════╝")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Server stopped.")


if __name__ == "__main__":
    main()
