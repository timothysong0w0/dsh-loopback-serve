# Security

**DeepSeek Harness web UI is a remote-code-execution surface.** It can read
files, run shell commands, and write disk. Treat its exposure very conservatively.

## Do not

- **Never use `tailscale funnel`** (or any public tunnel) for dsh web. Exposing
  it to the public internet hands remote code execution to anyone who reaches
  the URL.
- **Do not bind `--host 0.0.0.0`.** The maintainers deliberately reject it for a
  reason. Keep dsh on loopback and let Tailscale Serve terminate HTTPS.
- **Do not commit real identifiers.** This repo uses placeholders like
  `<node>.tailXXXX.ts.net` and `<节点>` on purpose. If you copy it, never
  replace them with your actual tailnet hostname, tailnet name, machine name,
  or IP and then push — it stays in git history.
- **Do not commit `local.conf`** or any file containing a real `?token=...`
  URL or API key. `local.conf` is gitignored precisely for this.

## Before pushing a change

Run a scan and confirm it is empty:

```bash
grep -rniE "tail[0-9a-f]{6}\.ts\.net|customhostname|100\.[0-9]+\.[0-9]+\.[0-9]+" .
```

(Adjust patterns to match your own real identifiers.)

## Recommended hardening (optional)

- The /api fence is an anti-DNS-rebinding guard, **not** authentication.
  Network-level protection is Serve's private tailnet. If you need per-identity
  authorization, put a zero-trust gateway in front (see
  `docs/TROUBLESHOOTING.md` → Alternatives): e.g. `dsh-one-gateway`.
- Keep dsh up to date; dsh is a developer preview and security fixes land with
  rc releases.

## Reporting

For issues in this repo, open a GitHub issue. For issues in DeepSeek Harness
itself, report upstream to `deepseek-ai/deepseek-harness`.