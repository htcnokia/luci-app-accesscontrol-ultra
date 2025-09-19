#!/bin/bash
# 一键生成 luci-app-accesscontrol-plus（增强：动态MAC、定时更新、自动填充终端名、语言对齐）

# 目录
mkdir -p ./package/luci-app-accesscontrol-plus/{luasrc/{controller,view/miaplus,model/cbi},root/etc/{config,uci-defaults,init.d},root/usr/share/rpcd/acl.d,po/zh-Hans}

# 控制器
cat <<'EOF' > ./package/luci-app-accesscontrol-plus/luasrc/controller/miaplus.lua
module("luci.controller.miaplus",package.seeall)

function index()
	if not nixio.fs.access("/etc/config/miaplus") then return end
	entry({"admin","services","miaplus"},cbi("base"),_("Internet Access Schedule Control Plus"),30).dependent=true
	entry({"admin","services","miaplus","status"},call("act_status")).leaf=true
	entry({"admin","services","miaplus","base"},cbi("base"),_("Base Setting"),40).leaf=true
	entry({"admin","services","miaplus","advanced"},cbi("advanced"),_("Advance Setting"),50).leaf=true
	entry({"admin","services","miaplus","template"},cbi("template"),nil).leaf=true
end

function act_status()
	local e={}
	e.running=luci.sys.call("iptables -L INPUT |grep MIAPLUS >/dev/null")==0
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end
EOF

# 状态视图
cat <<'EOF' > ./package/luci-app-accesscontrol-plus/luasrc/view/miaplus/miaplus_status.htm
<script type="text/javascript">//<![CDATA[
XHR.poll(3,'<%=url([[admin]],[[services]],[[miaplus]],[[status]])%>',null,function(x,data){
	var tb=document.getElementById('miaplus_status');
	if(data&&tb){
		if(data.running){
			tb.innerHTML='<em><b><font color=green><%:Internet Access Schedule Control Plus%> <%:RUNNING%></font></b></em>';
		}else{
			tb.innerHTML='<em><b><font color=red><%:Internet Access Schedule Control Plus%> <%:NOT RUNNING%></font></b></em>';
		}
	}
});
//]]>
</script>
<fieldset class="cbi-section">
<p id="miaplus_status"><em><%:Collecting data...%></em></p>
</fieldset>
EOF

# 高级设置
cat <<'EOF' > ./package/luci-app-accesscontrol-plus/luasrc/model/cbi/advanced.lua
local ds=require"luci.dispatcher"
a=Map("miaplus")
t=a:section(TypedSection,"templates")
t.template="cbi/tblsection";t.anonymous=true;t.addremove=true;t.sortable=true
t.extedit=ds.build_url("admin/services/miaplus/template/%s")

e=t:option(Flag,"enable",translate("Enabled"));e.rmempty=false;e.default="1"
e=t:option(Value,"title",translate("Template"));e.width="40%";e.optional=false;e.default="default"
return a
EOF

# 基础设置（改进：自动填充终端名）
cat <<'EOF' > ./package/luci-app-accesscontrol-plus/luasrc/model/cbi/base.lua
local uci=luci.model.uci.cursor()
a=Map("miaplus")
a.title=translate("Internet Access Schedule Control Plus")
a.description=translate("Access Schedule Control Description")
a:section(SimpleSection).template="miaplus/miaplus_status"

t=a:section(TypedSection,"basic");t.anonymous=true
e=t:option(Flag,"enable",translate("Enabled"));e.rmempty=false
e=t:option(Flag,"strict",translate("Strict Mode"));e.description=translate("Strict Mode will degrade CPU performance, but it can achieve better results");e.rmempty=false
e=t:option(Flag,"ipv6enable",translate("IPV6 Enabled"));e.rmempty=false

t=a:section(TypedSection,"macbind",translate("Client Rules"))
t.template="cbi/tblsection";t.anonymous=true;t.addremove=true;t.sortable=true
e=t:option(Flag,"enable",translate("Enabled"));e.rmempty=false;e.default="1"

e=t:option(Value,"scan_timeout",translate("Scan Interval (minutes)"));e.datatype="uinteger";e.default="30"
e=t:option(Flag,"dynamic",translate("Dynamic MAC"));e.default=0

e=t:option(Value,"hostname",translate("Terminal Name"))
e:depends("dynamic","1")
function e.cfgvalue(self, section)
    local v = Value.cfgvalue(self, section)
    if v and v ~= "" then return v end
    local mac_val = self.map:get(section, "macaddr")
    if mac_val and mac_val:match("%(") then
        local name = mac_val:match("%((.-)%)$")
        return name or ""
    end
    return ""
end

e=t:option(Value,"macaddr",translate("MAC address (Computer Name)"));e.rmempty=true
luci.sys.net.mac_hints(function(mac,name) e:value(mac,"%s (%s)"%{mac,name}) end)

e=t:option(ListValue,"template",translate("Template"))
uci:foreach("miaplus","templates",function(s) e:value(s[".name"],s["title"]) end)
return a
EOF

# 模板规则
cat <<'EOF' > ./package/luci-app-accesscontrol-plus/luasrc/model/cbi/template.lua
a=Map("miaplus")
local section=arg[1]
t=a:section(TypedSection,section,translate("Rules"))
t.template="cbi/tblsection";t.anonymous=true;t.addremove=true;t.sortable=true
e=t:option(Flag,"enable",translate("Enabled"));e.rmempty=false;e.default="1"
e=t:option(Value,"timeon",translate("Start time"));e.default="00:00"
e=t:option(Value,"timeoff",translate("End time"));e.default="23:59"
for _,d in ipairs({"Mon","Tue","Wed","Thu","Fri","Sat","Sun"}) do
 local z=t:option(Flag,"z".._,translate(d));z.rmempty=true;z.default=1
end
return a
EOF

# 默认配置
cat <<'EOF' > ./package/luci-app-accesscontrol-plus/root/etc/config/miaplus
config basic
	option enable '0'
	option strict '0'

config templates
	option enable '0'
	option title 'default'
EOF

# uci-defaults
cat <<'EOF' > ./package/luci-app-accesscontrol-plus/root/etc/uci-defaults/luci-miaplus
#!/bin/sh
uci -q batch <<-EOT >/dev/null
	delete ucitrack.@miaplus[-1]
	add ucitrack miaplus
	set ucitrack.@miaplus[-1].init=miaplus
	commit ucitrack
	delete firewall.miaplus
	set firewall.miaplus=include
	set firewall.miaplus.type=script
	set firewall.miaplus.path=/etc/miaplus.include
	set firewall.miaplus.reload=1
	commit firewall
EOT
rm -f /tmp/luci-indexcache
exit 0
EOF

# 防火墙 include
echo "/etc/init.d/miaplus restart" > ./package/luci-app-accesscontrol-plus/root/etc/miaplus.include

# init.d (改进 get_current_mac 优先 DHCP、取最新租约)
cat <<'EOF' > ./package/luci-app-accesscontrol-plus/root/etc/init.d/miaplus
#!/bin/sh /etc/rc.common
START=30
CONFIG=miaplus

uci_get_by_type(){ local idx=${4:-0};uci get $CONFIG.@$1[$idx].$2 2>/dev/null || echo $3; }

get_current_mac(){
 local h="$1" mac
 if [ -f /tmp/dhcp.leases ]; then
  mac=$(awk -v hn="$h" 'BEGIN{lc=tolower(hn);best="";max=0}
    {if(tolower($4)==lc && $1>max){best=$2;max=$1}}
    END{print best}' /tmp/dhcp.leases)
 fi
 [ -z "$mac" ] && mac=$(grep -i "$h" /proc/net/arp | awk '{print $4}' | head -n1)
 echo "$mac"
}

update_dynamic_mac(){
 local idx=0 changed=0
 while :;do
   local en=$(uci_get_by_type macbind enable "" $idx) || break
   [ -z "$en" ]&&break
   local dyn=$(uci_get_by_type macbind dynamic 0 $idx)
   [ "$en" = "1" ]&&[ "$dyn" = "1" ]||{ idx=$((idx+1));continue; }
   local hn=$(uci_get_by_type macbind hostname "" $idx)
   [ -z "$hn" ]&&{ idx=$((idx+1));continue; }
   local old=$(uci_get_by_type macbind macaddr "" $idx)
   local new=$(get_current_mac "$hn")
   [ -z "$new" ]&&{ idx=$((idx+1));continue; }
   if [ "$new" != "$old" ];then
     logger -t miaplus "MAC changed for $hn: $old -> $new"
     uci set $CONFIG.@macbind[$idx].macaddr="$new";changed=1
   fi
   idx=$((idx+1))
 done
 [ $changed -eq 1 ]&&uci commit $CONFIG && /etc/init.d/miaplus restart
}

setup_cron(){
 sed -i '/MIAPLUS_CRON/d' /etc/crontabs/root
 local min=0 idx=0
 while :;do
  local en=$(uci_get_by_type macbind enable "" $idx)||break
  [ -z "$en" ]&&break
  local dyn=$(uci_get_by_type macbind dynamic 0 $idx)
  local iv=$(uci_get_by_type macbind scan_timeout 30 $idx)
  [ "$en" = "1" ]&&[ "$dyn" = "1" ]&&{ [ $min -eq 0 ]||[ $iv -lt $min ]&&min=$iv; }
  idx=$((idx+1))
 done
 [ $min -gt 0 ]&&echo "*/$min * * * * /etc/init.d/miaplus update_dynamic_mac # MIAPLUS_CRON" >>/etc/crontabs/root && /etc/init.d/cron restart
}

add_rules(){
 local tpl_sections=$(uci -n show $CONFIG|grep "=templates"|cut -d. -f2)
 for s in $tpl_sections;do
  [ "$(uci get $CONFIG.$s.enable)" = "1" ]||continue
  local macs=$(uci -q show $CONFIG|grep macbind|grep "template='$s'"|grep "enable='1'"|cut -d= -f2)
  for m in $macs;do iptables -t filter -A MIAPLUS -m mac --mac-source $m -j DROP;done
 done
}

start(){ stop;[ "$(uci get $CONFIG.@basic[0].enable)" = "0" ]&&return
 iptables -t filter -N MIAPLUS 2>/dev/null
 iptables -I INPUT -p udp --dport 53 -j MIAPLUS
 iptables -I INPUT -p tcp --dport 53 -j MIAPLUS
 add_rules;setup_cron; }
stop(){
 iptables -t filter -F MIAPLUS 2>/dev/null
 iptables -t filter -X MIAPLUS 2>/dev/null
 sed -i '/MIAPLUS_CRON/d' /etc/crontabs/root; /etc/init.d/cron restart
}
case "$1" in
 start) start;;
 stop) stop;;
 restart) stop;start;;
 update_dynamic_mac) update_dynamic_mac;;
 *) echo "Usage: $0 start|stop|restart|update_dynamic_mac";;
esac
EOF

# ACL
cat <<'EOF' > ./package/luci-app-accesscontrol-plus/root/usr/share/rpcd/acl.d/luci-app-accesscontrol-plus.json
{
 "luci-app-accesscontrol-plus":{
  "description":"Grant UCI access for luci-app-accesscontrol-plus",
  "read":{"uci":["miaplus"]},
  "write":{"uci":["miaplus"]}
 }
}
EOF

# 语言文件
cat <<'EOF' > ./package/luci-app-accesscontrol-plus/po/zh-Hans/miaplus.po
msgid "Internet Access Schedule Control Plus"
msgstr "上网时间控制Plus"
msgid "Access Schedule Control Description"
msgstr "设置客户端访问互联网的时间"
msgid "Enabled"
msgstr "启用"
msgid "Base Setting"
msgstr "基础设置"
msgid "Advance Setting"
msgstr "高级设置"
msgid "Scan Interval (minutes)"
msgstr "扫描间隔(分钟)"
msgid "Dynamic MAC"
msgstr "动态MAC"
msgid "Terminal Name"
msgstr "终端名"
msgid "MAC address (Computer Name)"
msgstr "MAC地址(主机名)"
msgid "Template"
msgstr "模板"
msgid "Client Rules"
msgstr "客户端规则"
msgid "Strict Mode"
msgstr "严格模式"
msgid "Strict Mode will degrade CPU performance, but it can achieve better results"
msgstr "严格模式会消耗CPU性能，但能即时拦截"
msgid "Start time"
msgstr "开始时间"
msgid "End time"
msgstr "结束时间"
msgid "Mon"
msgstr "一"
msgid "Tue"
msgstr "二"
msgid "Wed"
msgstr "三"
msgid "Thu"
msgstr "四"
msgid "Fri"
msgstr "五"
msgid "Sat"
msgstr "六"
msgid "Sun"
msgstr "日"
msgid "Collecting data..."
msgstr "正在收集数据..."
msgid "RUNNING"
msgstr "运行中"
msgid "NOT RUNNING"
msgstr "未运行"
EOF

# 保留原始 Makefile
cat <<'EOF' > ./package/luci-app-accesscontrol-plus/Makefile
# Copyright (C) 2016 Openwrt.org
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Access Control Configuration
LUCI_DEPENDS:=+snmpd
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-accesscontrol-plus
PKG_VERSION:=1
PKG_RELEASE:=11

include $(TOPDIR)/feeds/luci/luci.mk
# call BuildPackage - OpenWrt buildroot signature
EOF

# 修正权限
chmod +x ./package/luci-app-accesscontrol-plus/root/etc/init.d/miaplus
chmod +x ./package/luci-app-accesscontrol-plus/root/etc/uci-defaults/luci-miaplus

echo "插件源码生成完成（含动态MAC、终端名自动填充、语言对齐、权限修复）"
echo "编译 make package/luci-app-accesscontrol-plus/compile V=s -j\$(nproc) "