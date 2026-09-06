# Troubleshooting & reference

How the authentication actually works, why you see 401 vs 403, and what to
re-check after a dsh upgrade.

## The dsh web auth token (Frequently asked first)

`dsh web` prints a URL such as:

```
http://127.0.0.1:3080/?token=DOxGRAOmswe4…UVc
```

That `?token=` is **a per-process launch token**. Every time dsh web starts it
mints a new random one — so the URL changes on every launch. This is not a
bug; it's the platform's browser-session handshake:

1. Browser opens the token URL once.
2. dsh validates the token and responds `303` + `Set-Cookie` with a **signed
   cookie** bound to the exact Host/authority you connected through.
3. dsh redirects to the clean `/`.
4. Later requests are authenticated by that cookie (HttpOnly, `SameSite=Strict`).

Properties that are easy to miss:

- The cookie's signing secret is **persisted**, so the cookie survives dsh
  restarts. Restarting `dsh web` does NOT invalidate a phone that already has a
  cookie.
- The cookie is **bound to the authority** you first connected through. A cookie
  minted for `<node>.tailXXXX.ts.net` will NOT authenticate a request to
  `127.0.0.1:3080` (they are different Host values → different cookie name).
- The cookie lasts **30 days** (`Max-Age=2592000`).

So the workflow is: launch via `start-dsh-web.sh`, then have the phone open the
printed `?token=` URL **once**. After that, plain `https://<node>.tail…ts.net/`
works for 30 days.

## 401 vs 403 — the two separate gates

The occasional summary in one line:

| Status | Meaning | When |
|--------|---------|------|
| `401 Unauthorized` | missing/expired/wrong cookie (the browser auth layer) | you opened the tailnet URL without ever doing the token exchange, or the 30-day cookie expired |
| `403 Forbidden` | Host/Origin not trusted (the `/api` request-trust fence) | you're hitting `/api` from a Host that dsh's fence doesn't allow — most often the tailnet hostname was NOT passed via `--trusted-host` |

| Fix for 403 | pass `--trusted-host <node>.tail…ts.net` at launch (the script does this) |
|---|---|
| Fix for 401 | do the token→cookie exchange once (open the `?token=` URL, or rerun the script to get a fresh one, then open it) |

The trust fence is implemented in `@deepseek-ai/dsh-client-connection`
(`/api` gate, `api-request-trust.ts`, `isAuthenticated`). It is an
anti-DNS-rebinding / cross-origin guard, **not** authentication.

## Verifying end-to-end with curl

```bash
BASE=https://<node>.tail…ts.net
TOKEN=<the token dsh web printed>

# 1. no cookie → 401
curl -s -o /dev/null -w '%{http_code}\n' $BASE/                       # 401

# 2. token exchange → 303 + Set-Cookie
curl -c /tmp/ck.txt -o /dev/null -w '%{http_code}\n' $BASE/?token=$TOKEN  # 303

# 3. with cookie → 200
curl -b /tmp/ck.txt -o /dev/null -w '%{http_code}\n' $BASE/           # 200
```

## How the launcher script works

```
start-dsh-web.sh --configure <hostname>   # writes hostname to local.conf (gitignored)
bash start-dsh-web.sh                     # uses local.conf or $DSH_TS_HOST
```

The script:

1. Reads the tailnet hostname (env `DSH_TS_HOST`, else `local.conf`).
2. `pkill`s any previous `dsh web --trusted-host <host>` instance (full-command
   match so it never kills itself).
3. `cd ~/.dsh && nohup dsh web --trusted-host "$TS_HOST" --no-open &`
4. Waits for the URL line, prints both the local URL and the phone's token URL.

The hostname is deliberately **not** hard-coded and `local.conf` is gitignored,
so the repo is portable and never leaks your hostname / token.

## Persisting trusted-host without the CLI flag (optional)

`--trusted-host` is a CLI flag that must appear on every launch. If you prefer,
you can hard-code it into the profile's patch layer so a plain `dsh web` also
accepts the tailnet host. In `~/.dsh/profiles/web/cordis.patch.yml` add:

```yaml
- id: connection
  config:
    trustedHosts: !!js ctx.webRuntime.trustedHosts.concat('<node>.tail…ts.net')
```

> **Note:** target the `connection` row (dsh-client-connection), **not** a
> `web-app` row — the `/api` fence reads `trustedHosts` from the connection
> row. A patch against a web-app row is a silent no-op. This detail is called
> out by community findings; verify against your dsh version before relying on
> it. The launcher's CLI-flag approach is the verified, version-agnostic path.

## Alternatives (when loopback+Serve isn't enough)

Several community projects tackle the same problem with different trade-offs:

- **dsh-one-gateway** (`TiantianFlow/dsh-one-gateway`) — a separate zero-trust
  gateway process in front of loopback dsh. identity-first: reads Serve's
  injected `Tailscale-User-Login` header, Cloudflare Access JWT, or a gateway
  credential. dsh still never leaves loopback. Strictest allowlist model.
- **dsh-auth-tailscale** (`sperictao/dsh-auth-tailscale`) — an auth adapter that
  turns Serve's injected identity headers into a login allowlist +
  capabilities. Droppable-in where `dsh-client-connection-authz` exists.
- **YiYan129600/dsh-mobile-access** — a browser plugin adding QR pairing, PWA
  "add to home screen", SSE/Web-Push mobile notifications, HTTP/2 toggle. No
  build step. Good UX layer on top of this architecture.
- **alexcarterio/dsh-mobile-access** — a `lan-gate` reverse proxy with device
  approval flow, mobile layout, ntfy push, file upload.
- **Hongtwenfive1226/DSH-Mobile-for-Android** — a native React Native Android
  client with a file bridge (needs building your own APK).

Generally you only need ONE remote-access mechanism. This project is the
minimal, durable one; reach for the zero-trust gateway only if you need
per-identity authorization or multi-user sharing.

## Running dsh web at boot (systemd user service)

`tailscale serve` runs for as long as `tailscaled` is up, but **dsh web is a
normal process and does NOT start itself at boot.** If you want the phone to
work right after the machine boots, run dsh web under systemd in *user* mode.

> Prerequisite: a **user** systemd service needs `linger` so it starts at boot
> without requiring you to log in:
> ```bash
> loginctl enable-linger "$USER"     # one-time
> loginctl show-user "$USER" | grep -i linger   # → Linger=yes
> ```

Example unit — `~/.config/systemd/user/dsh-web.service`:

```ini
[Unit]
Description=DeepSeek Harness (dsh) web UI over Tailscale Serve
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
Environment=HOME=%h
WorkingDirectory=%h/.dsh
# dsh is a node script; point directly at the node binary + bin.js so the
# shebang resolves regardless of PATH. Replace <NODE_BIN>, <BIN_JS> and
# <node>.tailXXXX.ts.net with your real paths/hostname.
ExecStart=<NODE_BIN> <BIN_JS> web --trusted-host <node>.tailXXXX.ts.net --no-open --port 3080
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

Register and start it:

```bash
systemctl --user daemon-reload
systemctl --user enable --now dsh-web.service
```

Check it came up and read the current token from the journal:

```bash
systemctl --user status dsh-web.service          # → active (running)
journalctl --user -u dsh-web.service --no-pager | grep -oE 'token=[A-Za-z0-9_-]*' | tail -1
```

### Stop / restart when it misbehaves

If dsh web wedges, the phone times out, or you need a fresh token:

```bash
# stop (dsh web no longer answers; phone will fail to load until restart)
systemctl --user stop dsh-web.service
# start again (after a fix, or to mint a new token)
systemctl --user start dsh-web.service
# or restart atomically
systemctl --user restart dsh-web.service
# disable boot autostart entirely (survives reboot as "not running")
systemctl --user disable --now dsh-web.service
```

`Restart=on-failure` already relaunches it automatically if it crashes; use
`stop`/`start` only when you need manual control. After a restart, the token
changes — re-read it from the journal and have the phone do the `?token=`
exchange again if its 30-day cookie is gone.

## After every dsh upgrade — re-verify

DeepSeek Harness is a developer preview with breaking changes between rc
releases. After `dsh` (or its plugins) update, confirm this checklist:

- [ ] `dsh web` still boots without the previous plugin-tree error
- [ ] `bash start-dsh-web.sh` still prints a token URL
- [ ] phone still loads `https://<node>.tail…ts.net/` (bonus: check for the
      `?token=` + 30-day behavior still present; it may change)

If something breaks, the fix is usually in the trust/auth layer (see the two
tables above), not in your config.

## Version this was verified against

- dsh: `0.1.2-rc.1` (npm `@deepseek-ai/dsh`)
- Tailscale: `1.102.3`
- Host: Ubuntu 26.04 Desktop