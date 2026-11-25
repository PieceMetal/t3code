# T3 Agent Desk

这是基于 T3 Code 修改的非官方 Windows 桌面自用版，用来在同一个窗口里管理本机项目，使用已配置好的 Codex、Claude Code 等编码智能体，并继续之前的会话。这个仓库公开保存源码和修改记录，桌面端和命令行工具只在本机打包使用。

## 相比原版改了什么

- **桌面启动。** 快捷方式、窗口标题和本地发布包统一使用 T3 Agent Desk 的名称。安装自用版后，双击快捷方式或运行 `t3 start` 都会打开桌面窗口。
- **只接受本机连接。** Windows 后端监听 `127.0.0.1:48773`。自用版关闭了 T3 Connect 远程连接、预览隧道和 Webhook 任务，也关闭了浏览器 Cookie 导入和应用遥测。
- **保留四档会话权限。** 每个会话仍可选择「需审批」「自动接受编辑」「自动」或「完全访问」。桌面端以 Windows 标准用户权限运行，启动时会检查程序文件、会话数据库和凭据目录的访问权限。
- **独立保存数据。** 项目记录和会话数据库放在 `%USERPROFILE%\.local-agent-desk\data\userdata`，桌面用户配置放在 `%USERPROFILE%\.local-agent-desk\desktop`。更换程序版本时继续使用原有目录，已经迁移的会话可以接着用。

## 如何维护

日常改动提交到 `personal/local-only` 分支。自用版关闭了自动更新，由维护者按需合并上游稳定版，通过检查后再在本机打包。

Windows 后台维护入口是 `personal-windows/run-background.pyw`。`Build` 构建桌面端和命令行工具，`Check` 检查代码变更，`Verify` 核对已安装的桌面端及其本机服务。通过 `pythonw.exe` 调用时，任务在后台写日志并返回退出码，不会弹出终端窗口。

上游源码见 [pingdotgg/t3code](https://github.com/pingdotgg/t3code)。
