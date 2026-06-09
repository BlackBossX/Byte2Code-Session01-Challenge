# Workshop Submission Dashboard (Python Standalone Server)

A lightweight, standalone Python web server for monitoring Linux workshop team submissions. This version eliminates the need for Nginx, PHP-FPM, or complex bind-mount permissions, allowing you to access and monitor submissions from other devices using the server's IP address.

---

## Directory Structure

```
python-server/
├── index.html       ← Single-page dashboard (HTML + CSS + JS)
├── server.py        ← Standalone Python server (handles API and file server)
├── setup-service.sh ← Installs the server as an automatic background service
└── README.md        ← This file
```

---

## Quick Start (Manual Run)

1. **Verify Python 3 is installed**:
   ```bash
   python3 --version
   ```

2. **Configure (Optional)**:
   Open `server.py` and modify the CONFIG block at the top if needed:
   ```python
   # Port to serve the dashboard on
   PORT = 8080

   # Path pattern for team submissions folder (where {team} is replaced by team name)
   SUB_PATH = "/home/{team}/submissions"

   # List of teams to scan
   TEAMS = [f"team{str(i).zfill(2)}" for i in range(1, 26)] # team01 ... team25
   ```

3. **Run the Server**:
   ```bash
   python3 server.py
   ```

4. **Access the Dashboard**:
   * **Locally**: `http://localhost:8080`
   * **From other computers on the same network**: `http://<your-server-ip>:8080` (e.g., `http://172.19.25.91:8080`)

---

## Automatic Service Setup (Recommended)

To run the server continuously in the background and ensure it starts automatically when the system boots up, install it as a systemd service.

1. **Run the installer script**:
   ```bash
   sudo bash setup-service.sh
   ```

2. **Useful service management commands**:
   * **Check status**: `sudo systemctl status workshop-dashboard`
   * **Stop service**: `sudo systemctl stop workshop-dashboard`
   * **Restart service**: `sudo systemctl restart workshop-dashboard`
   * **View live logs**: `sudo journalctl -u workshop-dashboard -f`

---

## Features

* **Zero external dependencies**: Requires only standard Python 3 libraries.
* **Auto-refresh**: The dashboard automatically fetches new data every 5 seconds without reloading the page.
* **Filter & Search**: Quickly search for files by name or filter by a specific team.
* **CSV Export**: Export all scanned submissions to a CSV file.
* **Secure Downloads**: Allows downloading submissions directly via the UI.
* **Light / Dark Mode**: Toggle between light and dark themes.
