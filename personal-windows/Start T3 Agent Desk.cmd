@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "desktop=%USERPROFILE%\.local-agent-desk\desktop-app\T3 Agent Desk.exe"
if not exist "%desktop%" (
  echo T3 Agent Desk Desktop is missing from its install directory. 1>&2
  exit /b 1
)
start "" "%desktop%"
exit /b %errorlevel%
