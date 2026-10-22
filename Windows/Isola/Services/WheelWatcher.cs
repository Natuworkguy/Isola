using System;
using System.Runtime.InteropServices;

namespace Isola.Services;

/// <summary>
/// Watches the mouse wheel system-wide. A wheel turned next to the island goes to the window underneath, so the
/// island never hears of it on its own.
/// </summary>
public sealed class WheelWatcher : IDisposable
{
    readonly Native.HookProc proc;
    IntPtr hook;

    /// <summary>A turn of the wheel, or a swipe on a touchpad, in wheel units: positive away from you.</summary>
    public event Action<int>? Turned;

    public WheelWatcher()
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
        if (code >= 0 && wParam.ToInt32() == Native.WM_MOUSEWHEEL)
        {
            var data = Marshal.PtrToStructure<Native.MSLLHOOKSTRUCT>(lParam);
            var delta = (short)(data.mouseData >> 16);
            // Acted on after the hook returns: the hook must answer quickly.
            System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => Turned?.Invoke(delta));
        }
        return Native.CallNextHookEx(hook, code, wParam, lParam);
    }
}
