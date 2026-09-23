# Windows 打包

在 Windows x64 上执行：

```powershell
flutter build windows --release
iscc installer\jianpu_keyboard.iss
Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath dist\jianpu-keyboard-v1.5.0-windows-x64.zip -Force
Get-FileHash dist\* -Algorithm SHA256 | Format-Table -AutoSize
```

将安装包、便携 ZIP 和 SHA-256 清单上传到 GitHub Release。安装向导允许选择当前用户或全部用户，并可选择开始菜单和桌面快捷方式。
