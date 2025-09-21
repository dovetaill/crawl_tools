# AIO Proxy & Scraper Suite (一体化代理与抓取套件)

这是一个一键安装脚本部署的一体化代理(All-in-One) 解决方案，集成了多个强大的开源工具，为您提供一个稳定、可靠且受密码保护的网页抓取和代理环境。所有服务的出站流量都将通过 Cloudflare WARP 路由，有效隐藏服务器的真实 IP 地址。

---

## 核心特性

*   **一体化部署**: 通过单个 `docker-compose.yml` 文件管理 FlareSolverr, Crawl4AI, Nginx 和 Cloudflare WARP。
*   **全局网络出口**: 所有抓取服务 (FlareSolverr, Crawl4AI) 的流量均通过 Cloudflare WARP 容器，使用 WARP 的 IP 作为出口。
*   **独立认证与访问**: 使用 Nginx 作为反向代理，为 FlareSolverr 和 Crawl4AI 提供了各自独立的端口和密码保护。
*   **一键化脚本安装**: 提供交互式和静默两种模式，简化了整个复杂的配置和部署流程。
*   **便捷管理**: 提供了清晰的服务管理和 IP 更换指令。

---

## 架构简图

外部请求的流向如下：

`用户` -> `互联网` -> `服务器IP:端口` -> `Nginx (密码认证)` -> `内部服务 (FlareSolverr/Crawl4AI)` -> `WARP 容器` -> `目标网站`

---

## 先决条件

*   一台拥有 `root` 权限的 Linux 服务器。
*   已安装 Docker 和 Docker Compose (推荐 v2)。

---

## 安装

使用以下一键安装指令。请务必将指令中的占位符替换为您自己的配置。

```bash
# 将 fs_user, FsPass123, 8191, c4ai_user, C4aiPass456, 11235 替换为您自己的设置
# 格式: <FlareSolverr用户名> <FlareSolverr密码> <FlareSolverr端口> <Crawl4AI用户名> <Crawl4AI密码> <Crawl4AI端口>
sudo bash -c ' \
    set -e; \
    INSTALLER_URL="https://gist.githubusercontent.com/MihaiTheCoder/11696489345b1d440d99539d997233d4/raw/install_aio_proxy.sh"; \
    INSTALLER_PATH="/tmp/install_aio_proxy.sh"; \
    echo "--> 正在下载 AIO Proxy 安装脚本..."; \
    curl -sLf "$INSTALLER_URL" -o "$INSTALLER_PATH"; \
    echo "--> 正在使用您的设置执行安装脚本..."; \
    chmod +x "$INSTALLER_PATH"; \
    "$INSTALLER_PATH" \
        "fs_user" "FsPass123" "8191" \
        "c4ai_user" "C4aiPass456" "11235"; \
    rm "$INSTALLER_PATH"; \
'
```

*   默认安装目录为 `/opt/aio_proxy`。

---

## 如何访问服务

请将 `<your_server_ip>` 替换为您服务器的公网 IP 地址。

### FlareSolverr

*   **访问地址**: `http://<your_server_ip>:<flaresolverr_port>`
*   **API 端点**: `http://<your_server_ip>:<flaresolverr_port>/v1`
*   **用户名/密码**: 安装时设置的值

**测试指令:**
```bash
curl --user "用户名:密码" \
     -X POST \
     -H "Content-Type: application/json" \
     -d '{
       "cmd": "request.get",
       "url": "https://www.69shuba.com/txt/81824/40604995",
       "maxTimeout": 60000
     }' \
     http://<your_server_ip>:<flaresolverr_port>/v1
```

### Crawl4AI

*   **访问地址**: `http://<your_server_ip>:<crawl4ai_port>`
*   **API 端点**: `http://<your_server_ip>:<crawl4ai_port>/crawl`
*   **用户名/密码**: 安装时设置的值

**测试指令:**
```bash
curl --user "用户名:密码" \
     -X POST \
     -H "Content-Type: application/json" \
     -d '{"url": "https://www.69shuba.com/txt/81824/40604995"}' \
     http://<your_server_ip>:<crawl4ai_port>/crawl
```

---

## 服务管理

所有管理命令都需要在安装目录 `/opt/aio_proxy` 下执行。

```bash
cd /opt/aio_proxy
```

*   **查看所有服务状态**:
    ```bash
    docker compose ps
    ```

*   **查看特定服务日志** (例如 `crawl4ai`):
    ```bash
    docker compose logs -f aio-crawl4ai
    ```

*   **停止并删除所有服务**:
    ```bash
    docker compose down
    ```

*   **启动所有服务**:
    ```bash
    docker compose up -d
    ```

---

## 更换 WARP IP 地址

### 手动更换

当您需要立即更换出口 IP 时，执行以下命令：
```bash
# 请确保在 /opt/aio_proxy 目录下
docker compose restart warp
```

### 自动定时更换

通过 `crontab` 设置定时任务。

1.  编辑 `crontab`: `crontab -e`
2.  添加一行（以下示例为每 6 小时更换一次）:
    ```crontab
    0 */6 * * * cd /opt/aio_proxy && docker compose restart warp >/dev/null 2>&1
    ```

---

## 卸载

如果您想完全移除此套件：

1.  进入安装目录: `cd /opt/aio_proxy`
2.  停止并删除所有容器、网络和数据卷: `docker compose down -v`
3.  删除安装目录: `cd .. && rm -rf /opt/aio_proxy`
