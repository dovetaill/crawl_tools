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
- 安装脚本支持“双模式”：
  - 无参数：进入菜单式交互控制台。
  - 传参数：执行命令行安装流程（适合自动化）。

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

### 3.2 菜单模式（推荐）

```bash
cd /home/wwwroot/crawl_tools
chmod +x install.sh install_docker.sh
sudo ./install.sh
```

无参数会进入交互式管理菜单，可执行：

- 查看当前配置（用户名、端口、安装状态、服务状态）
- 全新安装 / 重装
- 修改账号密码
- 修改对外端口
- 启动 / 停止 / 重启 / 查看状态 / 查看日志
- 卸载删除服务

说明：

- 密码以哈希存储，菜单不会显示明文密码。
- Docker 安装/更新确认会进入 yes/no 选择菜单。
- 在“全新安装 / 重装”中，用户名、密码、端口留空会自动随机生成。
- 安装完成后会输出本次实际账号、密码、端口，便于立即记录。

### 3.3 参数模式（适合自动化）

传参时会走 CLI 安装流程，必须提供：
`<FLARE_USER> <FLARE_PASS> <FLARE_PORT>`

交互确认 Docker（未安装默认安装，已安装默认不更新）：

```bash
sudo ./install.sh admin 'StrongPass123' 36584
```

按默认策略执行（未安装则安装，已安装则不更新）：

```bash
sudo ./install.sh --yes admin 'StrongPass123' 36584
```

强制更新 Docker：

```bash
sudo ./install.sh --yes --update-docker admin 'StrongPass123' 36584
```

### 3.4 远程拉取脚本执行（可选）

新手极简模式（推荐）：

```bash
curl -fsSL "https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/master/install.sh" | sudo bash -s -- --quick
```

说明：

- `--quick` 会自动生成账号/密码/端口。
- 若随机端口被占用，会在安装前自动重试随机端口。

管道无参数模式（自动回退 quick）：

```bash
curl -fsSL "https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/master/install.sh" | sudo bash
```

说明：

- 在无交互输入的管道场景中，无参数会自动进入 quick 逻辑。
- 同样会执行端口占用检测与自动重试随机端口。

参数模式（示例：指定账号密码端口）：

```bash
curl -fsSL "https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/master/install.sh" | sudo bash -s -- --yes admin "StrongPass123" 36584
```

说明：

- 指定端口会在安装前执行占用检测。
- 端口已占用时会直接报错并终止安装（不会静默覆盖）。

如需进入完整菜单交互，请先下载到本地再执行：

```bash
curl -fsSL "https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/master/install.sh" -o /tmp/install.sh && sudo bash /tmp/install.sh
```

---

## 4. 参数与默认值说明

### 4.1 `install.sh` 参数

```bash
install.sh [--yes] [--update-docker] <FLARE_USER> <FLARE_PASS> <FLARE_PORT>
```

```bash
install.sh --quick
```

```bash
install.sh
```

无参数时进入菜单式交互控制台。

参数说明：

- `--quick`：一键快速安装（自动生成账号/密码/端口，非交互）。
- `--yes`：非交互模式，采用默认决策。
- `--update-docker`：强制执行 Docker 更新。
- `FLARE_USER`：BasicAuth 用户名。
- `FLARE_PASS`：BasicAuth 密码。
- `FLARE_PORT`：对外访问端口（映射到 `edge:8081`）。

端口校验策略：

- quick / 一键模式：安装前检测占用，冲突时自动重试随机端口。
- 手动输入模式：安装前检测占用，冲突时提示更换（菜单）或直接失败（CLI 参数模式）。

### 4.2 默认值（脚本生成）

- 安装目录：`/opt/aio-proxy`
- 默认时区：自动继承当前机器时区（检测失败回退 `UTC`）
- 容器内部端口：`8191`
- Compose 网络名：`aio-proxy-net`

### 4.3 帮助命令

```bash
bash install.sh --help
bash install_docker.sh --help
```

---

## 5. 交互说明（菜单 + yes/no）

### 5.1 主菜单（无参数进入）

```bash
sudo ./install.sh
```

菜单项包含：

- 查看当前配置
- 全新安装 / 重装
- 修改账号密码
- 修改对外端口
- 启动 / 停止 / 重启
- 状态页 / 查看日志
- 卸载删除服务

主菜单交互支持：

- `0-10`：输入对应序号执行操作
- `0`：退出控制台

状态页操作：

- `1`：刷新当前状态快照
- `2`：启动服务
- `3`：停止服务
- `4`：重启服务
- `5`：进入日志跟随
- `0`：返回主菜单

安装输入规则：

- 用户名：可直接输入；留空自动随机生成。
- 密码：可见输入；留空自动随机生成。
- 端口：可直接输入；留空自动随机生成。

### 5.2 yes/no 确认菜单（Docker 安装/更新）

Docker 检测阶段的确认菜单统一为数字输入：

- `1`：表示 `yes`
- `2`：表示 `no`
- `q`：退出安装

---

## 6. 日常运维

安装完成后，进入工作目录：

```bash
cd /opt/aio-proxy
```

常用命令：

```bash
./manage.sh
./manage.sh start
./manage.sh stop
./manage.sh restart
./manage.sh ps
./manage.sh logs
```

`./manage.sh` 无参数会进入与 `install.sh` 相同的交互控制台，便于后续维护（含卸载删除）。

修改 BasicAuth：

```bash
./manage.sh set-credentials NEW_USER NEW_PASS
```

卸载删除：

```bash
./manage.sh uninstall
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

`install.sh` 的 Docker 处理策略：

- 若同目录存在 `install_docker.sh`：优先调用外部安装器。
- 若不存在：自动回退到 `install.sh` 内置 Docker 安装流程（单脚本模式可直接运行）。

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

处理：脚本会自动回退到数字输入；参数模式也可直接使用 `--yes`。

### 9.5 `[install] 未找到 Docker 安装器`

原因：`install.sh` 与 `install_docker.sh` 不在同一目录。

处理：新版本会自动回退到内置安装流程，通常可忽略该提示；也可将两个脚本放在同目录以使用外部安装器。

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
- 新增 `install.sh` 无参数菜单模式，可直接查看/修改配置与管理服务。
- Docker 安装策略支持交互确认与参数覆盖（`--yes` / `--update-docker`）。
- 菜单与交互确认统一为数字输入，兼容低能力终端与移动端 SSH。
