# domain-failover
1.询问您必要的配置信息（API Token, Zone ID, 备用 IP/域名）。

2.安装所需的系统依赖（curl, jq, nc, dig）。

3.创建 /opt/failover 目录。

4.生成配置脚本 (config.env) 和主执行脚本 (failover_script.sh)。

5.设置文件执行权限。

6.配置 Crontab 定时任务（每 5 分钟执行一次）。
```
chmod +x install.sh
```
