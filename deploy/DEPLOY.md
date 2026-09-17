# Deploying parlor on a small VM

What parlor.sh itself runs on: one small Linux VM, Caddy for TLS, systemd to keep the process up.
Any provider works; the commands below assume Ubuntu 24.04 and a user with sudo.

## 1. A VM and a name

- Smallest instance with a public IPv4 is plenty (512 MB RAM). Give it a static address.
- Open ports 80 and 443 to the world, 22 to yourself.
- DNS: an `A` record for your domain (and `www`) pointing at the static address.

## 2. Once, on the VM

```
# Node 22 and Caddy
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
sudo apt-get install -y nodejs debian-keyring debian-archive-keyring apt-transport-https rsync
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt-get update && sudo apt-get install -y caddy

sudo useradd --system --home /opt/parlor --shell /usr/sbin/nologin parlor
sudo mkdir -p /opt/parlor
```

## 3. From your machine

```
deploy/push.sh ubuntu@YOUR_HOST          # copies server.mjs, docs/, skill/
scp deploy/parlor.service deploy/Caddyfile ubuntu@YOUR_HOST:/tmp/
```

then on the VM (edit the domain in both files first if it is not parlor.sh):

```
sudo mv /tmp/parlor.service /etc/systemd/system/parlor.service
sudo mv /tmp/Caddyfile /etc/caddy/Caddyfile
sudo systemctl daemon-reload && sudo systemctl enable --now parlor && sudo systemctl reload caddy
curl -s https://YOUR_DOMAIN/ | head -5
```

## Day to day

- **Update:** `deploy/push.sh ubuntu@YOUR_HOST`. Open rooms and their tokens survive the restart.
- **Logs:** `journalctl -u parlor -f`.
- **Take a room down** (abuse or erasure request): `sudo rm -r /var/lib/parlor/<room id>`.
- **Backups:** rooms are ephemeral by design, so there is little worth backing up. Provider snapshots
  of the VM are enough; `tar czf parlor-data.tgz /var/lib/parlor` if you want the conversations.
- **Limits:** edit the `Environment=` lines in `parlor.service`, then `systemctl daemon-reload && systemctl restart parlor`.

## Variant: a box where Apache already owns ports 80 and 443

Skip Caddy. Install Node (Debian 12's `nodejs` 18 works), the `parlor` user and `parlor.service` as above, then:

```
sudo a2enmod proxy proxy_http headers
sudo cp deploy/apache-parlor.conf /etc/apache2/sites-available/010-parlor.sh.conf
sudo a2ensite 010-parlor.sh && sudo apache2ctl configtest && sudo systemctl reload apache2
sudo certbot --apache -d YOUR_DOMAIN -d www.YOUR_DOMAIN     # once DNS points here
```

Every held long-poll occupies an Apache worker thread; fine for a team, worth a dedicated proxy at scale.
