// winuse.cs.inc — winhand-use 的 Win32 辅助层（C#5，.NET Framework 4.8）
// 由 win.ps1 读入并 Add-Type 编译。请用 powershell.exe（Windows PowerShell 5.1）运行。
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Automation;

public static class WinUseNative
{
    // ---------- 基础结构 ----------
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left; public int Top; public int Right; public int Bottom;
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X; public int Y;
    }

    public class WindowInfo
    {
        public IntPtr Hwnd;
        public uint Pid;
        public string Title;
        public string ClassName;
        public string Owner;
        public RECT Rect;
        public bool Visible;
        public bool Iconic;
        public bool OnCurrentDesktop;
        public bool Cloaked;
    }

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    // ---------- user32 / dwm ----------
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
    [DllImport("user32.dll")] private static extern bool ScreenToClient(IntPtr hWnd, ref POINT lpPoint);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(POINT Point);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
    [DllImport("user32.dll")] private static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("user32.dll")] private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [DllImport("kernel32.dll")] private static extern ulong GetTickCount64();
    [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);
    [DllImport("user32.dll")] private static extern int GetWindowDisplayAffinity(IntPtr hWnd, out uint dwAffinity);

    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    private const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    private const int DWMWA_CLOAKED = 14;
    private const uint PW_RENDERFULLCONTENT = 2;
    private const uint GA_ROOT = 2;
    private const uint WM_MOUSEMOVE = 0x200;
    private const uint WM_LBUTTONDOWN = 0x201;
    private const uint WM_LBUTTONUP = 0x202;
    private const uint WM_SETTEXT = 0x000C;
    private const uint MK_LBUTTON = 0x0001;
    private const int SW_RESTORE = 9;
    private const int SW_SHOWNOACTIVATE = 4;
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOMOVE = 0x0002;
    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SWP_SHOWWINDOW = 0x0040;

    // 清理标题里的零宽/方向控制字符（网页标题常带，会污染 agent 的文本解析）
    private static string CleanTitle(string s)
    {
        if (string.IsNullOrEmpty(s)) return s;
        StringBuilder sb = new StringBuilder(s.Length);
        foreach (char c in s)
        {
            int v = (int)c;
            if ((v >= 0x200B && v <= 0x200F) || (v >= 0x202A && v <= 0x202E)
                || (v >= 0x2060 && v <= 0x206F) || v == 0xFEFF || v == 0x00AD)
                continue;
            sb.Append(c);
        }
        return sb.ToString();
    }
    private const uint SMTO_ABORTIFHUNG = 0x0002;

    // ---------- IVirtualDesktopManager ----------
    [ComImport, Guid("A5CD92FF-29BE-454C-8D04-D82879FB3F1B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IVirtualDesktopManager
    {
        [PreserveSig] int IsWindowOnCurrentVirtualDesktop(IntPtr topLevelWindow, out bool onCurrentDesktop);
        [PreserveSig] int GetWindowDesktopId(IntPtr topLevelWindow, out Guid desktopId);
        [PreserveSig] int MoveWindowToDesktop(IntPtr topLevelWindow, ref Guid desktopId);
    }

    private static IVirtualDesktopManager CreateVirtualDesktopManager()
    {
        Type t = Type.GetTypeFromCLSID(new Guid("AA509086-5CA9-4C25-8F95-589D3C07B48A"));
        return (IVirtualDesktopManager)Activator.CreateInstance(t);
    }

    public static bool WindowOnCurrentDesktop(IntPtr hwnd)
    {
        try
        {
            IVirtualDesktopManager mgr = CreateVirtualDesktopManager();
            bool onDesktop = true;
            mgr.IsWindowOnCurrentVirtualDesktop(hwnd, out onDesktop);
            return onDesktop;
        }
        catch
        {
            return true; // 无虚拟桌面时全在
        }
    }

    // ---------- DPI ----------
    public static void MakeDpiAware()
    {
        try { SetProcessDPIAware(); } catch { }
    }

    // ---------- 窗口枚举 ----------
    public static List<WindowInfo> ListWindows(string keyword, bool includeAll)
    {
        List<WindowInfo> result = new List<WindowInfo>();
        uint selfPid = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
        {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == selfPid) return true; // 跳过自己（HUD 等）
            if (!IsWindowVisible(hWnd) && !includeAll) return true;
            bool hasTitle = GetWindowTextLength(hWnd) > 0;
            if (!hasTitle && !includeAll) return true;

            WindowInfo wi = new WindowInfo();
            wi.Hwnd = hWnd;
            wi.Pid = pid;
            StringBuilder sb = new StringBuilder(1024);
            GetWindowText(hWnd, sb, 1024);
            wi.Title = CleanTitle(sb.ToString());
            GetClassName(hWnd, sb, 1024);
            wi.ClassName = sb.ToString();
            wi.Visible = IsWindowVisible(hWnd);
            wi.Iconic = IsIconic(hWnd);
            // 与截图统一用 DWM 扩展边框（含阴影，DPI 感知后为物理像素）
            RECT dwmRect;
            if (DwmGetWindowAttribute(hWnd, DWMWA_EXTENDED_FRAME_BOUNDS, out dwmRect, Marshal.SizeOf(typeof(RECT))) == 0)
                wi.Rect = dwmRect;
            else
                GetWindowRect(hWnd, out wi.Rect);
            wi.OnCurrentDesktop = WindowOnCurrentDesktop(hWnd);
            try { wi.Owner = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; }
            catch { wi.Owner = "?"; }
            try
            {
                int cloaked = 0;
                DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out cloaked, 4);
                wi.Cloaked = cloaked != 0;
            }
            catch { wi.Cloaked = false; }

            if (string.IsNullOrEmpty(keyword) || wi.Title.IndexOf(keyword, StringComparison.OrdinalIgnoreCase) >= 0
                || wi.Owner.IndexOf(keyword, StringComparison.OrdinalIgnoreCase) >= 0
                || wi.ClassName.IndexOf(keyword, StringComparison.OrdinalIgnoreCase) >= 0)
                result.Add(wi);
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static string WindowInfoLine(WindowInfo w)
    {
        return string.Format("hwnd=0x{0:X} pid={1} owner={2} on={3} vis={4} min={5} cloaked={6} rect=({7},{8},{9},{10}) title={11}",
            w.Hwnd.ToInt64(), w.Pid, w.Owner, w.OnCurrentDesktop ? 1 : 0, w.Visible ? 1 : 0, w.Iconic ? 1 : 0,
            w.Cloaked ? 1 : 0, w.Rect.Left, w.Rect.Top, w.Rect.Width, w.Rect.Height, w.Title);
    }

    // ---------- 前台 / 借焦点 ----------
    public static long ForegroundPid()
    {
        IntPtr fg = GetForegroundWindow();
        if (fg == IntPtr.Zero) return -1;
        uint pid;
        GetWindowThreadProcessId(fg, out pid);
        return (long)pid;
    }

    public static long ForegroundHwnd()
    {
        return GetForegroundWindow().ToInt64();
    }

    public static string ForegroundInfo()
    {
        IntPtr fg = GetForegroundWindow();
        if (fg == IntPtr.Zero) return "前台=无（安全桌面/锁屏？）";
        uint pid;
        GetWindowThreadProcessId(fg, out pid);
        StringBuilder sb = new StringBuilder(1024);
        GetWindowText(fg, sb, 1024);
        string title = CleanTitle(sb.ToString());
        string owner = "?";
        try { owner = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; }
        catch { }
        return string.Format("hwnd=0x{0:X} pid={1} owner={2} title={3}", fg.ToInt64(), pid, owner, title);
    }

    public static bool IsForeground(IntPtr hwnd)
    {
        IntPtr fg = GetForegroundWindow();
        return fg == hwnd || fg == GetAncestor(hwnd, GA_ROOT);
    }

    // 显示/还原窗口但不抢焦点：最小化窗口先用 SW_SHOWNOACTIVATE 还原，
    // 再以 SWP_NOACTIVATE 强制显示，保证用户当前前台窗口不变。
    public static string ShowNoActivate(IntPtr hwnd)
    {
        if (!IsWindow(hwnd)) return "fail:not-a-window";
        bool iconic = IsIconic(hwnd);
        if (iconic) ShowWindow(hwnd, SW_SHOWNOACTIVATE);
        bool ok = SetWindowPos(
            hwnd, IntPtr.Zero, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW
        );
        return string.Format("ok was_iconic={0} setpos={1}", iconic, ok);
    }

    // 把 hwnd 放到 belowHwnd 正上方，但不激活任何一方。
    // 用途：受控遮挡取证（验证 PrintWindow 在窗口被盖住时仍能截图）。
    public static string PlaceAboveNoActivate(IntPtr hwnd, IntPtr belowHwnd)
    {
        if (!IsWindow(hwnd) || !IsWindow(belowHwnd)) return "fail:not-a-window";
        bool ok = SetWindowPos(
            hwnd, belowHwnd, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW
        );
        return ok ? "ok" : "fail:setwindowpos";
    }

    public static bool BringToFront(IntPtr hwnd)
    {
        try
        {
            if (!IsWindow(hwnd)) return false;
            if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
            uint fgThread, targetThread, fgPid;
            IntPtr fg = GetForegroundWindow();
            fgThread = fg == IntPtr.Zero ? 0 : GetWindowThreadProcessId(fg, out fgPid);
            targetThread = GetWindowThreadProcessId(hwnd, out fgPid);
            uint cur = GetCurrentThreadId();
            if (fgThread != 0) AttachThreadInput(cur, fgThread, true);
            AttachThreadInput(cur, targetThread, true);
            SetForegroundWindow(hwnd);
            BringWindowToTop(hwnd);
            if (fgThread != 0) AttachThreadInput(cur, fgThread, false);
            AttachThreadInput(cur, targetThread, false);
            return GetForegroundWindow() == hwnd;
        }
        catch { return false; }
    }

    // ---------- 输入空闲 ----------
    public static ulong IdleMilliseconds()
    {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        if (GetLastInputInfo(ref info))
        {
            ulong now = GetTickCount64();
            return now - info.dwTime;
        }
        return ulong.MaxValue;
    }

    public static uint LastInputTick()
    {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        if (GetLastInputInfo(ref info)) return info.dwTime;
        return 0;
    }

    // ---------- 遮挡检查 ----------
    public static string TopWindowAt(int screenX, int screenY)
    {
        POINT p = new POINT(); p.X = screenX; p.Y = screenY;
        IntPtr top = WindowFromPoint(p);
        if (top == IntPtr.Zero) return "none";
        IntPtr root = GetAncestor(top, GA_ROOT);
        uint pid;
        GetWindowThreadProcessId(root, out pid);
        StringBuilder sb = new StringBuilder(512);
        GetWindowText(root, sb, 512);
        string owner = "?";
        try { owner = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; }
        catch { }
        return string.Format("hwnd=0x{0:X} pid={1} owner={2} title={3}", root.ToInt64(), pid, owner, sb.ToString());
    }

    // ---------- 后台点击（PostMessage，不抢焦点） ----------
    public static string PostClick(IntPtr hwnd, int clientX, int clientY, bool downUpOnly)
    {
        if (!IsWindow(hwnd)) return "fail:invalid-hwnd";
        IntPtr lp = (IntPtr)((clientY << 16) | (clientX & 0xFFFF));
        IntPtr wp = (IntPtr)MK_LBUTTON;
        if (!downUpOnly)
            PostMessage(hwnd, WM_MOUSEMOVE, IntPtr.Zero, lp);
        PostMessage(hwnd, WM_LBUTTONDOWN, wp, lp);
        PostMessage(hwnd, WM_LBUTTONUP, IntPtr.Zero, lp);
        Thread.Sleep(80);
        return "posted";
    }

    public static string SendSetText(IntPtr hwnd, string text)
    {
        IntPtr result;
        IntPtr r = SendMessageTimeout(hwnd, WM_SETTEXT, IntPtr.Zero, Marshal.StringToHGlobalUni(text), SMTO_ABORTIFHUNG, 3000, out result);
        if (r == IntPtr.Zero) return "fail:" + Marshal.GetLastWin32Error();
        return "ok";
    }

    // ---------- 截图 ----------
    public static string PrintWindowToFile(IntPtr hwnd, string path)
    {
        if (!IsWindow(hwnd)) return "fail:invalid-hwnd";
        RECT r;
        if (DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out r, Marshal.SizeOf(typeof(RECT))) != 0)
            GetWindowRect(hwnd, out r);
        int w = r.Width; int h = r.Height;
        if (w <= 0 || h <= 0) return "fail:zero-size";
        Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        bool ok = false;
        try
        {
            using (Graphics g = Graphics.FromImage(bmp))
            {
                IntPtr hdc = g.GetHdc();
                ok = PrintWindow(hwnd, hdc, PW_RENDERFULLCONTENT);
                if (!ok) ok = PrintWindow(hwnd, hdc, 0);
                g.ReleaseHdc(hdc);
            }
            if (!ok) return "fail:printwindow=" + Marshal.GetLastWin32Error();
            bmp.Save(path, ImageFormat.Png);
            return "ok " + w + "x" + h;
        }
        catch (Exception ex) { return "fail:" + ex.Message; }
        finally { bmp.Dispose(); }
    }

    // 前台截取屏幕上的窗口区域（要求窗口当前可见且未被完全遮挡）
    public static string CaptureForegroundRect(IntPtr hwnd, string path)
    {
        RECT r;
        GetWindowRect(hwnd, out r);
        int w = r.Width; int h = r.Height;
        if (w <= 0 || h <= 0) return "fail:zero-size";
        Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        try
        {
            using (Graphics g = Graphics.FromImage(bmp))
            {
                IntPtr hdc = g.GetHdc();
                IntPtr screenDc = GetDC(IntPtr.Zero);
                try
                {
                    bool ok = BitBlt(hdc, 0, 0, w, h, screenDc, r.Left, r.Top, 0x00CC0020);
                    if (!ok) return "fail:bitblt=" + Marshal.GetLastWin32Error();
                }
                finally { ReleaseDC(IntPtr.Zero, screenDc); g.ReleaseHdc(hdc); }
            }
            bmp.Save(path, ImageFormat.Png);
            return "ok " + w + "x" + h;
        }
        catch (Exception ex) { return "fail:" + ex.Message; }
        finally { bmp.Dispose(); }
    }

    [DllImport("gdi32.dll")]
    private static extern bool BitBlt(IntPtr hdcDest, int xDest, int yDest, int wDest, int hDest, IntPtr hdcSrc, int xSrc, int ySrc, uint rop);

    // ---------- 图像分析 ----------
    public static string AnalyzePng(string path)
    {
        try
        {
            using (Bitmap bmp = new Bitmap(path))
            {
                int w = bmp.Width; int h = bmp.Height;
                long black = 0, white = 0, total = 0;
                HashSet<int> colors = new HashSet<int>();
                int step = Math.Max(1, Math.Min(w, h) / 300);
                for (int y = 0; y < h; y += step)
                {
                    for (int x = 0; x < w; x += step)
                    {
                        Color c = bmp.GetPixel(x, y);
                        total++;
                        if (c.R < 8 && c.G < 8 && c.B < 8) black++;
                        else if (c.R > 247 && c.G > 247 && c.B > 247) white++;
                        int key = (c.R >> 4) << 8 | (c.G >> 4) << 4 | (c.B >> 4);
                        colors.Add(key);
                    }
                }
                double br = total == 0 ? 1 : (double)black / total;
                double wr = total == 0 ? 0 : (double)white / total;
                return string.Format("size={0}x{1} black={2:F3} white={3:F3} colors={4}", w, h, br, wr, colors.Count);
            }
        }
        catch (Exception ex) { return "fail:" + ex.Message; }
    }

    public static string DiffPngs(string a, string b)
    {
        try
        {
            using (Bitmap ba = new Bitmap(a))
            using (Bitmap bb = new Bitmap(b))
            {
                if (ba.Width != bb.Width || ba.Height != bb.Height)
                    return string.Format("size-mismatch {0}x{1} vs {2}x{3}", ba.Width, ba.Height, bb.Width, bb.Height);
                long diff = 0, total = 0;
                int step = Math.Max(1, Math.Min(ba.Width, ba.Height) / 250);
                for (int y = 0; y < ba.Height; y += step)
                {
                    for (int x = 0; x < ba.Width; x += step)
                    {
                        Color ca = ba.GetPixel(x, y);
                        Color cb = bb.GetPixel(x, y);
                        total++;
                        int d = Math.Abs(ca.R - cb.R) + Math.Abs(ca.G - cb.G) + Math.Abs(ca.B - cb.B);
                        if (d > 24) diff++;
                    }
                }
                double ratio = total == 0 ? 0 : (double)diff / total;
                return "changed=" + ratio.ToString("F4");
            }
        }
        catch (Exception ex) { return "fail:" + ex.Message; }
    }

    // ---------- SendInput 全局键鼠（需前台） ----------
    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_UNICODE = 0x0004;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;

    private static void SendKeyInput(ushort vk, ushort scan, uint flags)
    {
        INPUT[] inputs = new INPUT[1];
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].ki.wVk = vk;
        inputs[0].ki.wScan = scan;
        inputs[0].ki.dwFlags = flags;
        inputs[0].ki.time = 0;
        inputs[0].ki.dwExtraInfo = IntPtr.Zero;
        NativeSendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
        Thread.Sleep(8);
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint NativeSendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    public static void TypeUnicodeText(string text)
    {
        foreach (char c in text)
        {
            SendKeyInput(0, (ushort)c, KEYEVENTF_UNICODE);
            SendKeyInput(0, (ushort)c, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP);
            Thread.Sleep(10);
        }
    }

    public static void TypeKey(int vk, bool withCtrl, bool withShift, bool withAlt)
    {
        if (withCtrl) SendKeyInput(0x11, 0, 0);
        if (withAlt) SendKeyInput(0x12, 0, 0);
        if (withShift) SendKeyInput(0x10, 0, 0);
        SendKeyInput((ushort)vk, 0, 0);
        SendKeyInput((ushort)vk, 0, KEYEVENTF_KEYUP);
        if (withShift) SendKeyInput(0x10, 0, KEYEVENTF_KEYUP);
        if (withAlt) SendKeyInput(0x12, 0, KEYEVENTF_KEYUP);
        if (withCtrl) SendKeyInput(0x11, 0, KEYEVENTF_KEYUP);
    }

    // ---------- 焦点锁（全机同时只允许一个借焦点者） ----------
    private static Mutex _focusLock;
    private static bool _lockHeld;

    public static bool TryAcquireFocusLock()
    {
        try
        {
            _focusLock = new Mutex(false, "Local\\winhand-use-focus-v1");
            try
            {
                _lockHeld = _focusLock.WaitOne(0);
            }
            catch (AbandonedMutexException)
            {
                _lockHeld = true; // 上一个持有者崩溃，锁已移交
            }
            return _lockHeld;
        }
        catch { return false; }
    }

    public static void ReleaseFocusLock()
    {
        try
        {
            if (_lockHeld && _focusLock != null) _focusLock.ReleaseMutex();
            if (_focusLock != null) _focusLock.Dispose();
        }
        catch { }
        _lockHeld = false;
        _focusLock = null;
    }

    // ---------- UI Automation (UIA) ----------
    // 元素定位路径：从窗口 AutomationElement 出发，逐层 Children 的索引，如 0/2/1。
    // 路径只在「窗口结构未变」的短会话内稳定；跨进程命令重查树时若漂移会报 miss。

    private static AutomationElement WindowElement(IntPtr hwnd)
    {
        return AutomationElement.FromHandle(hwnd);
    }

    private static string ElemDesc(AutomationElement el)
    {
        string type = "?";
        try { type = el.Current.ControlType.ProgrammaticName.Replace("ControlType.", ""); } catch { }
        string name = "";
        try { name = el.Current.Name; } catch { }
        string value = "";
        try
        {
            object vp;
            if (el.TryGetCurrentPattern(ValuePattern.Pattern, out vp)) value = ((ValuePattern)vp).Current.Value;
        }
        catch { }
        // 列表/摘要输出只给前 120 字符，避免把大段文档灌进上下文；精确全文用 UiReadSmart
        if (type == "Document") value = "[文档 " + value.Length + " 字符]";
        else if (value.Length > 120) value = value.Substring(0, 120) + "...(" + value.Length + "字符)";
        string aid = "";
        try { aid = el.Current.AutomationId; } catch { }
        return string.Format("{0}|name={1}|value={2}|aid={3}", type, name, value, aid);
    }

    private static bool EditableLike(AutomationElement el)
    {
        try
        {
            ControlType t = el.Current.ControlType;
            if (t == ControlType.Edit || t == ControlType.Document) return true;
            object vp;
            if (el.TryGetCurrentPattern(ValuePattern.Pattern, out vp)) return true;
            string cn = "";
            try { cn = el.Current.ClassName; } catch { }
            return cn.IndexOf("Edit", StringComparison.OrdinalIgnoreCase) >= 0
                || cn.IndexOf("RichEdit", StringComparison.OrdinalIgnoreCase) >= 0;
        }
        catch { return false; }
    }

    private static void WalkTree(AutomationElement el, string path, int depth,
        List<AutomationElement> outList, List<string> outPaths, bool editableOnly, int max)
    {
        if (outList.Count >= max || depth > 30) return;
        try
        {
            AutomationElementCollection children = el.FindAll(TreeScope.Children, Condition.TrueCondition);
            for (int i = 0; i < children.Count && outList.Count < max; i++)
            {
                AutomationElement c = children[i];
                string p = path.Length == 0 ? i.ToString() : path + "/" + i.ToString();
                if (!editableOnly || EditableLike(c))
                {
                    outList.Add(c);
                    outPaths.Add(p);
                }
                WalkTree(c, p, depth + 1, outList, outPaths, editableOnly, max);
            }
        }
        catch { }
    }

    private static void ResolveTree(IntPtr hwnd, bool editableOnly, int max,
        out List<AutomationElement> elems, out List<string> paths)
    {
        elems = new List<AutomationElement>();
        paths = new List<string>();
        try
        {
            AutomationElement root = WindowElement(hwnd);
            if (root == null) return;
            WalkTree(root, "", 0, elems, paths, editableOnly, max);
        }
        catch { }
    }

    public static string UiScan(IntPtr hwnd, string keyword, int maxItems)
    {
        List<AutomationElement> elems;
        List<string> paths;
        ResolveTree(hwnd, false, maxItems, out elems, out paths);
        StringBuilder sb = new StringBuilder();
        int editable = 0, clickable = 0, matched = 0;
        for (int i = 0; i < elems.Count; i++)
        {
            string desc = ElemDesc(elems[i]);
            string[] parts = desc.Split('|');
            if (EditableLike(elems[i])) editable++;
            try
            {
                object ip;
                if (elems[i].TryGetCurrentPattern(InvokePattern.Pattern, out ip)) clickable++;
            }
            catch { }
            bool hit = string.IsNullOrEmpty(keyword);
            if (!hit)
            {
                string hay = desc.ToLowerInvariant();
                hit = hay.IndexOf(keyword.ToLowerInvariant()) >= 0;
            }
            if (hit)
            {
                matched++;
                sb.AppendLine(string.Format("e{0} path={1} {2}", i, paths[i], desc));
            }
        }
        sb.Insert(0, string.Format("uia=on elements={0} editable={1} clickable={2} matched={3}\n", elems.Count, editable, clickable, matched));
        return sb.ToString();
    }

    public static string UiSetValueByPath(IntPtr hwnd, string path, string text, out string readback)
    {
        readback = "";
        List<AutomationElement> elems;
        List<string> paths;
        ResolveTree(hwnd, true, 400, out elems, out paths);
        AutomationElement target = null;
        for (int i = 0; i < elems.Count; i++)
        {
            if (paths[i] == path) { target = elems[i]; break; }
        }
        if (target == null) return "fail:path-miss（树已变，重新 win ax）";
        try
        {
            object vp;
            if (target.TryGetCurrentPattern(ValuePattern.Pattern, out vp))
            {
                ValuePattern v = (ValuePattern)vp;
                if (v.Current.IsReadOnly) return "fail:readonly";
                v.SetValue(text);
                Thread.Sleep(120);
                readback = v.Current.Value;
                return "ok";
            }
            return "fail:no-value-pattern（contenteditable？试 win type --bg）";
        }
        catch (Exception ex) { return "fail:" + ex.Message; }
    }

    // 按「ref 或关键词」写值：e0/e1 序号 → 转成当时路径不可靠，这里按当前枚举序号处理；
    // 传 path=0/1/2 用路径；其它按 name/aid/value 模糊匹配第一个可编辑控件。
    public static string UiSetValueSmart(IntPtr hwnd, string selector, string text, out string readback)
    {
        readback = "";
        // 与 win ax 输出一致：eN/path 都是全树语义（可编辑子树会让序号错位，见踩坑实录）
        List<AutomationElement> elems;
        List<string> paths;
        ResolveTree(hwnd, false, 400, out elems, out paths);
        if (elems.Count == 0) return "fail:uia-tree-empty";
        AutomationElement target = null;
        string usePath = "";
        if (selector != null && selector.IndexOf('/') >= 0)
        {
            for (int i = 0; i < elems.Count; i++)
                if (paths[i] == selector) { target = elems[i]; usePath = selector; break; }
            if (target == null) return "fail:path-miss（树已变，重新 win ax）";
        }
        else
        {
            int idx = -1;
            if (selector != null && selector.StartsWith("e") && selector.Length > 1)
                int.TryParse(selector.Substring(1), out idx);
            if (idx >= 0 && idx < elems.Count)
            {
                target = elems[idx];
                usePath = paths[idx];
            }
            else
            {
                for (int i = 0; i < elems.Count; i++)
                {
                    string desc = ElemDesc(elems[i]).ToLowerInvariant();
                    if (string.IsNullOrEmpty(selector) || desc.IndexOf(selector.ToLowerInvariant()) >= 0)
                    {
                        target = elems[i];
                        usePath = paths[i];
                        break;
                    }
                }
            }
        }
        if (target == null) return "fail:no-match";
        if (!EditableLike(target)) return "fail:not-editable path=" + usePath + " " + ElemDesc(target);
        try
        {
            object vp;
            if (target.TryGetCurrentPattern(ValuePattern.Pattern, out vp))
            {
                ValuePattern v = (ValuePattern)vp;
                if (v.Current.IsReadOnly) return "fail:readonly path=" + usePath;
                v.SetValue(text);
                Thread.Sleep(150);
                readback = v.Current.Value;
                return "ok path=" + usePath;
            }
            return "fail:no-value-pattern path=" + usePath;
        }
        catch (Exception ex) { return "fail:" + ex.Message; }
    }

    // 读回任意控件（Value/Text/Name）
    public static string UiReadSmart(IntPtr hwnd, string selector)
    {
        List<AutomationElement> elems;
        List<string> paths;
        ResolveTree(hwnd, false, 400, out elems, out paths);
        if (elems.Count == 0) return "（UIA 树为空）";
        AutomationElement target = null;
        if (selector != null && selector.IndexOf('/') >= 0)
        {
            for (int i = 0; i < elems.Count; i++)
                if (paths[i] == selector) { target = elems[i]; break; }
        }
        else
        {
            int idx = -1;
            if (selector != null && selector.StartsWith("e") && selector.Length > 1)
                int.TryParse(selector.Substring(1), out idx);
            if (idx >= 0 && idx < elems.Count) target = elems[idx];
            else
            {
                for (int i = 0; i < elems.Count; i++)
                {
                    string desc = ElemDesc(elems[i]).ToLowerInvariant();
                    if (string.IsNullOrEmpty(selector) || desc.IndexOf(selector.ToLowerInvariant()) >= 0)
                    {
                        target = elems[i];
                        break;
                    }
                }
            }
        }
        if (target == null) return "fail:no-match";
        try
        {
            object vp;
            if (target.TryGetCurrentPattern(ValuePattern.Pattern, out vp))
                return "value=" + ((ValuePattern)vp).Current.Value;
            object tp;
            if (target.TryGetCurrentPattern(TextPattern.Pattern, out tp))
            {
                string t = ((TextPattern)tp).DocumentRange.GetText(4000);
                return "text=" + t;
            }
            return "name=" + target.Current.Name;
        }
        catch (Exception ex) { return "fail:" + ex.Message; }
    }

    // 按 selector（path / eN / 关键词）Invoke 一个可点击控件（对应 mac 版 AXPress）：
    // 不移动鼠标、不需要前台、不受遮挡影响。web view 上可能返回 success 却无效——照样回读。
    public static string UiInvokeSmart(IntPtr hwnd, string selector)
    {
        List<AutomationElement> elems;
        List<string> paths;
        ResolveTree(hwnd, false, 400, out elems, out paths);
        if (elems.Count == 0) return "fail:uia-tree-empty";
        AutomationElement target = null;
        string usePath = "";
        if (selector != null && selector.IndexOf('/') >= 0)
        {
            for (int i = 0; i < elems.Count; i++)
                if (paths[i] == selector) { target = elems[i]; usePath = selector; break; }
            if (target == null) return "fail:path-miss（树已变，重新 win ax）";
        }
        else
        {
            int idx = -1;
            if (selector != null && selector.StartsWith("e") && selector.Length > 1)
                int.TryParse(selector.Substring(1), out idx);
            if (idx >= 0 && idx < elems.Count) { target = elems[idx]; usePath = paths[idx]; }
            else
            {
                for (int i = 0; i < elems.Count; i++)
                {
                    string desc = ElemDesc(elems[i]).ToLowerInvariant();
                    if (string.IsNullOrEmpty(selector) || desc.IndexOf(selector.ToLowerInvariant()) >= 0)
                    {
                        target = elems[i];
                        usePath = paths[i];
                        break;
                    }
                }
            }
        }
        if (target == null) return "fail:no-match";
        try
        {
            object ip;
            if (target.TryGetCurrentPattern(InvokePattern.Pattern, out ip))
            {
                ((InvokePattern)ip).Invoke();
                Thread.Sleep(200);
                return "ok path=" + usePath + " desc=" + ElemDesc(target);
            }
            object lp;
            if (target.TryGetCurrentPattern(SelectionItemPattern.Pattern, out lp))
            {
                ((SelectionItemPattern)lp).Select();
                Thread.Sleep(150);
                return "ok(select) path=" + usePath + " desc=" + ElemDesc(target);
            }
            return "fail:no-invoke-pattern path=" + usePath + " desc=" + ElemDesc(target);
        }
        catch (Exception ex) { return "fail:" + ex.Message; }
    }

    // 只还原前台（不还原最小化窗口，避免把用户最小化的窗口弹回来）
    public static bool RestoreForeground(IntPtr hwnd)
    {
        try
        {
            if (hwnd == IntPtr.Zero || !IsWindow(hwnd)) return false;
            if (IsIconic(hwnd)) return false;
            uint cur = GetCurrentThreadId();
            uint ignorePid;
            uint targetThread = GetWindowThreadProcessId(hwnd, out ignorePid);
            AttachThreadInput(cur, targetThread, true);
            bool ok = SetForegroundWindow(hwnd);
            AttachThreadInput(cur, targetThread, false);
            return ok;
        }
        catch { return false; }
    }

    // 鼠标位置处元素（供 op 后台档决定该不该走 UIA）
    public static string ElementAtPoint(int screenX, int screenY)
    {
        try
        {
            POINT p = new POINT(); p.X = screenX; p.Y = screenY;
            AutomationElement el = AutomationElement.FromPoint(new System.Windows.Point(screenX, screenY));
            if (el == null) return "none";
            return ElemDesc(el);
        }
        catch { return "none"; }
    }

    // op 后台档：屏幕坐标处的元素若是可编辑控件，直接 ValuePattern 写整段，返回 ok+readback
    public static string UiSetValueAtPoint(int screenX, int screenY, string text, out string readback)
    {
        readback = "";
        try
        {
            AutomationElement el = AutomationElement.FromPoint(new System.Windows.Point(screenX, screenY));
            if (el == null) return "fail:no-element";
            if (!EditableLike(el)) return "fail:not-editable " + ElemDesc(el);
            object vp;
            if (el.TryGetCurrentPattern(ValuePattern.Pattern, out vp))
            {
                ValuePattern v = (ValuePattern)vp;
                if (v.Current.IsReadOnly) return "fail:readonly";
                v.SetValue(text);
                Thread.Sleep(180);
                readback = v.Current.Value;
                return "ok";
            }
            return "fail:no-value-pattern";
        }
        catch (Exception ex) { return "fail:" + ex.Message; }
    }

    // 把「窗口 rect 相对坐标」（win shot 截图上的像素）换算成 client 坐标（PostMessage 用）
    public static string ConvertToClient(IntPtr hwnd, int rectX, int rectY)
    {
        try
        {
            RECT r;
            if (DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out r, Marshal.SizeOf(typeof(RECT))) != 0)
                GetWindowRect(hwnd, out r);
            POINT p = new POINT();
            p.X = r.Left + rectX;
            p.Y = r.Top + rectY;
            if (!ScreenToClient(hwnd, ref p)) return "fail";
            return p.X.ToString() + " " + p.Y.ToString();
        }
        catch (Exception ex) { return "fail:" + ex.Message; }
    }

    // 全局真实点击（SendInput 鼠标；要求目标在前台/可见）
    [DllImport("user32.dll")]
    private static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, IntPtr dwExtraInfo);
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;

    public static void GlobalClick(int screenX, int screenY)
    {
        SetCursorPos(screenX, screenY);
        Thread.Sleep(60);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, IntPtr.Zero);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, IntPtr.Zero);
        Thread.Sleep(80);
    }

    // ---------- HUD：四角取景框（WPF，无焦点、鼠标穿透、置顶） ----------
    public static void ShowHud(int durationMs, string text)
    {
        Thread t = new Thread(delegate()
        {
            try
            {
                System.Windows.Window w = new System.Windows.Window();
                w.WindowStyle = System.Windows.WindowStyle.None;
                w.AllowsTransparency = true;
                w.Background = System.Windows.Media.Brushes.Transparent;
                w.Topmost = true;
                w.ShowActivated = false;
                w.Width = System.Windows.SystemParameters.PrimaryScreenWidth;
                w.Height = System.Windows.SystemParameters.PrimaryScreenHeight;
                w.Left = 0; w.Top = 0;
                w.WindowStartupLocation = System.Windows.WindowStartupLocation.Manual;
                w.ResizeMode = System.Windows.ResizeMode.NoResize;

                System.Windows.Controls.Canvas canvas = new System.Windows.Controls.Canvas();
                double wdt = System.Windows.SystemParameters.PrimaryScreenWidth;
                double hgt = System.Windows.SystemParameters.PrimaryScreenHeight;
                double len = 90, thick = 6;
                System.Windows.Media.Brush brush = System.Windows.Media.Brushes.OrangeRed;
                AddCorner(canvas, 0, 0, len, thick, 0, brush);
                AddCorner(canvas, wdt - len - thick, 0, len, thick, 90, brush);
                AddCorner(canvas, 0, hgt - len - thick, len, thick, 270, brush);
                AddCorner(canvas, wdt - len - thick, hgt - len - thick, len, thick, 180, brush);
                if (!string.IsNullOrEmpty(text))
                {
                    System.Windows.Controls.TextBlock tb = new System.Windows.Controls.TextBlock();
                    tb.Text = text;
                    tb.Foreground = System.Windows.Media.Brushes.OrangeRed;
                    tb.FontSize = 22;
                    tb.FontWeight = System.Windows.FontWeights.Bold;
                    tb.Margin = new System.Windows.Thickness(24, 14, 0, 0);
                    canvas.Children.Add(tb);
                }
                w.Content = canvas;
                w.Loaded += delegate
                {
                    System.Windows.Threading.DispatcherTimer timer = new System.Windows.Threading.DispatcherTimer();
                    timer.Interval = TimeSpan.FromMilliseconds(durationMs);
                    timer.Tick += delegate { w.Close(); };
                    timer.Start();
                };
                // 鼠标穿透 + 不抢焦点
                w.SourceInitialized += delegate
                {
                    IntPtr h = new System.Windows.Interop.WindowInteropHelper(w).Handle;
                    int ex = GetWindowLong(h, -20);
                    SetWindowLong(h, -20, ex | 0x00000020 | 0x08000000 | 0x00080000); // WS_EX_TRANSPARENT|WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW
                };
                w.Show();
                System.Windows.Threading.Dispatcher.Run();
            }
            catch { }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
        if (!t.Join(durationMs + 800))
        {
            try { t.Abort(); } catch { }
        }
    }

    private static void AddCorner(System.Windows.Controls.Canvas canvas, double x, double y,
        double len, double thick, double angle, System.Windows.Media.Brush brush)
    {
        System.Windows.Shapes.Rectangle r1 = new System.Windows.Shapes.Rectangle();
        r1.Width = len; r1.Height = thick; r1.Fill = brush; r1.RadiusX = 3; r1.RadiusY = 3;
        System.Windows.Controls.Canvas.SetLeft(r1, x); System.Windows.Controls.Canvas.SetTop(r1, y);
        canvas.Children.Add(r1);
        System.Windows.Shapes.Rectangle r2 = new System.Windows.Shapes.Rectangle();
        r2.Width = thick; r2.Height = len; r2.Fill = brush; r2.RadiusX = 3; r2.RadiusY = 3;
        System.Windows.Controls.Canvas.SetLeft(r2, x); System.Windows.Controls.Canvas.SetTop(r2, y);
        canvas.Children.Add(r2);
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
