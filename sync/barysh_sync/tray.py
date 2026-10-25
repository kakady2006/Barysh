"""Tray icon for BaryshSync (Windows, plain ctypes): "last sync" in the tooltip and a small menu.
TZ: "окно — значок в трее с состоянием «последняя синхронизация»"."""

import ctypes
import os
import threading
import time

TIP_MAX = 127


def status_text(summary, now=None):
    """Tooltip text: when the last sync was and what it did."""
    if not summary:
        return "BaryshSync · ждёт сохранения в игре"
    if summary.get("error"):
        return ("BaryshSync · ошибка: " + summary["error"])[:TIP_MAX]
    t = summary.get("t")
    when = time.strftime("%H:%M", time.localtime(t)) if t else "—"
    parts = [f"BaryshSync · синхронизация {when}"]
    if summary.get("sheets") is not None:
        parts.append(f"таблица +{summary['sheets']}")
    if summary.get("errors_sent"):
        parts.append(f"ошибок на GitHub {summary['errors_sent']}")
    if summary.get("exports"):
        parts.append(f"экспорт {summary['exports']}")
    return " · ".join(parts)[:TIP_MAX]


def run(app, interval=None):
    """Runs the sync loop in a background thread and the tray icon in this one. Windows only."""
    import ctypes.wintypes as wt

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    shell32 = ctypes.WinDLL("shell32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    LRESULT = ctypes.c_ssize_t
    WNDPROC = ctypes.WINFUNCTYPE(LRESULT, wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM)

    class WNDCLASSW(ctypes.Structure):
        _fields_ = [("style", wt.UINT), ("lpfnWndProc", WNDPROC), ("cbClsExtra", ctypes.c_int),
                    ("cbWndExtra", ctypes.c_int), ("hInstance", wt.HINSTANCE), ("hIcon", wt.HICON),
                    ("hCursor", wt.HANDLE), ("hbrBackground", wt.HBRUSH), ("lpszMenuName", wt.LPCWSTR),
                    ("lpszClassName", wt.LPCWSTR)]

    class NOTIFYICONDATAW(ctypes.Structure):
        _fields_ = [("cbSize", wt.DWORD), ("hWnd", wt.HWND), ("uID", wt.UINT), ("uFlags", wt.UINT),
                    ("uCallbackMessage", wt.UINT), ("hIcon", wt.HICON), ("szTip", wt.WCHAR * 128),
                    ("dwState", wt.DWORD), ("dwStateMask", wt.DWORD), ("szInfo", wt.WCHAR * 256),
                    ("uVersion", wt.UINT), ("szInfoTitle", wt.WCHAR * 64), ("dwInfoFlags", wt.DWORD),
                    ("guidItem", ctypes.c_byte * 16), ("hBalloonIcon", wt.HICON)]

    user32.DefWindowProcW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]
    user32.DefWindowProcW.restype = LRESULT
    user32.CreateWindowExW.argtypes = [wt.DWORD, wt.LPCWSTR, wt.LPCWSTR, wt.DWORD, ctypes.c_int, ctypes.c_int,
                                       ctypes.c_int, ctypes.c_int, wt.HWND, wt.HMENU, wt.HINSTANCE, wt.LPVOID]
    user32.CreateWindowExW.restype = wt.HWND
    user32.LoadIconW.argtypes = [wt.HINSTANCE, wt.LPVOID]
    user32.LoadIconW.restype = wt.HICON
    user32.CreatePopupMenu.restype = wt.HMENU
    user32.AppendMenuW.argtypes = [wt.HMENU, wt.UINT, ctypes.c_size_t, wt.LPCWSTR]
    user32.TrackPopupMenu.argtypes = [wt.HMENU, wt.UINT, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.HWND, wt.LPVOID]
    user32.SetTimer.argtypes = [wt.HWND, ctypes.c_size_t, wt.UINT, wt.LPVOID]
    shell32.Shell_NotifyIconW.argtypes = [wt.DWORD, ctypes.POINTER(NOTIFYICONDATAW)]
    kernel32.GetModuleHandleW.restype = wt.HMODULE

    WM_APP, WM_DESTROY, WM_COMMAND, WM_TIMER = 0x8000, 0x0002, 0x0111, 0x0113
    WM_RBUTTONUP, WM_LBUTTONDBLCLK, WM_NULL = 0x0205, 0x0203, 0x0000
    NIM_ADD, NIM_MODIFY, NIM_DELETE = 0, 1, 2
    NIF_MESSAGE, NIF_ICON, NIF_TIP = 1, 2, 4
    TPM_RIGHTBUTTON, TPM_RETURNCMD = 0x0002, 0x0100
    IDI_APPLICATION = 32512
    CMD_SYNC, CMD_DATA, CMD_EXPORTS, CMD_EXIT = 1, 2, 3, 4
    CALLBACK = WM_APP + 1

    stop = threading.Event()

    def loop():
        while not stop.is_set():
            try:
                app.poll_once(settle=1.0)
            except Exception as e:  # keep the icon alive whatever happens
                app.last = {"error": str(e)}
            stop.wait(interval or app.cfg.poll_seconds)

    worker = threading.Thread(target=loop, daemon=True)
    hinst = kernel32.GetModuleHandleW(None)
    nid = NOTIFYICONDATAW()

    def update_tip():
        nid.szTip = status_text(getattr(app, "last", None))
        shell32.Shell_NotifyIconW(NIM_MODIFY, ctypes.byref(nid))

    def menu(hwnd):
        m = user32.CreatePopupMenu()
        user32.AppendMenuW(m, 0, CMD_SYNC, "Синхронизировать сейчас")
        user32.AppendMenuW(m, 0, CMD_DATA, "Открыть папку данных")
        user32.AppendMenuW(m, 0, CMD_EXPORTS, "Открыть папку экспорта")
        user32.AppendMenuW(m, 0, CMD_EXIT, "Выход")
        pt = wt.POINT()
        user32.GetCursorPos(ctypes.byref(pt))
        user32.SetForegroundWindow(hwnd)
        cmd = user32.TrackPopupMenu(m, TPM_RIGHTBUTTON | TPM_RETURNCMD, pt.x, pt.y, 0, hwnd, None)
        user32.PostMessageW(hwnd, WM_NULL, 0, 0)
        user32.DestroyMenu(m)
        return cmd

    def command(hwnd, cmd):
        if cmd == CMD_SYNC:
            app.seen.clear()
        elif cmd == CMD_DATA:
            os.startfile(app.cfg.data_dir)
        elif cmd == CMD_EXPORTS:
            app.cfg.exports.mkdir(parents=True, exist_ok=True)
            os.startfile(app.cfg.exports)
        elif cmd == CMD_EXIT:
            user32.DestroyWindow(hwnd)

    @WNDPROC
    def wndproc(hwnd, msg, wparam, lparam):
        if msg == CALLBACK:
            if lparam == WM_RBUTTONUP:
                command(hwnd, menu(hwnd))
            elif lparam == WM_LBUTTONDBLCLK:
                os.startfile(app.cfg.data_dir)
            return 0
        if msg == WM_TIMER:
            update_tip()
            return 0
        if msg == WM_DESTROY:
            shell32.Shell_NotifyIconW(NIM_DELETE, ctypes.byref(nid))
            stop.set()
            user32.PostQuitMessage(0)
            return 0
        return user32.DefWindowProcW(hwnd, msg, wparam, lparam)

    wc = WNDCLASSW()
    wc.lpfnWndProc = wndproc
    wc.hInstance = hinst
    wc.lpszClassName = "BaryshSyncTray"
    user32.RegisterClassW(ctypes.byref(wc))
    hwnd = user32.CreateWindowExW(0, wc.lpszClassName, "BaryshSync", 0, 0, 0, 0, 0, None, None, hinst, None)

    nid.cbSize = ctypes.sizeof(NOTIFYICONDATAW)
    nid.hWnd = hwnd
    nid.uID = 1
    nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP
    nid.uCallbackMessage = CALLBACK
    nid.hIcon = user32.LoadIconW(None, ctypes.c_void_p(IDI_APPLICATION))
    nid.szTip = status_text(None)
    shell32.Shell_NotifyIconW(NIM_ADD, ctypes.byref(nid))
    user32.SetTimer(hwnd, 1, 5000, None)

    worker.start()
    msg = wt.MSG()
    while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
        user32.TranslateMessage(ctypes.byref(msg))
        user32.DispatchMessageW(ctypes.byref(msg))
    stop.set()
