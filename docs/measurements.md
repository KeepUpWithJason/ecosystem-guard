# 实测记录（2026-10）

这份文档记录项目诞生的起因和一组实机数据，方便后来者判断哪些结论是实测的、哪些是推测的。

测试环境：macOS 27.0（26A428），Apple Silicon，SIP 开启。

## 1. 现象

活动监视器里 `ecosystemd` 与 `ecosystemanalyticsd` 反复占据 CPU 前列（47.2% / 28.1%），在活动监视器里强制退出后，过一会儿又出现。

这两个进程的真实身份：

| 进程 | 路径 |
|---|---|
| `ecosystemd` | `/System/Library/PrivateFrameworks/Ecosystem.framework/Support/ecosystemd` |
| `ecosystemanalyticsd` | `/System/Library/PrivateFrameworks/EcosystemAnalytics.framework/Support/ecosystemanalyticsd` |

两者都以 root 运行，父进程是 `launchd`(PID 1)，由 `/System/Library/LaunchDaemons/` 下的 plist 注册，并声明了 Mach 服务——这意味着**按需唤醒**：进程退出后，只要有系统组件查找对应服务，`launchd` 就会把它拉起来（plist 中 `minimum runtime` 为 10 秒）。

## 2. 两分钟连续采样

每 3 秒执行 `ps -Ao pid,pcpu,etime,comm`，摘录：

```
14:24:29 67564  35.1   01:10  .../ecosystemanalyticsd
14:24:29 67565  30.8   01:10  .../ecosystemd
14:24:41 67564  31.9   01:22  .../ecosystemanalyticsd
14:24:41 67565  51.8   01:22  .../ecosystemd
14:24:50 67564  30.9   01:31  .../ecosystemanalyticsd
14:24:50 67565  52.1   01:31  .../ecosystemd
14:24:53 67564  43.5   01:34  .../ecosystemanalyticsd
14:24:53 67565  40.1   01:34  .../ecosystemd
```

结论：

- `ecosystemd` 长期在 **30%–52%**；
- `ecosystemanalyticsd` 长期在 **21%–43%**；
- PID 在几分钟内反复变化（67564/67565 → 680xx → 75646 → 84027 → 88547），确认存在「退出—重来」循环。

同期还观察到 `WindowServer` 约 105%、可用内存仅剩 100–400 MB、压缩内存约 3 GB，负载均值 7–10。也就是说，卡顿未必全部来自这两个进程。

## 3. 权限实测

普通用户对 root 进程发信号会被拒绝：

```
$ kill -0 88547
kill: 88547: Operation not permitted
```

这是所有「菜单栏 App 类限流工具」拿这类进程没办法的根本原因。

## 4. launchd 行为实测

| 操作 | 结果 |
|---|---|
| `launchctl disable system/com.apple.ecosystemd` | ✅ 成功，`print-disabled` 中标记为 `disabled` |
| `launchctl bootout system/com.apple.ecosystemd` | ❌ `Boot-out failed: 150: Operation not permitted while System Integrity Protection is engaged` |
| 杀进程后观察 | 数秒~数十秒后出现新 PID，说明仅靠杀进程不够 |

`launchctl bootout` 被 SIP 拒绝这一点，与 [RemoveMacAI](https://github.com/omlahore/RemoveMacAI) README 中「SIP 开启时 macOS 拒绝卸载大部分后台服务」的说法一致。

因此本工具的默认 `MODE=both`：先尝试 `disable`（重启后见效），同时保留按阈值的清理作为兜底。

## 5. 一个容易踩的坑：launchd bootout 是异步的

安装脚本第一版在 `launchctl bootout` 之后立刻 `bootstrap`，结果服务被**彻底移除**：

```
14:29:46.910  bootout initiated, scheduling cleanup in 5 sec
14:29:46.918  bootstrap        <- 被忽略
14:29:46.923  kickstart: service already stopped
14:29:51.324  exited due to exit(0)  -> removing service -> job state = removed
```

修复方式：bootout 之后轮询 `launchctl print` 直到确认卸载完成，再执行 `bootstrap` + `kickstart`，最后校验 `state = running` 而不是仅仅「job 存在」。

## 6. 另一类坑：桌面目录的隐私保护

以管理员身份执行 `do shell script` 时，root 进程读不到「桌面 / 文稿」目录，会得到：

```
/bin/bash: ./install.sh: Operation not permitted (126)
```

系统日志显示是 `kTCCServiceSystemPolicyDesktopFolder` 拒绝授权。所以 `install.sh` 会先把整个目录复制到 `/tmp`，再提权执行副本。
