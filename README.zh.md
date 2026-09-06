# dsh-loopback-serve

**用手机远程访问 DeepSeek Harness(dsh)Web UI 的最小稳定方案——基于 Tailscale
Serve,dsh 永不离开本机回环。**

[English](README.md) · [简体中文](README.zh.md)

核心设计:

- dsh web 始终监听 `127.0.0.1:3080`(这是官方**有意为之**的安全默认——agent
  能跑 shell 命令、读写文件,官方因此拒绝 `--host 0.0.0.0`)。
- Tailscale Serve 在 tailnet 私有网内终结 HTTPS,再代理回这个回环端口。
- 全程只用 **官方、文档化** 的 dsh 参数(`--trusted-host` / `--no-open` /
  `--port`)。不 patch dsh 源码、不动 `node_modules` → dsh 每次 `rc` 升级都更
  不容易搞坏你。

## 为什么会有这个项目

DeepSeek Harness(`dsh`)是插件优先的 agent 框架。它的 Web UI 天生是
"远程代码执行面"——能读文件、跑 shell、写磁盘。因此官方:

- 默认把 UI 绑在回环(`127.0.0.1:3080`);
- 并**有意拒绝** `--host 0.0.0.0`。

所以你不能简单地让手机浏览器敲 `http://<ip>:3080`。你需要一条隧道。而
最安全、部件最少的就是 **Tailscale Serve**:它只把 `127.0.0.1:3080` 暴露在
**你自己的 tailnet 私有网**里,自动签 HTTPS 证书,完全不碰公网。dsh 保持回环,
Serve 是它前面唯一的对外监听。

社区里还有更花哨的玩法(Cloudflare Tunnel + Access、单独的零信任网关插件、
绑 `0.0.0.0` + 密码墙 + 防火墙收口)。有的同样安全但更重;绑 `0.0.0.0` 那种
明确更不安全。本项目刻意选择 **回环 + Serve**,因为它既把 dsh 自身攻击面
压到最小,又能在 dsh 版本升级时活下来,不用你反复重打补丁。

## 结构

```
手机/电脑(浏览器,在你自己的 tailnet 里)
        │  https://<节点>.tailXXXX.ts.net/   (TLS 由 Serve 终结)
        ▼
Tailscale Serve(终结 HTTPS,这里不注入任何东西)
        │  明文 HTTP 代理
        ▼
dsh web on 127.0.0.1:3080   (唯一能碰到 dsh 的监听)
```

dsh 唯一需要加的参数是 `--trusted-host <节点>.tailXXXX.ts.net`,让它的
`/api` 请求信任围栏接受 tailnet 的 Origin/Host(否则 403)。

## 内容

- [`start-dsh-web.sh`](start-dsh-web.sh) —— 一键启动器:停掉旧实例 → 带信任
  参数启动 dsh web → 打印本机 URL 和手机**首次访问** URL(token → 30 天 cookie
  兑换)。
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) —— 认证/token 机制、
  401 与 403 的区别、如何持久化 trusted-host、备选方案。
- `local.conf`(自动生成、已 gitignore)—— 存你的 tailnet 主机名。

## 前置条件

- `dsh` 已安装且在 `PATH` 上(已存在 Web profile,`~/.dsh`)
- 本机 Tailscale:已登录、节点在 tailnet 上、**MagicDNS 已开启**
- 有一条 `serve` 路由:`https://<节点>.tailXXXX.ts.net/` → `127.0.0.1:3080`
- 手机/其它设备在**同一个 tailnet**

## 快速开始

```bash
# 0. 一次性:记住或配置你的 tailnet 主机名
#    (用 tailscale status 查看  → self 节点: <name>.<tail>.ts.net)
bash start-dsh-web.sh --configure '<节点>.tailXXXX.ts.net'

# 1. 建立 Serve 映射到 3080(只需一次 sudo,绑 443)
sudo tailscale serve --bg 3080
#    验证:
tailscale serve status

# 2. 启动 dsh web 供远程使用
bash start-dsh-web.sh
#    会打印:
#      Local access : http://127.0.0.1:3080/?token=...
#      Phone FIRST visit (exchanges token for a 30-day cookie):
#        https://<节点>.tailXXXX.ts.net/?token=...
```

手机上(浏览器,同一个 tailnet):

1. 打开 `https://<节点>.tailXXXX.ts.net/?token=...` **一次** → dsh 签发一个
   **30 天有效**的签名 cookie,重启 dsh 也不失效。
2. 之后直接打开 `https://<节点>.tailXXXX.ts.net/` 即可。

> cookie 一旦设好,dsh 本身可以随便停/重启,手机在 cookie 过期前(或换浏览器
> 前)一直能用。

### 非特权端口(可选)

不想用 `sudo`(443)的话:

```bash
tailscale serve --bg --https 8443 http://127.0.0.1:3080
# 你的 URL 变成 https://<节点>.tailXXXX.ts.net:8443/
```

## 安全说明

- Serve 只把 UI 暴露给**你自己的 tailnet 设备**——不出公网。这本身就比公网
  隧道强一档。
- **永远不要**为它用 `tailscale funnel`。dsh web 能跑 shell、写文件;把它暴露
  到公网,等于把远程代码执行交给任何拿到 URL 的人。
- 首次访问后,手机的 30 天 cookie 就是实际访问边界。按此对待;撤销 = 清掉
  浏览器 cookie。
- dsh 的 `/api` 围栏是防 DNS rebinding / 跨站的护栏,**不是**鉴权层。Serve 的
  私有 tailnet 才是你网络层的认证。若需要"按身份授权",看
  `dsh-one-gateway` / `dsh-auth-tailscale`(读 Serve 注入的
  `Tailscale-User-Login` 头),见 TROUBLESHOOTING §备选方案。

## 环境/依赖

- Linux(已在 Ubuntu 26.04 Desktop 验证),但思路跨平台;Tailscale + dsh web
  在 macOS/WSL2 行为一致。
- Node.js(dsh 通常自带运行环境)。

## License

MIT —— 见 [LICENSE](LICENSE)。

## 免责声明

DeepSeek Harness 是 developer preview。**这里的一切都针对某个具体的 dsh
`rc` 版本验证过**,而 dsh API 变得很快。在 dsh 升级后依赖本方案前,请重验:
`dsh web` 能否启动、trust 参数是否仍生效、手机是否还能加载。见
`docs/TROUBLESHOOTING.md` 的核对清单。