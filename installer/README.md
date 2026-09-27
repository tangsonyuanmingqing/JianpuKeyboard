# Windows 打包

在 Windows x64 上执行：

```powershell
.\installer\build_windows_release.ps1
```

本地交付文件为 `JianpuKeyboard-v1.6.0-windows-setup.exe` 和 `JianpuKeyboard-v1.6.0-windows-portable.zip`。安装向导允许选择当前用户或全部用户，并可选择开始菜单和桌面快捷方式。

脚本会重新构建 Release、调用 Inno Setup、将项目许可证与字体许可证加入便携目录、生成两个交付文件，并输出 SHA-256。运行前需要安装 Inno Setup 6；脚本会从 PATH、当前用户和系统默认安装目录查找 `ISCC.exe`。

可指定独立目录，避免覆盖之前的交付文件；相对路径基于运行命令时的工作目录：

```powershell
.\installer\build_windows_release.ps1 -OutputDirectory .\dist\release-v1.6.0
```

Flutter 或 Inno Setup 返回非零退出码时脚本立即终止，不能把旧构建当作新包。发布时应核对 `pubspec.yaml`、Inno Setup 脚本和产物中的版本号，并将安装版、便携版与对应 SHA-256 一起上传。产物在 `dist/`，不提交二进制安装包到 Git。

v1.6.0 的下载、升级说明与验证范围见 [发布说明](../docs/releases/v1.6.0.md)。安装前请保存并正常关闭旧版，建议先导出全库 JSON；便携版也使用本机应用支持目录保存数据，不是完全自包含的数据沙箱。安装包尚未配置代码签名。
