local sys = require "luci.sys"

local m = Map("accesscontrol-ultra", translate("Access Control Ultra"),
    translate("Advanced DHCP + Time + Speed based access control."))

-- Turbo ACC 检测提醒
if nixio.fs.access("/etc/init.d/turboacc") then
    m:section(SimpleSection).template = "accesscontrol_ultra/turboacc_warn"
end

s = m:section(TypedSection, "rule", translate("Rules"))
s.addremove = true
s.anonymous = true

e = s:option(Flag, "enable", translate("Enable"))
e.default = 0

mac = s:option(Value, "mac", translate("MAC Address"))
ip = s:option(Value, "ip", translate("IP Address"))
hn = s:option(Value, "hostname", translate("Hostname Match (Regex)"))
o60 = s:option(Value, "option60", translate("Option60 (Vendor Class)"))
o61 = s:option(Value, "option61", translate("Option61 (Client ID)"))

target = s:option(ListValue, "target", translate("Action"))
target:value("drop", translate("Block Internet"))
target:value("limit", translate("Limit Speed"))

ul = s:option(Value, "upload", translate("Upload Limit (kbps)"))
dl = s:option(Value, "download", translate("Download Limit (kbps)"))
ul:depends("target", "limit")
dl:depends("target", "limit")

weekdays = s:option(Value, "weekdays", translate("Weekdays (1-7, comma)"))
start = s:option(Value, "start", translate("Start Time (HH:MM)"))
stop = s:option(Value, "stop", translate("Stop Time (HH:MM)"))

return m
