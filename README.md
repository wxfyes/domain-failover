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
#### 1. 备份原文件 (可选，但推荐)
cp /opt/failover/failover_script.sh /opt/failover/failover_script.sh.bak

##### 2. 清理脚本文件（使用 sed 命令）
###### 这个命令会移除所有非打印ASCII字符，并将Windows换行符(\r\n)转换为Linux换行符(\n)
```
sed -i 's/\r//g; s/[^[:print:][:space:]\t]//g' /opt/failover/failover_script.sh
```
# 运行问题
openwrt中可能bash的路径不对，可以尝试一下路径，直接运行which bash就可以看到bash路径
```
/bin/bash /opt/failover/failover_script.sh
```

