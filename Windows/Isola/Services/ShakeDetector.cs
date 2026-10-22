using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Isola.Services;

/// <summary>
/// Watches the mouse system-wide for a shake while the left button is held, the way you shake a dragged file. Windows
/// does not say when a drag is in progress, so a held button that has travelled a little stands in for one, unless the
/// press was on a window's title bar or border (moving a window, or Windows' own shake-to-minimise).
/// </summary>
public sealed class ShakeDetector : IDisposable
{
    readonly Native.HookProc proc;
    IntPtr hook;
    bool down, fired, onFrame;
    DateTime downAt;
    Native.POINT downPoint;
    int direction, extreme;
    readonly List<DateTime> reversals = new();

    /// <summary>A shake, with the pointer's screen position in pixels.</summary>
    public event Action<int, int>? Shaken;
    /// <summary>The button went up after a shake.</summary>
    public event Action? Released;

    public ShakeDetector()
    {
        proc = Callback;
    }

    public void Start()
    {
        if (hook == IntPtr.Zero) hook = Native.SetWindowsHookEx(Native.WH_MOUSE_LL, proc, Native.GetModuleHandle(null), 0);
    }

    public void Dispose()
    {
        if (hook != IntPtr.Zero) Native.UnhookWindowsHookEx(hook);
        hook = IntPtr.Zero;
    }

    IntPtr Callback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            var msg = wParam.ToInt32();
            var data = Marshal.PtrToStructure<Native.MSLLHOOKSTRUCT>(lParam);
            switch (msg)
            {
                case Native.WM_LBUTTONDOWN:
                    down = true;
                    fired = false;
                    downAt = DateTime.UtcNow;
                    downPoint = data.pt;
                    onFrame = false;
                    // Hit-test after the hook returns: the hook must answer quickly.
                    var point = data.pt;
                    System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => onFrame = Native.IsWindowFrame(point));
                    direction = 0;
                    extreme = data.pt.X;
                    reversals.Clear();
                    break;
                case Native.WM_LBUTTONUP:
                    if (fired) Released?.Invoke();
                    down = false;
                    fired = false;
                    break;
                case Native.WM_MOUSEMOVE when down && !fired && Settings.Current.ShakeBasket:
                    Track(data.pt);
                    break;
            }
        }
        return Native.CallNextHookEx(hook, code, wParam, lParam);
    }

    void Track(Native.POINT p)
    {
        var now = DateTime.UtcNow;
        // A drag starts with a held button and some travel; clicks and tiny wiggles never count.
        if ((now - downAt).TotalMilliseconds < 200) return;
        if (Math.Abs(p.X - downPoint.X) + Math.Abs(p.Y - downPoint.Y) < 12 && reversals.Count == 0) return;

        var dx = p.X - extreme;
        if (direction == 0)
        {
            if (Math.Abs(dx) > 18) { direction = Math.Sign(dx); extreme = p.X; }
            return;
        }
        if (Math.Sign(dx) == direction) { extreme = p.X; return; }
        if (Math.Abs(dx) < 28) return;

        // Turned round far enough: one swing of the shake.
        direction = -direction;
        extreme = p.X;
        reversals.Add(now);
        reversals.RemoveAll(t => (now - t).TotalMilliseconds > 700);
        if (reversals.Count >= 4 && !onFrame)
        {
            fired = true;
            reversals.Clear();
            Shaken?.Invoke(p.X, p.Y);
        }
    }
}
