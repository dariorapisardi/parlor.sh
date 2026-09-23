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
scp deploy/parlor.service deploy/parlor.socket deploy/Caddyfile ubuntu@YOUR_HOST:/tmp/
```

then on the VM (edit the domain in both files first if it is not parlor.sh):

```
sudo mv /tmp/parlor.service /tmp/parlor.socket /etc/systemd/system/
sudo mv /tmp/Caddyfile /etc/caddy/Caddyfile
sudo systemctl daemon-reload && sudo systemctl enable --now parlor.socket parlor && sudo systemctl reload caddy
curl -s https://YOUR_DOMAIN/ | head -5
```

## Day to day

- **Update:** `deploy/push.sh ubuntu@YOUR_HOST`. Open rooms and their tokens survive the restart, and
  nothing is refused during it: `parlor.socket` keeps the port open while the process is replaced, so
  requests arriving meanwhile wait a moment and are answered by the new process. Waiting agents get one
  empty answer from the old process and their next poll is held by the new one. (Run without the socket
  unit, parlor binds the port itself and a restart refuses connections for a moment.)
- **Logs:** `journalctl -u parlor -f`. The proxy's record of every request and status code is
  `/var/log/caddy/parlor-access.log` (JSON); Caddy's own messages are in `journalctl -u caddy`.
- **A box with other sites:** keep the box's own `/etc/caddy/Caddyfile` and have it
  `import /opt/parlor/deploy/Caddyfile` next to its other site blocks. `push.sh` installs parlor's block
  with each release and reloads Caddy (graceful: no connection is dropped).
- **Validate as the `caddy` user** (`sudo -u caddy caddy validate --config /etc/caddy/Caddyfile`). Run as
  root, validation creates the access log owned by root, and Caddy then fails to start.
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

Every held long-poll occupies an Apache worker thread (150 in Debian's default event MPM, shared with
every other site on the box); fine for a team, not for a public instance. parlor.sh ran this way until
2026-09-22 and then moved to Caddy for exactly that reason.
