using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using Isola.Services;

namespace Isola.Views;

/// <summary>The closed island while something plays: the artwork on the left, an equaliser on the right.</summary>
sealed class CollapsedView : Grid
{
    readonly Border art = new() { Width = 20, Height = 20, CornerRadius = new CornerRadius(5), ClipToBounds = true };
    readonly Rectangle[] bars = new Rectangle[4];
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(1000.0 / 24) };
    Color tint = Ui.Rgb(180, 180, 180);
    bool playing;

    public CollapsedView()
    {
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(50) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(50) });
        art.HorizontalAlignment = HorizontalAlignment.Center;
        art.VerticalAlignment = VerticalAlignment.Center;
        Children.Add(art);
        var eq = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        for (var i = 0; i < 4; i++)
        {
            bars[i] = new Rectangle { Width = 3, Height = 6, RadiusX = 1.5, RadiusY = 1.5, Margin = new Thickness(1, 0, 1, 0), VerticalAlignment = VerticalAlignment.Center };
            eq.Children.Add(bars[i]);
        }
        SetColumn(eq, 2);
        Children.Add(eq);
        timer.Tick += (_, _) => Animate();
    }

    public void Show(NowPlayer? player)
    {
        playing = player?.IsPlaying == true;
        if (player is null) return;
        art.Background = player.Artwork is null
            ? new LinearGradientBrush(Ui.Rgb(255, 55, 95), Ui.Rgb(94, 92, 230), 45)
            : new ImageBrush(player.Artwork) { Stretch = Stretch.UniformToFill };
        tint = player.Tint;
        foreach (var b in bars) b.Fill = new SolidColorBrush(tint);
        if (playing && IsVisible) timer.Start(); else timer.Stop();
    }

    public void Active(bool on)
    {
        if (on && playing) timer.Start(); else timer.Stop();
    }

    void Animate()
    {
        var t = Environment.TickCount64 / 1000.0;
        for (var i = 0; i < 4; i++)
            bars[i].Height = 5 + 11 * (Math.Sin(t * 5.5 + i * 1.4) + 1) / 2;
    }
}

/// <summary>Volume or brightness, as one centred row: icon, bar, number.</summary>
sealed class HudView : Grid
{
    readonly TextBlock icon = Ui.Glyph(Ui.Volume, 13);
    readonly Border track = new() { Height = 5, CornerRadius = new CornerRadius(3), Background = Ui.White(0.2) };
    readonly Border fill = new() { Height = 5, CornerRadius = new CornerRadius(3), HorizontalAlignment = HorizontalAlignment.Left };
    readonly TextBlock number = Ui.Label("0", 11, FontWeights.SemiBold);
    double level;

    public HudView()
    {
        Margin = new Thickness(16, 0, 16, 0);
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(22) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(30) });
        Children.Add(icon);
        var bar = new Grid { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 8, 0) };
        bar.Children.Add(track);
        bar.Children.Add(fill);
        bar.SizeChanged += (_, _) => Layout();
        SetColumn(bar, 1);
        Children.Add(bar);
        number.HorizontalAlignment = HorizontalAlignment.Right;
        number.VerticalAlignment = VerticalAlignment.Center;
        number.Typography.NumeralAlignment = FontNumeralAlignment.Tabular;
        SetColumn(number, 2);
        Children.Add(number);
    }

    public void Show(HudKind kind, double value, bool muted)
    {
        level = Math.Clamp(value, 0, 1);
        var color = kind == HudKind.Brightness ? Ui.Brush(Ui.Yellow) : Brushes.White;
        icon.Text = kind == HudKind.Brightness ? Ui.Brightness : muted || level == 0 ? Ui.Mute : Ui.Volume;
        icon.Foreground = color;
        fill.Background = color;
        number.Text = muted ? "0" : $"{Math.Round(level * 100)}";
        if (muted) level = 0;
        Layout();
    }

    void Layout()
    {
        if (fill.Parent is FrameworkElement bar) fill.Width = Math.Max(bar.ActualWidth * level, 0);
    }
}

/// <summary>
/// A banner: an icon in a coloured circle, a title and a line under it, and up to two buttons, centred. A ringing
/// banner (a timer or alarm going off) shakes its bell and glows until it is answered.
/// </summary>
sealed class BannerView : Grid
{
    public void Show(Banner banner, Action dismiss)
    {
        Children.Clear();
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        var dot = new Border
        {
            Width = 32, Height = 32, CornerRadius = new CornerRadius(16),
            Background = new LinearGradientBrush(banner.Tint, Ui.Rgb((byte)(banner.Tint.R * 0.8), (byte)(banner.Tint.G * 0.8), (byte)(banner.Tint.B * 0.8)), 90),
            Effect = Ui.Glow(banner.Tint, 14, 0.6),
            Child = Ui.Glyph(banner.Glyph, 15),
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (banner.Ringing) Shake(dot);
        row.Children.Add(dot);
        var text = new StackPanel { Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, MaxWidth = 230 };
        text.Children.Add(Ui.Label(banner.Title, 13, FontWeights.SemiBold));
        if (banner.Subtitle.Length > 0) text.Children.Add(Ui.Label(banner.Subtitle, 11, FontWeights.Normal, 0.62));
        row.Children.Add(text);
        if (banner.SecondAction is { } second) row.Children.Add(Button(second, false, dismiss, 12));
        if (banner.Action is { } action) row.Children.Add(Button(action, true, dismiss, banner.SecondAction is null ? 12 : 6));
        Children.Add(row);
    }

    static Border Button(BannerAction action, bool primary, Action dismiss, double left)
    {
        var ink = primary ? Brushes.Black : Brushes.White;
        var label = new StackPanel { Orientation = Orientation.Horizontal };
        label.Children.Add(Ui.Glyph(action.Glyph, 11, ink));
        label.Children.Add(new TextBlock
        {
            Text = action.Title, FontFamily = Ui.Text, FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = ink,
            Margin = new Thickness(6, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center,
        });
        var normal = primary ? Brushes.White : Ui.White(0.18);
        var button = Ui.Capsule(new Border
        {
            Child = label, Background = normal, Padding = new Thickness(10, 5, 10, 5),
            Margin = new Thickness(left, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, Cursor = Cursors.Hand,
        });
        Ui.Hover(button, normal, primary ? Ui.White(0.85) : Ui.White(0.28));
        button.MouseLeftButtonUp += (_, e) => { e.Handled = true; action.Perform(); dismiss(); };
        return button;
    }

    /// <summary>Two quick shakes, then a pause, like a bell, and a glow that breathes.</summary>
    static void Shake(Border bell)
    {
        var turn = new RotateTransform(0, 16, 16);
        bell.RenderTransform = turn;
        var shake = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromSeconds(1.2), RepeatBehavior = RepeatBehavior.Forever };
        double[] angles = { 0, 16, -14, 12, -9, 6, -3, 0 };
        for (var i = 0; i < angles.Length; i++)
            shake.KeyFrames.Add(new EasingDoubleKeyFrame(angles[i], KeyTime.FromTimeSpan(TimeSpan.FromSeconds(i * 0.07))));
        Timeline.SetDesiredFrameRate(shake, 30);
        turn.BeginAnimation(RotateTransform.AngleProperty, shake);
        if (bell.Effect is System.Windows.Media.Effects.DropShadowEffect glow)
        {
            var breathe = new DoubleAnimation(0.35, 0.9, TimeSpan.FromSeconds(0.8)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever };
            Timeline.SetDesiredFrameRate(breathe, 30);
            glow.BeginAnimation(System.Windows.Media.Effects.DropShadowEffect.OpacityProperty, breathe);
        }
    }
}
