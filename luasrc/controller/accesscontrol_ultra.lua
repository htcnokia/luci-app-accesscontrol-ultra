module("luci.controller.accesscontrol_ultra", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/accesscontrol-ultra") then
        return
    end

    entry({"admin", "network", "accesscontrol-ultra"},
        firstchild(), _("Access Control Ultra"), 60).dependent=false

    entry({"admin", "network", "accesscontrol-ultra", "rules"},
        cbi("accesscontrol_ultra"), _("Rules"), 10).leaf=true

    entry({"admin", "network", "accesscontrol-ultra", "apply"},
        call("action_apply"), nil).leaf=true
end

function action_apply()
    luci.sys.call("/usr/bin/acu_apply_rules.sh &")
    luci.http.redirect(luci.dispatcher.build_url("admin/network/accesscontrol-ultra/rules"))
end
