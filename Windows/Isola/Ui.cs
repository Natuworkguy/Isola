using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;

namespace Isola;

/// <summary>Small builders for the code-only interface, in the island's style.</summary>
static class Ui
{
    public static readonly FontFamily Text = new("Segoe UI Variable Text, Segoe UI");
    public static readonly FontFamily Display = new("Segoe UI Variable Display, Segoe UI");
    public static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");
    public static readonly FontFamily Mono = new("Cascadia Mono, Consolas");

    public static readonly Duration Quick = new(TimeSpan.FromMilliseconds(180));

    // Segoe Fluent Icons / MDL2 code points.
    public const string Play = "", Pause = "", Previous = "", Next = "";
    public const string Volume = "", Mute = "", Brightness = "";
    public const string Charging = "", Battery = "", BatteryLow = "";
    public const string Headphones = "", Drive = "", Vpn = "", Unlock = "";
    public const string Check = "", Close = "", Bell = "", Warning = "", Info = "";
    public const string Heart = "", Star = "", Bolt = "", Sync = "", Share = "";
    public const string Package = "", Folder = "", Paste = "", Gauge = "", Media = "";
    public const string Pin = "", Pinned = "", Gear = "", Search = "", Link = "";
    public const string Color = "", Picture = "", Font = "", Download = "", Music = "";
    public const string OpenApp = "", Delete = "";
    public const string Home = "\uE80F", Clock = "\uE917", Calendar = "\uE787", Stopwatch = "\uE916", Tiles = "\uECA5";
    public const string Up = "\uE70E", Down = "\uE70D", Reset = "\uE72C", Edit = "\uE70F", Minus = "\uE738";

    public static Color Rgb(byte r, byte g, byte b, byte a = 255) => System.Windows.Media.Color.FromArgb(a, r, g, b);
    public static SolidColorBrush Brush(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
    public static SolidColorBrush White(double opacity) => Brush(Rgb(255, 255, 255, (byte)Math.Round(255 * opacity)));
    public static SolidColorBrush Black(double opacity) => Brush(Rgb(0, 0, 0, (byte)Math.Round(255 * opacity)));

    public static readonly Color Green = Rgb(48, 209, 88), Blue = Rgb(10, 132, 255), Orange = Rgb(255, 159, 10);
    public static readonly Color Red = Rgb(255, 69, 58), Purple = Rgb(191, 90, 242), Gray = Rgb(142, 142, 147);
    public static readonly Color Mint = Rgb(99, 230, 226), Yellow = Rgb(255, 214, 10), Teal = Rgb(64, 200, 224);

    public static TextBlock Label(string text, double size, FontWeight weight, double opacity = 1, FontFamily? family = null) => new()
    {
        Text = text,
        FontSize = size,
        FontWeight = weight,
        FontFamily = family ?? Text,
        Foreground = White(opacity),
        TextTrimming = TextTrimming.CharacterEllipsis,
        TextWrapping = TextWrapping.NoWrap,
    };

    public static TextBlock Glyph(string glyph, double size, Brush? brush = null) => new()
    {
        Text = glyph,
        FontFamily = Icons,
        FontSize = size,
        Foreground = brush ?? Brushes.White,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
        TextAlignment = TextAlignment.Center,
    };

    /// <summary>A capsule button: icon and title, translucent white, brighter under the pointer.</summary>
    public static Border Pill(string glyph, string title, Action click)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        row.Children.Add(Glyph(glyph, 11));
        row.Children.Add(new TextBlock
        {
            Text = title, FontFamily = Text, FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White,
            Margin = new Thickness(6, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center,
        });
        var pill = Capsule(new Border
        {
            Child = row,
            Background = White(0.14),
            Padding = new Thickness(10, 4, 10, 4),
            Cursor = Cursors.Hand,
        });
        Hover(pill, White(0.14), White(0.24));
        pill.MouseLeftButtonUp += (_, e) => { e.Handled = true; click(); };
        return pill;
    }

    /// <summary>A round icon button.</summary>
    public static Border Round(string glyph, double size, Action click, double glyphSize = 11)
    {
        var b = new Border
        {
            Width = size, Height = size, CornerRadius = new CornerRadius(size / 2), Background = White(0.1),
            Child = Glyph(glyph, glyphSize, White(0.8)), Cursor = Cursors.Hand,
        };
        Hover(b, White(0.1), White(0.22));
        b.MouseLeftButtonUp += (_, e) => { e.Handled = true; click(); };
        return b;
    }

    /// <summary>
    /// Rounds B into a capsule: ends exactly half its height. (A radius larger than that makes WPF draw a pointed
    /// lens, not a capsule.)
    /// </summary>
    public static T Capsule<T>(T b) where T : Border
    {
        void Round() => b.CornerRadius = new CornerRadius(Math.Max(b.ActualHeight, 0) / 2);
        b.SizeChanged += (_, _) => Round();
        if (!double.IsNaN(b.Height)) b.CornerRadius = new CornerRadius(b.Height / 2);
        return b;
    }

    public static void Hover(Border b, Brush normal, Brush hover)
    {
        b.MouseEnter += (_, _) => b.Background = hover;
        b.MouseLeave += (_, _) => b.Background = normal;
    }

    public static void FadeTo(UIElement e, double opacity, double ms = 200)
    {
        e.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(opacity, TimeSpan.FromMilliseconds(ms))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
        });
        e.IsHitTestVisible = opacity > 0.01;
    }

    /// <summary>A rounded rectangle with separate top and bottom radii, as the island's outline.</summary>
    public static Geometry Outline(double x, double y, double w, double h, double top, double bottom)
    {
        w = Math.Max(w, 1);
        h = Math.Max(h, 1);
        top = Math.Min(top, Math.Min(w, h) / 2);
        bottom = Math.Min(bottom, Math.Min(w, h) / 2);
        var g = new StreamGeometry();
        using (var c = g.Open())
        {
            c.BeginFigure(new Point(x + top, y), true, true);
            c.LineTo(new Point(x + w - top, y), true, false);
            if (top > 0) c.ArcTo(new Point(x + w, y + top), new Size(top, top), 0, false, SweepDirection.Clockwise, true, false);
            c.LineTo(new Point(x + w, y + h - bottom), true, false);
            if (bottom > 0) c.ArcTo(new Point(x + w - bottom, y + h), new Size(bottom, bottom), 0, false, SweepDirection.Clockwise, true, false);
            c.LineTo(new Point(x + bottom, y + h), true, false);
            if (bottom > 0) c.ArcTo(new Point(x, y + h - bottom), new Size(bottom, bottom), 0, false, SweepDirection.Clockwise, true, false);
            c.LineTo(new Point(x, y + top), true, false);
            if (top > 0) c.ArcTo(new Point(x + top, y), new Size(top, top), 0, false, SweepDirection.Clockwise, true, false);
        }
        g.Freeze();
        return g;
    }

    /// <summary>Artwork, or a gradient with an icon when there is none.</summary>
    public static Border Artwork(ImageSource? image, double size, double radius, string glyph = Music)
    {
        var border = new Border
        {
            Width = size, Height = size, CornerRadius = new CornerRadius(radius), ClipToBounds = true,
        };
        if (image is not null)
            border.Background = new ImageBrush(image) { Stretch = Stretch.UniformToFill };
        else
        {
            border.Background = new LinearGradientBrush(Rgb(255, 55, 95), Rgb(94, 92, 230), 45);
            border.Child = Glyph(glyph, size * 0.4, White(0.9));
        }
        return border;
    }

    public static DropShadowEffect Glow(Color color, double radius, double opacity) => new()
    {
        Color = color, BlurRadius = radius, ShadowDepth = 0, Opacity = opacity,
    };

    /// <summary>The average colour of an image, lifted so it reads on black: the tint for the glow and equaliser.</summary>
    public static Color VibrantColor(ImageSource? image)
    {
        if (image is not System.Windows.Media.Imaging.BitmapSource bitmap) return Rgb(180, 180, 180);
        try
        {
            var small = new System.Windows.Media.Imaging.TransformedBitmap(bitmap,
                new ScaleTransform(8.0 / bitmap.PixelWidth, 8.0 / bitmap.PixelHeight));
            var converted = new System.Windows.Media.Imaging.FormatConvertedBitmap(small, PixelFormats.Bgra32, null, 0);
            int w = converted.PixelWidth, h = converted.PixelHeight;
            var pixels = new byte[w * h * 4];
            converted.CopyPixels(pixels, w * 4, 0);
            double r = 0, g = 0, b = 0;
            for (int i = 0; i < pixels.Length; i += 4) { b += pixels[i]; g += pixels[i + 1]; r += pixels[i + 2]; }
            int n = pixels.Length / 4;
            var (hue, sat, val) = ToHsv(r / n / 255, g / n / 255, b / n / 255);
            return FromHsv(hue, Math.Min(1, sat * 1.25 + 0.1), Math.Max(val, 0.65));
        }
        catch { return Rgb(180, 180, 180); }
    }

    static (double h, double s, double v) ToHsv(double r, double g, double b)
    {
        double max = Math.Max(r, Math.Max(g, b)), min = Math.Min(r, Math.Min(g, b)), d = max - min, h = 0;
        if (d > 0)
        {
            if (max == r) h = ((g - b) / d) % 6;
            else if (max == g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h *= 60;
            if (h < 0) h += 360;
        }
        return (h, max == 0 ? 0 : d / max, max);
    }

    static Color FromHsv(double h, double s, double v)
    {
        double c = v * s, x = c * (1 - Math.Abs(h / 60 % 2 - 1)), m = v - c;
        var (r, g, b) = h switch
        {
            < 60 => (c, x, 0.0),
            < 120 => (x, c, 0.0),
            < 180 => (0.0, c, x),
            < 240 => (0.0, x, c),
            < 300 => (x, 0.0, c),
            _ => (c, 0.0, x),
        };
        return Rgb((byte)((r + m) * 255), (byte)((g + m) * 255), (byte)((b + m) * 255));
    }
}
