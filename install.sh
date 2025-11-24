#!/bin/bash

# ====================================================================
# Cloudflare DDNS 故障转移一键安装脚本
# 作者: Gemini (基于用户需求定制)
# 目录: /opt/failover/
# ====================================================================

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 固定的目标域名列表 (基于您的需求)
TARGET_DOMAINS_LIST=(
    "qdlt.808622.xyz" 
    "123.808622.xyz" 
    "456.808622.xyz"
)
INSTALL_DIR="/opt/failover"
CONFIG_FILE="$INSTALL_DIR/config.env"
SCRIPT_FILE="$INSTALL_DIR/failover_script.sh"

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN} Cloudflare 多域名/多IP 故障转移一键安装 ${NC}"
echo -e "${GREEN}=============================================${NC}"

# --- 1. 获取用户输入 ---

echo -e "\n${GREEN}--- 1. 密钥和 ID 配置 ---${NC}"

# API Token
read -r -s -p "请输入您的 Cloudflare API Token (Zone.DNS Edit 权限): " CF_API_TOKEN
echo ""

# Zone ID
read -r -p "请输入您顶级域名 808622.xyz 的唯一 Zone ID (区域 ID): " CF_ZONE_ID

# 备用目标
echo -e "\n${GREEN}--- 2. 故障转移目标配置 (可按 Enter 使用默认值) ---${NC}"
echo -e "注: IP 列表请用逗号分隔，优先级按顺序。"

# 组 0
DEFAULT_FB0="cu1.xcuuu.cn"
read -r -p " [0] ${TARGET_DOMAINS_LIST[0]} 的备用目标 [默认: $DEFAULT_FB0]: " FB_TARGET0
FB_TARGET0=${FB_TARGET0:-$DEFAULT_FB0}

# 组 1
DEFAULT_FB1="cu2.xcuuu.cn"
read -r -p " [1] ${TARGET_DOMAINS_LIST[1]} 的备用目标 [默认: $DEFAULT_FB1]: " FB_TARGET1
FB_TARGET1=${FB_TARGET1:-$DEFAULT_FB1}

# 组 2 (多静态 IP)
DEFAULT_FB2="9.9.9.9,8.8.8.8,1.1.1.1"
read -r -p " [2] ${TARGET_DOMAINS_LIST[2]} 的备用目标 (多IP) [默认: $DEFAULT_FB2]: " FB_TARGET2
FB_TARGET2=${FB_TARGET2:-$DEFAULT_FB2}

# --- 2. 安装依赖和创建目录 ---

echo -e "\n${GREEN}--- 3. 安装依赖和创建目录 ---${NC}"

if ! sudo apt update; then
    echo -e "${RED}更新软件包列表失败，请检查网络或权限。${NC}"
    exit 1
fi

if ! sudo apt install curl jq netcat-openbsd dnsutils -y; then
    echo -e "${RED}安装依赖失败，请检查权限。${NC}"
    exit 1
fi
echo "依赖安装成功。"

sudo mkdir -p "$INSTALL_DIR"
echo "工作目录 $INSTALL_DIR 创建成功。"

# --- 3. 生成配置文件 config.env ---

echo -e "\n${GREEN}--- 4. 生成配置文件 $CONFIG_FILE ---${NC}"
sudo tee "$CONFIG_FILE" > /dev/null << EOF
# /opt/failover/config.env

# =======================================================
# Cloudflare 授权配置
# =======================================================
CLOUDFLARE_API_TOKEN="$CF_API_TOKEN"
DNS_PROXIED="true" 


# =======================================================
# 多域名监控组配置
# =======================================================
TARGET_DOMAINS=(
    "${TARGET_DOMAINS_LIST[0]}" 
    "${TARGET_DOMAINS_LIST[1]}" 
    "${TARGET_DOMAINS_LIST[2]}"
)

FALLBACK_TARGETS=(
    "$FB_TARGET0"                  
    "$FB_TARGET1"      
    "$FB_TARGET2"       
)

# 顶级域名的唯一 Zone ID (重复三次)
CLOUDFLARE_ZONE_IDS=(
    "$CF_ZONE_ID" 
    "$CF_ZONE_ID" 
    "$CF_ZONE_ID"
)


# =======================================================
# 检测参数
# =======================================================
CHECK_PORT=80
TIMEOUT=5
CHECK_COUNT=2
DNS_TTL=60
EOF
echo "$CONFIG_FILE 生成成功。"

# --- 4. 生成主脚本 failover_script.sh ---

echo -e "\n${GREEN}--- 5. 生成主脚本 $SCRIPT_FILE ---${NC}"

# 使用单引号阻止内部变量或命令被提前展开
sudo tee "$SCRIPT_FILE" > /dev/null << 'MAIN_SCRIPT_EOF'
#!/bin/bash

# =======================================================
# 配置和日志路径
# =======================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_FILE="$SCRIPT_DIR/config.env"
LOG_FILE="$SCRIPT_DIR/failover_log.log"

# 全局变量：用于存储自动获取的 Record ID (每个循环更新)
DNS_RECORD_ID="" 
# 动态 Zone ID：用于存储当前循环中的 Zone ID (每个循环更新)
CURRENT_ZONE_ID="" 

# =======================================================
# 预检查与配置加载
# =======================================================

if [ ! -f "$CONFIG_FILE" ]; then
    echo "$(date +%Y-%m-%d\ %H:%M:%S) [FATAL] 错误: 配置文件 $CONFIG_FILE 不存在！" | tee -a "$LOG_FILE"
    exit 1
fi

# 启用 Shell 数组解析
source "$CONFIG_FILE"

# 检查依赖 (依赖已在安装阶段安装)
check_dependencies() {
    local dependencies=("curl" "jq" "nc" "dig")
    for dep in "${dependencies[@]}"; do
        if ! command-v "$dep" &> /dev/null; then
            echo "$(date +%Y-%m-%d\ %H:%M:%S) [FATAL] 错误: 必需的依赖 '$dep' 未安装，请重新运行安装脚本。" | tee -a "$LOG_FILE"
            exit 1
        fi
    done
}

# =======================================================
# 核心函数
# =======================================================

# 检查字符串是否为有效的 IPv4 地址
is_valid_ipv4() {
    local ip=$1
    # 移除首尾空白符
    ip=$(echo "$ip" | xargs)

    if [ -z "$ip" ]; then return 1; fi
    
    # 检查 IPv4 格式
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        read -ra octets <<< "$ip"
        if [ "${#octets[@]}" -ne 4 ]; then return 1; fi
        for octet in "${octets[@]}"; do
            if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# 自动获取 DNS Record ID 函数
get_dns_record_id() {
    local target_domain=$1
    
    echo "$(date +%Y-%m-%d\ %H:%M:%S) [INFO] 正在为 $target_domain 自动查询 Record ID..." | tee -a "$LOG_FILE"
    
    local API_URL="https://api.cloudflare.com/client/v4/zones/$CURRENT_ZONE_ID/dns_records?name=$target_domain&type=A"
    
    RESPONSE=$(curl -s -X GET "$API_URL" \
         -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
         -H "Content-Type: application/json")

    if ! echo "$RESPONSE" | jq -e '.success' > /dev/null; then
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.errors[].message')
        echo "$(date +%Y-%m-%d\ %H:%M:%S) [FATAL] ❌ API 错误，无法获取 $target_domain 的 Record ID：$ERROR_MSG" | tee -a "$LOG_FILE"
        return 1
    fi

    local record_count=$(echo "$RESPONSE" | jq '.result | length')

    if [ "$record_count" -eq 1 ]; then
        DNS_RECORD_ID=$(echo "$RESPONSE" | jq -r '.result[0].id')
        echo "$(date +%Y-%m-%d\ %H:%M:%S) [SUCCESS] ✅ 成功获取到 Record ID: $DNS_RECORD_ID" | tee -a "$LOG_FILE"
        return 0
    else
        echo "$(date +%Y-%m-%d\ %H:%M:%S) [FATAL] ❌ 错误: 未找到或找到多条 ($record_count) 匹配 $target_domain 的 A 记录。请检查。" | tee -a "$LOG_FILE"
        return 1
    fi
}

# 域名解析函数：获取最新的 A 记录 IP
resolve_domain() {
    local domain=$1
    local ip=$(dig +short "$domain" A | grep -v '^;' | head -n 1)
    echo "$ip"
}

# 检查 IP 连通性函数 (使用 nc)
check_host_alive() {
    local target_ip=$1
    local port=$2
    local count=$3
    local timeout=$4
    local success=0

    echo "$(date +%Y-%m-%d\ %H:%M:%S) [INFO] -> 正在尝试连接 $target_ip:$port (超时: ${timeout}s)..." | tee -a "$LOG_FILE"

    for i in $(seq 1 "$count"); do
        # nc -z: 扫描模式, -w: 超时时间
        if nc -z -w "$timeout" "$target_ip" "$port" &>/dev/null; then
            success=1
            break
        fi
        echo "$(date +%Y-%m-%d\ %H:%M:%S) [WARN]    尝试 $i/$count 失败。" | tee -a "$LOG_FILE"
        sleep 1
    done

    return $success
}

# 更新 Cloudflare A 记录函数
update_cf_record() {
    local target_domain=$1
    local new_ip=$2
    
    echo "$(date +%Y-%m-%d\ %H:%M:%S) [ACTION] >>> 触发更新 Cloudflare DNS 记录 <<<" | tee -a "$LOG_FILE"
    echo "$(date +%Y-%m-%d\ %H:%M:%S) [ACTION]    目标域名: $target_domain" | tee -a "$LOG_FILE"
    echo "$(date +%Y-%m-%d\ %H:%M:%S) [ACTION]    新 IP 地址: $new_ip" | tee -a "$LOG_FILE"
    
    # 构建 JSON 数据
    local json_data=$(cat <<JSON_EOF
{
  "type": "A",
  "name": "$target_domain",
  "content": "$new_ip",
  "ttl": $DNS_TTL,
  "proxied": $DNS_PROXIED
}
JSON_EOF
)

    # 调用 Cloudflare API
    RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CURRENT_ZONE_ID/dns_records/$DNS_RECORD_ID" \
         -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
         -H "Content-Type: application/json" \
         --data "$json_data")

    # 检查 API 调用结果
    if echo "$RESPONSE" | jq -e '.success' > /dev/null; then
        echo "$(date +%Y-%m-%d\ %H:%M:%S) [SUCCESS] ✅ Cloudflare DNS 更新成功！新 IP: $new_ip" | tee -a "$LOG_FILE"
    else
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.errors[].message')
        echo "$(date +%Y-%m-%d\ %H:%M:%S) [ERROR] ❌ Cloudflare DNS 更新失败！错误信息: $ERROR_MSG" | tee -a "$LOG_FILE"
    fi
}

# =======================================================
# 主逻辑
# =======================================================

check_dependencies

echo -e "\n$(date +%Y-%m-%d\ %H:%M:%S) --- 多域名故障转移检查启动 ---" | tee -a "$LOG_FILE"

# 遍历所有配置的监控组
for i in "${!TARGET_DOMAINS[@]}"; do
    TARGET_DOMAIN="${TARGET_DOMAINS[$i]}"
    FALLBACK_TARGET="${FALLBACK_TARGETS[$i]}"
    CURRENT_ZONE_ID="${CLOUDFLARE_ZONE_IDS[$i]}"
    
    # 检查是否跳过此组（任一关键字段为空则跳过）
    if [ -z "$TARGET_DOMAIN" ] || [ -z "$FALLBACK_TARGET" ] || [ -z "$CURRENT_ZONE_ID" ]; then
        echo "$(date +%Y-%m-%d\ %H:%M:%S) [SKIP] 跳过组 $i: 域名、目标或 Zone ID 留空。" | tee -a "$LOG_FILE"
        echo "---" | tee -a "$LOG_FILE"
        continue
    fi

    echo -e "\n$(date +%Y-%m-%d\ %H:%M:%S) --- 正在处理组 $i: $TARGET_DOMAIN 切换至 $FALLBACK_TARGET ---" | tee -a "$LOG_FILE"

    # 1. 自动获取 DNS Record ID
    get_dns_record_id "$TARGET_DOMAIN"
    if [ $? -ne 0 ]; then continue; fi

    # 2. 获取目标域名当前解析的 IP
    CURRENT_IP=$(resolve_domain "$TARGET_DOMAIN")
    if [ -z "$CURRENT_IP" ]; then
        echo "$(date +%Y-%m-%d\ %H:%M:%S) [FATAL] 组 $i 错误: 无法解析 $TARGET_DOMAIN 的当前 IP。终止。" | tee -a "$LOG_FILE"
        continue
    fi
    echo "$(date +%Y-%m-%d\ %H:%M:%S) [INFO] $TARGET_DOMAIN 当前解析 IP: $CURRENT_IP" | tee -a "$LOG_FILE"


    # 3. 检查当前 IP 连通性
    if check_host_alive "$CURRENT_IP" "$CHECK_PORT" "$CHECK_COUNT" "$TIMEOUT"; then
        echo "$(date +%Y-%m-%d\ %H:%M:%S) [INFO] 👍 当前 IP $CURRENT_IP 连通正常。无需操作。" | tee -a "$LOG_FILE"
    else
        # 4. 当前 IP 离线，启动故障转移流程
        echo "$(date +%Y-%m-%d\ %H:%M:%S) [ALERT] ❌ 当前 IP $CURRENT_IP 离线。启动故障转移到 $FALLBACK_TARGET。" | tee -a "$LOG_FILE"
        
        FALLBACK_IP=""
        FALLBACK_IP_LIST=()
        
        # 5. 确定备用 IP 候选列表
        if echo "$FALLBACK_TARGET" | grep -q ','; then
            # Case A: 多个静态 IP (CSV 列表)
            IFS=',' read -ra FALLBACK_IP_LIST <<< "$FALLBACK_TARGET"
            echo "$(date +%Y-%m-%d\ %H:%M:%S) [INFO] 备用目标为 IP 列表，将按优先级逐个检查连通性。" | tee -a "$LOG_FILE"

        elif is_valid_ipv4 "$FALLBACK_TARGET"; then
            # Case B: 单个静态 IP
            FALLBACK_IP_LIST+=("$FALLBACK_TARGET")
            echo "$(date +%Y-%m-%d\ %H:%M:%S) [INFO] 备用目标为单个静态 IP。" | tee -a "$LOG_FILE"

        else
            # Case C: 动态域名
            RESOLVED_IP=$(resolve_domain "$FALLBACK_TARGET")
            if [ -z "$RESOLVED_IP" ]; then
                echo "$(date +%Y-%m-%d\ %H:%M:%S) [CRIT] 错误: 无法解析备用域名 $FALLBACK_TARGET 的 IP。终止故障转移。" | tee -a "$LOG_FILE"
                continue
            fi
            FALLBACK_IP_LIST+=("$RESOLVED_IP")
            echo "$(date +%Y-%m-%d\ %H:%M:%S) [INFO] 备用域名 $FALLBACK_TARGET 解析到 IP: $RESOLVED_IP" | tee -a "$LOG_FILE"
        fi


        # 6. 检查备用 IP 连通性 (遍历列表)
        for ip_candidate in "${FALLBACK_IP_LIST[@]}"; do
            ip_candidate=$(echo "$ip_candidate" | xargs) # 移除空格
            
            if ! is_valid_ipv4 "$ip_candidate"; then
                echo "$(date +%Y-%m-%d\ %H:%M:%S) [WARN] 目标 '$ip_candidate' 不是有效的 IPv4 地址，跳过。" | tee -a "$LOG_FILE"
                continue
            fi
            
            if check_host_alive "$ip_candidate" "$CHECK_PORT" "$CHECK_COUNT" "$TIMEOUT"; then
                FALLBACK_IP="$ip_candidate"
                echo "$(date +%Y-%m-%d\ %H:%M:%S) [SUCCESS] ✅ 找到可用备用 IP: $FALLBACK_IP" | tee -a "$LOG_LOG"
                break # 找到可用 IP，立即跳出循环
            fi
        done
        
        # 7. 最终决策：检查是否找到了可用的 FALLBACK_IP
        if [ -z "$FALLBACK_IP" ]; then
            # 8. 主备 IP 均离线
            echo "$(date +%Y-%m-%d\ %H:%M:%S) [CRIT] ❌ 所有备用目标均离线或超时。未进行 DNS 记录更新。" | tee -a "$LOG_FILE"
        else
            # 9. 找到可用 IP，执行更新
            if [ "$CURRENT_IP" != "$FALLBACK_IP" ]; then
                echo "$(date +%Y-%m-%d\ %H:%M:%S) [ACTION] 切换 IP: $CURRENT_IP -> $FALLBACK_IP" | tee -a "$LOG_FILE"
                update_cf_record "$TARGET_DOMAIN" "$FALLBACK_IP"
            else
                echo "$(date +%Y-%m-%d\ %H:%M:%S) [WARN] ⚠️ 备用 IP ($FALLBACK_IP) 与当前 IP 相同，无需更新。" | tee -a "$LOG_FILE"
            fi
        fi
    fi
done

echo -e "\n$(date +%Y-%m-%d\ %H:%M:%S) --- 脚本运行结束 ---" | tee -a "$LOG_FILE"
MAIN_SCRIPT_EOF

# --- 5. 设置权限和 Crontab ---

echo -e "\n${GREEN}--- 6. 设置权限和 Crontab 定时任务 ---${NC}"

# 设置脚本权限
sudo chmod +x "$SCRIPT_FILE"

# 检查并添加 Crontab 任务
CRON_JOB="*/5 * * * * $SCRIPT_FILE"
(sudo crontab -l 2>/dev/null | grep -v -F "$SCRIPT_FILE"; echo "$CRON_JOB") | sudo crontab -
echo "Crontab 任务添加成功：脚本将每 5 分钟自动执行。"

# --- 6. 最终确认 ---

echo -e "\n${GREEN}=============================================${NC}"
echo -e "${GREEN} ✅ 恭喜！Cloudflare 故障转移系统安装成功！ ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo -e "配置路径: ${RED}$CONFIG_FILE${NC}"
echo -e "脚本路径: ${RED}$SCRIPT_FILE${NC}"
echo -e "日志路径: ${RED}$INSTALL_DIR/failover_log.log${NC}"
echo -e "\n${GREEN}请运行以下命令查看首次运行日志，确认配置无误：${NC}"
echo -e "${RED}sudo $SCRIPT_FILE${NC}"
echo -e "${RED}tail -f $INSTALL_DIR/failover_log.log${NC}"
