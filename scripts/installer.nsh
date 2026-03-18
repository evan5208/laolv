; 老驴 Custom NSIS Installer/Uninstaller Script
;
; Install: enables long paths, adds resources\cli to user PATH for openclaw CLI.
; Uninstall: removes the PATH entry and optionally deletes user data.

!ifndef nsProcess::FindProcess
  !include "nsProcess.nsh"
!endif

!macro customCheckAppRunning

  ${nsProcess::FindProcess} "${APP_EXECUTABLE_FILENAME}" $R0

  ${if} $R0 == 0
    ${if} ${isUpdated}
      # allow app to exit without explicit kill
      Sleep 1000
      Goto doStopProcess
    ${endIf}
    MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION "$(appRunning)" /SD IDOK IDOK doStopProcess
    Quit

    doStopProcess:
    DetailPrint `Closing running "${PRODUCT_NAME}"...`

    # Silently kill the process using nsProcess instead of taskkill / cmd.exe
    ${nsProcess::KillProcess} "${APP_EXECUTABLE_FILENAME}" $R0
    
    # to ensure that files are not "in-use"
    Sleep 300

    # Retry counter
    StrCpy $R1 0

    loop:
      IntOp $R1 $R1 + 1

      ${nsProcess::FindProcess} "${APP_EXECUTABLE_FILENAME}" $R0
      ${if} $R0 == 0
        # wait to give a chance to exit gracefully
        Sleep 1000
        ${nsProcess::KillProcess} "${APP_EXECUTABLE_FILENAME}" $R0
        
        ${nsProcess::FindProcess} "${APP_EXECUTABLE_FILENAME}" $R0
        ${If} $R0 == 0
          DetailPrint `Waiting for "${PRODUCT_NAME}" to close.`
          Sleep 2000
        ${else}
          Goto not_running
        ${endIf}
      ${else}
        Goto not_running
      ${endIf}

      # App likely running with elevated permissions.
      # Ask user to close it manually
      ${if} $R1 > 1
        MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "$(appCannotBeClosed)" /SD IDCANCEL IDRETRY loop
        Quit
      ${else}
        Goto loop
      ${endIf}
    not_running:
      ${nsProcess::Unload}
  ${endIf}
!macroend

!macro customInstall
  ; Enable Windows long path support (Windows 10 1607+ / Windows 11).
  ; pnpm virtual store paths can exceed the default MAX_PATH limit of 260 chars.
  ; Writing to HKLM requires admin privileges; on per-user installs without
  ; elevation this call silently fails — no crash, just no key written.
  WriteRegDWORD HKLM "SYSTEM\CurrentControlSet\Control\FileSystem" "LongPathsEnabled" 1

  ; Use PowerShell to update the current user's PATH.
  ; This avoids NSIS string-buffer limits and preserves long PATH values.
  InitPluginsDir
  ClearErrors
  File "/oname=$PLUGINSDIR\update-user-path.ps1" "${PROJECT_DIR}\resources\cli\win32\update-user-path.ps1"
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\update-user-path.ps1" -Action add -CliDir "$INSTDIR\resources\cli"'
  Pop $0
  Pop $1
  StrCmp $0 "error" 0 +2
    DetailPrint "Warning: Failed to launch PowerShell while updating PATH."
  StrCmp $0 "timeout" 0 +2
    DetailPrint "Warning: PowerShell PATH update timed out."
  StrCmp $0 "0" 0 +2
    Goto _ci_done
  DetailPrint "Warning: PowerShell PATH update exited with code $0."

  _ci_done:

  ; Updates can preserve an old .lnk whose target no longer exists.
  ; Recreate shortcuts against the freshly installed executable every time.
  !ifndef DO_NOT_CREATE_START_MENU_SHORTCUT
    Push $newStartMenuLink
    Call GetFileParent
    Pop $2
    ${if} $2 != ""
      CreateDirectory "$2"
    ${endIf}
    Delete "$newStartMenuLink"
    CreateShortCut "$newStartMenuLink" "$appExe" "" "$appExe" 0 "" "" "${APP_DESCRIPTION}"
    ClearErrors
    WinShell::SetLnkAUMI "$newStartMenuLink" "${APP_ID}"
  !endif

  !ifndef DO_NOT_CREATE_DESKTOP_SHORTCUT
    ${ifNot} ${isNoDesktopShortcut}
      Delete "$newDesktopLink"
      CreateShortCut "$newDesktopLink" "$appExe" "" "$appExe" 0 "" "" "${APP_DESCRIPTION}"
      ClearErrors
      WinShell::SetLnkAUMI "$newDesktopLink" "${APP_ID}"
    ${endIf}
  !endif

  ; Launch the current install directly on the finish page instead of relying
  ; on a preserved shortcut target from an older installation.
  StrCpy $launchLink "$appExe"
!macroend

!macro customUnInstall
  ; Remove resources\cli from user PATH via PowerShell so long PATH values are handled safely
  InitPluginsDir
  ClearErrors
  File "/oname=$PLUGINSDIR\update-user-path.ps1" "${PROJECT_DIR}\resources\cli\win32\update-user-path.ps1"
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\update-user-path.ps1" -Action remove -CliDir "$INSTDIR\resources\cli"'
  Pop $0
  Pop $1
  StrCmp $0 "error" 0 +2
    DetailPrint "Warning: Failed to launch PowerShell while removing PATH entry."
  StrCmp $0 "timeout" 0 +2
    DetailPrint "Warning: PowerShell PATH removal timed out."
  StrCmp $0 "0" 0 +2
    Goto _cu_pathDone
  DetailPrint "Warning: PowerShell PATH removal exited with code $0."

  _cu_pathDone:

  ; Ask user if they want to completely remove all user data
  MessageBox MB_YESNO|MB_ICONQUESTION \
    "Do you want to completely remove all 老驴 user data?$\r$\n$\r$\nThis will delete:$\r$\n  • .openclaw folder (configuration & skills)$\r$\n  • 老驴 local app data$\r$\n  • 老驴 roaming app data$\r$\n$\r$\nSelect 'No' to keep your data for future reinstallation." \
    /SD IDNO IDYES _cu_removeData IDNO _cu_skipRemove

  _cu_removeData:
    ; Kill any lingering 老驴 processes to release file locks on electron-store
    ; JSON files (settings.json, laolv-providers.json, window-state.json, etc.)
    ${nsProcess::FindProcess} "${APP_EXECUTABLE_FILENAME}" $R0
    ${if} $R0 == 0
      ${nsProcess::KillProcess} "${APP_EXECUTABLE_FILENAME}" $R0
    ${endIf}
    ${nsProcess::Unload}

    ; Wait for processes to fully exit and release file handles
    Sleep 2000

    ; --- Always remove current user's data first ---
    RMDir /r "$PROFILE\.openclaw"
    RMDir /r "$LOCALAPPDATA\laolv"
    RMDir /r "$APPDATA\laolv"

    ; --- Retry: if directories still exist (locked files), wait and try again ---
    ; Check .openclaw
    IfFileExists "$PROFILE\.openclaw\*.*" 0 _cu_openclawDone
      Sleep 3000
      RMDir /r "$PROFILE\.openclaw"
      IfFileExists "$PROFILE\.openclaw\*.*" 0 _cu_openclawDone
        nsExec::ExecToStack 'cmd.exe /c rd /s /q "$PROFILE\.openclaw"'
        Pop $0
        Pop $1
    _cu_openclawDone:

    ; Check AppData\Local\laolv
    IfFileExists "$LOCALAPPDATA\laolv\*.*" 0 _cu_localDone
      Sleep 3000
      RMDir /r "$LOCALAPPDATA\laolv"
      IfFileExists "$LOCALAPPDATA\laolv\*.*" 0 _cu_localDone
        nsExec::ExecToStack 'cmd.exe /c rd /s /q "$LOCALAPPDATA\laolv"'
        Pop $0
        Pop $1
    _cu_localDone:

    ; Check AppData\Roaming\laolv
    IfFileExists "$APPDATA\laolv\*.*" 0 _cu_roamingDone
      Sleep 3000
      RMDir /r "$APPDATA\laolv"
      IfFileExists "$APPDATA\laolv\*.*" 0 _cu_roamingDone
        nsExec::ExecToStack 'cmd.exe /c rd /s /q "$APPDATA\laolv"'
        Pop $0
        Pop $1
    _cu_roamingDone:

    ; --- Final check: warn user if any directories could not be removed ---
    StrCpy $R3 ""
    IfFileExists "$PROFILE\.openclaw\*.*" 0 +2
      StrCpy $R3 "$R3$\r$\n  • $PROFILE\.openclaw"
    IfFileExists "$LOCALAPPDATA\laolv\*.*" 0 +2
      StrCpy $R3 "$R3$\r$\n  • $LOCALAPPDATA\laolv"
    IfFileExists "$APPDATA\laolv\*.*" 0 +2
      StrCpy $R3 "$R3$\r$\n  • $APPDATA\laolv"
    StrCmp $R3 "" _cu_cleanupOk
      MessageBox MB_OK|MB_ICONEXCLAMATION \
        "Some data directories could not be removed (files may be in use):$\r$\n$R3$\r$\n$\r$\nPlease delete them manually after restarting your computer."
    _cu_cleanupOk:

    ; --- For per-machine (all users) installs, enumerate all user profiles ---
    StrCpy $R0 0

  _cu_enumLoop:
    EnumRegKey $R1 HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" $R0
    StrCmp $R1 "" _cu_enumDone

    ReadRegStr $R2 HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$R1" "ProfileImagePath"
    StrCmp $R2 "" _cu_enumNext

    ExpandEnvStrings $R2 $R2
    StrCmp $R2 $PROFILE _cu_enumNext

    RMDir /r "$R2\.openclaw"
    RMDir /r "$R2\AppData\Local\laolv"
    RMDir /r "$R2\AppData\Roaming\laolv"

  _cu_enumNext:
    IntOp $R0 $R0 + 1
    Goto _cu_enumLoop

  _cu_enumDone:
  _cu_skipRemove:
!macroend
