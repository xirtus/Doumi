; ═══════════════════════════════════════════════════════════════════════════════
; Doumi for Windows — NSIS Installer
;
; Build with: makensis doumi-setup.nsi
; Requires: NSIS 3.x (https://nsis.sourceforge.io)
;
; Place doumi.exe, doumid.exe, doumi-gui.exe in the same directory first.
; ═══════════════════════════════════════════════════════════════════════════════

!define PRODUCT_NAME "Doumi"
!define PRODUCT_VERSION "0.1.0"
!define PRODUCT_PUBLISHER "Xirtus"
!define PRODUCT_WEB_SITE "https://github.com/xirtus/doumi"
!define PRODUCT_DIR_REGKEY "Software\Microsoft\Windows\CurrentVersion\App Paths\doumi.exe"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"

SetCompressor lzma

; ─── Modern UI ────────────────────────────────────────────────────────────────
!include "MUI2.nsh"

!define MUI_ABORTWARNING
!define MUI_ICON "resources\doumi.ico"
!define MUI_UNICON "resources\doumi.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; ─── Installer ────────────────────────────────────────────────────────────────
Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "Doumi-Setup-${PRODUCT_VERSION}.exe"
InstallDir "$LOCALAPPDATA\Programs\${PRODUCT_NAME}"
InstallDirRegKey HKCU "${PRODUCT_DIR_REGKEY}" ""
ShowInstDetails show
ShowUnInstDetails show
RequestExecutionLevel user

Section "Doumi (required)" SecMain
    SetOutPath "$INSTDIR"

    ; Binaries
    File "doumi.exe"
    File "doumid.exe"
    File /nonfatal "doumi-gui.exe"

    ; Service script
    File "doumi-service.ps1"

    ; Documentation
    File "..\LICENSE"
    File "README.md"

    ; Resources
    SetOutPath "$INSTDIR\resources"
    File "resources\doumi.ico"

    ; Create start menu shortcuts
    CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
    CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Doumi GUI.lnk" "$INSTDIR\doumi-gui.exe" "" "$INSTDIR\resources\doumi.ico"
    CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Doumi README.lnk" "$INSTDIR\README.md"
    CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall Doumi.lnk" "$INSTDIR\uninst.exe"

    ; Register application path
    WriteRegStr HKCU "${PRODUCT_DIR_REGKEY}" "" "$INSTDIR\doumi.exe"
    WriteRegStr HKCU "${PRODUCT_DIR_REGKEY}" "Path" "$INSTDIR"

    ; Add to PATH (current user)
    ; Store uninstall info
    WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
    WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\uninst.exe"
    WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\resources\doumi.ico"
    WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
    WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
    WriteRegStr HKCU "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"

    ; Write uninstaller
    WriteUninstaller "$INSTDIR\uninst.exe"

    ; Add to PATH
    EnVar::AddHKCU "PATH" "$INSTDIR"
    Pop $0
    ; If EnVar plugin not available, provide instructions
    StrCmp $0 "0" path_done
    DetailPrint "NOTE: Add $INSTDIR to your PATH manually for command-line use."
    path_done:
SectionEnd

Section "Start Menu Shortcuts" SecShortcuts
    CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Doumi Daemon Start.lnk" \
        "$INSTDIR\doumi.exe" "daemon start" "$INSTDIR\resources\doumi.ico"
    CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Doumi Service Install.lnk" \
        "powershell.exe" '-ExecutionPolicy Bypass -File "$INSTDIR\doumi-service.ps1" install' \
        "$INSTDIR\resources\doumi.ico"
SectionEnd

; ─── Uninstaller ──────────────────────────────────────────────────────────────
Section "Uninstall"
    ; Stop daemon if running
    ExecWait '"$INSTDIR\doumi.exe" daemon stop'
    ExecWait 'powershell.exe -ExecutionPolicy Bypass -File "$INSTDIR\doumi-service.ps1" uninstall'

    ; Remove from PATH
    EnVar::DeleteHKCU "PATH" "$INSTDIR"
    Pop $0

    Delete "$INSTDIR\doumi.exe"
    Delete "$INSTDIR\doumid.exe"
    Delete "$INSTDIR\doumi-gui.exe"
    Delete "$INSTDIR\doumi-service.ps1"
    Delete "$INSTDIR\LICENSE"
    Delete "$INSTDIR\README.md"
    Delete "$INSTDIR\resources\doumi.ico"
    Delete "$INSTDIR\uninst.exe"
    RMDir "$INSTDIR\resources"
    RMDir "$INSTDIR"

    ; Remove start menu
    Delete "$SMPROGRAMS\${PRODUCT_NAME}\*.*"
    RMDir "$SMPROGRAMS\${PRODUCT_NAME}"

    ; Remove registry keys
    DeleteRegKey HKCU "${PRODUCT_UNINST_KEY}"
    DeleteRegKey HKCU "${PRODUCT_DIR_REGKEY}"
SectionEnd
