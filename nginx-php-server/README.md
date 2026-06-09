# Workshop Submission Dashboard

A production-ready, real-time web dashboard for monitoring Linux workshop team
submissions — built for Ubuntu 24.04 on DigitalOcean.

---

## Directory Structure

```
workshop-dashboard/
├── public/
│   └── index.html          ← Single-page dashboard (HTML + CSS + JS)
├── api/
│   ├── submissions.php     ← JSON API: scans all team folders
│   └── download.php        ← Secure file download endpoint
├── config/
│   ├── nginx-workshop.conf ← Nginx virtual host (recommended)
│   └── apache-workshop.conf← Apache alternative
├── scripts/
│   └── install.sh          ← Full automated installation script
└── README.md
```

Server layout after install:

```
/var/www/workshop/          ← Nginx web root (www-data owned)
│   ├── index.html
│   └── api/
│       ├── submissions.php
│       └── download.php

/var/workshop/submissions/  ← Bind-mount mirror (www-data readable)
│   ├── team01/             ← bind-mounted from /home/team01/submissions
│   ├── team02/
│   └── … team25/

/home/teamXX/submissions/   ← Real files (students upload here via SSH/SCP)
```

---

## Features

| Feature | Detail |
|---|---|
| Auto-refresh | AJAX every 5 seconds, no full page reload |
| Total submissions | Live count across all 25 teams |
| Team leaderboard | Ranked by submission count with animated bars |
| Latest 50 uploads | Sorted by timestamp |
| Per-file details | Team · filename · size · timestamp |
| Recent highlight | Files < 5 min old highlighted green |
| Search | Live filter by filename |
| Team filter | Drop-down to isolate a single team |
| File download | One-click download per file |
| CSV export | Full export of all submissions |
| Dark / light mode | Toggle with persistence |
| Countdown ring | Visual indicator of next refresh |
| Mobile responsive | Works on phones/tablets |

---

## Quick Install (Automated)

```bash
# 1. Upload this repo to your server
scp -r workshop-dashboard/ root@YOUR_IP:/root/

# 2. SSH into the server
ssh root@YOUR_IP

# 3. Run the installer
cd /root/workshop-dashboard
chmod +x scripts/install.sh
sudo bash scripts/install.sh
```

The installer will:
- Install Nginx + PHP 8.3-FPM
- Create the 25 team user accounts (if they don't exist)
- Set up `/home/teamXX/submissions/` folders with correct permissions
- Create `/var/workshop/submissions/` mirror with bind mounts
- Deploy the web app to `/var/www/workshop/`
- Configure Nginx and open the firewall
- Start all services

---

## Manual Install (Step-by-Step)

### 1. Install packages

```bash
sudo apt-get update
sudo apt-get install -y nginx php8.3-fpm php8.3-cli
```

### 2. Create team accounts & submission folders

```bash
for i in $(seq -w 1 25); do
    TEAM="team${i}"
    useradd -m -s /bin/bash "$TEAM"
    echo "$TEAM:ChangeMe123!" | chpasswd
    mkdir -p "/home/$TEAM/submissions"
    chown "$TEAM:workshop" "/home/$TEAM/submissions"
    chmod 2770 "/home/$TEAM/submissions"
done
```

### 3. Set up the submissions mirror

```bash
groupadd workshop
usermod -aG workshop www-data

mkdir -p /var/workshop/submissions
chown root:workshop /var/workshop/submissions
chmod 2750 /var/workshop/submissions

for i in $(seq -w 1 25); do
    TEAM="team${i}"
    mkdir -p "/var/workshop/submissions/$TEAM"
    chown "$TEAM:workshop" "/var/workshop/submissions/$TEAM"
    chmod 2770 "/var/workshop/submissions/$TEAM"
    mount --bind "/home/$TEAM/submissions" "/var/workshop/submissions/$TEAM"
done
```

Add to `/etc/fstab` for persistence (run for each team):
```
/home/team01/submissions /var/workshop/submissions/team01 none bind 0 0
# ... repeat for team02 through team25
```

### 4. Deploy web files

```bash
mkdir -p /var/www/workshop/api

cp public/index.html          /var/www/workshop/index.html
cp api/submissions.php        /var/www/workshop/api/
cp api/download.php           /var/www/workshop/api/

chown -R www-data:www-data /var/www/workshop
chmod -R 750 /var/www/workshop
```

### 5. Configure Nginx

```bash
cp config/nginx-workshop.conf /etc/nginx/sites-available/workshop
rm -f /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/workshop /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
```

### 6. Start services

```bash
systemctl enable --now php8.3-fpm nginx
```

---

## Permission Strategy (Security)

The challenge: `www-data` (the web server) must NOT have direct read access to
`/home/teamXX/` home directories, which are mode `700` by default.

**Solution: bind-mount mirror with a shared group**

```
/home/team01/       ← mode 700, owned by team01 — web server CANNOT enter
/home/team01/submissions/  ← mode 2770, group: workshop — team01 + workshop group can write

/var/workshop/submissions/team01/  ← bind-mounted to same inode
   │  owned: team01:workshop, mode 2770
   └─ www-data is in `workshop` group → can READ but not write
```

**Why this is secure:**
- `www-data` can read files in submission folders, nothing else
- Students (`teamXX`) can only write to their own `/home/teamXX/submissions/`
- No student can read another student's files (each account is isolated)
- The PHP download handler validates team name + filename before serving
- `realpath()` check prevents path traversal (`../../etc/passwd` etc.)
- Nginx blocks direct filesystem browsing (`-Indexes`)

---

## Changing Student Passwords

After setup, change the default passwords:

```bash
# Change a single team's password
passwd team01

# Or set all at once (use proper random passwords in production!)
for i in $(seq -w 1 25); do
    echo "team${i}:$(openssl rand -base64 12)" | chpasswd
done
```

---

## SSH Access for Students

Students connect with:

```bash
ssh team01@YOUR_SERVER_IP
# Then upload files:
scp myfile.pdf team01@YOUR_SERVER_IP:~/submissions/
```

Or using SFTP:

```bash
sftp team01@YOUR_SERVER_IP
sftp> cd submissions
sftp> put assignment.zip
```

### Restrict student SSH (optional hardening)

Add to `/etc/ssh/sshd_config`:

```
Match Group workshop
    ChrootDirectory /home/%u
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
```

This limits students to SFTP-only in their home directory.

---

## Monitoring & Troubleshooting

```bash
# Watch live submissions
watch -n 2 'find /var/workshop/submissions -type f | wc -l'

# Nginx logs
tail -f /var/log/nginx/workshop.access.log
tail -f /var/log/nginx/workshop.error.log

# PHP errors
tail -f /var/log/php8.3-fpm.log

# Check mounts
findmnt | grep workshop

# Verify www-data can read
sudo -u www-data ls /var/workshop/submissions/team01/

# Test API directly
curl http://localhost/api/submissions.php | python3 -m json.tool
```

---

## Security Recommendations

1. **HTTPS** — Add a TLS certificate (Let's Encrypt is free):
   ```bash
   apt install certbot python3-certbot-nginx
   certbot --nginx -d yourdomain.com
   ```

2. **Basic Auth** — Protect the dashboard behind a password:
   ```bash
   apt install apache2-utils
   htpasswd -c /etc/nginx/.htpasswd instructor
   ```
   Then add to Nginx config:
   ```nginx
   auth_basic "Workshop Dashboard";
   auth_basic_user_file /etc/nginx/.htpasswd;
   ```

3. **IP whitelist** — Restrict to your laptop's IP in Nginx:
   ```nginx
   allow YOUR_LAPTOP_IP;
   deny all;
   ```

4. **Fail2ban** — Block brute-force SSH attempts:
   ```bash
   apt install fail2ban
   ```

5. **Disable password SSH** — Use key-based auth:
   Add to `/etc/ssh/sshd_config`:
   ```
   PasswordAuthentication no
   ```
   (Only after you've copied SSH keys to team accounts.)

6. **Regular cleanup** — Script to archive submissions after workshop:
   ```bash
   tar czf submissions-backup-$(date +%Y%m%d).tar.gz /var/workshop/submissions/
   ```
