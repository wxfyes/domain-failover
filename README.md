# DDNS故障转移使用教程
1.询问您必要的配置信息（API Token, Zone ID, 备用 IP/域名）。

2.安装所需的系统依赖（curl, jq, nc, dig）。

3.创建 /opt/failover 目录。

4.生成配置脚本 (config.env) 和主执行脚本 (failover_script.sh)。

5.设置文件执行权限。

6.配置 Crontab 定时任务（每 5 分钟执行一次）。
```
wget https://raw.githubusercontent.com/wxfyes/domain-failover/refs/heads/main/install.sh && chmod +x install.sh && ./install.sh
```
### 如果在openwrt中报错，可能是修改后的语法问题导致
步骤一：SSH 并安装依赖
通过 SSH 连接到您的 OpenWrt 路由器，并使用 opkg 包管理器安装必需的工具。

Bash

## 步骤一. 更新包列表
```
opkg update
```
### 2. 安装所有依赖
#### 注意：脚本依赖 Bash 的高级数组功能，所以必须安装 bash
```
opkg install bash curl jq netcat bind-dig
```

##### 提示: 如果 bind-dig 占用空间太大，可以尝试安装 dnsmasq-full (可能包含 dig 功能)
##### 如果 netcat 提示找不到，可能需要安装 nc 或 netcat-openbsd
## 步骤二：创建工作目录和配置路径
OpenWrt 路由器通常没有 /opt 目录。我们建议使用 /root 或 /etc/config 附近的目录。

Bash

### 创建工作目录
```
mkdir -p /root/failover 
cd /root/failover
```
## 步骤三：修改脚本中的路径
您需要将您的 failover_script.sh 文件中的路径变量修改为 /root/failover：

请编辑 /root/failover/failover_script.sh 文件（如果它是您从一键脚本中提取出来的）：
```
Bash

# 找到这两行（位于脚本顶部）：
# SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# CONFIG_FILE="$SCRIPT_DIR/config.env"
# LOG_FILE="$SCRIPT_DIR/failover_log.log"
```

# 将它们修改为：
```
SCRIPT_DIR="/root/failover"
CONFIG_FILE="$SCRIPT_DIR/config.env"
LOG_FILE="$SCRIPT_DIR/failover_log.log"
```
## 步骤四：检查 SHELL 兼容性
由于 OpenWrt 默认使用 ash，而我们的脚本是为 bash 编写的，我们需要强制脚本使用您刚刚安装的 bash。
```

请确保 /root/failover/failover_script.sh 的第一行是：

Bash
```
#!/bin/bash
## 步骤五：创建或移动配置和脚本文件
#### 将之前在服务器上创建的 config.env 和 failover_script.sh 文件上传或重新创建到 /root/failover 目录下。此步骤已经操作可以忽略！


### 设置权限
chmod +x /root/failover/failover_script.sh
#### 1. 备份原文件 (可选，但推荐)
cp /opt/failover/failover_script.sh /opt/failover/failover_script.sh.bak

##### 2. 清理脚本文件（使用 sed 命令）非必要操作步骤，只遇到修改后语法问题报错才使用此命令，无问题直接忽略
###### 这个命令会移除所有非打印ASCII字符，并将Windows换行符(\r\n)转换为Linux换行符(\n)
```
sed -i 's/\r//g; s/[^[:print:][:space:]\t]//g' /opt/failover/failover_script.sh
```
# 运行问题
openwrt中可能bash的路径不对，可以尝试一下路径，直接运行which bash就可以看到bash路径
```
/bin/bash /opt/failover/failover_script.sh
```
openwet不适用apt命令，所以可以跳过脚本中的 apt 安装步骤，直接下载脚本手动上传/opt/failover/目录下即可，没有就创建一个/opt/failover/文件夹
您不需要重新运行整个安装脚本。只需执行最后关键的 部署和验证 步骤：

确保文件已就位： 确认 /opt/failover/config.env 和 /opt/failover/failover_script.sh 都在正确位置。

设置权限：
```
Bash

chmod +x /opt/failover/failover_script.sh
```
配置 Crontab（如果未配置）：
```
Bash

crontab -e
 添加：*/5 * * * * /usr/bin/bash /opt/failover/failover_script.sh
```
```
然后运行
/etc/init.d/cron restart
```
