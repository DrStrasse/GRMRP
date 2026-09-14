; Inno Setup — сценарий установщика «Терминала Комитета»
; Соберите сначала dist\Komitet.exe (build_exe.bat),
; затем откройте этот файл в Inno Setup и нажмите Compile.

[Setup]
AppId={{8F2C1A4E-7B3D-4C5E-9A6B-1D2E3F4A5B6C}
AppName=Терминал Комитета
AppVersion=1.0
AppPublisher=Комитет
DefaultDirName={localappdata}\Komitet
DefaultGroupName=Терминал Комитета
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename=Komitet_Setup_1.0
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
UninstallDisplayIcon={app}\Komitet.exe
PrivilegesRequired=lowest

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Files]
Source: "dist\Komitet.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Терминал Комитета"; Filename: "{app}\Komitet.exe"
Name: "{autodesktop}\Терминал Комитета"; Filename: "{app}\Komitet.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительно:"

[Run]
Filename: "{app}\Komitet.exe"; Description: "Запустить Терминал Комитета"; Flags: nowait postinstall skipifsilent
