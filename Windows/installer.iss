; Isola's Windows installer, built with Inno Setup 6 by build.ps1 -Installer:
;   ISCC.exe /DArch=x64 /DVersion=1.2.0 installer.iss
; It installs for the current user only, so no administrator prompt: Isola.exe goes in
; %LocalAppData%\Programs\Isola, with a Start menu shortcut and an uninstaller in Settings, Apps. Installing over a
; running Isola closes it first, and it starts again at the end. Uninstalling keeps the settings and clipboard history
; in %AppData%\Isola.

#ifndef Arch
  #define Arch "x64"
#endif
#ifndef Version
  #define Version "0.0.0"
#endif

[Setup]
AppId={{F4148347-4C89-4708-94ED-00FFC9F28B00}
AppName=Isola
AppVersion={#Version}
AppVerName=Isola {#Version}
AppPublisher=Natuworkguy
AppPublisherURL=https://github.com/Natuworkguy/Isola
AppSupportURL=https://github.com/Natuworkguy/Isola/issues
AppUpdatesURL=https://github.com/Natuworkguy/Isola/releases
DefaultDirName={localappdata}\Programs\Isola
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
ArchitecturesAllowed={#Arch}
ArchitecturesInstallIn64BitMode={#Arch}
MinVersion=10.0.19041
OutputDir=build
OutputBaseFilename=Isola-Windows-{#Arch}-Setup
SetupIconFile=Isola\Isola.ico
UninstallDisplayIcon={app}\Isola.exe
UninstallDisplayName=Isola
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\win-{#Arch}\Isola.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Isola"; Filename: "{app}\Isola.exe"
Name: "{autodesktop}\Isola"; Filename: "{app}\Isola.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Isola.exe"; Description: "{cm:LaunchProgram,Isola}"; Flags: nowait postinstall

[Code]
procedure CloseIsola();
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM Isola.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  CloseIsola();
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    CloseIsola();
    // Isola adds these itself, the first when it starts with Windows and the second for isola:// links.
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'Isola');
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\isola');
  end;
end;
