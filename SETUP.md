# Cloud Office – Setup Guide

## Architecture Overview

```
Internet
    │
    ▼
[Hetzner Cloud Firewall]  ← allow only 22, 80, 443
    │
    ▼
[Nginx Proxy Manager]  :80/:443 (host)
    │  proxy network
    ├──► Nextcloud        cloud.yourdomain.de
    ├──► OnlyOffice       office.yourdomain.de
    ├──► Vikunja          tasks.yourdomain.de
    └──► Uptime Kuma      status.yourdomain.de

  internal network (no internet access)
    ├──── nextcloud-db
    ├──── nextcloud-redis
    └──── vikunja-db
```

---

## 1. Hetzner Cloud Firewall

In the Hetzner Cloud Console, create a firewall with **inbound rules**:

| Protocol | Port | Source      | Purpose       |
|----------|------|-------------|---------------|
| TCP      | 22   | Your IP/32  | SSH           |
| TCP      | 80   | 0.0.0.0/0   | HTTP (→ HTTPS)|
| TCP      | 443  | 0.0.0.0/0   | HTTPS         |

Block everything else. Attach the firewall to your server.

> **SSH tip:** Disable password authentication once your SSH key works:
> ```
> # /etc/ssh/sshd_config
> PasswordAuthentication no
> PubkeyAuthentication yes
> ```
> Then: `systemctl restart sshd`

---

## 2. DNS – A-Records

At your domain registrar (or Hetzner DNS), create these A-Records  
pointing to your server's public IPv4 address:

| Hostname              | Type | Value          | TTL  |
|-----------------------|------|----------------|------|
| yourdomain.de         | A    | YOUR_SERVER_IP | 300  |
| www.yourdomain.de     | A    | YOUR_SERVER_IP | 300  |
| cloud.yourdomain.de   | A    | YOUR_SERVER_IP | 300  |
| office.yourdomain.de  | A    | YOUR_SERVER_IP | 300  |
| tasks.yourdomain.de   | A    | YOUR_SERVER_IP | 300  |
| status.yourdomain.de  | A    | YOUR_SERVER_IP | 300  |

Wait for DNS propagation (~5 minutes with TTL 300).  
Verify with: `dig cloud.yourdomain.de +short`

---

## 3. Server Preparation

```bash
# Update system
apt update && apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh

# Add your user to the docker group (optional)
usermod -aG docker $USER
```

---

## 4. Deploy

```bash
# Clone / copy this repo to the server
cd /opt
git clone <repo-url> onlineOffice
cd onlineOffice

# Create your environment file
cp .env.example .env
nano .env          # Fill in all passwords and your domain

# Start everything
docker compose up -d

# Watch logs during first start
docker compose logs -f
```

---

## 5. Nginx Proxy Manager – First Login

The NPM admin panel is available **only from the server itself** (bound to 127.0.0.1:81).  
Use an SSH tunnel to access it:

```bash
ssh -L 8181:127.0.0.1:81 user@YOUR_SERVER_IP
```

Then open: http://localhost:8181

Default credentials:
- Email: `admin@example.com`
- Password: `changeme`

**Change these immediately after first login.**

### Add Proxy Hosts (repeat for each service)

1. Click **Proxy Hosts → Add Proxy Host**
2. Fill in:

| Field              | Website             | Nextcloud           | OnlyOffice          | Vikunja             | Uptime Kuma         |
|--------------------|---------------------|---------------------|---------------------|---------------------|---------------------|
| Domain             | yourdomain.de       | cloud.yourdomain.de | office.yourdomain.de| tasks.yourdomain.de | status.yourdomain.de|
| Scheme             | http                | http                | http                | http                | http                |
| Forward Hostname   | laborluzern-website | nextcloud           | onlyoffice          | vikunja             | uptime-kuma         |
| Forward Port       | 80                  | 80                  | 80                  | 3456                | 3001                |
| Block Common Exploits | ✓              | ✓                   | ✓                   | ✓                   | ✓                   |

3. On the **SSL** tab:
   - SSL Certificate: **Request a new SSL Certificate**
   - Enable **Force SSL** and **HTTP/2 Support**
   - Enter your email for Let's Encrypt notifications

### Nextcloud: Extra Nginx Config

In the Nextcloud proxy host, click **Advanced** and add:

```nginx
client_max_body_size 10G;
proxy_buffering off;
proxy_request_buffering off;

location /.well-known/carddav {
  return 301 $scheme://$host/remote.php/dav;
}
location /.well-known/caldav {
  return 301 $scheme://$host/remote.php/dav;
}
```

---

## 6. Connect OnlyOffice to Nextcloud

1. In Nextcloud, go to **Apps** and install **ONLYOFFICE**
2. Go to **Settings → ONLYOFFICE**
3. Document Editing Service address: `https://office.yourdomain.de`
4. Secret key: the value of `ONLYOFFICE_JWT_SECRET` from your `.env`
5. Save and test the connection

---

## 7. Backup

### Manual backup

```bash
sudo bash backup/scripts/backup.sh
```

Archives are stored in `backup/archives/` and kept for 7 days.

### Automated daily backup (2 AM)

```bash
crontab -e
# Add:
0 2 * * * /opt/onlineOffice/backup/scripts/backup.sh >> /var/log/cloud-backup.log 2>&1
```

### Offsite backup with restic (recommended)

```bash
apt install restic

# Initialize a Hetzner Storage Box repo (sftp example)
restic -r sftp:user@uXXXXXX.your-storagebox.de:/cloud-backup init

# Back up the archives directory
restic -r sftp:user@uXXXXXX.your-storagebox.de:/cloud-backup \
  backup /opt/onlineOffice/backup/archives \
  --password-file /root/.restic-password

# Keep last 30 daily snapshots
restic -r ... forget --keep-daily 30 --prune
```

---

## 8. Uptime Kuma – Monitoring Setup

1. Open `https://status.yourdomain.de` and create your admin account
2. Add monitors for each service:

| Name       | Type    | URL                             |
|------------|---------|---------------------------------|
| Nextcloud  | HTTPS   | https://cloud.yourdomain.de     |
| OnlyOffice | HTTPS   | https://office.yourdomain.de    |
| Vikunja    | HTTPS   | https://tasks.yourdomain.de     |

3. Configure notifications (Telegram, Email, Signal, etc.) under **Settings → Notifications**

---

## 9. Maintenance Commands

```bash
# View running containers
docker compose ps

# View logs for a specific service
docker compose logs -f nextcloud

# Update all images
docker compose pull && docker compose up -d

# Nextcloud OCC command
docker compose exec nextcloud php occ <command>

# Nextcloud background jobs (run manually)
docker compose exec nextcloud php occ background:cron
```

---

## Security Checklist

- [ ] Hetzner Firewall active (ports 22/80/443 only)
- [ ] SSH password authentication disabled
- [ ] `.env` file has strong unique passwords (never reuse passwords)
- [ ] NPM default credentials changed
- [ ] Uptime Kuma notifications configured
- [ ] Automated backups running (`crontab -l`)
- [ ] Offsite backup configured (Hetzner Storage Box or S3)
- [ ] `fail2ban` installed and protecting SSH
