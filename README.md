# AIO Proxy 参考手册（edge + flaresolverr）

## 1. 概览与能力边界

本项目提供一个最小化可运维的代理入口：

- 公网入口：`edge`（`nginx:alpine`）
- 核心服务：`flaresolverr`（`flaresolverr/flaresolverr:latest`）
- 认证方式：BasicAuth（bcrypt htpasswd）
- 编排方式：单一 `docker-compose.yml`

能力边界：

- 仅包含 `edge + flaresolverr` 两个服务。
- 仅维护一套单文件编排，不含多文件叠加编排。
- 安装脚本当前为“参数驱动 + Docker 交互确认”模式。

---

## 2. 架构与组件说明

```text
Internet --> edge (BasicAuth, :8081) --> flaresolverr (:8191)
```

组件说明：

- `edge`：对外暴露端口，处理 BasicAuth，反向代理到 `flaresolverr`。
- `flaresolverr`：处理目标站点请求。
- `backend` 网络：由 Compose 创建，名称 `aio-proxy-net`，类型 `bridge`。

---

## 3. 快速安装（交互 / 非交互）

### 3.1 前置条件

- Debian/Ubuntu 系统。
- 使用 `root`，或当前用户具备 `sudo` 能力。
- 已克隆本仓库并进入目录：`/home/wwwroot/crawl_tools`。

### 3.2 本地执行（推荐）

```bash
cd /home/wwwroot/crawl_tools
chmod +x install.sh install_docker.sh
sudo ./install.sh admin 'StrongPass123' 36584
```

执行过程中会进入 yes/no 菜单：

- 若未检测到 Docker：默认安装 Docker。
- 若检测到 Docker：默认不更新 Docker。

### 3.3 非交互执行

按默认策略执行（未安装则安装，已安装则不更新）：

```bash
sudo ./install.sh --yes admin 'StrongPass123' 36584
```

强制更新 Docker：

```bash
sudo ./install.sh --yes --update-docker admin 'StrongPass123' 36584
```

### 3.4 远程拉取安装脚本（可选）

```bash
sudo bash -c '
  set -e
  SCRIPT_URL="https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/master/install.sh"
  SCRIPT_PATH="/tmp/install_aio_proxy.sh"
  curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH"
  chmod +x "$SCRIPT_PATH"
  "$SCRIPT_PATH" --yes admin "StrongPass123" 36584
  rm -f "$SCRIPT_PATH"
'
```

---

## 4. 参数与默认值说明

### 4.1 `install.sh` 参数

```bash
install.sh [--yes] [--update-docker] <FLARE_USER> <FLARE_PASS> <FLARE_PORT>
```

参数说明：

- `--yes`：非交互模式，采用默认决策。
- `--update-docker`：强制执行 Docker 更新。
- `FLARE_USER`：BasicAuth 用户名。
- `FLARE_PASS`：BasicAuth 密码。
- `FLARE_PORT`：对外访问端口（映射到 `edge:8081`）。

### 4.2 默认值（脚本生成）

- 安装目录：`/opt/aio-proxy`
- 默认时区：`Europe/Berlin`
- 容器内部端口：`8191`
- Compose 网络名：`aio-proxy-net`

### 4.3 帮助命令

```bash
bash install.sh --help
bash install_docker.sh --help
```

---

## 5. 交互菜单说明（方向键 + 回退）

`install.sh` 的确认菜单支持：

- `↑/↓`：切换选项
- `Enter`：确认
- `q`：退出安装

当当前终端不支持菜单渲染时，会回退为数字输入：

- `1` 表示 `yes`
- `2` 表示 `no`
- `q` 退出

---

## 6. 日常运维

安装完成后，进入工作目录：

```bash
cd /opt/aio-proxy
```

常用命令：

```bash
./manage.sh start
./manage.sh stop
./manage.sh restart
./manage.sh ps
./manage.sh logs
```

修改 BasicAuth：

```bash
./manage.sh set-credentials NEW_USER NEW_PASS
```

修改对外端口：

```bash
sed -i 's/^FLARE_PUBLIC_PORT=.*/FLARE_PUBLIC_PORT=36585/' .env
./manage.sh restart
```

---

## 7. 验证与联调命令

### 7.1 容器状态与日志

```bash
cd /opt/aio-proxy
docker compose -f docker-compose.yml ps
docker compose -f docker-compose.yml logs --tail=200
```

### 7.2 API 可用性验证

```bash
curl --user "USER:PASS" \
  -H "Content-Type: application/json" \
  -d '{"cmd":"request.get","url":"https://example.com","maxTimeout":20000}' \
  http://<SERVER_IP>:<FLARE_PORT>/v1
```

预期：返回 JSON，包含 `status` 与 `solution` 等字段。

### 7.3 配置与产物检查

```bash
ls -la /opt/aio-proxy
cat /opt/aio-proxy/.env
```

---

## 8. Docker 安装与更新策略说明

`install.sh` 会调用同目录下的 `install_docker.sh`：

- `--action install`：安装 Docker 引擎与 Compose 插件。
- `--action update`：更新 Docker；若系统尚未安装则自动回退安装。

可单独调用：

```bash
sudo ./install_docker.sh --action install
sudo ./install_docker.sh --action update
sudo ./install_docker.sh --action update --yes
```

---

## 9. 常见问题与排查

### 9.1 401 Unauthorized

原因：BasicAuth 用户名或密码不匹配。

处理：

```bash
cd /opt/aio-proxy
./manage.sh set-credentials NEW_USER NEW_PASS
```

### 9.2 端口占用导致启动失败

定位占用：

```bash
ss -ltnp | grep ':36584' || true
```

处理：修改 `.env` 中 `FLARE_PUBLIC_PORT` 后重启。

### 9.3 `docker compose` 不可用

定位：

```bash
docker compose version
```

处理：

```bash
sudo ./install_docker.sh --action update
```

### 9.4 菜单显示异常

原因：终端不支持 `tput` 或非 TTY 场景。

处理：脚本会自动回退到数字输入；也可直接使用 `--yes`。

---

## 10. 卸载与清理

```bash
cd /opt/aio-proxy
./manage.sh stop || true
docker compose -f docker-compose.yml down -v || true
rm -rf /opt/aio-proxy
```

如需清理网络（确认无其他项目使用）：

```bash
docker network rm aio-proxy-net 2>/dev/null || true
```

---

## 11. 文件结构

```text
/opt/aio-proxy
├─ docker-compose.yml
├─ .env
├─ manage.sh
└─ nginx/
   ├─ nginx.conf
   └─ htpasswd_flaresolverr
```

---

## 12. 版本变更记录

- `2026-03-08`
- 安装流程收敛为 `edge + flaresolverr`。
- 文档改为参考手册结构。
- Docker 安装策略支持交互确认与参数覆盖（`--yes` / `--update-docker`）。
- 交互确认支持方向键菜单，非兼容终端自动回退数字输入。
