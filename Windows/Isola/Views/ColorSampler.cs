using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace Isola.Views;

/// <summary>
/// An eyedropper over every screen: a swatch follows the pointer showing the colour under it, a click reads it, and
/// Escape or a right-click cancels.
/// </summary>
sealed class ColorSampler : Window
{
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
    [DllImport("gdi32.dll")] static extern uint GetPixel(IntPtr dc, int x, int y);

    readonly Border swatch = new()
    {
        Width = 44, Height = 44, CornerRadius = new CornerRadius(22), BorderBrush = Brushes.White, BorderThickness = new Thickness(3),
        Effect = new DropShadowEffect { BlurRadius = 10, ShadowDepth = 2, Opacity = 0.5 }, IsHitTestVisible = false,
    };

    public ColorSampler(Action<Color> picked)
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        // Almost clear, but not quite, so the clicks land here and not on the app underneath.
        Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
        Topmost = true;
        ShowInTaskbar = false;
        ResizeMode = ResizeMode.NoResize;
        Left = SystemParameters.VirtualScreenLeft;
        Top = SystemParameters.VirtualScreenTop;
        Width = SystemParameters.VirtualScreenWidth;
        Height = SystemParameters.VirtualScreenHeight;
        Cursor = Cursors.Cross;
        var canvas = new Canvas();
        canvas.Children.Add(swatch);
        Content = canvas;

        MouseMove += (_, e) =>
        {
            var p = e.GetPosition(canvas);
            Canvas.SetLeft(swatch, p.X + 18);
            Canvas.SetTop(swatch, p.Y + 18);
            swatch.Background = new SolidColorBrush(Read());
        };
        MouseLeftButtonUp += (_, _) =>
        {
            var color = Read();
            Close();
            picked(color);
        };
        MouseRightButtonUp += (_, _) => Close();
        KeyDown += (_, e) => { if (e.Key == Key.Escape) Close(); };
        Loaded += (_, _) =>
        {
            Activate();
            Focus();
        };
    }

    /// <summary>The colour of the screen pixel under the pointer.</summary>
    static Color Read()
    {
        Native.GetCursorPos(out var p);
        var dc = GetDC(IntPtr.Zero);
        try
        {
            var value = GetPixel(dc, p.X, p.Y);
            return Color.FromRgb((byte)(value & 0xFF), (byte)((value >> 8) & 0xFF), (byte)((value >> 16) & 0xFF));
        }
        finally
        {
            ReleaseDC(IntPtr.Zero, dc);
        }
    }
}
