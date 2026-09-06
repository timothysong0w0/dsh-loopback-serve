# dsh-loopback-serve

**Minimal, upgrade-safe remote access to the DeepSeek Harness (dsh) Web UI
from your phone over Tailscale Serve — dsh never leaves loopback.**

[English](README.md) · [简体中文](README.zh.md)

At a glance:

- dsh web keeps listening on `127.0.0.1:3080` (its **intentional** secure
  default — the maintainers refuse `--host 0.0.0.0` because an agent that can
  run shell commands must not be exposed on a network).
- Tailscale Serve terminates HTTPS from the tailnet and proxies back to that
  loopback port.
- Only **official, documented dsh flags** are used
  (`--trusted-host`, `--no-open`, `--port`). No dsh source is patched, no
  `node_modules` is edited → dsh `rc` upgrades are far less likely to break you.

## Why this exists

DeepSeek Harness (`dsh`) is a plugin-first agent harness. Its Web UI is a
remote-code-execution surface by design — it can read files, run shell
commands and write disk. The maintainers therefore:

- bind the UI to loopback (`127.0.0.1:3080`) by default, and
- deliberately reject `--host 0.0.0.0`.

So you cannot simply point a phone browser at `http://<ip>:3080`. You need a
tunnel. The safest and least-moving-parts option is **Tailscale Serve**: it
exposes `127.0.0.1:3080` on your *private tailnet* only, issues an HTTPS cert
automatically, and never touches the public internet. The UI stays on
loopback; Serve is the only off-host listener in front of it.

There are fancier setups (Cloudflare Tunnel + Access, a separate zero-trust
gateway plugin, bind `0.0.0.0` + a password wall + firewall scoping). Some are
equally safe but heavier; one (`0.0.0.0`) is explicitly less safe. This
project deliberately chooses the **loopback + Serve** shape because it keeps
dsh's own attack surface minimal **and** survives dsh releases without you
re-applying patches.

## Architecture

```
phone/desktop (browser, on your tailnet)
        │  https://<node>.tailXXXX.ts.net/   (TLS terminated by Serve)
        ▼
Tailscale Serve (terminates HTTPS, injects nothing here)
        │  plain HTTP proxy
        ▼
dsh web on 127.0.0.1:3080   (the ONLY listener that can touch dsh)
```

The one extra flag dsh needs is `--trusted-host <node>.tailXXXX.ts.net` so its
`/api` request-trust fence accepts the tailnet Origin/Host instead of 403ing it.

## Contents

- [`start-dsh-web.sh`](start-dsh-web.sh) — one-shot launcher: stops a previous
  instance, starts dsh web with the trust flag, prints the local URL **and** the
  phone's FIRST-visit URL (token → 30-day cookie exchange).
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — the auth/token
  mechanism, the 401 vs 403 distinction, and how to persist trusted-host.
- `local.conf` (generated, gitignored) — holds your tailnet hostname.

## Prerequisites

- `dsh` installed and on `PATH` (a Web profile, `~/.dsh`, present)
- Tailscale on the host: logged in, node on your tailnet, **MagicDNS enabled**
- A `serve` route from `https://<node>.tailXXXX.ts.net/` to `127.0.0.1:3080`
- Phone / other machine on the **same tailnet**

## Quick start

```bash
# 0. One-time: remember or configure your tailnet hostname
#    (find it with: tailscale status  →  self node:  <name>.<tail>.ts.net)
bash start-dsh-web.sh --configure '<node>.tailXXXX.ts.net'

# 1. Make sure Serve maps 3080 (needs sudo once; 443)
sudo tailscale serve --bg 3080
#    verify:
tailscale serve status

# 2. Launch dsh web for remote use
bash start-dsh-web.sh
#    prints:
#      Local access : http://127.0.0.1:3080/?token=...
#      Phone FIRST visit (exchanges token for a 30-day cookie):
#        https://<node>.tailXXXX.ts.net/?token=...
```

On the phone (browser, same tailnet):

1. Open the `https://<node>.tailXXXX.ts.net/?token=...` URL once → dsh mints a
   signed cookie **valid 30 days**, persisted across dsh restarts.
2. From then on, just open `https://<node>.tailXXXX.ts.net/`.

> After the cookie is set, dsh itself can be stopped/restarted freely and your
> phone keeps working until the cookie expires (or you use a new browser).

### Non-privileged port (optional)

If you don't want `sudo` (443):

```bash
tailscale serve --bg --https 8443 http://127.0.0.1:3080
# your URL becomes https://<node>.tailXXXX.ts.net:8443/
```

## Security notes

- Serve exposes the UI to your **own tailnet devices only** — not the public
  internet. That is already one order stronger than a public tunnel.
- **Never** use `tailscale funnel` for this. dsh web can run shell commands and
  write files; exposing it to the public internet is remote code execution for
  anyone who reaches the URL.
- The phone's 30-day cookie is the effective access boundary after the first
  visit. Treat it accordingly; revoke by deleting the browser cookie.
- dsh's `/api` fence is an anti-DNS-rebinding / cross-origin guard, **not** an
  authentication layer. Serve's private tailnet IS your network-level auth.
  If you need per-identity authorization, consider `dsh-one-gateway` /
  `dsh-auth-tailscale` (see TROUBLESHOOTING §Alternatives), which read the
  `Tailscale-User-Login` header Serve injects.

## Requirements / environment

- Linux (tested on Ubuntu 26.04 Desktop), but the pattern is cross-platform;
  Tailscale + dsh web behave the same on macOS/WSL2.
- Node.js (dsh supplies its own runtime usually).

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

DeepSeek Harness is a developer preview. **Everything here is verified against
a specific dsh `rc` version** and dsh APIs change fast. Before trusting this
after a dsh upgrade, re-check: does `dsh web` still boot, does the trust flag
still work, does the phone still load. See `docs/TROUBLESHOOTING.md` for the
verification checklist.