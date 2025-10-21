#!/bin/bash
# 
# 自动化安装并配置 Docker 的一键脚本
#

# 当任何命令执行失败时，立即退出脚本
set -e

# --- 步骤 1: 卸载旧版本 ---
echo "INFO: 正在卸载可能存在的旧版本 Docker..."
sudo apt-get remove -y docker docker-engine docker.io containerd runc &> /dev/null || true

# --- 步骤 2: 安装必要的依赖包 ---
echo "INFO: 正在更新软件源并安装依赖..."
sudo apt-get update
sudo apt-get install -y \
    curl \
    vim \
    wget \
    gnupg \
    dpkg \
    apt-transport-https \
    lsb-release \
    ca-certificates

# --- 步骤 3: 添加 Docker 官方 GPG 密钥 ---
echo "INFO: 正在添加 Docker 官方 GPG 密钥..."
sudo install -m 0755 -d /usr/share/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-ce.gpg
sudo chmod a+r /usr/share/keyrings/docker-ce.gpg

# --- 步骤 4: 添加 Docker 的 APT 软件源 ---
echo "INFO: 正在设置 Docker APT 软件源..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-ce.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# --- 步骤 5: 安装 Docker 引擎 ---
echo "INFO: 正在安装 Docker 引擎..."
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# --- 步骤 6: 配置 Docker 守护进程 (daemon.json) ---
echo "INFO: 正在配置 /etc/docker/daemon.json..."
sudo tee /etc/docker/daemon.json <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "20m",
        "max-file": "3"
    },
    "ipv6": true,
    "fixed-cidr-v6": "fd00:dead:beef:c0::/80",
    "experimental": true,
    "ip6tables": true
}
EOF

# --- 步骤 7: 重启 Docker 服务使配置生效 ---
echo "INFO: 正在重启 Docker 服务..."
sudo systemctl restart docker

echo "✅ Docker 安装和配置成功！"
echo "   您可以运行 'sudo docker run hello-world' 来进行验证。"
