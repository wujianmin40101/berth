# 泊位

中文说明见 [README.zh-CN.md](README.zh-CN.md)。

在 Mac 上给 Node.js、Python、Go、Java 和 Rust 停靠一个版本。可以设全局默认，也可以把版本写进项目目录。

Dock、窗口和侧栏上的名字是泊位。程序坞认的是应用文件名，所以产物是「泊位.app」。里面的可执行文件、工程目标、包名和本机数据目录仍叫 MacBJ，已经写进终端的钩子不用改。

## 架构

界面不直接调用 fnm、nvm 或 uv。它只认识 `RuntimeKind` 和一份 `RuntimeSnapshot`。

```
MacBJ/
  App/        窗口入口，以及列表选中、刷新、切换这些界面状态
  Domain/     运行时、版本、管理器，都是值类型
  Services/   登录 shell、探测脚本、输出解析、切换命令
  UI/         侧边栏和版本列表
```

读取和切换都走同一个登录 zsh（`zsh -lic`）。图形程序本身没有终端的 PATH，nvm 也只是 shell 函数，所以必须进用户自己的 shell 配置。

探测顺序：

- Node.js：fnm，然后 nvm，然后 Volta。都没有时，只显示当前 `node -v`，不能切换。
- Python：pyenv，然后 uv。都没有时，只显示当前 `python3 --version`，不能切换。

「默认」指新开终端会用的版本，不是某一个已经打开的终端里临时 `nvm use` 的结果。

没有版本管理器时，版本页只显示当前解释器，不能切换。装好管理器后点「刷新」。应用里不提供安装引导。

## 工具箱

端口、进程和本地服务在新安装时打开。本机和其他工具默认关闭，在工具箱里打开。已经打开过的保持打开。本机不会变成侧栏里和版本并列的一项。

本地服务从工具箱启动，项目页不放启动按钮。

## 增加一种运行时

1. 在 `RuntimeKind` 加一个 case，侧边栏会跟着出现。
2. 新增一个 `RuntimeProvider`，在 `ProviderRegistry` 里返回它。
3. 版本号和别名只能通过 `VersionToken`。安装命令要能带上镜像环境变量。
4. 用一段真实输出给解析补测试。

## 构建

用 Xcode 打开 `MacBJ.xcodeproj`，或：

```
xcodebuild -project MacBJ.xcodeproj -scheme MacBJ -destination 'platform=macOS' build test
```

应用没有打开 App Sandbox。它需要运行用户本机的版本管理器，并读取 home 目录里的配置。

<!-- CHECKPOINT id="ckpt_mw34nfkp_slcekc" time="2026-11-05T05:50:55.129Z" note="auto" fixes=0 questions=0 highlights=0 sections="" -->
