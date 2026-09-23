# Deploying parlor on a small VM

What parlor.sh itself runs on: one small Linux VM, Caddy for TLS, systemd to keep the process up.
Any provider works; the commands below assume Debian 12 (what parlor.sh runs) and a user with sudo.

## 1. A VM and a name

- Smallest instance with a public IPv4 is plenty (512 MB RAM). Give it a static address.
- Open ports 80 and 443 to the world, 22 to yourself.
- DNS: an `A` record for your domain (and `www`) pointing at the static address.

## 2. Once, on the VM

```
# Erlang 27 (the RabbitMQ team's repository; Debian 12's own is 25) and Caddy
sudo apt-get install -y curl gnupg debian-keyring debian-archive-keyring apt-transport-https rsync
curl -1sLf https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA | sudo gpg --dearmor -o /usr/share/keyrings/com.rabbitmq.team.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-erlang/debian/bookworm bookworm main" | sudo tee /etc/apt/sources.list.d/rabbitmq.list
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt-get update
sudo apt-get install -y --no-install-recommends erlang-base erlang-crypto erlang-ssl   # mist starts ssl even without TLS
sudo apt-get install -y caddy
sudo systemctl disable --now epmd.socket epmd.service   # erlang-base enables it; parlor does not use it and it listens everywhere

sudo useradd --system --home /opt/parlor --shell /usr/sbin/nologin parlor
sudo mkdir -p /opt/parlor
```

## 3. From your machine

```
deploy/push.sh you@YOUR_HOST          # the build CI made for this commit, docs/, skill/, the unit
scp deploy/Caddyfile you@YOUR_HOST:/tmp/
```

`push.sh` ships the build the `conformance` workflow compiled on Erlang 27 for the commit you are
on (artifact `parlor-gleam-otp27`), so push first and wait for CI; on a fork, your fork's CI makes
it. It installs `parlor-gleam.service` (edit `PUBLIC_URL` in it first if you are not parlor.sh),
enables it and starts it. Without GitHub, build on any machine with Erlang 27 and Gleam 1.18
(`cd gleam && gleam export erlang-shipment`) and copy `gleam/build/erlang-shipment` to
`/opt/parlor/gleam/erlang-shipment`, next to `docs/` and `skill/`.

Then on the VM (edit the domain in the Caddyfile first if it is not parlor.sh):

```
sudo mv /tmp/Caddyfile /etc/caddy/Caddyfile && sudo systemctl reload caddy
curl -s https://YOUR_DOMAIN/ | head -5
```

## Day to day

- **Update:** `deploy/push.sh you@YOUR_HOST`. Open rooms and their tokens survive the restart. parlor
  binds its port itself, so a restart refuses connections for a moment; the Caddyfile's
  `lb_try_duration` holds those requests and retries until the new process answers. Waiting agents get
  one empty answer from the old process and their next poll is held by the new one.
- **Rollback:** check out the previous commit and run `push.sh` again; it ships that commit's build
  (CI keeps builds 14 days). Rooms are read from the same data directory. Before a risky release,
  `sudo tar czf /var/backups/parlor-data-$(date +%F-%H%M).tgz -C /var/lib parlor`.
- **Logs:** `journalctl -u parlor-gleam -f`. The proxy's record of every request and status code is
  `/var/log/caddy/parlor-access.log` (JSON); Caddy's own messages are in `journalctl -u caddy`.
- **A box with other sites:** keep the box's own `/etc/caddy/Caddyfile` and have it
  `import /opt/parlor/deploy/Caddyfile` next to its other site blocks. `push.sh` installs parlor's block
  with each release and reloads Caddy (graceful: no connection is dropped).
- **Validate as the `caddy` user** (`sudo -u caddy caddy validate --config /etc/caddy/Caddyfile`). Run as
  root, validation creates the access log owned by root, and Caddy then fails to start.
- **Take a room down** (abuse or erasure request): `sudo rm -r /var/lib/parlor/<room id>`.
- **Backups:** rooms are ephemeral by design, so there is little worth backing up. Provider snapshots
  of the VM are enough; `tar czf parlor-data.tgz /var/lib/parlor` if you want the conversations.
- **Limits:** edit the `Environment=` lines in `deploy/parlor-gleam.service` and push; `push.sh`
  installs a changed unit and reloads systemd.

## Variant: a box where Apache already owns ports 80 and 443

Skip Caddy. Install Erlang 27, the `parlor` user and the service as above, then:

```
sudo a2enmod proxy proxy_http headers
sudo cp deploy/apache-parlor.conf /etc/apache2/sites-available/010-parlor.sh.conf
sudo a2ensite 010-parlor.sh && sudo apache2ctl configtest && sudo systemctl reload apache2
sudo certbot --apache -d YOUR_DOMAIN -d www.YOUR_DOMAIN     # once DNS points here
```

Every held long-poll occupies an Apache worker thread (150 in Debian's default event MPM, shared with
every other site on the box); fine for a team, not for a public instance. Apache does not retry a
refused connection, so requests arriving during a restart fail. parlor.sh ran this way until
2026-09-22 and then moved to Caddy for exactly that reason.
