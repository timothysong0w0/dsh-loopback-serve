# dsh-loopback-serve

[English](README.md) · [简体中文](README.zh.md)

**用手机远程访问 DeepSeek Harness(dsh)Web UI 的最小稳定方案——基于 Tailscale
Serve,dsh 永不离开本机回环。**

---

## 一句话概述(人和 AI 都适用)

`dsh web` 默认绑定 `127.0.0.1:3080`,并**有意拒绝 `--host 0.0.0.0`**。要在手机
上经 Tailscale 使用 UI:保持 dsh 在回环,让 `tailscale serve` 在你私有 tailnet
里终结 HTTPS,再代理回这个端口。全程只用官方参数(`--trusted-host` /
`--no-open` / `--port`);不碰 dsh 源码或 `node_modules`,所以 rc 升级极不容易
坏。

## 关键事实(方便机器检索)

| 事实 | 值 |
|------|-----|
| 服务对象 | DeepSeek Harness(`dsh`)Web UI |
| dsh 绑定 | `127.0.0.1:3080`(仅回环,设计如此) |
| `--host 0.0.0.0` | **dsh 拒绝**(勿用) |
| 远程访问 | Tailscale Serve(tailnet 内 HTTPS) |
| 公网 | **绝不**(绝不用 `tailscale funnel`) |
| 必需 dsh 参数 | `--trusted-host <节点>.tailXXXX.ts.net` |
| 启动器 | `bash start-dsh-web.sh` |
| 主机名配置 | `local.conf`(gitignored)或 `$DSH_TS_HOST` |
| 首次鉴权 | 访问一次 `?token=...` URL → 30 天签名 cookie |
| 已验证版本 | dsh `0.1.2-rc.1`、Tailscale `1.102.3`、Ubuntu 26.04 |

## 仓库结构

```
start-dsh-web.sh        一键启动器(停旧→带信任参数启动→打印 URL)
README.md               本文件(英文)
README.zh.md            简体中文
docs/TROUBLESHOOTING.md 认证/token 内幕、401 vs 403、持久化、备选方案、开机自启
local.conf              --configure 生成;gitignored(存主机名)
LICENSE, SECURITY.md
```

## 为什么是这种架构

DeepSeek Harness 是插件优先的 agent 框架,其 Web UI 能读文件、跑 shell、
写磁盘——天生是"远程代码执行面"。因此 dsh 绑定回环并拒绝 `--host 0.0.0.0`。
你不能让手机浏览器直接敲 `http://<ip>:3080`,必须走隧道。

**Tailscale Serve** 是部件最少、且只在 tailnet 内的方案:终结 HTTPS,只暴露给
你自己设备,再代理回回环端口。UI 保持回环(dsh 攻击面最小),dsh 内部不被改动
(rc 升级不坏)。更花哨的替代(Cloudflare Tunnel + Access、零信任网关插件)同样
安全但更重;绑 `0.0.0.0` + 密码墙则明确更不安全。

## 结构

```
手机/电脑浏览器(tailnet)
      │  https://<节点>.tailXXXX.ts.net/      (TLS 由 Serve)
      ▼
Tailscale Serve  (终结 HTTPS;此处不注入任何东西)
      │  明文 HTTP 代理
      ▼
dsh web 127.0.0.1:3080   (唯一能碰到 dsh 的监听)
```

## 前置条件

- `dsh` 在 `PATH` 上,已有 Web profile(`~/.dsh`)
- Tailscale:已登录、节点在 tailnet、**MagicDNS 已开启**
- 有 `serve` 路由 `https://<节点>.tailXXXX.ts.net/` → `127.0.0.1:3080`
- 手机/其它设备在**同一 tailnet**

## 快速开始

```bash
# 0. 一次性配置 tailnet 主机名(用 tailscale status 看 self 节点)
bash start-dsh-web.sh --configure '<节点>.tailXXXX.ts.net'

# 1. Serve 映射 3080(只需一次 sudo,绑 443)
sudo tailscale serve --bg 3080
tailscale serve status          # 验证

# 2. 启动 dsh web 供远程使用
bash start-dsh-web.sh
#   会打印:
#     Local access : http://127.0.0.1:3080/?token=...
#     Phone FIRST visit (exchanges token for a 30-day cookie):
#       https://<节点>.tailXXXX.ts.net/?token=...
```

手机(浏览器,tailnet):打开 `?token=...` URL **一次** → dsh 签发 30 天签名
cookie(重启 dsh 仍有效)。之后直接开 `https://<节点>.…/` 即可。

### 本机浏览器同样要先认证一次

浏览器认证对**任何来源**都生效,包括本机自己的 `127.0.0.1:3080`。如果你
裸开 `127.0.0.1:3080` 看到 `dsh web authentication required; reopen the URL
printed by dsh web`,这正常——必须先带 token 访问一次:

```
http://127.0.0.1:3080/?token=<当前token>
```

之后裸开 `http://127.0.0.1:3080/` 该浏览器 30 天内直接可用。

### 查询当前 token(含 systemd 自启场景)

dsh web 由 systemd 用户服务(`dsh-web.service`)自启时,URL 不打在终端,
而是进 journal。从这里读:

```bash
journalctl --user -u dsh-web.service --no-pager | grep -oE 'token=[A-Za-z0-9_-]*' | tail -1
```

(`start-dsh-web.sh` 启动器则会直接打印。)每次启动 dsh web 都会生成新
token,重启后要重读。完整认证模型见 `docs/TROUBLESHOOTING.md`。

### 日常操作(启动 / 停止 / 重启)

dsh web 有两种跑法——启动脚本,和 systemd 开机自启服务。按你用的那个来:

**A. systemd 用户服务(开机自启)**

```bash
systemctl --user status  dsh-web.service    # 是否在跑?(→ active)
systemctl --user restart dsh-web.service    # 重启(会生成新 token)
systemctl --user stop    dsh-web.service    # 停止(手机直到启动前都连不上)
systemctl --user start   dsh-web.service    # 再次启动
systemctl --user disable --now dsh-web.service   # 关闭开机自启
journalctl --user -u dsh-web.service --no-pager | grep -oE 'token=[A-Za-z0-9_-]*' | tail -1   # 当前 token
```

服务配置了 `Restart=on-failure`(崩溃自动拉起),上面的手动命令是给你主动
控制或换新 token 用的。

**B. 启动脚本(手动,无自启)**

```bash
bash start-dsh-web.sh            # 启动(打印本机+手机 URL 及 token)
pkill -f "dsh web --trusted-host <节点>.tailXXXX.ts.net"   # 停止
```

**每次重启之后**

token 会变。重读它(`journalctl` 或脚本输出),并让手机/浏览器**只在**
30 天 cookie 已过期、或换了新浏览器时,再重新做一次 `?token=` 兑换。

### 非特权端口(免 sudo)

```bash
tailscale serve --bg --https 8443 http://127.0.0.1:3080   # URL 用 :8443
```

## 安全

- Serve 只暴露给你自己的 tailnet——不出公网。
- **绝不要** `tailscale funnel`——那会把能跑 shell 的 UI 暴露给全世界。
- 首次访问后,30 天 cookie 就是访问边界;撤销 = 删 cookie。
- dsh 的 `/api` 围栏是防 DNS rebinding / 跨站,**不是**鉴权。Serve 的私有
  tailnet 才是你网络层的认证。需要"按身份授权"见
  `docs/TROUBLESHOOTING.md → 备选方案`(`dsh-one-gateway`、
  `dsh-auth-tailscale`,读 Serve 注入的 `Tailscale-User-Login` 头)。
- push 前先按 `SECURITY.md` 扫描真实标识符。

## 环境

- Linux(已验证 Ubuntu 26.04 Desktop);思路跨平台(macOS/WSL2)。
- Node.js(dsh 通常自带运行环境)。

## License

MIT —— 见 [LICENSE](LICENSE)。

## 免责声明

DeepSeek Harness 是 developer preview。这里的一切都针对某个具体 dsh rc 版本
验证过,而 dsh API 变得很快。升级后请按 `docs/TROUBLESHOOTING.md` 的核对清单
重验。

## 贡献

提 issue 或 PR。改动前按 `SECURITY.md` 做真实标识符扫描。