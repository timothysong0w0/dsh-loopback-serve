# dsh-loopback-serve

[English](README.md) · [简体中文](README.zh.md)

**Minimal, upgrade-safe remote access to the DeepSeek Harness (dsh) Web UI
from your phone over Tailscale Serve — dsh never leaves loopback.**

---

## TL;DR for agents and humans

`dsh web` binds `127.0.0.1:3080` by design and **refuses `--host 0.0.0.0`**.
To use the UI from a phone over Tailscale, keep dsh on loopback and let
`tailscale serve` terminate HTTPS from your private tailnet and proxy to that
port. Only official flags are used (`--trusted-host`, `--no-open`, `--port`);
no dsh source or `node_modules` is touched, so rc upgrades are far less likely
to break.

## Key facts (machine-greppable)

| Fact | Value |
|------|-------|
| What it serves | DeepSeek Harness (`dsh`) Web UI |
| dsh bind | `127.0.0.1:3080` (loopback only, by design) |
| `--host 0.0.0.0` | **rejected by dsh** (do not use) |
| Remote access | Tailscale Serve (HTTPS on your tailnet) |
| Public internet | **never** (never `tailscale funnel`) |
| Required dsh flag | `--trusted-host <node>.tailXXXX.ts.net` |
| Launcher | `bash start-dsh-web.sh` |
| Hostname config | `local.conf` (gitignored) or `$DSH_TS_HOST` |
| First-use auth | visit `?token=...` URL once → 30-day signed cookie |
| Verified against | dsh `0.1.2-rc.1`, Tailscale `1.102.3`, Ubuntu 26.04 |

## Repo layout

```
start-dsh-web.sh        one-shot launcher (stop → start with trust flag → print URLs)
README.md               this file
README.zh.md            简体中文
docs/TROUBLESHOOTING.md auth/token internals, 401 vs 403, persistence, alternatives
local.conf              generated at --configure; gitignored (holds hostname)
LICENSE, SECURITY.md
```

## Why this architecture

DeepSeek Harness is a plugin-first agent harness whose Web UI can read files,
run shell commands, and write disk — a remote-code-execution surface. For that
reason dsh binds to loopback and refuses `--host 0.0.0.0`. You therefore cannot
use a phone browser straight at `http://<ip>:3080`; you need a tunnel.

**Tailscale Serve** is the least-moving-parts, tailnet-only option: it
terminates HTTPS, exposes only to your own devices, and proxies back to the
loopback port. The UI stays on loopback (smallest dsh attack surface) and dsh
internals stay untouched (rc upgrades don't break you). Cleaner/faster
alternatives exist (Cloudflare Tunnel + Access, zero-trust gateway plugin) but
are heavier; binding `0.0.0.0` + a password wall is explicitly less safe.

## Architecture

```
phone/desktop browser (tailnet)
      │  https://<node>.tailXXXX.ts.net/      (TLS by Serve)
      ▼
Tailscale Serve  (terminates HTTPS; no header injection here)
      │  plain HTTP proxy
      ▼
dsh web 127.0.0.1:3080   (the ONLY listener that can touch dsh)
```

## Prerequisites

- `dsh` on `PATH`, with a Web profile (`~/.dsh` present)
- Tailscale: logged in, node on your tailnet, **MagicDNS enabled**
- A `serve` route `https://<node>.tailXXXX.ts.net/` → `127.0.0.1:3080`
- Phone / other device on the **same tailnet**

## Quick start

```bash
# 0. Configure tailnet hostname once (find it via `tailscale status` → self node)
bash start-dsh-web.sh --configure '<node>.tailXXXX.ts.net'

# 1. Serve maps 3080 (needs sudo once, 443)
sudo tailscale serve --bg 3080
tailscale serve status          # verify

# 2. Launch dsh web for remote use
bash start-dsh-web.sh
#   prints:
#     Local access : http://127.0.0.1:3080/?token=...
#     Phone FIRST visit (exchanges token for a 30-day cookie):
#       https://<node>.tailXXXX.ts.net/?token=...
```

Phone (browser, tailnet): open the `?token=...` URL once → dsh mints a signed,
30-day cookie (persisted across dsh restarts). After that, `https://<node>.…/`
just works.

### Non-privileged port (no sudo)

```bash
tailscale serve --bg --https 8443 http://127.0.0.1:3080   # URL uses :8443
```

## Security

- Serve exposes only to your own tailnet — not the public internet.
- **Never** `tailscale funnel` — that exposes a shell-capable UI to the world.
- After first visit, the 30-day cookie is the access boundary; revoke = delete
  cookie.
- dsh's `/api` fence is anti-DNS-rebinding / cross-origin, **not** auth. Serve's
  private tailnet is your network-level auth. For per-identity auth see
  `docs/TROUBLESHOOTING.md → Alternatives` (`dsh-one-gateway`,
  `dsh-auth-tailscale`, read Serve's `Tailscale-User-Login` header).
- Before pushing a change, scan for real identifiers per `SECURITY.md`.

## Requirements

- Linux (verified Ubuntu 26.04 Desktop); pattern is cross-platform (macOS/WSL2).
- Node.js (dsh usually supplies its runtime).

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

DeepSeek Harness is a developer preview. Everything here is verified against a
specific dsh rc version and dsh APIs change fast. After an upgrade, re-check the
checklist in `docs/TROUBLESHOOTING.md`.

## Contributing

Open an issue or PR. Keep change-scans per `SECURITY.md`.