"""Run a Windows maintenance PowerShell script as the current standard user without a console.

Invoke with pythonw.exe, followed by Build, Check or Verify, a log path, and task arguments.
Maintenance tooling on Windows requires pywin32. Interactive terminals use their usual launcher.
"""

import ctypes
from ctypes import wintypes
import os
from pathlib import Path
import shutil
import subprocess
import sys
from contextlib import ExitStack

import ntsecuritycon
import pywintypes
import win32api
import win32con
import win32event
import win32file
import win32process
import win32security


def standard_token():
    # SAFER_LEVELID_NORMALUSER is the same policy as runas /trustlevel:0x20000.
    api = ctypes.WinDLL("advapi32", use_last_error=True)
    handle_pointer = ctypes.POINTER(wintypes.HANDLE)
    api.SaferCreateLevel.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.DWORD,
                                     handle_pointer, wintypes.LPVOID]
    api.SaferComputeTokenFromLevel.argtypes = [wintypes.HANDLE, wintypes.HANDLE,
                                                handle_pointer, wintypes.DWORD, wintypes.LPVOID]
    api.SaferCloseLevel.argtypes = [wintypes.HANDLE]
    level = wintypes.HANDLE()
    result = wintypes.HANDLE()
    if not api.SaferCreateLevel(2, 0x20000, 0, ctypes.byref(level), None):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        if not api.SaferComputeTokenFromLevel(level, None, ctypes.byref(result), 0, None):
            raise ctypes.WinError(ctypes.get_last_error())
    finally:
        api.SaferCloseLevel(level)
    token = pywintypes.HANDLE(result.value)
    try:
        sid, _ = win32security.GetTokenInformation(token, win32security.TokenIntegrityLevel)
        if int(win32security.ConvertSidToStringSid(sid).rsplit("-", 1)[1]) > 8192:
            medium = win32security.ConvertStringSidToSid("S-1-16-8192")
            win32security.SetTokenInformation(token, win32security.TokenIntegrityLevel, (medium, 0x20))
        return token
    except BaseException:
        token.Close()
        raise


def run(script, log, arguments):
    script = script.resolve(strict=True)
    if script.suffix.lower() != ".ps1" or not script.is_file():
        raise ValueError("Expected a PowerShell maintenance script")
    shell = shutil.which("pwsh.exe") or str(Path(os.environ["SystemRoot"]) / "System32"
                                             / "WindowsPowerShell" / "v1.0" / "powershell.exe")
    command = subprocess.list2cmdline([shell, "-NoLogo", "-NoProfile", "-NonInteractive",
                                       "-File", str(script), *arguments])
    attrs = pywintypes.SECURITY_ATTRIBUTES()
    attrs.bInheritHandle = True
    with ExitStack() as handles:
        token = standard_token()
        handles.callback(token.Close)
        output = win32file.CreateFile(str(log), ntsecuritycon.FILE_APPEND_DATA,
                                      win32con.FILE_SHARE_READ | win32con.FILE_SHARE_WRITE,
                                      attrs, win32con.OPEN_ALWAYS, win32con.FILE_ATTRIBUTE_NORMAL, None)
        handles.callback(output.Close)
        stdin = win32file.CreateFile("NUL", win32con.GENERIC_READ,
                                     win32con.FILE_SHARE_READ | win32con.FILE_SHARE_WRITE,
                                     attrs, win32con.OPEN_EXISTING, win32con.FILE_ATTRIBUTE_NORMAL, None)
        handles.callback(stdin.Close)
        startup = win32process.STARTUPINFO()
        startup.dwFlags = win32con.STARTF_USESTDHANDLES
        startup.hStdInput = stdin
        startup.hStdOutput = startup.hStdError = output
        process, thread, _, _ = win32process.CreateProcessAsUser(
            token, shell, command, None, None, True, subprocess.CREATE_NO_WINDOW,
            None, str(script.parent), startup)
        thread.Close()
        handles.callback(process.Close)
        win32event.WaitForSingleObject(process, win32event.INFINITE)
        return win32process.GetExitCodeProcess(process)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(2)
    log_path = Path(sys.argv[2]).resolve()
    try:
        task = sys.argv[1].capitalize()
        if task not in {"Build", "Check", "Verify"}:
            raise ValueError("Expected Build, Check or Verify")
        worker = Path(__file__).resolve().with_name("maintain.ps1")
        exit_code = run(worker, log_path, ["-Task", task, *sys.argv[3:]])
    except Exception as error:
        with log_path.open("a", encoding="utf-8") as log:
            print(f"Maintenance launcher: {error}", file=log)
        sys.exit(1)
    sys.exit(exit_code)
