#define MyAppName "Jianpu Keyboard"
#define MyAppVersion "1.6.1"
#define MyAppPublisher "tangsonyuanmingqing"
#define MyAppExeName "jianpu_keyboard.exe"

[Setup]
AppId={{EDB91331-84B5-45A5-9E95-6D5845E262B2}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=JianpuKeyboard-v{#MyAppVersion}-windows-setup
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
LicenseFile=..\LICENSE

[Tasks]
Name: "startmenuicon"; Description: "创建开始菜单快捷方式"; Flags: unchecked
Name: "desktopicon"; Description: "创建桌面快捷方式"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "licenses\*"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE"; DestDir: "{app}\licenses"; DestName: "JianpuKeyboard-LICENSE.txt"; Flags: ignoreversion
Source: "..\assets\fonts\OFL-1.1.txt"; DestDir: "{app}\licenses"; DestName: "NotoSansCJK-OFL-1.1.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startmenuicon
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
