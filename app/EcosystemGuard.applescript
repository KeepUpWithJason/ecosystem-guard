-- EcosystemGuard 控制面板
-- 由 osacompile 打包成 .app；安装包内自带 payload，可独立安装监控服务。

property appName : "EcosystemGuard"
property egBin : "/usr/local/sbin/ecoguard"

on run
	repeat
		if not isInstalled() then
			set r to display dialog "监控还没有安装。" & return & return & "安装后会在后台常驻、随开机自动启动，把两个导致卡顿的系统进程控制在阈值内。" with title appName buttons {"退出", "安装"} default button "安装" with icon caution
			if button returned of r is "安装" then
				doInstall()
			else
				exit repeat
			end if
		else
			set r to display dialog (summaryText()) with title appName buttons {"关闭", "更多操作", "刷新"} default button "刷新" with icon note
			set b to button returned of r
			if b is "关闭" then
				exit repeat
			else if b is "更多操作" then
				showMenu()
			end if
		end if
	end repeat
end run

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

on showMenu()
	set opts to {"查看完整统计", "查看最近日志", "停止监控", "启动监控", "重启监控", "开机自启设置…", "卸载监控", "取消"}
	set sel to choose from list opts with title appName with prompt "选择要执行的操作：" default items {"查看完整统计"}
	if sel is false then return
	set c to item 1 of sel

	if c is "查看完整统计" then
		showText("清理统计", runCmd(egBin & " stats"))
	else if c is "查看最近日志" then
		showText("最近日志", runCmd(egBin & " log 30"))
	else if c is "停止监控" then
		showText("停止监控", runPriv(egBin & " stop"))
	else if c is "启动监控" then
		showText("启动监控", runPriv(egBin & " start"))
	else if c is "重启监控" then
		showText("重启监控", runPriv(egBin & " restart"))
	else if c is "卸载监控" then
		set q to display dialog "确定要卸载监控吗？" & return & return & "会删除后台服务与开机自启，并恢复两个 Apple 系统服务。" buttons {"取消", "卸载"} default button "取消" with icon caution
		if button returned of q is "卸载" then
			showText("卸载监控", runPriv(egBin & " uninstall"))
		end if
	else if c is "开机自启设置…" then
		toggleLoginItem()
	end if
end showMenu

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

on toggleLoginItem()
	set appPath to POSIX path of (path to me)
	if appPath ends with "/" then set appPath to text 1 thru -2 of appPath
	set existing to {}
	tell application "System Events" to set existing to name of every login item
	if existing contains appName then
		tell application "System Events" to delete login item appName
		display dialog "已取消开机自启。" buttons {"好"} default button 1
	else
		tell application "System Events" to make login item at end with properties {name:appName, path:appPath, hidden:false}
		display dialog "已设置开机自启。" & return & return & "下次登录会自动打开这个面板。" buttons {"好"} default button 1
	end if
end toggleLoginItem

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
