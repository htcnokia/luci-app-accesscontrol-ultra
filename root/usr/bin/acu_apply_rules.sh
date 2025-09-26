#!/bin/sh
# Apply Access Control Ultra rules

CONFIG=accesscontrol-ultra
CHAIN=acu_chain
IPSET_NAME=acu_ipset

. /lib/functions.sh

logger -t accesscontrol-ultra "Applying rules..."

# Flush old
iptables -F $CHAIN 2>/dev/null || iptables -N $CHAIN
ipset destroy $IPSET_NAME 2>/dev/null
ipset create $IPSET_NAME hash:ip timeout 0

# Attach to FORWARD
iptables -C FORWARD -j $CHAIN 2>/dev/null || iptables -A FORWARD -j $CHAIN

# Time function helper
check_time() {
    local weekdays start stop
    weekdays="$1"; start="$2"; stop="$3"
    local day=$(date +%u) # 1-7
    local now=$(date +%H:%M)
    echo "$weekdays" | grep -qw "$day" || return 1
    [ "$now" \< "$start" ] && return 1
    [ "$now" \> "$stop" ] && return 1
    return 0
}

apply_rule() {
    local enabled mac ip hostname option60 option61 target upload download weekdays start stop
    config_get enabled $1 enable 0
    [ "$enabled" -ne 1 ] && return

    config_get mac $1 mac ""
    config_get ip $1 ip ""
    config_get hostname $1 hostname ""
    config_get option60 $1 option60 ""
    config_get option61 $1 option61 ""
    config_get target $1 target "drop"
    config_get upload $1 upload ""
    config_get download $1 download ""
    config_get weekdays $1 weekdays "1,2,3,4,5,6,7"
    config_get start $1 start "00:00"
    config_get stop $1 stop "23:59"

    # 时间检测
    check_time "$weekdays" "$start" "$stop" || return

    # 匹配 dhcp.leases
    while read -r ts lmac lip lname cid; do
        [ -n "$mac" ] && [ "$lmac" != "$mac" ] && continue
        [ -n "$ip" ] && [ "$lip" != "$ip" ] && continue
        [ -n "$hostname" ] && echo "$lname" | grep -qi "$hostname" || [ -z "$hostname" ] || continue
        [ -n "$option61" ] && [ "$cid" != "$option61" ] && continue
        [ -n "$option60" ] && [ "$lname" != "$option60" ] && continue

        ipset add $IPSET_NAME $lip
        if [ "$target" = "drop" ]; then
            iptables -A $CHAIN -s $lip -j DROP
            logger -t accesscontrol-ultra "DROP $lip ($lname)"
        else
            # 限速: 调用 tc
            dev=$(uci get network.lan.ifname 2>/dev/null || echo br-lan)
            tc qdisc del dev $dev root 2>/dev/null
            tc qdisc add dev $dev root handle 1: htb default 30
            tc class add dev $dev parent 1: classid 1:1 htb rate 100mbit
            [ -n "$download" ] && tc class add dev $dev parent 1:1 classid 1:10 htb rate ${download}kbit
            [ -n "$upload" ] && tc class add dev $dev parent 1:1 classid 1:20 htb rate ${upload}kbit
            tc filter add dev $dev protocol ip parent 1:0 prio 1 u32 match ip src $lip flowid 1:20
            tc filter add dev $dev protocol ip parent 1:0 prio 1 u32 match ip dst $lip flowid 1:10
            logger -t accesscontrol-ultra "LIMIT $lip up=$upload kbps down=$download kbps"
        fi
    done < /tmp/dhcp.leases
}

config_load $CONFIG
config_foreach apply_rule rule

logger -t accesscontrol-ultra "Rules applied"
