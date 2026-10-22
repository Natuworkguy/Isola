using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using Isola.Services;

namespace Isola;

/// <summary>Shake a dragged file and this pops up under the pointer: drop it on Tray, Share, Convert or Zip.</summary>
sealed class BasketWindow : Window
{
    public enum Target { Tray, Share, Convert, Zip }

    const double Size = 236;
    readonly Grid grid = new() { Margin = new Thickness(12) };
    readonly Border panel;
    readonly ScaleTransform scale = new(0.6, 0.6);
    readonly Border[] tiles = new Border[4];
    readonly DispatcherTimer hideTimer = new() { Interval = TimeSpan.FromMilliseconds(450) };
    readonly Action<Target, string[]> perform;
    Target? targeted;
    bool visible;

    public BasketWindow(Action<Target, string[]> perform)
    {
        this.perform = perform;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.NoResize;
        Width = Height = Size + 40;

        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.RowDefinitions.Add(new RowDefinition());
        grid.RowDefinitions.Add(new RowDefinition());
        var all = new[] { (Target.Tray, Ui.Download, "Tray"), (Target.Share, Ui.Share, "Share"), (Target.Convert, Ui.Sync, "Convert"), (Target.Zip, Ui.Package, "Zip") };
        for (var i = 0; i < 4; i++)
        {
            var (target, glyph, title) = all[i];
            var stack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, IsHitTestVisible = false };
            stack.Children.Add(Ui.Glyph(glyph, 20));
            var label = Ui.Label(title, 11, FontWeights.SemiBold);
            label.HorizontalAlignment = HorizontalAlignment.Center;
            label.Margin = new Thickness(0, 6, 0, 0);
            stack.Children.Add(label);
            var tile = new Border
            {
                Child = stack, CornerRadius = new CornerRadius(18), Background = Ui.White(0.1), Margin = new Thickness(5),
                AllowDrop = true, RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = new ScaleTransform(1, 1),
            };
            tile.DragEnter += (_, e) => Over(target, e);
            tile.DragOver += (_, e) => Over(target, e);
            tile.DragLeave += (_, _) => { if (targeted == target) Light(null); };
            tile.Drop += (_, e) =>
            {
                e.Handled = true;
                Light(null);
                if (e.Data.GetData(DataFormats.FileDrop) is string[] files && files.Length > 0) perform(target, files);
                Hide(true);
            };
            Grid.SetColumn(tile, i % 2);
            Grid.SetRow(tile, i / 2);
            grid.Children.Add(tile);
            tiles[i] = tile;
        }

        panel = new Border
        {
            Width = Size, Height = Size, CornerRadius = new CornerRadius(26), Child = grid,
            Background = new LinearGradientBrush(Ui.Rgb(40, 40, 48, 235), Ui.Rgb(18, 18, 22, 242), 90),
            BorderBrush = Ui.White(0.18), BorderThickness = new Thickness(1),
            Effect = new DropShadowEffect { BlurRadius = 28, ShadowDepth = 6, Direction = 270, Opacity = 0.35 },
            RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = scale, Opacity = 0,
        };
        Content = panel;
        hideTimer.Tick += (_, _) => { hideTimer.Stop(); if (targeted is null) Hide(true); };

        SourceInitialized += (_, _) =>
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            Native.SetWindowLong(hwnd, Native.GWL_EXSTYLE,
                Native.GetWindowLong(hwnd, Native.GWL_EXSTYLE) | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE);
        };
    }

    void Over(Target target, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
        Light(target);
    }

    void Light(Target? target)
    {
        targeted = target;
        for (var i = 0; i < 4; i++)
        {
            var on = target == (Target)i;
            tiles[i].Background = on ? Brushes.White : Ui.White(0.1);
            foreach (var t in ((StackPanel)tiles[i].Child).Children.OfType<TextBlock>()) t.Foreground = on ? Brushes.Black : Brushes.White;
            var s = (ScaleTransform)tiles[i].RenderTransform;
            s.ScaleX = s.ScaleY = on ? 1.06 : 1;
        }
    }

    /// <summary>Pops up centred on the pointer, given in screen pixels.</summary>
    public void ShowAt(int x, int y)
    {
        if (!IsLoaded) { Show(); Hide(false); }
        var source = PresentationSource.FromVisual(this);
        var toDip = source?.CompositionTarget?.TransformFromDevice ?? Matrix.Identity;
        var p = toDip.Transform(new Point(x, y));
        Left = p.X - Width / 2;
        Top = p.Y - Height / 2;
        visible = true;
        Visibility = Visibility.Visible;
        Show();
        var spring = new ElasticEase { Oscillations = 1, Springiness = 6, EasingMode = EasingMode.EaseOut };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(0.6, 1, TimeSpan.FromMilliseconds(380)) { EasingFunction = spring });
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(0.6, 1, TimeSpan.FromMilliseconds(380)) { EasingFunction = spring });
        panel.BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(150)));
    }

    /// <summary>The button went up: if nothing was dropped on a tile, put the Basket away.</summary>
    public void Released()
    {
        if (visible) hideTimer.Start();
    }

    void Hide(bool animate)
    {
        visible = false;
        if (!animate)
        {
            panel.Opacity = 0;
            Visibility = Visibility.Hidden;
            return;
        }
        var fade = new DoubleAnimation(0, TimeSpan.FromMilliseconds(160));
        fade.Completed += (_, _) => { if (!visible) Visibility = Visibility.Hidden; };
        panel.BeginAnimation(OpacityProperty, fade);
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(0.8, TimeSpan.FromMilliseconds(160)));
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(0.8, TimeSpan.FromMilliseconds(160)));
    }
}
