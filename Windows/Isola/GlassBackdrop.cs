using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace Isola;

/// <summary>
/// The real blur under the island's Dynamic Glass. Windows only blurs what is behind a whole window, so this is an empty
/// window of its own, kept just under the island, cut to its outline and never taking a click. The island draws its
/// tint, sheen and edges on top. Where Windows will not blur, Available is false and the island uses a darker tint.
/// </summary>
sealed class GlassBackdrop : Window
{
    IntPtr hwnd;
    string shown = "";
    bool visible;

    public bool Available { get; private set; }

    public GlassBackdrop()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        // All but clear: the window has to draw something for the blur behind it to show.
        Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.NoResize;
        Focusable = false;
        IsHitTestVisible = false;
        Left = Top = -32000;
        Width = Height = 1;
        SourceInitialized += (_, _) =>
        {
            hwnd = new WindowInteropHelper(this).Handle;
            Native.SetWindowLong(hwnd, Native.GWL_EXSTYLE, Native.GetWindowLong(hwnd, Native.GWL_EXSTYLE)
                | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE | Native.WS_EX_TRANSPARENT);
            Available = Native.SetBlurBehind(hwnd, true);
        };
    }

    /// <summary>
    /// Puts the blur under the island: its top left corner on screen and its size, in pixels, with its top and bottom
    /// corner radii, also in pixels. ISLAND is the island's own window, which stays just above this one.
    /// </summary>
    public void Cover(IntPtr island, int x, int y, int width, int height, double topRadius, double bottomRadius)
    {
        if (hwnd == IntPtr.Zero || !Available || width < 2 || height < 2) return;
        var key = $"{x},{y},{width},{height},{Math.Round(topRadius)},{Math.Round(bottomRadius)}";
        // Below the island in the stack every time, in case something raised either window.
        Native.SetWindowPos(hwnd, island, x, y, width, height, Native.SWP_NOACTIVATE | Native.SWP_SHOWWINDOW);
        visible = true;
        if (key == shown) return;
        shown = key;

        // A pixel inside the island's edge, so the region's stepped edge stays under the island's smooth one.
        const double inset = 1;
        var outline = Ui.Outline(inset, inset, width - inset * 2, height - inset * 2,
            Math.Max(topRadius - inset, 0), Math.Max(bottomRadius - inset, 0));
        var points = new List<Native.POINT>();
        foreach (var figure in outline.GetFlattenedPathGeometry(0.25, ToleranceType.Absolute).Figures)
        {
            Add(points, figure.StartPoint);
            foreach (var segment in figure.Segments)
            {
                if (segment is System.Windows.Media.LineSegment line) Add(points, line.Point);
                else if (segment is PolyLineSegment poly)
                    foreach (var p in poly.Points) Add(points, p);
            }
        }
        if (points.Count < 3) return;
        const int winding = 2;
        var region = Native.CreatePolygonRgn(points.ToArray(), points.Count, winding);
        // Windows owns the region once it is set; it is only ours to delete if that fails.
        if (region != IntPtr.Zero && Native.SetWindowRgn(hwnd, region, true) == 0) Native.DeleteObject(region);
    }

    static void Add(List<Native.POINT> points, Point p) =>
        points.Add(new Native.POINT { X = (int)Math.Round(p.X), Y = (int)Math.Round(p.Y) });

    /// <summary>
    /// The average colour of the screen in AREAS (screen pixels), for the glass to take on: strips just outside the
    /// island, beyond its shadow, so Isola never reads its own pixels and never has to hide from screenshots to see
    /// what is behind it. Null when nothing could be read (on the secure desktop, for instance).
    /// </summary>
    public static Color? SampleAround(IEnumerable<Int32Rect> areas)
    {
        const int SM_XVIRTUALSCREEN = 76, SM_YVIRTUALSCREEN = 77, SM_CXVIRTUALSCREEN = 78, SM_CYVIRTUALSCREEN = 79;
        var screen = new Int32Rect(Native.GetSystemMetrics(SM_XVIRTUALSCREEN), Native.GetSystemMetrics(SM_YVIRTUALSCREEN),
            Native.GetSystemMetrics(SM_CXVIRTUALSCREEN), Native.GetSystemMetrics(SM_CYVIRTUALSCREEN));
        double r = 0, g = 0, b = 0;
        long count = 0;
        try
        {
            foreach (var wanted in areas)
            {
                var x = Math.Max(wanted.X, screen.X);
                var y = Math.Max(wanted.Y, screen.Y);
                var right = Math.Min(wanted.X + wanted.Width, screen.X + screen.Width);
                var bottom = Math.Min(wanted.Y + wanted.Height, screen.Y + screen.Height);
                if (right - x < 1 || bottom - y < 1) continue;
                using var bitmap = new System.Drawing.Bitmap(right - x, bottom - y);
                using (var graphics = System.Drawing.Graphics.FromImage(bitmap))
                    graphics.CopyFromScreen(x, y, 0, 0, bitmap.Size);
                // Every other pixel is plenty for an average.
                for (var py = 0; py < bitmap.Height; py += 2)
                    for (var px = 0; px < bitmap.Width; px += 2)
                    {
                        var c = bitmap.GetPixel(px, py);
                        r += c.R; g += c.G; b += c.B;
                        count++;
                    }
            }
        }
        catch (Exception) { return null; }
        if (count == 0) return null;
        return Color.FromRgb((byte)(r / count), (byte)(g / count), (byte)(b / count));
    }

    /// <summary>Takes the blur away, while the island is solid black, hidden or out of sight.</summary>
    public void Conceal()
    {
        if (hwnd == IntPtr.Zero || !visible) return;
        Native.ShowWindow(hwnd, Native.SW_HIDE);
        visible = false;
    }
}
