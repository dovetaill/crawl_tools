# AIO Proxy (FlareSolverr + Crawl4AI + WARP 出站) — README (v6.1)

> 方案B：**edge 公网（Nginx 反代 + BasicAuth）**，**WARP 仅出站**。  
> 一键安装，支持随时开关 WARP、修改密码、验证出口、刷新 WARP IP。  
> **v6.1 新增：安装期 WARP 自动回退策略**（见下文），确保在受限地区也能顺利完成安装与使用。

---

## 目录

- [架构与组件](#架构与组件)
- [一键安装](#一键安装)
- [日常使用（启停、日志、改密、改端口）](#日常使用启停日志改密改端口)
- [WARP：开/关、重启与刷新出口 IP](#warp开关重启与刷新出口-ip)
- [校验是否工作正常](#校验是否工作正常)
  - [校验服务可用性](#校验服务可用性)
  - [校验是否走 WARP](#校验是否走-warp)
- [自动回退策略（受限地区友好）](#自动回退策略受限地区友好)
- [常见问题与排查](#常见问题与排查)
- [安全建议](#安全建议)
- [卸载/清理](#卸载清理)
- [文件结构](#文件结构)
- [版本信息](#版本信息)

---

## 架构与组件

```

Internet  <--(BasicAuth)-->  edge(Nginx)  <--内部网-->  flaresolverr
|                      (8191)
+------------------>  crawl4ai
(11235)
+------------------>  warp (HTTP 8080 / SOCKS5 1080)

````

- **edge（Nginx, `nginx:alpine`）**：反向代理 + BasicAuth（htpasswd/bcrypt）。  
- **FlareSolverr（`flaresolverr/flaresolverr:latest`）**：挑战处理；WARP 开启时经 `PROXY_URL=http://warp:8080` 出站。  
- **Crawl4AI（`unclecode/crawl4ai:latest`）**：API + `/playground`；WARP 开启时经 `HTTP_PROXY/HTTPS_PROXY=http://warp:8080` 出站。  
- **WARP（`shahradel/cfw-proxy:latest`）**：仅供内部容器使用的上游代理；HTTP:8080 / SOCKS5:1080；支持 Warp+（可选）。  
- **网络**：统一 external 网络 `aio-proxy-net`（安装时自动创建）。

---

## 一键安装

> 运行于 Debian 系（root/sudo）。安装路径：`/opt/aio-proxy`。

### 开启 WARP（无 Warp+）

```bash
sudo bash -c '
  set -e;
  SCRIPT_URL="https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/main/install.sh?v=6.1";
  SCRIPT_PATH="/tmp/install_aio_proxy.sh";
  curl -sLf "$SCRIPT_URL" -o "$SCRIPT_PATH";
  chmod +x "$SCRIPT_PATH";
  "$SCRIPT_PATH" \
      "user" "passwd" "1234" \
      "user" "passwd" "12345" \
      "on";
  rm -f "$SCRIPT_PATH";
'
````

### 关闭 WARP

```bash
sudo bash -c '
  set -e;
  SCRIPT_URL="https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/main/install.sh?v=6.1";
  SCRIPT_PATH="/tmp/install_aio_proxy.sh";
  curl -sLf "$SCRIPT_URL" -o "$SCRIPT_PATH"; chmod +x "$SCRIPT_PATH";
  "$SCRIPT_PATH" "user" "passwd" "1234" "user" "passwd" "12345" "off";
  rm -f "$SCRIPT_PATH";
'
```

### 开启 WARP（带 Warp+）

```bash
sudo bash -c '
  set -e;
  SCRIPT_URL="https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/main/install.sh?v=6.1";
  SCRIPT_PATH="/tmp/install_aio_proxy.sh";
  curl -sLf "$SCRIPT_URL" -o "$SCRIPT_PATH"; chmod +x "$SCRIPT_PATH";
  "$SCRIPT_PATH" \
      "user" "passwd" "1234" \
      "user" "passwd" "12345" \
      "on" "YOUR_WARP_PLUS_KEY";
  rm -f "$SCRIPT_PATH";
'
```

**参数**：
1~3：FlareSolverr 的 `用户名 密码 对外端口`
4~6：Crawl4AI 的 `用户名 密码 对外端口`
7：WARP 开关（`on/off/true/false/1/0/yes/no`）
8：可选 Warp+ License Key（不传=不启用 Warp+）

---

## 日常使用（启停、日志、改密、改端口）

```bash
cd /opt/aio-proxy

# 启停与状态
./manage.sh start
./manage.sh stop
./manage.sh restart
./manage.sh ps
./manage.sh logs

# 修改 BasicAuth（加密写入 htpasswd，热重启 edge）
./manage.sh set-credentials flaresolverr NEW_USER NEW_PASS
./manage.sh set-credentials crawl4ai    NEW_USER NEW_PASS

# 修改对外端口
nano .env     # 改 FLARE_PUBLIC_PORT / CRAWL4AI_PUBLIC_PORT
./manage.sh restart
```

---

## WARP：开关、重启与刷新出口 IP

```bash
cd /opt/aio-proxy

# 开/关 WARP（自动重启全栈）
./manage.sh warp on
./manage.sh warp off

# 只重启 WARP（轻量“刷新”出口）
docker restart aio-proxy-warp-1

# 更强的刷新（不保证每次变 IP）
docker compose -f docker-compose.yml -f docker-compose.warp.yml down
docker compose -f docker-compose.yml -f docker-compose.warp.yml up -d

# 最强（清卷重建；Warp+ 会按同 License 重建）
docker compose -f docker-compose.yml -f docker-compose.warp.yml down -v
docker compose -f docker-compose.yml -f docker-compose.warp.yml up -d
```

---

## 校验是否工作正常

### 校验服务可用性

**FlareSolverr：**

```bash
curl --user "USER:PASS" -H "Content-Type: application/json" \
  -d '{"cmd":"request.get","url":"https://example.com","maxTimeout":20000}' \
  http://<host>:<FLARE_PORT>/v1
```

**Crawl4AI：**

```bash
curl -H "Content-Type: application/json" \
  -d '{"urls":["https://example.com"]}' \
  http://<host>:<CRAWL4AI_PORT>/crawl
```

### 校验是否走 WARP

**方法 A：Cloudflare trace（看 `warp=on/off`）**

* FlareSolverr：

```bash
curl --user "USER:PASS" -H "Content-Type: application/json" \
  -d '{"cmd":"request.get","url":"https://www.cloudflare.com/cdn-cgi/trace","maxTimeout":30000}' \
  http://<host>:<FLARE_PORT>/v1
```

* Crawl4AI：

```bash
curl -H "Content-Type: application/json" \
  -d '{"urls":["https://www.cloudflare.com/cdn-cgi/trace"]}' \
  http://<host>:<CRAWL4AI_PORT>/crawl
```

**方法 B：IP JSON（看 ASN/ORG 是否 Cloudflare/AS13335）**

* FlareSolverr：

```bash
curl --user "USER:PASS" -H "Content-Type: application/json" \
  -d '{"cmd":"request.get","url":"https://ipinfo.io/json","maxTimeout":30000}' \
  http://<host>:<FLARE_PORT>/v1
```

* Crawl4AI：

```bash
curl -H "Content-Type: application/json" \
  -d '{"urls":["https://ipinfo.io/json"]}' \
  http://<host>:<CRAWL4AI_PORT>/crawl
```

---

## 自动回退策略（受限地区友好）

一些地区/机房（例如**香港/土耳其/印尼**等）对 **WireGuard/UDP 或 Cloudflare WARP** 有策略限制，可能导致 WARP 在安装时无法握手成功，表现为：

* 业务容器解析得到 `warp` 主机，但 **连接 `warp:8080` 失败**；
* 请求 FlareSolverr/Crawl4AI 报错 `ERR_PROXY_CONNECTION_FAILED` 或 500。

**v6.1 的策略：**

1. 你选择 `WARP=on` 安装时，脚本会先按开启状态启动所有容器；
2. 紧接着进行**多次连通性检测**（探测 `warp:8080` 是否对外监听）；
3. **若检测失败**：脚本会 **自动把 `.env` 中 `WARP_ENABLED=true` 改为 `false`**，并自动重启为**直连**模式；
4. 安装**不会中断**，FlareSolverr、Crawl4AI 可正常使用；
5. 将来你可以在网络条件允许时执行 `./manage.sh warp on && ./manage.sh restart` 再次尝试启用。

> 这样，团队同事即便在受限的 VPS/地区也能“一键安装 → 可用”，不因 WARP 失败而影响工作。

---

## 常见问题与排查

**1）`ERR_PROXY_CONNECTION_FAILED`（FlareSolverr）**

* 查看容器间连通性（应解析到同一网络并能通 `warp:8080`）：

  ```bash
  docker exec aio-proxy-flaresolverr-1 sh -lc 'getent hosts warp && (echo | nc -vz warp 8080 >/dev/null 2>&1 && echo TCP_OK || echo TCP_FAIL)'
  docker exec aio-proxy-crawl4ai-1    sh -lc 'getent hosts warp && (echo | nc -vz warp 8080 >/dev/null 2>&1 && echo TCP_OK || echo TCP_FAIL)'
  ```
* 如受限，可 `./manage.sh warp off` 改为直连；或请求级临时改为 `socks5://warp:1080` 再测。

**2）Compose 网络冲突/告警**

* 已统一 external 网络。若手工误操作：

  ```bash
  docker network rm aio-proxy-net 2>/dev/null || true
  docker network create --driver bridge aio-proxy-net
  cd /opt/aio-proxy && ./manage.sh restart
  ```

**3）401 未授权**

* 用安装时的 BasicAuth；忘记就重置：

  ```bash
  ./manage.sh set-credentials flaresolverr NEW_USER NEW_PASS
  ./manage.sh set-credentials crawl4ai    NEW_USER NEW_PASS
  ```

**4）APT 锁冲突**

* v6.1 已自动等待 `dpkg lock`；若仍担心，可先让系统自动更新结束再执行安装。

---

## 安全建议

* 不把账号/密码写进仓库或 YAML；使用 `set-credentials` 动态改密（bcrypt htpasswd）。
* 仅对可信 IP 放行对外端口；如需 HTTPS，可再加一层反代或接入 Cloudflare。
* 定期更新镜像与系统补丁。

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

* **install.sh v6.1**

  * external 网络 `aio-proxy-net`；
  * APT 锁智能等待；
  * **WARP 自动回退策略**（受限地区自动直连，安装不中断）；
  * `manage.sh`：`warp on/off`、`set-credentials`、日志/状态等；
  * htpasswd 采用 **bcrypt**；默认时区 `Europe/Berlin`。

```

---
