# Windows 打包

在 Windows x64 的 PowerShell 终端中执行（兼容 Windows PowerShell 5.1 和 PowerShell 7）：

```powershell
.\installer\build_windows_release.ps1
```

本地交付文件为 `JianpuKeyboard-v1.6.1-windows-setup.exe` 和 `JianpuKeyboard-v1.6.1-windows-portable.zip`。安装向导允许选择当前用户或全部用户，并可选择开始菜单和桌面快捷方式。

默认输出到项目的 `dist\yyyy-MM-dd\HH-mm\`，日期和时间使用打包开始时的同一个本机时间。小时采用 24 小时制，小时、分钟均补齐两位，例如 `dist\2026-09-27\16-07\JianpuKeyboard-v1.6.1-windows-setup.exe`。同一分钟重复打包会覆盖该时间目录中的同名安装包、便携包和校验文件；不同分钟的产物分别保留，每次构建日志也分别保留。已有日期目录中的历史产物不会移动。

脚本启动时显示并创建输出目录、保存 `build-时间戳.log`，先检查 Flutter 和 Inno Setup，再重新构建 Release、调用 Inno Setup、加入项目与字体许可证、生成两个交付文件，并写入 `SHA256SUMS.txt`。日志包含外部工具的标准输出与标准错误，成功与否按退出码判定，不把警告输出等同于失败。看到日期目录不等于打包成功：只有三步完成、校验产物存在并输出“打包完成”才算完成；失败时会抛出错误，不进入后续打包步骤。

运行前需要 Flutter、Windows C++ 编译环境和 Inno Setup 6。脚本默认从 PATH 查找 Flutter，从 PATH、当前用户和系统默认安装目录查找 `ISCC.exe`。Flutter 不在 PATH 时可显式指定：

```powershell
.\installer\build_windows_release.ps1 `
    -FlutterExecutable 'D:\developer\Flutter\bin\flutter.bat'
```

Inno Setup 装在其他位置时可追加 `-InnoSetupCompiler '完整路径\ISCC.exe'`。如果终端提示执行策略阻止脚本，可以对本次可信本地脚本调用使用以下命令，不修改系统执行策略：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\installer\build_windows_release.ps1 `
    -FlutterExecutable 'D:\developer\Flutter\bin\flutter.bat'
```

可指定独立目录，避免覆盖之前的交付文件；显式指定的目录不会再自动追加日期和时间，相对路径基于运行命令时的工作目录：

```powershell
.\installer\build_windows_release.ps1 -OutputDirectory .\dist\release-v1.6.1
```

Flutter 或 Inno Setup 返回非零退出码时脚本立即终止，不能把旧构建当作新包。发布时应核对 `pubspec.yaml`、Inno Setup 脚本和产物中的版本号，并将安装版、便携版与对应 SHA-256 一起上传。产物在 `dist/`，不提交二进制安装包到 Git。

v1.6.1 的下载、升级说明与验证范围见 [发布说明](../docs/releases/v1.6.1.md)。安装前请保存并正常关闭旧版，建议先导出全库 JSON；便携版也使用本机应用支持目录保存数据，不是完全自包含的数据沙箱。安装包尚未配置代码签名。

## 编码故障与回归

2026-09-27 复现了旧脚本在 Windows PowerShell 5.1 中启动即失败：无 BOM 的 UTF-8 中文脚本被按系统编码读取，导致 `ExpectedValueExpression`／`UnexpectedToken`，报错定位到 Inno Setup 的 `/O` 参数处，实际上尚未执行任何构建。同一源码显式按 UTF-8 读取后解析错误为 0，PowerShell 7 也能完成原脚本打包；故障不是缺少 Inno Setup 或日期计算错误。

脚本现保存为 **UTF-8 with BOM**，修改时须保留 BOM。新增快速回归检查编码、当前解释器解析、日期与小时分钟目录（固定时间验证 `2026-09-27\16-07`）、显式输出目录，以及缺少 Flutter 时的终止与日志保留；还通过小型外部进程验证非零退出码会失败、零退出码的 stderr 不误报失败、两个输出流都进日志，不进行编译或安装：

另已修正显式相对输出目录的解析：旧 `.NET GetFullPath` 会按进程初始目录解析，可能与 PowerShell 的 `Set-Location` 后当前位置不同；现在按 PowerShell 当前目录解析。回归会先切换目录，再检查相对输出路径，避免同一实现计算“预期值”造成假通过。

```powershell
.\installer\test_windows_packaging.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\installer\test_windows_packaging.ps1
```

产物按当前工作区代码生成，包含未提交修改。脚本不自动安装应用、提交、推送或发布到 GitHub。

本轮修复后的快速回归在 PowerShell 5.1／7 均通过，两种终端的完整 Release 构建与安装包／便携包生成均实际通过。最终日志为本机 `dist/2026-09-27/build-20260927-155705-973.log`（5.1）和 `build-20260927-155731-938.log`（7），均已核对包含 Flutter／Inno Setup 输出与成功结果。最终两个交付文件的 SHA-256 与 `SHA256SUMS.txt` 一致，便携包全部 19 个文件与 Release 内容哈希一致；未执行安装器或覆盖个人曲谱数据。

后续 v1.6.1 发布构建实际输出到 `dist/2026-09-27/16-20/`，日志为 `build-20260927-162055-185.log`；日期／时间层级、Windows Release、安装包、便携包与校验文件均成功生成，程序文件版本和产品版本为 1.6.1。v1.6.0 的上述历史构建记录保持原样。
