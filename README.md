# AIO Proxy & Scraper Suite (一体化代理与抓取套件) - v3.0

这是一个通过一键安装脚本部署的“All-in-One”解决方案，集成了多个强大的开源工具，为您提供一个稳定、可靠且受密码保护的网页抓取和代理环境。所有服务的出站流量都将通过 Cloudflare WARP 路由，有效隐藏服务器的真实 IP 地址并绕过部分网络限制。

该文档为最新版本，包含了从安装、使用、日常管理到高级 IP 控制的全部内容。

---

## 目录

* [架构与组件](#架构与组件)
* [一键安装](#一键安装)
* [日常使用（启停、重启、日志、改密、改端口）](#日常使用启停重启日志改密改端口)
* [WARP：开关、重启与刷新出口 IP](#warp开关重启与刷新出口-ip)
* [校验是否工作正常](#校验是否工作正常)

  * [校验服务是否可用](#校验服务是否可用)
  * [校验是否走 WARP](#校验是否走-warp)
* [常见问题与排查](#常见问题与排查)
* [安全建议](#安全建议)
* [卸载/清理](#卸载清理)
* [文件结构](#文件结构)
* [版本信息](#版本信息)

---

## 架构与组件

```
Internet  <--(BasicAuth)-->  edge(Nginx)  <--内部网-->  flaresolverr
                                   |                      (8191)
                                   +------------------>  crawl4ai
                                                         (11235)
                                   +------------------>  warp (HTTP 8080 / SOCKS5 1080)
```

* **edge（Nginx, `nginx:alpine`）**

  * 反向代理到内部服务，提供 **HTTP 基本认证**（htpasswd / bcrypt）。
  * 对外端口：`.env` 中 `FLARE_PUBLIC_PORT`（默认示例：1234）、`CRAWL4AI_PUBLIC_PORT`（默认示例：12345）。

* **FlareSolverr（`flaresolverr/flaresolverr:latest`）**

  * 端口 8191（容器内），对抗挑战；当 WARP 开启时通过 `PROXY_URL=http://warp:8080` 出站。

* **Crawl4AI（`unclecode/crawl4ai:latest`）**

  * 端口 11235（容器内），/playground 可视化；当 WARP 开启时通过 `HTTP_PROXY/HTTPS_PROXY=http://warp:8080` 出站。

* **WARP（`shahradel/cfw-proxy:latest`）**

  * 仅供**内部**容器作为上游代理；HTTP 8080 / SOCKS5 1080；支持可选 `WGCF_LICENSE_KEY`（Warp+）。

* **网络**

  * 使用 **external** 网络 `aio-proxy-net`（脚本会自动创建），所有容器加入同一网络，保证 `warp:8080` 可达。

---

## 一键安装

> 要求：Debian 系（root/sudo），确保对外端口未被占用。
> 安装路径：`/opt/aio-proxy`（脚本自动创建）。

### 1）开启 WARP（无 Warp+）

```bash
sudo bash -c '
  set -e;
  SCRIPT_URL="https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/main/install.sh?v=6";
  SCRIPT_PATH="/tmp/install_aio_proxy.sh";
  curl -sLf "$SCRIPT_URL" -o "$SCRIPT_PATH";
  chmod +x "$SCRIPT_PATH";
  "$SCRIPT_PATH" \
      "user" "passwd" "1234" \
      "user" "passwd" "12345" \
      "on";
  rm -f "$SCRIPT_PATH";
'
```

### 2）关闭 WARP

```bash
sudo bash -c '
  set -e;
  SCRIPT_URL="https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/main/install.sh?v=6";
  SCRIPT_PATH="/tmp/install_aio_proxy.sh";
  curl -sLf "$SCRIPT_URL" -o "$SCRIPT_PATH"; chmod +x "$SCRIPT_PATH";
  "$SCRIPT_PATH" "user" "passwd" "1234" "user" "passwd" "12345" "off";
  rm -f "$SCRIPT_PATH";
'
```

### 3）开启 WARP（带 Warp+）

```bash
sudo bash -c '
  set -e;
  SCRIPT_URL="https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/main/install.sh?v=6";
  SCRIPT_PATH="/tmp/install_aio_proxy.sh";
  curl -sLf "$SCRIPT_URL" -o "$SCRIPT_PATH"; chmod +x "$SCRIPT_PATH";
  "$SCRIPT_PATH" \
      "user" "passwd" "1234" \
      "user" "passwd" "12345" \
      "on" "YOUR_WARP_PLUS_KEY";
  rm -f "$SCRIPT_PATH";
'
```

**参数说明**
1~3：FlareSolverr 的 `用户名 密码 对外端口`
4~6：Crawl4AI 的 `用户名 密码 对外端口`
7：WARP 开关（`on/off/true/false/1/0/yes/no`）
8：可选 Warp+ License Key（不传 = 不启用 Warp+）

---

## 日常使用（启停、重启、日志、改密、改端口）

工作目录：`/opt/aio-proxy`

```bash
cd /opt/aio-proxy

# 启停与状态
./manage.sh start
./manage.sh stop
./manage.sh restart
./manage.sh ps
./manage.sh logs

# 修改 BasicAuth（不会写入明文，只更新 htpasswd 并热重启 Nginx）
./manage.sh set-credentials flaresolverr NEW_USER NEW_PASS
./manage.sh set-credentials crawl4ai    NEW_USER NEW_PASS

# 修改对外端口（编辑 .env 后重启）
nano .env
# 改 FLARE_PUBLIC_PORT / CRAWL4AI_PUBLIC_PORT
./manage.sh restart
```

---

## WARP：开关、重启与刷新出口 IP

```bash
cd /opt/aio-proxy

# 开/关 WARP（自动重启全栈）
./manage.sh warp on
./manage.sh warp off

# 重启 WARP（最轻量的刷新出口方式：重启 warp 容器或全栈重启）
docker restart aio-proxy-warp-1
# 或
./manage.sh restart

# 更强的刷新（可能会拿到新出口；不保证每次都变）
docker compose -f docker-compose.yml -f docker-compose.warp.yml down
docker compose -f docker-compose.yml -f docker-compose.warp.yml up -d

# 最强（清卷重拉，可能重置身份；如启用 Warp+ 会用同一 License 重建）
docker compose -f docker-compose.yml -f docker-compose.warp.yml down -v
docker compose -f docker-compose.yml -f docker-compose.warp.yml up -d
```

> 提示：Cloudflare 分配出口有一定复用概率，**“刷新 ≠ 每次必变”**。

---

## 校验是否工作正常

### 校验服务是否可用

**FlareSolverr 快速测试**（需 BasicAuth）：

```bash
curl --user "user:passwd" \
  -H "Content-Type: application/json" \
  -d '{"cmd":"request.get","url":"https://example.com","maxTimeout":20000}' \
  http://<你的IP或域名>:1234/v1
```

**Crawl4AI 快速测试**：

```bash
curl -H "Content-Type: application/json" \
  -d '{"urls":["https://example.com"]}' \
  http://<你的IP或域名>:12345/crawl
```

### 校验是否走 WARP

**方法 A：Cloudflare trace（看 `warp=on/off`）**

* FlareSolverr：

```bash
curl --user "user:passwd" \
  -H "Content-Type: application/json" \
  -d '{"cmd":"request.get","url":"https://www.cloudflare.com/cdn-cgi/trace","maxTimeout":30000}' \
  http://<你的IP或域名>:1234/v1
```

在返回体的 `solution.response` 文本中找到：

```
ip=xxx.xxx.xxx.xxx
warp=on        # ← 走 WARP
# 或 warp=off  # ← 未走 WARP
```

* Crawl4AI：

```bash
curl -H "Content-Type: application/json" \
  -d '{"urls":["https://www.cloudflare.com/cdn-cgi/trace"]}' \
  http://<你的IP或域名>:12345/crawl
```

**方法 B：IP JSON（看 ASN/ORG 是否 Cloudflare/AS13335）**

* FlareSolverr：

```bash
curl --user "user:passwd" \
  -H "Content-Type: application/json" \
  -d '{"cmd":"request.get","url":"https://ipinfo.io/json","maxTimeout":30000}' \
  http://<你的IP或域名>:1234/v1
```

返回 JSON 里若出现 `AS13335` / `Cloudflare, Inc.`，基本可认定走 WARP。

* Crawl4AI：

```bash
curl -H "Content-Type: application/json" \
  -d '{"urls":["https://ipinfo.io/json"]}' \
  http://<你的IP或域名>:12345/crawl
```

> **A/B 对比建议**：
> 1）`./manage.sh warp off && ./manage.sh restart` → 看直连出口；
> 2）`./manage.sh warp on && ./manage.sh restart` → 再看是否变为 Cloudflare/AS13335。

---

## 常见问题与排查

**1）`ERR_PROXY_CONNECTION_FAILED`（FlareSolverr）**

* 多半是业务容器访问 `warp:8080` 失败。检查：

  ```bash
  # FlareSolverr → warp 连接性
  docker exec aio-proxy-flaresolverr-1 sh -lc 'getent hosts warp && (echo | nc -vz warp 8080 >/dev/null 2>&1 && echo TCP_OK || echo TCP_FAIL)'
  # Crawl4AI → warp 连接性
  docker exec aio-proxy-crawl4ai-1    sh -lc 'getent hosts warp && (echo | nc -vz warp 8080 >/dev/null 2>&1 && echo TCP_OK || echo TCP_FAIL)'
  ```
* 确认所有容器在同一 **external** 网络 `aio-proxy-net`：
  `docker network inspect aio-proxy-net`

**2）Compose 网络警告/报错（external 标签）**

* 脚本 v6 已统一使用 external 网络。若手工操作异常：

  ```bash
  docker network rm aio-proxy-net 2>/dev/null || true
  docker network create --driver bridge aio-proxy-net
  cd /opt/aio-proxy && ./manage.sh restart
  ```

**3）401 未授权**

* 使用安装时设置的 BasicAuth。忘记就重置：

  ```bash
  ./manage.sh set-credentials flaresolverr NEW_USER NEW_PASS
  ./manage.sh set-credentials crawl4ai    NEW_USER NEW_PASS
  ```

**4）目标站直连可用、走 WARP 不可用**

* 可能是目标站对 WARP 段限流/封禁：

  * 临时 `./manage.sh warp off`；
  * 或把代理协议换成 `socks5://warp:1080`（FlareSolverr 可在请求体里 `proxy.url` 覆盖）。

**5）端口被占用**

* 修改 `.env` 的 `FLARE_PUBLIC_PORT` / `CRAWL4AI_PUBLIC_PORT`，然后 `./manage.sh restart`。

---

## 安全建议

* 不把账户/密码写进仓库或 YAML；本项目使用 **htpasswd(bcrypt)**，可随时 `set-credentials` 改密。
* 在防火墙/安全组层面仅放行可信来源 IP。
* 如需 HTTPS，可在前面再加一层反代（Caddy/Traefik/Nginx）或挂到 Cloudflare。

---

## 卸载/清理

```bash
cd /opt/aio-proxy
./manage.sh stop
docker compose -f docker-compose.yml -f docker-compose.warp.yml down -v || docker compose -f docker-compose.yml down -v
docker network rm aio-proxy-net 2>/dev/null || true
rm -rf /opt/aio-proxy
```

---

## 文件结构

```
/opt/aio-proxy
├─ docker-compose.yml            # backend: external aio-proxy-net
├─ docker-compose.warp.yml       # warp 服务 + 代理注入
├─ .env                          # 端口/WARP 开关/Warp+ Key/时区
├─ manage.sh                     # 启停/日志/改密/warp on|off
└─ nginx/
   ├─ nginx.conf                 # 反代 + BasicAuth
   ├─ htpasswd_flaresolverr      # bcrypt
   └─ htpasswd_crawl4ai          # bcrypt
```

---

## 版本信息

* **install.sh v6**（推荐）

  * 统一 external 网络 `aio-proxy-net`，避免 Compose 标签冲突；
  * 所有容器加入同一网络，WARP 可被 `warp:8080` 访问；
  * `manage.sh` 内置 `warp on|off`、`set-credentials`、日志/状态等；
  * htpasswd 采用 **bcrypt**；默认时区 `Europe/Berlin`。
