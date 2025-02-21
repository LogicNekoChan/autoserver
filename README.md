# AutoServer 自动化部署工具

AutoServer 是一个用于服务器自动化部署的工具，支持 Debian/Ubuntu 与 CentOS 系列操作系统。项目采用模块化设计，包含以下主要功能：

- **一键部署环境**：自动安装所需软件（jq、vim、neofetch、sudo、docker、docker-compose），并配置 TCP BBR 与 fq。
- **服务选择部署**：自动读取项目根目录下的 docker-compose 配置文件，让用户选择需要部署的服务。
- **容器管理**：支持对 Docker 容器映射卷的备份、恢复和删除操作。
- **Crontab 管理**：提供系统定时任务的新增和删除功能。

本项目托管于 GitHub，点击下面链接即可访问代码：
[https://github.com/LogicNekoChan/autoserver/tree/main](https://github.com/LogicNekoChan/autoserver/tree/main)

## 部署前准备

1. **安装 Git**  
   确保服务器中已安装 Git，若未安装请先安装：
   ```bash
   # Debian/Ubuntu 系统安装 Git
   sudo apt-get update && sudo apt-get install -y git

   # CentOS 系统安装 Git
   sudo yum install -y git
