-- EcosystemGuard 状态栏
-- 常驻菜单栏显示累计清理次数；点击出菜单，可打开控制面板、启停监控、设置开机自启、退出。
-- 由 osacompile -s 编译为 stay-open applet（LSUIElement，不占用 Dock）。

use AppleScript version "2.4"
use framework "Foundation"
use framework "AppKit"
use scripting additions

property si : missing value
property itemCount : missing value
property itemMonitor : missing value
property itemLogin : missing value
property homePath : ""
property isRunning : "stopped"

on run
	set my homePath to do shell script "echo $HOME"
	set bar to current application's NSStatusBar's systemStatusBar()
	set my si to bar's statusItemWithLength_(current application's NSVariableStatusItemLength)
	my si's retain()
	my si's button()'s setTitle_("E …")
	my buildMenu()
	my refresh()
end run

on idle
	my refresh()
	return 8
end idle

on buildMenu()
	set m to current application's NSMenu's alloc()'s init()
	m's setAutoenablesItems_(false)

	set my itemCount to my addLabel(m, "累计清理：-- 次")
	my addSeparator(m)
	my addAction(m, "打开控制面板", "openPanel:")
	my addSeparator(m)
	set my itemMonitor to my addAction(m, "停止监控", "toggleMonitor:")
	my addSeparator(m)
	set my itemLogin to my addAction(m, "开机自启", "toggleLogin:")
	my addSeparator(m)
	my addAction(m, "退出菜单栏", "quitApp:")

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

on refresh()
	try
		set scriptPath to (my bundlePath()) & "/Contents/Resources/ui/menubar.sh"
		set t to do shell script "/bin/bash " & quoted form of scriptPath
		set ps to paragraphs of t
		set n to item 1 of ps as text
		set my isRunning to item 2 of ps as text
		set li to item 3 of ps as text

		my itemCount's setTitle_("累计清理：" & n & " 次")
		if isRunning is "running" then
			my itemMonitor's setTitle_("停止监控")
			my si's button()'s setTitle_("E " & n & "次")
		else
			my itemMonitor's setTitle_("启动监控")
			my si's button()'s setTitle_("E " & n & "次 ⏸")
		end if
		if li is "1" then
			my itemLogin's setState_(1)
		else
			my itemLogin's setState_(0)
		end if
	on error
		my si's button()'s setTitle_("E ?")
	end try
end refresh

on openPanel_(sender)
	try
		do shell script "/usr/bin/open -b com.github.keepupwithjason.ecosystemguard"
	on error
		try
			do shell script "/usr/bin/open -a '/Applications/EcosystemGuard.app'"
		end try
	end try
end openPanel_

on toggleMonitor_(sender)
	try
		if isRunning is "running" then
			do shell script "sudo -n /usr/local/sbin/ecoguard stop"
		else
			do shell script "sudo -n /usr/local/sbin/ecoguard start"
		end if
	on error errMsg
		display notification errMsg with title "EcosystemGuard"
	end try
	my refresh()
end toggleMonitor_

on toggleLogin_(sender)
	set la to homePath & "/Library/LaunchAgents/com.github.keepupwithjason.ecosystemguard.menubar.plist"
	set existsNow to do shell script "test -f " & quoted form of la & " && echo 1 || echo 0"
	if existsNow is "1" then
		try
			do shell script "/bin/launchctl bootout gui/" & (do shell script "id -u") & "/com.github.keepupwithjason.ecosystemguard.menubar"
		end try
		do shell script "rm -f " & quoted form of la
	else
		set appPath to my bundlePath()
		set tpl to appPath & "/Contents/Resources/ui/loginitem.plist.template"
		set agentsDir to homePath & "/Library/LaunchAgents"
		do shell script "/bin/mkdir -p " & quoted form of agentsDir & " && /usr/bin/sed " & quoted form of ("s|__APP_PATH__|" & appPath & "|") & " " & quoted form of tpl & " > " & quoted form of la
	end if
	my refresh()
end toggleLogin_

on quitApp_(sender)
	quit
end quitApp_

on bundlePath()
	set p to POSIX path of (path to me)
	if p ends with "/" then set p to text 1 thru -2 of p
	return p
end bundlePath
