# TDD 交接文档：optimize-script

- 日期：2026-03-08
- 对应实现计划：`docs/plans/2026-03-08-optimize-script-plan.md`
- 交接目标：为下一阶段 `test-driven-development` 提供可直接落地的测试范围与验收基线。

## 1. 本次改动范围（实现结果）

本轮实现已完成以下收敛：

1. 从安装脚本链路中移除 `WARP`、`Crawl4AI`、`SERVICE_MODE` 相关逻辑。
2. 收敛部署拓扑为 `edge + flaresolverr`。
3. 引入 Docker 安装/更新交互策略（默认未装则装、已装不更新；支持 `--yes` / `--update-docker`）。
4. 引入原生终端菜单（方向键）并提供非 TTY 数字回退输入。
5. 生成物收敛为单 `docker-compose.yml`，并由 Compose 自管理 `bridge` 网络。
6. README 已重写并与脚本参数、命令、行为对齐。

## 2. 核心文件与职责

### 2.1 `install.sh`

职责：主安装入口，负责参数解析、Docker 策略决策、生成部署产物并启动服务。

关键函数（测试重点）：

1. `usage()`
- 输出 `install.sh [--yes] [--update-docker] <FLARE_USER> <FLARE_PASS> <FLARE_PORT>`。

2. 参数解析主循环（`while [ "$#" -gt 0 ]`）
- 识别 `--yes`、`--update-docker`、`--help`、未知参数。
- 未知参数需 `exit 1`。

3. `is_interactive_terminal()` / `can_use_arrow_menu()`
- 决定交互模式：方向键菜单 or 数字输入回退。

4. `confirm_with_number_input()`
- 支持 `1/2` 与 `q`，空输入采用默认值。

5. `confirm_with_arrow_menu()`
- 支持 `↑/↓`、`Enter`、`q`。
- 使用 `tput` 与 `trap` 恢复终端状态。

6. `confirm_with_default()`
- 统一调度菜单模式与回退模式。

7. `run_docker_installer(action)`
- 调用同目录 `install_docker.sh`，并按 `--yes` 透传。

8. `ensure_docker_runtime()`
- Docker 未安装：默认询问安装（默认 yes）。
- Docker 已安装：默认询问更新（默认 no）。
- `--update-docker` 强制更新优先。

9. `detect_compose_bin()`
- 选择 `docker compose` 或 `docker-compose`。

10. 产物生成段
- `.env`
- `nginx/nginx.conf`
- `docker-compose.yml`
- `manage.sh`

11. 启动段
- `docker compose -f docker-compose.yml up -d flaresolverr edge`

### 2.2 `install_docker.sh`

职责：Docker 安装器/更新器，可由主脚本调用或单独执行。

关键函数（测试重点）：

1. `usage()`
- 输出 `install_docker.sh [--action install|update] [--yes]`。

2. 参数解析
- `--action install|update`
- `--yes`
- 非法 action 需 `exit 1`。

3. 权限处理（`SUDO` / root）
- 非 root 且无 `sudo` 时失败退出。

4. `apt_wait_lock()` / `apt_run()`
- 处理 `dpkg lock` 等待逻辑。

5. `ensure_docker_repo()`
- 写入 Docker APT key 与 source。

6. `install_docker_engine()` / `update_docker_engine()`
- install：完整安装。
- update：升级；若检测不到 Docker 自动回退 install。

7. `ensure_service_running()`
- systemd/service 双路径启动。

### 2.3 `README.md`

职责：参考手册与运行指引，应与脚本行为保持一致。

测试重点：

1. 参数说明与 `--help` 输出一致。
2. 运维命令与 `manage.sh` 生成接口一致。
3. 不出现旧架构关键词（`WARP/Crawl4AI`）。

## 3. 对外接口契约（必须稳定）

### 3.1 安装命令接口

```bash
install.sh [--yes] [--update-docker] <FLARE_USER> <FLARE_PASS> <FLARE_PORT>
```

### 3.2 Docker 安装器接口

```bash
install_docker.sh [--action install|update] [--yes]
```

### 3.3 `manage.sh` 接口（生成物）

```bash
./manage.sh {start|stop|restart|ps|logs|set-credentials <user> <pass>}
```

## 4. 边界场景（Edge Cases）

1. 非 TTY 场景（CI、管道）
- 方向键菜单不可用，必须稳定回退为数字输入或默认策略。

2. 终端能力不足（`TERM=dumb` / 无 `tput`）
- 不能进入光标控制逻辑，需可继续执行。

3. 用户中断
- `q` 退出时返回非 0（当前为 130），且终端状态恢复正常。

4. Docker 状态分支
- 未安装 Docker + 用户拒绝安装：流程应失败退出。
- 已安装 Docker + 默认不更新：应继续后续部署。
- `--update-docker`：必须触发 update 分支。

5. `install_docker.sh --action update` 但系统无 Docker
- 必须回退到 install 分支而非直接失败。

6. 参数异常
- 未知参数、参数数量不匹配均需 `exit 1` 并输出用法。

7. APT 锁长时间占用
- `apt_wait_lock` 超时后需返回错误路径。

8. 凭据与端口输入
- 密码包含特殊字符时命令调用需正确（调用方需正确引用）。
- 端口被占用时应通过日志可诊断。

## 5. 建议的 TDD 测试分层

### 5.1 L1：静态与语法测试（快速）

1. `bash -n install.sh`
2. `bash -n install_docker.sh`
3. `--help` 输出快照对比测试。
4. 关键关键词约束测试（禁止旧关键词残留）。

### 5.2 L2：行为测试（模拟）

建议使用 `bats` 或 shell harness，对外部命令做 stub：

1. 参数解析测试：
- 合法参数通过
- 非法参数失败

2. Docker 决策测试：
- mock `command -v docker` 命中/未命中
- 断言 `install` / `update` 分支调用

3. 菜单分支测试：
- mock TTY 条件，验证菜单/回退路径切换

4. 生成文件测试：
- 校验 `.env`、`docker-compose.yml`、`manage.sh` 核心字段

### 5.3 L3：集成验证（受控环境）

1. 干净环境安装
- `sudo ./install.sh --yes test_user test_pass 36584`

2. 运行后检查
- `docker compose -f /opt/aio-proxy/docker-compose.yml ps`
- `curl --user ... http://<host>:36584/v1`

3. 运维命令链路
- `start/stop/restart/ps/logs/set-credentials` 全链路烟雾测试

## 6. 当前已验证项（实现阶段完成）

1. `install.sh`、`install_docker.sh` 语法检查通过。
2. `--help` 输出与 README 参数说明一致。
3. 旧关键词（`WARP/Crawl4AI/...`）在目标文件中已清理。
4. 非法参数返回码与错误提示行为正确。

## 7. 下一阶段进入条件

满足以下条件后可进入正式 TDD 落地：

1. 在测试仓库引入 shell 测试框架（如 `bats`）或约定统一 harness。
2. 先固化 L1/L2 测试，再进入 L3 环境验证。
3. 所有新增测试应以本文件第 3 节接口契约为判定基线。
