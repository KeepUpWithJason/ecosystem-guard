-- EcosystemGuard 单一 App
--   菜单栏常驻：显示今日清理次数（E · N次），点开可启停、看面板、开关自启、退出
--   控制面板：双击 App 时弹出，看今日/累计、统计、日志、卸载
--   由 osacompile -s 编译为 stay-open applet（LSUIElement，不占 Dock）
--   安装包内自带 payload，未克隆仓库也能一键安装监控服务

use AppleScript version "2.4"
use framework "Foundation"
use framework "AppKit"
use scripting additions

property appName : "EcosystemGuard"
property egBin : "/usr/local/sbin/ecoguard"

property si : missing value
property itemCount : missing value
property itemMonitor : missing value
property itemLogin : missing value
property homePath : ""
property isRunning : "stopped"
property ready : false

-- 登录启动时用标记文件区分：只进菜单栏，不弹面板
property markDir : "/Library/Application Support/EcosystemGuard"

on run
	my setup()
	if not (my isBackgroundLaunch()) then my showPanel()
end run

on reopen
	my showPanel()
end reopen

on idle
	my refreshStatus()
	return 8
end idle

-- ---------------------------------------------------------------- 初始化 ----

on setup()
	if ready then return
	set my homePath to do shell script "echo $HOME"
	set bar to current application's NSStatusBar's systemStatusBar()
	set my si to bar's statusItemWithLength_(current application's NSVariableStatusItemLength)
	my si's retain()
	my si's button()'s setTitle_("E · …")
	my buildMenu()
	my ensureLoginItem()
	my refreshStatus()
	set my ready to true
end setup

on buildMenu()
	set m to current application's NSMenu's alloc()'s init()
	m's setAutoenablesItems_(false)

	set my itemCount to my addLabel(m, "今日清理：-- 次")
	my addSeparator(m)
	my addAction(m, "打开控制面板", "openPanel:")
	my addSeparator(m)
	set my itemMonitor to my addAction(m, "停止监控", "toggleMonitor:")
	my addSeparator(m)
	set my itemLogin to my addAction(m, "开机自启", "toggleLogin:")
	my addSeparator(m)
	my addAction(m, "退出", "quitApp:")

	my si's setMenu_(m)
end buildMenu

on addAction(m, title, sel)
	set mi to current application's NSMenuItem's alloc()'s initWithTitle_action_keyEquivalent_(title, sel, "")
	mi's setTarget_(me)
	m's addItem_(mi)
	return mi
end addAction

on addLabel(m, title)
	set mi to current application's NSMenuItem's alloc()'s initWithTitle_action_keyEquivalent_(title, missing value, "")
	mi's setEnabled_(false)
	m's addItem_(mi)
	return mi
end addLabel

on addSeparator(m)
	m's addItem_(current application's NSMenuItem's separatorItem())
end addSeparator

-- 状态栏的标题与菜单项文字每 8 秒刷新一次
on refreshStatus()
	try
		set scriptPath to (my bundlePath()) & "/Contents/Resources/ui/menubar.sh"
		set t to do shell script "/bin/bash " & quoted form of scriptPath
		set ps to paragraphs of t
		set n to item 1 of ps as text
		set my isRunning to item 2 of ps as text
		set li to item 3 of ps as text

		my itemCount's setTitle_("今日清理：" & n & " 次")
		if isRunning is "running" then
			my itemMonitor's setTitle_("停止监控")
			my si's button()'s setTitle_("E · " & n & "次")
		else
			my itemMonitor's setTitle_("启动监控")
			my si's button()'s setTitle_("E · " & n & "次 ⏸")
		end if
		if li is "1" then
			my itemLogin's setState_(1)
		else
			my itemLogin's setState_(0)
		end if
	on error
		my si's button()'s setTitle_("E · ?")
	end try
end refreshStatus

-- ------------------------------------------------------------ 菜单栏动作 ----

on openPanel_(sender)
	my showPanel()
end openPanel_

on toggleMonitor_(sender)
	try
		if isRunning is "running" then
			do shell script "sudo -n /usr/local/sbin/ecoguard stop"
		else
			do shell script "sudo -n /usr/local/sbin/ecoguard start"
		end if
	on error errMsg
		display notification errMsg with title appName
	end try
	my refreshStatus()
end toggleMonitor_

on toggleLogin_(sender)
	my toggleLoginCore()
	my refreshStatus()
end toggleLogin_

on quitApp_(sender)
	quit
end quitApp_

-- ---------------------------------------------------------------- 面板 ----

on showPanel()
	my bringToFront()
	repeat
		if not (my isInstalled()) then
			set r to display dialog "监控还没有安装。" & return & return & "安装后会在后台常驻、随开机自动启动，把两个导致卡顿的系统进程控制在阈值内。" with title appName buttons {"稍后", "安装"} default button "安装" with icon caution
			if button returned of r is "安装" then
				my doInstall()
			else
				return
			end if
		else
			set r to display dialog (my summaryText()) with title appName buttons {"关闭", "更多操作", "刷新"} default button "刷新" with icon note
			set b to button returned of r
			if b is "关闭" then
				return
			else if b is "更多操作" then
				my showMenu()
			end if
		end if
	end repeat
end showPanel

on bringToFront()
	try
		current application's NSApp's activateIgnoringOtherApps_(true)
	end try
end bringToFront

on showMenu()
	set opts to {"查看完整统计", "查看最近日志", "停止监控", "启动监控", "重启监控", "开机自启：开 / 关", "卸载监控", "取消"}
	set sel to choose from list opts with title appName with prompt "选择要执行的操作：" default items {"查看完整统计"}
	if sel is false then return
	set c to item 1 of sel

	if c is "查看完整统计" then
		my showText("清理统计", my runCmd(egBin & " stats"))
	else if c is "查看最近日志" then
		my showText("最近日志", my runCmd(egBin & " log 30"))
	else if c is "停止监控" then
		my showText("停止监控", my runPriv(egBin & " stop"))
	else if c is "启动监控" then
		my showText("启动监控", my runPriv(egBin & " start"))
	else if c is "重启监控" then
		my showText("重启监控", my runPriv(egBin & " restart"))
	else if c is "卸载监控" then
		set q to display dialog "确定要卸载监控吗？" & return & return & "会删除后台服务与开机自启，并恢复两个 Apple 系统服务。" buttons {"取消", "卸载"} default button "取消" with icon caution
		if button returned of q is "卸载" then
			my showText("卸载监控", my runPriv(egBin & " uninstall"))
		end if
	else if c is "开机自启：开 / 关" then
		set newState to my toggleLoginCore()
		if newState is "on" then
			display dialog "已开启开机自启。" & return & return & "下次登录时菜单栏会自动出现。" buttons {"好"} default button 1
		else
			display dialog "已关闭开机自启。" & return & return & "后台监控服务不受影响，仍然随开机启动。" buttons {"好"} default button 1
		end if
		my refreshStatus()
	end if
end showMenu

-- ------------------------------------------------------------------ 工具 ----

on isInstalled()
	try
		do shell script "test -x " & egBin & " && test -f '/Library/LaunchDaemons/com.local.ecosystemguard.plist'"
		return true
	on error
		return false
	end try
end isInstalled

on bundlePath()
	set p to POSIX path of (path to me)
	if p ends with "/" then set p to text 1 thru -2 of p
	return p
end bundlePath

on summaryText()
	set scriptPath to (my bundlePath()) & "/Contents/Resources/ui/summary.sh"
	return do shell script "/bin/bash " & quoted form of scriptPath
end summaryText

on doInstall()
	set payload to (my bundlePath()) & "/Contents/Resources/payload"
	try
		set out to do shell script "/bin/bash " & quoted form of (payload & "/install.sh") with administrator privileges
		display dialog "✅ 安装完成，监控已在后台运行。" & return & return & (my tailOf(out, 5)) buttons {"好"} default button 1 with icon note
	on error errMsg
		if errMsg contains "-128" then return
		display dialog "安装失败：" & return & return & errMsg buttons {"好"} default button 1 with icon stop
	end try
end doInstall

on runCmd(cmd)
	try
		return do shell script cmd
	on error errMsg
		return "执行失败：" & errMsg
	end try
end runCmd

on runPriv(cmd)
	try
		return do shell script "sudo -n " & cmd
	on error
		try
			return do shell script cmd with administrator privileges
		on error errMsg
			if errMsg contains "-128" then return "已取消。"
			return "执行失败：" & errMsg
		end try
	end try
end runPriv

-- ------------------------------------------------------------ 登录项管理 ----

on agentPlist()
	return homePath & "/Library/LaunchAgents/com.github.keepupwithjason.ecosystemguard.menubar.plist"
end agentPlist

on offMarker()
	return homePath & "/Library/Application Support/EcosystemGuard/menubar-manual-off"
end offMarker

-- 首次运行自动设为登录项；用户手动关过就不再自动加回
on ensureLoginItem()
	try
		set appPath to my bundlePath()
		if not (appPath starts with "/Applications/") then return
		set la to my agentPlist()
		set mk to my offMarker()
		set hasPlist to do shell script "test -f " & quoted form of la & " && echo 1 || echo 0"
		set hasMarker to do shell script "test -f " & quoted form of mk & " && echo 1 || echo 0"
		if hasPlist is "0" and hasMarker is "0" then my writeLoginItem()
	end try
end ensureLoginItem

on writeLoginItem()
	set appPath to my bundlePath()
	set tpl to appPath & "/Contents/Resources/ui/loginitem.plist.template"
	set agentsDir to homePath & "/Library/LaunchAgents"
	set la to my agentPlist()
	do shell script "/bin/mkdir -p " & quoted form of agentsDir & " && /usr/bin/sed " & quoted form of ("s|__APP_PATH__|" & appPath & "|") & " " & quoted form of tpl & " > " & quoted form of la
end writeLoginItem

-- 返回 "on" / "off"
on toggleLoginCore()
	set la to my agentPlist()
	set mk to my offMarker()
	set backupDir to homePath & "/Library/Application Support/EcosystemGuard"
	set existsNow to do shell script "test -f " & quoted form of la & " && echo 1 || echo 0"
	if existsNow is "1" then
		try
			do shell script "/bin/launchctl bootout gui/" & (do shell script "id -u") & "/com.github.keepupwithjason.ecosystemguard.menubar"
		end try
		do shell script "/bin/rm -f " & quoted form of la & " && /bin/mkdir -p " & quoted form of backupDir & " && /usr/bin/touch " & quoted form of mk
		return "off"
	else
		my writeLoginItem()
		do shell script "/bin/rm -f " & quoted form of mk
		return "on"
	end if
end toggleLoginCore

-- 登录启动判定：登录脚本会先写标记，App 读到新鲜标记就只进菜单栏
on isBackgroundLaunch()
	try
		set mk to homePath & markDir & "/background-launch"
		set fresh to do shell script "/usr/bin/find " & quoted form of mk & " -mmin -1 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' '"
		do shell script "/bin/rm -f " & quoted form of mk
		return (fresh is "1")
	on error
		return false
	end try
end isBackgroundLaunch

on showText(t, body)
	display dialog body with title (appName & " — " & t) buttons {"好"} default button 1
end showText

on tailOf(txt, n)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set ls to text items of txt
	set cnt to count of ls
	if cnt > n then set ls to items (cnt - n + 1) thru cnt of ls
	set r to ls as text
	set AppleScript's text item delimiters to oldDelims
	return r
end tailOf
