using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Isola.Services;

namespace Isola.Views;

/// <summary>The Media tab: one big player, or a card for each app when several are playing.</summary>
sealed class MediaView : ITabView
{
    readonly MediaService media;
    readonly Grid root = new();
    readonly DispatcherTimer clock = new() { Interval = TimeSpan.FromMilliseconds(500) };
    string layoutKey = "";
    Action? tick;

    public FrameworkElement Root => root;

    public MediaView(MediaService media)
    {
        this.media = media;
        media.Changed += () => Rebuild(false);
        clock.Tick += (_, _) => tick?.Invoke();
        Rebuild(true);
    }

    public void Shown() { Rebuild(true); clock.Start(); }
    public void Hidden() => clock.Stop();

    void Rebuild(bool force)
    {
        var players = media.Players;
        // Rebuild only when what is shown changes; positions update on the clock.
        var key = string.Join("\n", players.Select(p => $"{p.Id}|{p.Title}|{p.Artist}|{p.IsPlaying}|{p.Artwork?.GetHashCode()}"));
        if (!force && key == layoutKey) return;
        layoutKey = key;
        root.Children.Clear();
        tick = null;
        if (players.Count == 0) root.Children.Add(Empty());
        else if (players.Count == 1) root.Children.Add(Hero(players[0]));
        else root.Children.Add(Stack());
        tick?.Invoke();
    }

    static FrameworkElement Empty()
    {
        var stack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        stack.Children.Add(Ui.Glyph(Ui.Music, 28, Ui.White(0.8)));
        var title = Ui.Label("Nothing playing", 15, FontWeights.SemiBold, 0.85);
        title.HorizontalAlignment = HorizontalAlignment.Center;
        title.Margin = new Thickness(0, 8, 0, 2);
        stack.Children.Add(title);
        var detail = Ui.Label("Play music or a video in any app.", 12, FontWeights.Normal, 0.5);
        detail.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(detail);
        return stack;
    }

    FrameworkElement Hero(NowPlayer p)
    {
        var row = new Grid { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Stretch };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(300) });

        var art = Ui.Artwork(p.Artwork, 132, 20);
        art.Effect = Ui.Glow(p.Tint, 30, 0.55);
        art.VerticalAlignment = VerticalAlignment.Center;
        art.Margin = new Thickness(0, 0, 24, 0);
        art.RenderTransformOrigin = new Point(0.5, 0.5);
        art.RenderTransform = new ScaleTransform(p.IsPlaying ? 1 : 0.94, p.IsPlaying ? 1 : 0.94);
        row.Children.Add(art);

        var col = new DockPanel { LastChildFill = false };
        Grid.SetColumn(col, 1);
        row.Children.Add(col);

        var top = new StackPanel();
        top.Children.Add(SourceChip(p));
        top.Children.Add(Ui.Label(p.Title.Length > 0 ? p.Title : p.AppName, 20, FontWeights.Bold));
        if (p.Artist.Length > 0) top.Children.Add(Ui.Label(p.Artist, 14, FontWeights.Medium, 0.62));
        DockPanel.SetDock(top, Dock.Top);
        col.Children.Add(top);

        var bottom = new StackPanel();
        DockPanel.SetDock(bottom, Dock.Bottom);
        col.Children.Add(bottom);

        var scrub = new Scrubber(p);
        bottom.Children.Add(scrub);
        var times = new Grid { Margin = new Thickness(0, 2, 0, 0) };
        var now = Ui.Label("0:00", 10, FontWeights.Medium, 0.5);
        var left = Ui.Label("-0:00", 10, FontWeights.Medium, 0.5);
        left.HorizontalAlignment = HorizontalAlignment.Right;
        times.Children.Add(now);
        times.Children.Add(left);
        bottom.Children.Add(times);
        bottom.Children.Add(Controls(p, 17, 25, 30));

        tick = () =>
        {
            scrub.Update();
            now.Text = Format(scrub.DisplayPosition);
            left.Text = "-" + Format(Math.Max(p.Duration - scrub.DisplayPosition, 0));
        };
        return row;
    }

    FrameworkElement Stack()
    {
        var list = new StackPanel();
        Action? ticks = null;
        foreach (var p in media.Players)
        {
            var (card, update) = Card(p);
            list.Children.Add(card);
            ticks += update;
        }
        tick = ticks;
        return new ScrollViewer
        {
            Content = list,
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            PanningMode = PanningMode.VerticalOnly,
        };
    }

    (FrameworkElement, Action) Card(NowPlayer p)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var art = Ui.Artwork(p.Artwork, 52, 11);
        art.Effect = Ui.Glow(p.Tint, 16, 0.45);
        art.Margin = new Thickness(0, 0, 14, 0);
        grid.Children.Add(art);

        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(text, 1);
        var source = new StackPanel { Orientation = Orientation.Horizontal };
        if (p.AppIcon is not null) source.Children.Add(new Image { Source = p.AppIcon, Width = 11, Height = 11, Margin = new Thickness(0, 0, 5, 0) });
        source.Children.Add(Ui.Label(p.AppName, 10, FontWeights.SemiBold, 0.6));
        text.Children.Add(source);
        text.Children.Add(Ui.Label(p.Title.Length > 0 ? p.Title : p.AppName, 14, FontWeights.Bold));
        if (p.Artist.Length > 0) text.Children.Add(Ui.Label(p.Artist, 12, FontWeights.Medium, 0.6));
        grid.Children.Add(text);

        var controls = Controls(p, 12, 18, 14);
        controls.Margin = new Thickness(8, 0, 4, 0);
        Grid.SetColumn(controls, 2);
        grid.Children.Add(controls);

        var progress = new Border { Height = 2, CornerRadius = new CornerRadius(1), Background = new SolidColorBrush(p.Tint), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Bottom };
        var shell = new Grid();
        var card = new Border
        {
            Child = grid,
            Padding = new Thickness(10),
            CornerRadius = new CornerRadius(16),
            Background = Ui.White(0.07),
            Margin = new Thickness(0, 0, 0, 8),
            ClipToBounds = true,
        };
        Ui.Hover(card, Ui.White(0.07), Ui.White(0.11));
        shell.Children.Add(card);
        shell.Children.Add(progress);
        progress.Margin = new Thickness(12, 0, 12, 9);

        void Update()
        {
            var width = Math.Max(card.ActualWidth - 24, 0);
            progress.Width = p.Duration > 0 ? width * Math.Clamp(p.LivePosition / p.Duration, 0, 1) : 0;
        }
        return (shell, Update);
    }

    static StackPanel Controls(NowPlayer p, double side, double middle, double gap)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 0) };
        row.Children.Add(Control(Ui.Previous, side, p.Previous));
        var play = Control(p.IsPlaying ? Ui.Pause : Ui.Play, middle, p.TogglePlayPause);
        play.Margin = new Thickness(gap, 0, gap, 0);
        row.Children.Add(play);
        row.Children.Add(Control(Ui.Next, side, p.Next));
        return row;
    }

    static Border Control(string glyph, double size, Action action)
    {
        var b = new Border { Width = size + 16, Height = size + 10, Background = Brushes.Transparent, Cursor = Cursors.Hand, Child = Ui.Glyph(glyph, size) };
        b.MouseEnter += (_, _) => b.Opacity = 0.75;
        b.MouseLeave += (_, _) => b.Opacity = 1;
        b.MouseLeftButtonUp += (_, e) => { e.Handled = true; action(); };
        return b;
    }

    static FrameworkElement SourceChip(NowPlayer p)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        if (p.AppIcon is not null) row.Children.Add(new Image { Source = p.AppIcon, Width = 12, Height = 12, Margin = new Thickness(0, 0, 5, 0) });
        row.Children.Add(Ui.Label(p.AppName, 10, FontWeights.SemiBold, 0.7));
        return Ui.Capsule(new Border
        {
            Child = row,
            Background = Ui.White(0.12),
            Padding = new Thickness(7, 3, 7, 3),
            Margin = new Thickness(0, 0, 0, 6),
            HorizontalAlignment = HorizontalAlignment.Left,
        });
    }

    static string Format(double seconds)
    {
        var s = (int)Math.Max(seconds, 0);
        return $"{s / 60}:{s % 60:00}";
    }

    /// <summary>A progress bar you can drag to seek, thicker while dragging.</summary>
    sealed class Scrubber : Grid
    {
        readonly NowPlayer player;
        readonly Border track = new() { CornerRadius = new CornerRadius(3), Background = Ui.White(0.18), Height = 5 };
        readonly Border fill = new() { CornerRadius = new CornerRadius(3), Background = Brushes.White, Height = 5, HorizontalAlignment = HorizontalAlignment.Left };
        double? dragging;

        public double DisplayPosition => dragging is { } f ? f * player.Duration : player.LivePosition;

        public Scrubber(NowPlayer player)
        {
            this.player = player;
            Height = 16;
            Background = Brushes.Transparent;
            Cursor = player.CanSeek ? Cursors.Hand : Cursors.Arrow;
            Children.Add(track);
            Children.Add(fill);
            MouseLeftButtonDown += (_, e) =>
            {
                if (!player.CanSeek || player.Duration <= 0) return;
                CaptureMouse();
                Drag(e.GetPosition(this).X);
                e.Handled = true;
            };
            MouseMove += (_, e) => { if (dragging is not null) Drag(e.GetPosition(this).X); };
            MouseLeftButtonUp += (_, e) =>
            {
                if (dragging is not { } f) return;
                ReleaseMouseCapture();
                player.Seek(f * player.Duration);
                dragging = null;
                track.Height = fill.Height = 5;
                fill.Effect = null;
                Update();
            };
        }

        void Drag(double x)
        {
            dragging = Math.Clamp(x / Math.Max(ActualWidth, 1), 0, 1);
            track.Height = fill.Height = 8;
            fill.Effect = Ui.Glow(player.Tint, 8, 0.8);
            Update();
        }

        public void Update()
        {
            var f = player.Duration > 0 ? Math.Clamp(DisplayPosition / player.Duration, 0, 1) : 0;
            fill.Width = Math.Max(ActualWidth * f, 0);
        }
    }
}
