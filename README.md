# AIO Proxy & Scraper Suite (一体化代理与抓取套件) - v3.0

这是一个通过一键安装脚本部署的“All-in-One”解决方案，集成了多个强大的开源工具，为您提供一个稳定、可靠且受密码保护的网页抓取和代理环境。所有服务的出站流量都将通过 Cloudflare WARP 路由，有效隐藏服务器的真实 IP 地址并绕过部分网络限制。

该文档为最新版本，包含了从安装、使用、日常管理到高级 IP 控制的全部内容。

---

## 核心特性

*   **一体化部署**: 通过单个 `docker-compose.yml` 文件统一管理 FlareSolverr, Crawl4AI, Nginx 和 Cloudflare WARP。
*   **全局网络出口**: 所有抓取服务 (FlareSolverr, Crawl4AI) 的流量均通过 Cloudflare WARP 容器，使用 WARP 的 IP 作为出口。
*   **独立认证与访问**: 使用 Nginx 作为反向代理，为 FlareSolverr 和 Crawl4AI 提供了各自独立的访问端口和密码保护。
*   **一键化覆盖安装**: 提供的一键指令会先清理旧版相关容器，再执行全新安装，确保环境的纯净与一致性。
*   **强大的 IP 控制**: 支持手动、自动定时以及强制更换 IP，甚至可以通过 SOCKS5 代理获取指定地区的出口 IP。

---

## 架构简图

外部请求的流向如下：

`用户` -> `互联网` -> `服务器IP:端口` -> `Nginx (密码认证)` -> `内部服务 (FlareSolverr/Crawl4AI)` -> `WARP 容器` -> `目标网站`

---

## 先决条件

*   一台拥有 `root` 权限的 Linux 服务器。
*   已安装 Docker 和 Docker Compose (推荐 v2 版本，即 `docker compose`)。

---

## 🚀 一键安装指令

**重要提示**：此指令会**首先强制删除**名为 `aio-warp`, `aio-proxy`, `aio-flaresolverr`, `aio-crawl4ai` 的容器，然后再进行全新安装。这对于重复执行和更新非常方便。

**请根据注释修改以下指令中的参数，然后在您的服务器上执行。**

```bash
# 1. 首先，定义要清理的旧容器名称列表
OLD_CONTAINERS="aio-warp aio-proxy aio-flaresolverr aio-crawl4ai"

# 2. 执行清理和安装指令
docker rm -f $OLD_CONTAINERS || true; \
sudo bash -c ' \
    set -e; \
    # 这是新的安装脚本地址
    SCRIPT_URL="https://raw.githubusercontent.com/dovetaill/crawl_tools/refs/heads/main/install.sh"; \
    SCRIPT_PATH="/tmp/install_aio_proxy.sh"; \
    echo "--> 正在下载一体化安装脚本..."; \
    curl -sLf "$SCRIPT_URL" -o "$SCRIPT_PATH"; \
    echo "--> 正在使用您的设置执行安装..."; \
    chmod +x "$SCRIPT_PATH"; \
    # 按顺序传入6个参数:
    # <FlareSolverr用户名> <FlareSolverr密码> <FlareSolverr端口> \
    # <Crawl4AI用户名>   <Crawl4AI密码>   <Crawl4AI端口>
    "$SCRIPT_PATH" \
        "your_flaresolverr_username" "your_flaresolverr_passwd" "56788" \
        "your_crawl4ai_username" "your_crawl4ai_passwd" "56789"; \
    echo "--> 清理安装脚本..."; \
    rm "$SCRIPT_PATH"; \
'
```

*   默认安装目录为 `/opt/aio_proxy`。

---

## ✅ 如何访问与测试服务

安装完成后，请将 `<your_server_ip>` 替换为您服务器的公网 IP 地址进行测试。

### FlareSolverr

*   **访问地址**: `http://<your_server_ip>:56788`
*   **API 端点**: `http://<your_server_ip>:56788/v1`
*   **用户名/密码**: `your_flaresolverr_username` / `your_flaresolverr_passwd` (或您设置的值)

**API 测试指令 (验证 Cloudflare 绕过能力):**
```bash
curl --user "your_flaresolverr_username:your_flaresolverr_passwd" \
     -X POST -H "Content-Type: application/json" \
     -d '{"cmd": "request.get", "url": "https://example.com", "maxTimeout": 60000}' \
     http://<your_server_ip>:56788/v1
```

### Crawl4AI

*   **访问地址**: `http://<your_server_ip>:56789`
*   **API 端点**: `http://<your_server_ip>:56789/crawl`
*   **用户名/密码**: `your_crawl4ai_username` / `your_crawl4ai_passwd` (或您设置的值)

**API 测试指令 (验证通用网页抓取):**
```bash
curl --user "your_crawl4ai_username:your_crawl4ai_passwd" \
     -X POST -H "Content-Type: application/json" \
     -d '{"url": "https://example.com"}' \
     http://<your_server_ip>:56789/crawl
```

---

## 🛡️ 验证 WARP 网络出口是否生效

这是**关键的验证步骤**，用于确认所有服务的出口流量都通过 WARP 网络，从而隐藏了服务器的真实 IP。

**第 1 步：获取服务器的本机公网 IP**

在您的服务器上直接运行此命令，记下返回的 IP 地址。这是您服务器的真实 IP。

```bash
curl ip.gs
```

**第 2 步：获取容器的出口公网 IP**

此命令会进入 `aio-flaresolverr` 容器内部，查询它访问外部网络时所使用的 IP 地址。

```bash
docker exec aio-flaresolverr curl -s ip.gs
```

**第 3 步：对比结果**

*   ✅ **成功**: 如果**两个 IP 地址不同**，恭喜您，配置完全正确！所有服务的流量都已成功通过 WARP 路由。
*   ❌ **失败**: 如果**两个 IP 地址相同**，说明网络配置存在问题，服务的流量仍然在使用服务器的本机 IP。请检查 `docker-compose.yml` 文件中的 `network_mode: "service:warp"` 配置是否正确。

---

## 🛠️ 日常服务管理

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

*   **停止并删除所有服务容器**:
    ```bash
    docker compose down
    ```
    *注意：此命令默认不删除数据卷 (`warp-data`)。*

*   **启动所有服务**:
    ```bash
    docker compose up -d
    ```

---

## 🌐 WARP IP 地址管理

这是本套件的核心功能之一。您可以根据需求选择不同的策略来更换出口 IP。

### 方法一：手动更换 IP (推荐)

此方法会强制重建 WARP 容器，更换 IP 的成功率很高。

```bash
# 确保在 /opt/aio_proxy 目录下
docker compose up -d --force-recreate --no-deps warp
```

### 方法二：自动定时更换 IP (Cron Job)

您可以设置一个定时任务来自动执行 IP 更换操作。

1.  打开定时任务编辑器: `crontab -e`
2.  在文件末尾添加一行（以下示例为**每 6 小时**更换一次 IP）:
    ```crontab
    0 */6 * * * cd /opt/aio_proxy && docker compose up -d --force-recreate --no-deps warp >/dev/null 2>&1
    ```

### 方法三：终极手段 - 强制刷新身份以获取全新 IP

当您发现 IP 地址长期“卡”在某个段，或者方法一失效时，使用此方法。它通过删除 WARP 的身份数据来强制获取一个全新的身份和 IP。

1.  **停止所有服务**: `docker compose down`
2.  **删除 WARP 身份数据**: `sudo rm -rf ./warp-data/*`
3.  **重新启动所有服务**: `docker compose up -d`
4.  等待约 15 秒后，检查 IP 即可。

### 方法四：高级技巧 - 获取指定地区的出口 IP

通过“代理链”技术，让 WARP 通过一个位于目标国家的 SOCKS5 代理进行连接。

1.  **获取一个 SOCKS5 代理** (例如 `1.2.3.4:1080`)。
2.  **修改 `docker-compose.yml` 文件**，在 `warp` 服务的 `environment` 部分添加代理信息：
    ```yaml
    services:
      warp:
        # ... 其他配置 ...
        environment:
          - WARP_SLEEP=10
          - WARP_SOCKS5_PROXY=1.2.3.4:1080 # 添加此行
    ```
3.  **应用配置**: `docker compose up -d --force-recreate --no-deps warp`
4.  验证新 IP，它现在应该来自您的 SOCKS5 代理所在的地区。

---

## 🗑️ 如何完全卸载

如果您想彻底移除此套件和所有相关数据：

1.  **进入安装目录**:
    ```bash
    cd /opt/aio_proxy
    ```
2.  **停止并删除所有容器、网络和数据卷**:
    ```bash
    # 使用 -v 参数确保 warp-data 数据卷被一并删除
    docker compose down -v
    ```
3.  **删除安装目录**:
    ```bash
    cd ..
    sudo rm -rf /opt/aio_proxy
    ```
4.  **(可选) 清理 Cron Job**:
    如果您设置了定时任务，运行 `crontab -e` 并删除相关行。
