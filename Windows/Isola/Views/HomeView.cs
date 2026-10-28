using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using Isola.Services;
using NAudio.CoreAudioApi;

namespace Isola.Views;

/// <summary>A widget the Home tab can show: its name, icon and gallery colours.</summary>
sealed record HomeWidgetInfo(string Id, string Title, string Glyph, Color Top, Color Bottom, bool Wide = false, bool Separator = false)
{
    public double Width => Separator ? 28 : Wide ? 250 : 120;
}

/// <summary>Every widget there is. The pencil on the Home tab chooses which show, and in what order.</summary>
static class HomeWidgetCatalog
{
    static Color C(byte r, byte g, byte b) => Ui.Rgb(r, g, b);

    public static readonly HomeWidgetInfo[] All =
    {
        new("clock", "Clock", "", C(255, 158, 51), C(242, 102, 26)),
        new("analog", "Analog Clock", "", C(140, 140, 140), C(77, 77, 77)),
        new("world", "World Clock", "", C(77, 204, 217), C(26, 128, 179)),
        new("media", "Now Playing", Ui.Media, C(255, 77, 115), C(153, 64, 230), Wide: true),
        new("weather", "Weather", "", C(89, 179, 255), C(26, 102, 230)),
        new("battery", "Battery", Ui.Battery, C(77, 217, 102), C(26, 153, 77)),
        new("system", "System", Ui.Gauge, C(89, 230, 217), C(26, 153, 153)),
        new("network", "Network", "", C(77, 140, 255), C(51, 77, 217)),
        new("disk", "Storage", Ui.Drive, C(128, 128, 242), C(77, 64, 191)),
        new("uptime", "Uptime", "", C(115, 204, 128), C(51, 128, 89)),
        new("date", "Today", "", C(255, 89, 77), C(204, 26, 38)),
        new("month", "Month", Ui.Calendar, C(255, 128, 89), C(230, 64, 51)),
        new("progress", "Progress", "", C(191, 115, 255), C(128, 51, 217)),
        new("timer", "Timer", "", C(255, 179, 51), C(255, 115, 26)),
        new("focus", "Focus", "", C(255, 89, 77), C(217, 51, 89)),
        new("stopwatch", "Stopwatch", Ui.Stopwatch, C(255, 204, 64), C(242, 140, 26)),
        new("clipboard", "Clipboard", Ui.Paste, C(77, 191, 191), C(38, 128, 140)),
        new("tray", "File Tray", Ui.Folder, C(89, 166, 255), C(38, 115, 242)),
        new("shortcuts", "Shortcuts", "", C(115, 115, 255), C(191, 77, 230)),
        new("awake", "Keep Awake", Ui.Brightness, C(255, 217, 77), C(230, 153, 26)),
        new("moon", "Moon", "", C(77, 77, 153), C(26, 26, 77)),
        new("dice", "Dice", "", C(89, 217, 140), C(26, 140, 102)),
        new("counter", "Counter", "", C(255, 115, 179), C(217, 51, 128)),
        new("colors", "Color Picker", "\uEF3C", C(255, 153, 51), C(140, 77, 242)),
        new("mixer", "Volume Mixer", Ui.Volume, C(255, 128, 64), C(204, 51, 102), Wide: true),
    };

    /// <summary>A thin line between widgets. There can be any number, each placed one numbered: separator-1, -2 and so on.</summary>
    public static readonly HomeWidgetInfo SeparatorInfo = new("separator", "Separator", "", C(140, 140, 140), C(82, 82, 82), Separator: true);

    public static HomeWidgetInfo? Find(string id) => All.FirstOrDefault(w => w.Id == id);

    public static bool IsSeparator(string id) =>
        id.StartsWith("separator-", StringComparison.Ordinal) && int.TryParse(id.AsSpan("separator-".Length), out _);

    /// <summary>What a placed id is: one of the widgets, or a separator.</summary>
    public static HomeWidgetInfo? Info(string id) => IsSeparator(id) ? SeparatorInfo : Find(id);

    /// <summary>A separator numbered after every one in the list.</summary>
    public static string NewSeparator(IEnumerable<string> ids) =>
        "separator-" + (ids.Where(IsSeparator).Select(id => int.Parse(id.AsSpan("separator-".Length))).DefaultIfEmpty(0).Max() + 1);

    /// <summary>The chosen widgets and separators, known ones only, each once.</summary>
    public static List<string> Current =>
        (Settings.Current.HomeWidgets ?? new List<string>()).Where(id => Info(id) is not null).Distinct().ToList();

    /// <summary>A widget's icon: a rounded square in its colours, like an app icon.</summary>
    public static Border Icon(HomeWidgetInfo info, double size) => new()
    {
        Width = size, Height = size, CornerRadius = new CornerRadius(size * 0.27),
        Background = new LinearGradientBrush(info.Top, info.Bottom, 90),
        BorderBrush = Ui.White(0.2), BorderThickness = new Thickness(0.5),
        Child = info.Separator
            ? new Rectangle { Width = Math.Max(size * 0.07, 1.5), Height = size * 0.5, RadiusX = 1, RadiusY = 1, Fill = Brushes.White }
            : Ui.Glyph(info.Glyph, size * 0.44),
    };
}

/// <summary>
/// The Home tab: a row of live widgets. The pencil turns on arranging, Droppy-style: the widgets shrink, get dashed
/// outlines and drag into a new order, and a gallery of every widget slides up to drag (or click) more in.
/// </summary>
sealed class HomeView : ITabView
{
    const double GalleryHeight = 64, GalleryGap = 8, EditInset = 10;

    readonly MediaService media;
    readonly ClipboardService clipboard;
    readonly SystemStats stats;
    readonly FileTray tray;
    readonly Action<IslandTab> openTab;

    readonly Grid root = new() { Background = Brushes.Transparent };
    readonly RowDefinition galleryRow = new() { Height = new GridLength(0) };
    readonly Grid rowHost = new();
    readonly StackPanel row = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
    readonly ScaleTransform rowScale = new(1, 1);
    readonly ScrollViewer rowScroll;
    readonly FrameworkElement emptyHint, dropHint;
    readonly Border gallery;
    readonly Dictionary<string, (Border badge, TextBlock label)> tiles = new();
    readonly Canvas overlay = new() { IsHitTestVisible = false };
    readonly DispatcherTimer ticker = new() { Interval = TimeSpan.FromMilliseconds(200) };
    readonly Dictionary<string, Slot> slots = new();

    List<string> working;
    List<string> snapshot = new();
    bool shown;
    double morph;
    EventHandler? morphTick;

    // The widget being pressed or dragged.
    string? pressId;
    bool pressFromGallery, dragging, dragWasPlaced;
    Point pressAt;
    FrameworkElement? ghost;

    public FrameworkElement Root => root;
    public bool Editing { get; private set; }
    public event Action<bool>? EditingChanged;

    public HomeView(MediaService media, ClipboardService clipboard, SystemStats stats, FileTray tray, Action<IslandTab> openTab)
    {
        this.media = media;
        this.clipboard = clipboard;
        this.stats = stats;
        this.tray = tray;
        this.openTab = openTab;

        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(galleryRow);

        row.LayoutTransform = rowScale;
        rowScroll = HorizontalScroller(row);
        rowHost.Children.Add(rowScroll);
        emptyHint = Hint(Ui.Tiles, "No widgets", "Click the pencil to add some.");
        dropHint = new Grid
        {
            Margin = new Thickness(EditInset),
            Children =
            {
                new Rectangle { RadiusX = 16, RadiusY = 16, Stroke = Ui.White(0.35), StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 4, 3 } },
                Centered(Ui.Label("Drag widgets here", 12, FontWeights.SemiBold, 0.6)),
            },
        };
        ((TextBlock)((Grid)dropHint).Children[1]).VerticalAlignment = VerticalAlignment.Center;
        rowHost.Children.Add(emptyHint);
        rowHost.Children.Add(dropHint);
        root.Children.Add(rowHost);

        gallery = BuildGallery();
        Grid.SetRow(gallery, 1);
        root.Children.Add(gallery);

        Grid.SetRowSpan(overlay, 2);
        root.Children.Add(overlay);

        root.MouseMove += (_, e) => PointerMoved(e.GetPosition(root));
        root.MouseLeftButtonUp += (_, e) => PointerReleased(e.GetPosition(root));
        root.LostMouseCapture += (_, _) => { if (pressId is not null) PointerReleased(Mouse.GetPosition(root)); };
        root.SizeChanged += (_, _) => SetMorph(morph);

        ticker.Tick += (_, _) => Each(w => w.Tick());
        stats.Changed += () => { if (shown) Each(w => w.StatsChanged()); };
        media.Changed += () => Each(w => w.MediaChanged());
        clipboard.Changed += () => Each(w => w.ClipboardChanged());
        tray.Changed += () => Each(w => w.TrayChanged());
        WeatherService.Changed += () => Each(w => w.WeatherChanged());

        working = HomeWidgetCatalog.Current;
        SyncRow();
        SetMorph(0);
    }

    void Each(Action<Widget> action)
    {
        foreach (var slot in slots.Values) action(slot.Widget);
    }

    public void Shown()
    {
        if (shown) return;
        shown = true;
        stats.Start();
        Each(w => w.Refresh());
        ticker.Start();
    }

    public void Hidden()
    {
        if (!shown) return;
        shown = false;
        if (pressId is not null) PointerReleased(Mouse.GetPosition(root));
        SetEditing(false);
        stats.Stop();
        ticker.Stop();
    }

    // MARK: The row

    /// <summary>Makes the row's slots match the working list, keeping the widgets that stay (and their state).</summary>
    void SyncRow()
    {
        // A widget still fading out goes at once, and is made afresh if it was put back.
        foreach (var id in slots.Keys.Where(id => !working.Contains(id) || slots[id].Leaving).ToList())
        {
            row.Children.Remove(slots[id].Root);
            slots.Remove(id);
        }
        for (var i = 0; i < working.Count; i++)
        {
            var id = working[i];
            if (!slots.TryGetValue(id, out var slot))
            {
                slot = CreateSlot(id);
                slots[id] = slot;
            }
            var at = row.Children.IndexOf(slot.Root);
            if (at == i) continue;
            if (at >= 0) row.Children.RemoveAt(at);
            row.Children.Insert(i, slot.Root);
        }
        SyncHints();
    }

    /// <summary>The empty row's hints and the gallery's ticks.</summary>
    void SyncHints()
    {
        emptyHint.Visibility = working.Count == 0 && !Editing ? Visibility.Visible : Visibility.Collapsed;
        dropHint.Visibility = working.Count == 0 && Editing ? Visibility.Visible : Visibility.Collapsed;
        foreach (var (id, (badge, label)) in tiles)
        {
            var added = working.Contains(id);
            badge.Visibility = added ? Visibility.Visible : Visibility.Collapsed;
            label.Opacity = added ? 0.5 : 0.85;
        }
    }

    Slot CreateSlot(string id)
    {
        var info = HomeWidgetCatalog.Info(id)!;
        Widget widget = info.Separator ? new SeparatorWidget() : id switch
        {
            "clock" => new ClockWidget(),
            "analog" => new AnalogClockWidget(),
            "world" => new WorldClockWidget(),
            "media" => new MediaWidget(media),
            "weather" => new WeatherWidget(),
            "battery" => new BatteryWidget(stats),
            "system" => new SystemWidget(stats),
            "network" => new NetworkWidget(stats),
            "disk" => new DiskWidget(stats),
            "uptime" => new UptimeWidget(),
            "date" => new DateWidget(),
            "month" => new MonthWidget(),
            "progress" => new ProgressWidget(),
            "timer" => new TimerWidget(),
            "focus" => new FocusWidget(),
            "stopwatch" => new StopwatchWidget(),
            "clipboard" => new ClipboardWidget(clipboard),
            "tray" => new TrayWidget(tray, () => openTab(IslandTab.Tray)),
            "shortcuts" => new ShortcutsWidget(),
            "awake" => new AwakeWidget(),
            "moon" => new MoonWidget(),
            "dice" => new DiceWidget(),
            "colors" => new ColorPickerWidget(),
            "mixer" => new MixerWidget(),
            _ => new CounterWidget(),
        };
        var slot = new Slot(info, widget, () => Remove(id));
        slot.SetEditing(Editing);
        slot.Root.PreviewMouseLeftButtonDown += (_, e) =>
        {
            if (!Editing || slot.OverBadge) return;
            Press(id, false, e.GetPosition(root));
            e.Handled = true;
        };
        widget.Refresh();
        return slot;
    }

    void Remove(string id)
    {
        working.Remove(id);
        Commit();
        Leave(id);
    }

    void Toggle(string id)
    {
        // The gallery's separator adds a new one each time.
        if (id == HomeWidgetCatalog.SeparatorInfo.Id) id = HomeWidgetCatalog.NewSeparator(working);
        if (working.Contains(id))
        {
            Remove(id);
            return;
        }
        working.Add(id);
        SyncRow();
        Commit();
        slots[id].Root.BringIntoView();
    }

    /// <summary>Fades a removed widget out while the ones beside it close in on its space, then takes it out.</summary>
    void Leave(string id)
    {
        if (!slots.TryGetValue(id, out var slot) || !slot.Root.IsVisible)
        {
            SyncRow();
            return;
        }
        slot.Leave(() =>
        {
            if (!slots.TryGetValue(id, out var current) || current != slot) return;
            row.Children.Remove(slot.Root);
            slots.Remove(id);
        });
        SyncHints();
    }

    void Commit()
    {
        Settings.Current.HomeWidgets = working.ToList();
        Settings.SaveQuietly();
    }

    // MARK: Editing

    public void ToggleEditing() => SetEditing(!Editing);

    void SetEditing(bool on)
    {
        if (Editing == on) return;
        Editing = on;
        if (on) snapshot = working.ToList();
        foreach (var slot in slots.Values) slot.SetEditing(on);
        SyncRow();
        AnimateMorph(on ? 1 : 0);
        EditingChanged?.Invoke(on);
    }

    void Cancel()
    {
        working = snapshot.ToList();
        SyncRow();
        Commit();
        SetEditing(false);
    }

    void AnimateMorph(double to)
    {
        if (morphTick is not null) CompositionTarget.Rendering -= morphTick;
        var from = morph;
        var start = DateTime.UtcNow;
        morphTick = (_, _) =>
        {
            var t = Math.Min((DateTime.UtcNow - start).TotalMilliseconds / 300, 1);
            SetMorph(from + (to - from) * (1 - Math.Pow(1 - t, 3)));
            if (t >= 1 && morphTick is not null)
            {
                CompositionTarget.Rendering -= morphTick;
                morphTick = null;
            }
        };
        CompositionTarget.Rendering += morphTick;
    }

    /// <summary>
    /// Between the plain row (0) and arranging (1): the gallery's room grows while the row shrinks by the same amount,
    /// so each widget keeps its full-size layout, only scaled down.
    /// </summary>
    void SetMorph(double m)
    {
        morph = m;
        var full = root.ActualHeight;
        var room = (GalleryHeight + GalleryGap) * m;
        var inset = EditInset * m;
        galleryRow.Height = new GridLength(room);
        row.Margin = new Thickness(inset);
        var scale = full > 0 ? Math.Clamp((full - room - inset * 2) / full, 0.2, 1) : 1;
        rowScale.ScaleX = rowScale.ScaleY = scale;
        gallery.Opacity = m;
        gallery.Visibility = m > 0.001 ? Visibility.Visible : Visibility.Collapsed;
    }

    Border BuildGallery()
    {
        var strip = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(8, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
        foreach (var info in HomeWidgetCatalog.All.Append(HomeWidgetCatalog.SeparatorInfo))
        {
            var icon = HomeWidgetCatalog.Icon(info, 32);
            var badge = new Border
            {
                Width = 14, Height = 14, CornerRadius = new CornerRadius(7), Background = Ui.Brush(Ui.Blue),
                BorderBrush = Brushes.White, BorderThickness = new Thickness(1.2),
                Child = Ui.Glyph(Ui.Check, 7), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(0, -5, -5, 0), Visibility = Visibility.Collapsed,
            };
            var iconHost = new Grid { Width = 32, Height = 32, Children = { icon, badge } };
            var label = Centered(Ui.Label(info.Title, 8.5, FontWeights.Medium, 0.85));
            label.Width = 56;
            label.Margin = new Thickness(0, 4, 0, 0);
            var tile = new StackPanel { Width = 56, Background = Brushes.Transparent, Cursor = Cursors.Hand, Children = { iconHost, label } };
            tile.ToolTip = info.Separator
                ? "Separator: click to add one, or drag one into place"
                : $"{info.Title}: click to add or remove, or drag into place";
            var scale = new ScaleTransform(1, 1, 16, 16);
            iconHost.RenderTransform = scale;
            tile.MouseEnter += (_, _) => { scale.ScaleX = scale.ScaleY = 1.08; };
            tile.MouseLeave += (_, _) => { scale.ScaleX = scale.ScaleY = 1; };
            tile.MouseLeftButtonDown += (_, e) =>
            {
                Press(info.Id, true, e.GetPosition(root));
                e.Handled = true;
            };
            strip.Children.Add(tile);
            tiles[info.Id] = (badge, label);
        }

        var cancel = Ui.Round(Ui.Close, 30, Cancel);
        cancel.ToolTip = "Cancel";
        var done = new Border
        {
            Width = 30, Height = 30, CornerRadius = new CornerRadius(15), Background = Ui.Brush(Ui.Blue), Cursor = Cursors.Hand,
            Child = Ui.Glyph(Ui.Check, 12), Margin = new Thickness(8, 0, 0, 0), ToolTip = "Done",
            Effect = Ui.Glow(Ui.Blue, 10, 0.5),
        };
        Ui.Hover(done, Ui.Brush(Ui.Blue), Ui.Brush(Ui.Rgb(64, 156, 255)));
        done.MouseLeftButtonUp += (_, e) => { e.Handled = true; SetEditing(false); };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 12, 0), Children = { cancel, done } };
        var dock = new DockPanel();
        DockPanel.SetDock(buttons, Dock.Right);
        dock.Children.Add(buttons);
        dock.Children.Add(HorizontalScroller(strip));
        return new Border
        {
            Child = dock, Height = GalleryHeight, VerticalAlignment = VerticalAlignment.Bottom, CornerRadius = new CornerRadius(18),
            Background = Ui.White(0.06), BorderBrush = Ui.White(0.08), BorderThickness = new Thickness(0.5),
        };
    }

    // MARK: Dragging

    void Press(string id, bool fromGallery, Point at)
    {
        pressId = id;
        pressFromGallery = fromGallery;
        pressAt = at;
        dragging = false;
        root.CaptureMouse();
    }

    void PointerMoved(Point p)
    {
        if (pressId is null) return;
        if (!dragging)
        {
            if (Math.Abs(p.X - pressAt.X) + Math.Abs(p.Y - pressAt.Y) < 5) return;
            dragging = true;
            // A separator dragged from the gallery is a new one.
            if (pressFromGallery && pressId == HomeWidgetCatalog.SeparatorInfo.Id) pressId = HomeWidgetCatalog.NewSeparator(working);
            dragWasPlaced = working.Contains(pressId);
            ghost = HomeWidgetCatalog.Icon(HomeWidgetCatalog.Info(pressId)!, 46);
            ghost.Effect = new DropShadowEffect { BlurRadius = 14, ShadowDepth = 4, Direction = 270, Opacity = 0.5 };
            overlay.Children.Add(ghost);
            if (slots.TryGetValue(pressId, out var lifted)) lifted.SetLifted(true);
        }
        Canvas.SetLeft(ghost, p.X - 23);
        Canvas.SetTop(ghost, p.Y - 23);
        Place(pressId, p);
    }

    /// <summary>
    /// Puts the dragged widget where the pointer is in the row. One brought from the gallery leaves again if the pointer
    /// goes back down; one that was already placed keeps its spot until it is dropped.
    /// </summary>
    void Place(string id, Point p)
    {
        var next = working.Where(x => x != id).ToList();
        if (p.Y <= rowHost.ActualHeight + 4)
        {
            var index = next.Count(x => slots.TryGetValue(x, out var s) && CenterX(s) < p.X);
            next.Insert(index, id);
        }
        else if (dragWasPlaced) return;
        if (next.SequenceEqual(working)) return;
        working = next;
        SyncRow();
        if (slots.TryGetValue(id, out var slot)) slot.SetLifted(true);
    }

    double CenterX(Slot slot) => slot.Root.TranslatePoint(new Point(slot.Root.ActualWidth / 2, 0), root).X;

    void PointerReleased(Point p)
    {
        if (pressId is not { } id) return;
        pressId = null;
        if (root.IsMouseCaptured) root.ReleaseMouseCapture();
        if (!dragging)
        {
            if (pressFromGallery) Toggle(id);
            return;
        }
        dragging = false;
        if (ghost is not null) overlay.Children.Remove(ghost);
        ghost = null;
        if (slots.TryGetValue(id, out var slot)) slot.SetLifted(false);
        // A placed widget dropped back on the gallery comes off the Home tab.
        if (!pressFromGallery && p.Y > rowHost.ActualHeight + 4)
        {
            Remove(id);
            return;
        }
        SyncRow();
        Commit();
    }

    // MARK: Building blocks

    static ScrollViewer HorizontalScroller(FrameworkElement content)
    {
        var scroll = new ScrollViewer
        {
            Content = content,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            PanningMode = PanningMode.HorizontalOnly,
        };
        scroll.PreviewMouseWheel += (_, e) =>
        {
            if (scroll.ScrollableWidth <= 0) return;
            scroll.ScrollToHorizontalOffset(scroll.HorizontalOffset - e.Delta);
            e.Handled = true;
        };
        return scroll;
    }

    static FrameworkElement Hint(string glyph, string title, string detail)
    {
        var panel = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        panel.Children.Add(Ui.Glyph(glyph, 26, Ui.White(0.8)));
        var heading = Centered(Ui.Label(title, 14, FontWeights.SemiBold, 0.85));
        heading.Margin = new Thickness(0, 6, 0, 2);
        panel.Children.Add(heading);
        panel.Children.Add(Centered(Ui.Label(detail, 11, FontWeights.Normal, 0.5)));
        return panel;
    }

    static TextBlock Centered(TextBlock t)
    {
        t.HorizontalAlignment = HorizontalAlignment.Center;
        t.TextAlignment = TextAlignment.Center;
        return t;
    }

    static TextBlock Link(string text, Action click)
    {
        var link = Centered(Ui.Label(text, 10, FontWeights.SemiBold));
        link.Foreground = Ui.Brush(Ui.Rgb(64, 156, 255));
        link.Cursor = Cursors.Hand;
        link.MouseLeftButtonUp += (_, e) => { e.Handled = true; click(); };
        return link;
    }

    /// <summary>A round button tinted with its colour.</summary>
    static Border Tinted(string glyph, Color color, Action click, double size = 30)
    {
        var normal = Ui.Brush(Ui.Rgb(color.R, color.G, color.B, 46));
        var b = new Border
        {
            Width = size, Height = size, CornerRadius = new CornerRadius(size / 2), Background = normal, Cursor = Cursors.Hand,
            Child = Ui.Glyph(glyph, size * 0.36, Ui.Brush(color)),
        };
        Ui.Hover(b, normal, Ui.Brush(Ui.Rgb(color.R, color.G, color.B, 90)));
        b.MouseLeftButtonUp += (_, e) => { e.Handled = true; click(); };
        return b;
    }

    static StackPanel Buttons(params FrameworkElement[] buttons)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) };
        for (var i = 0; i < buttons.Length; i++)
        {
            buttons[i].Margin = new Thickness(i > 0 ? 8 : 0, 0, 0, 0);
            panel.Children.Add(buttons[i]);
        }
        return panel;
    }

    /// <summary>One widget in the row: its card, and while arranging a dashed outline and a remove badge.</summary>
    sealed class Slot
    {
        public readonly Widget Widget;
        public readonly Grid Root = new() { Background = Brushes.Transparent, Margin = new Thickness(5, 0, 5, 0) };
        readonly Border card, placeholder, badge;
        readonly Rectangle dash;
        bool editing, lifted;

        public bool OverBadge => badge.IsMouseOver;
        public bool Leaving { get; private set; }

        public Slot(HomeWidgetInfo info, Widget widget, Action remove)
        {
            Widget = widget;
            Root.Width = info.Width;

            if (info.Separator)
            {
                // Just the line: no card behind it.
                card = new Border { Child = widget.Root, Background = Brushes.Transparent };
            }
            else
            {
                var header = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 8) };
                header.Children.Add(Ui.Glyph(info.Glyph, 10, Ui.White(0.55)));
                var name = Ui.Label(info.Title.ToUpperInvariant(), 9.5, FontWeights.SemiBold, 0.55);
                name.Margin = new Thickness(5, 0, 0, 0);
                name.VerticalAlignment = VerticalAlignment.Center;
                header.Children.Add(name);
                var dock = new DockPanel();
                DockPanel.SetDock(header, Dock.Top);
                dock.Children.Add(header);
                dock.Children.Add(widget.Root);
                card = new Border
                {
                    Child = dock, Padding = new Thickness(12), CornerRadius = new CornerRadius(18), ClipToBounds = true,
                    Background = Ui.White(0.07), BorderBrush = Ui.White(0.06), BorderThickness = new Thickness(0.5),
                };
            }
            var ghostIcon = HomeWidgetCatalog.Icon(info, info.Separator ? 20 : 56);
            ghostIcon.Opacity = 0.45;
            placeholder = new Border { CornerRadius = new CornerRadius(18), Background = Ui.White(0.05), Child = ghostIcon, Visibility = Visibility.Collapsed };
            dash = new Rectangle
            {
                RadiusX = 18, RadiusY = 18, Stroke = Ui.White(0.5), StrokeThickness = 1.6, StrokeDashArray = new DoubleCollection { 4, 3 },
                IsHitTestVisible = false, Visibility = Visibility.Collapsed,
            };
            badge = new Border
            {
                Width = 28, Height = 28, CornerRadius = new CornerRadius(14), Background = Brushes.White, Cursor = Cursors.Hand,
                Child = Ui.Glyph(Ui.Minus, 12, Brushes.Black), HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(-9, -9, 0, 0), Visibility = Visibility.Collapsed,
                Effect = new DropShadowEffect { BlurRadius = 6, ShadowDepth = 1, Opacity = 0.4, Direction = 270 }, ToolTip = "Remove",
            };
            badge.MouseLeftButtonDown += (_, e) => e.Handled = true;
            badge.MouseLeftButtonUp += (_, e) => { e.Handled = true; remove(); };
            Root.Children.Add(card);
            Root.Children.Add(placeholder);
            Root.Children.Add(dash);
            Root.Children.Add(badge);
        }

        public void SetEditing(bool on)
        {
            editing = on;
            Update();
        }

        /// <summary>Fades out and narrows to nothing, its card keeping its width so it does not squash, then calls
        /// done.</summary>
        public void Leave(Action done)
        {
            Leaving = true;
            Root.IsHitTestVisible = false;
            badge.Visibility = Visibility.Collapsed;
            foreach (var part in new FrameworkElement[] { card, placeholder, dash })
            {
                part.Width = Root.Width;
                part.HorizontalAlignment = HorizontalAlignment.Center;
            }
            Root.ClipToBounds = true;
            var ease = new CubicEase { EasingMode = EasingMode.EaseInOut };
            var time = TimeSpan.FromMilliseconds(300);
            var narrow = new DoubleAnimation(Root.Width, 0, time) { EasingFunction = ease };
            narrow.Completed += (_, _) => done();
            Root.BeginAnimation(FrameworkElement.WidthProperty, narrow);
            Root.BeginAnimation(FrameworkElement.MarginProperty, new ThicknessAnimation(new Thickness(0), time) { EasingFunction = ease });
            Root.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(220)));
        }

        public void SetLifted(bool on)
        {
            lifted = on;
            Update();
        }

        void Update()
        {
            card.IsHitTestVisible = !editing;
            card.Opacity = lifted ? 0 : 1;
            placeholder.Visibility = lifted ? Visibility.Visible : Visibility.Collapsed;
            dash.Visibility = editing ? Visibility.Visible : Visibility.Collapsed;
            dash.Stroke = Ui.White(lifted ? 0.75 : 0.5);
            badge.Visibility = editing && !lifted ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    // MARK: Widgets

    /// <summary>A thin upright line between widgets.</summary>
    sealed class SeparatorWidget : Widget
    {
        public override FrameworkElement Root { get; } = new Border
        {
            Width = 1.5, CornerRadius = new CornerRadius(0.75), Background = Ui.White(0.18),
            HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 22, 0, 22),
        };
    }

    abstract class Widget
    {
        public abstract FrameworkElement Root { get; }
        public virtual void Refresh() { }
        public virtual void Tick() { }
        public virtual void StatsChanged() { }
        public virtual void MediaChanged() { }
        public virtual void ClipboardChanged() { }
        public virtual void TrayChanged() { }
        public virtual void WeatherChanged() { }
    }

    /// <summary>A thin capsule bar that fills to a fraction.</summary>
    sealed class Bar : Grid
    {
        readonly Border fill;
        double fraction;

        public Bar(Brush brush, double height = 4)
        {
            Height = height;
            SizeChanged += (_, _) => Set(fraction);
            Children.Add(new Border { Background = Ui.White(0.14), CornerRadius = new CornerRadius(height / 2) });
            fill = new Border { Background = brush, CornerRadius = new CornerRadius(height / 2), HorizontalAlignment = HorizontalAlignment.Left, Width = 0 };
            Children.Add(fill);
        }

        public void Set(double value)
        {
            fraction = Math.Clamp(value, 0, 1);
            fill.Width = Math.Max(ActualWidth, 0) * fraction;
        }
    }

    /// <summary>A ring that fills clockwise, with something in the middle.</summary>
    sealed class Ring : Grid
    {
        readonly double size, line;
        readonly Path arc;

        public Ring(double size, double line)
        {
            this.size = size;
            this.line = line;
            Width = Height = size;
            HorizontalAlignment = HorizontalAlignment.Center;
            Children.Add(new Ellipse { Stroke = Ui.White(0.12), StrokeThickness = line });
            arc = new Path { StrokeThickness = line, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
            Children.Add(arc);
        }

        public void Set(double value, Color a, Color b)
        {
            arc.Stroke = new LinearGradientBrush(a, b, 45);
            arc.Effect = Ui.Glow(a, 10, 0.5);
            if (value >= 0.9999)
            {
                arc.Data = new EllipseGeometry(new Point(size / 2, size / 2), (size - line) / 2, (size - line) / 2);
                return;
            }
            value = Math.Clamp(value, 0.001, 0.9999);
            double r = (size - line) / 2, c = size / 2, angle = value * 2 * Math.PI;
            var figure = new PathFigure { StartPoint = new Point(c, c - r) };
            figure.Segments.Add(new ArcSegment(new Point(c + r * Math.Sin(angle), c - r * Math.Cos(angle)), new Size(r, r), 0, value > 0.5, SweepDirection.Clockwise, true));
            arc.Data = new PathGeometry(new[] { figure });
        }
    }

    /// <summary>A small line graph of recent values, from 0 to 1, with a soft fill under it.</summary>
    sealed class Sparkline : Grid
    {
        readonly Path line = new() { StrokeThickness = 1.6, StrokeLineJoin = PenLineJoin.Round };
        readonly Path area = new();
        IReadOnlyList<double> values = Array.Empty<double>();

        public Sparkline(Color color, double height)
        {
            Height = height;
            line.Stroke = Ui.Brush(color);
            area.Fill = new LinearGradientBrush(Ui.Rgb(color.R, color.G, color.B, 90), Ui.Rgb(color.R, color.G, color.B, 0), 90);
            Children.Add(area);
            Children.Add(line);
            SizeChanged += (_, _) => Set(values);
        }

        public void Set(IReadOnlyList<double> next)
        {
            values = next;
            double w = ActualWidth, h = Height;
            if (values.Count < 2 || w <= 0)
            {
                line.Data = area.Data = null;
                return;
            }
            var step = w / 39;
            var x0 = w - step * (values.Count - 1);
            var points = values.Select((v, i) => new Point(x0 + i * step, h - Math.Clamp(v, 0, 1) * (h - 2) - 1)).ToList();
            var stroke = new PathFigure { StartPoint = points[0] };
            stroke.Segments.Add(new PolyLineSegment(points.Skip(1), true));
            line.Data = new PathGeometry(new[] { stroke });
            var fill = new PathFigure { StartPoint = new Point(points[0].X, h), IsClosed = true };
            fill.Segments.Add(new PolyLineSegment(points.Append(new Point(points[^1].X, h)), false));
            area.Data = new PathGeometry(new[] { fill });
        }
    }

    // Time

    sealed class ClockWidget : Widget
    {
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly TextBlock time = Centered(Ui.Label("", 30, FontWeights.SemiBold, 1, Ui.Display));
        readonly TextBlock weekday = Centered(Ui.Label("", 12, FontWeights.SemiBold, 0.9));
        readonly TextBlock date = Centered(Ui.Label("", 11, FontWeights.Normal, 0.55));
        readonly Bar seconds = new(Ui.Brush(Ui.Orange), 3);

        public override FrameworkElement Root => root;

        public ClockWidget()
        {
            root.Children.Add(time);
            weekday.Margin = new Thickness(0, 2, 0, 0);
            root.Children.Add(weekday);
            root.Children.Add(date);
            seconds.Margin = new Thickness(6, 12, 6, 0);
            root.Children.Add(seconds);
        }

        public override void Refresh() => Tick();

        public override void Tick()
        {
            var now = DateTime.Now;
            time.Text = now.ToString(CultureInfo.CurrentCulture.DateTimeFormat.ShortTimePattern.Replace("tt", "").Trim());
            weekday.Text = now.ToString("dddd");
            date.Text = now.ToString("MMMM d");
            seconds.Set((now.Second + now.Millisecond / 1000.0) / 60);
        }
    }

    sealed class AnalogClockWidget : Widget
    {
        const double Size = 80, R = Size / 2;
        readonly Grid root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly RotateTransform hour, minute, second;

        public override FrameworkElement Root => root;

        public AnalogClockWidget()
        {
            var face = new Canvas { Width = Size, Height = Size, HorizontalAlignment = HorizontalAlignment.Center };
            face.Children.Add(new Ellipse { Width = Size, Height = Size, Fill = Ui.White(0.08), Stroke = Ui.White(0.15), StrokeThickness = 1 });
            for (var i = 0; i < 12; i++)
            {
                var major = i % 3 == 0;
                double w = major ? 2 : 1.2, h = major ? 6 : 3.5;
                var tick = new Rectangle { Width = w, Height = h, RadiusX = w / 2, RadiusY = w / 2, Fill = Ui.White(major ? 0.9 : 0.35) };
                Canvas.SetLeft(tick, R - w / 2);
                Canvas.SetTop(tick, 3);
                tick.RenderTransform = new RotateTransform(i * 30, w / 2, R - 3);
                face.Children.Add(tick);
            }
            hour = Hand(face, 3, R * 0.5, Brushes.White);
            minute = Hand(face, 2, R * 0.74, Brushes.White);
            second = Hand(face, 1, R * 0.84, Ui.Brush(Ui.Orange));
            var pin = new Ellipse { Width = 5, Height = 5, Fill = Ui.Brush(Ui.Orange) };
            Canvas.SetLeft(pin, R - 2.5);
            Canvas.SetTop(pin, R - 2.5);
            face.Children.Add(pin);
            root.Children.Add(face);
        }

        static RotateTransform Hand(Canvas face, double width, double length, Brush brush)
        {
            var hand = new Rectangle { Width = width, Height = length, RadiusX = width / 2, RadiusY = width / 2, Fill = brush };
            Canvas.SetLeft(hand, R - width / 2);
            Canvas.SetTop(hand, R - length);
            var rotate = new RotateTransform(0, width / 2, length);
            hand.RenderTransform = rotate;
            face.Children.Add(hand);
            return rotate;
        }

        public override void Refresh() => Tick();

        public override void Tick()
        {
            var now = DateTime.Now;
            double s = now.Second, m = now.Minute + s / 60, h = now.Hour % 12 + m / 60;
            second.Angle = s * 6;
            minute.Angle = m * 6;
            hour.Angle = h * 30;
        }
    }

    sealed class WorldClockWidget : Widget
    {
        static readonly (string Name, string Iana, string Windows)[] Cities =
        {
            ("New York", "America/New_York", "Eastern Standard Time"),
            ("London", "Europe/London", "GMT Standard Time"),
            ("Tokyo", "Asia/Tokyo", "Tokyo Standard Time"),
            ("Sydney", "Australia/Sydney", "AUS Eastern Standard Time"),
        };

        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly List<(TimeZoneInfo zone, TextBlock time, TextBlock offset)> rows = new();
        int minute = -1;

        public override FrameworkElement Root => root;

        public WorldClockWidget()
        {
            var local = TimeZoneInfo.Local.Id;
            TimeZoneInfo.TryConvertWindowsIdToIanaId(local, out var localIana);
            foreach (var (name, iana, windows) in Cities)
            {
                if (rows.Count == 3 || local == windows || local == iana || localIana == iana) continue;
                if (Find(iana, windows) is not { } zone) continue;
                var head = new DockPanel { Margin = new Thickness(0, rows.Count > 0 ? 6 : 0, 0, 0) };
                var offset = Ui.Label("", 8.5, FontWeights.Medium, 0.4);
                DockPanel.SetDock(offset, Dock.Right);
                head.Children.Add(offset);
                head.Children.Add(Ui.Label(name, 9.5, FontWeights.SemiBold, 0.55));
                root.Children.Add(head);
                var time = Ui.Label("", 15, FontWeights.Bold, 1, Ui.Display);
                root.Children.Add(time);
                rows.Add((zone, time, offset));
            }
        }

        static TimeZoneInfo? Find(string iana, string windows)
        {
            try { return TimeZoneInfo.FindSystemTimeZoneById(iana); } catch { }
            try { return TimeZoneInfo.FindSystemTimeZoneById(windows); } catch { }
            return null;
        }

        public override void Refresh()
        {
            minute = -1;
            Tick();
        }

        public override void Tick()
        {
            var now = DateTime.UtcNow;
            if (now.Minute == minute) return;
            minute = now.Minute;
            foreach (var (zone, time, offset) in rows)
            {
                time.Text = TimeZoneInfo.ConvertTimeFromUtc(now, zone).ToString("t");
                var hours = (zone.GetUtcOffset(now) - TimeZoneInfo.Local.GetUtcOffset(now)).TotalHours;
                offset.Text = hours == 0 ? "Same" : $"{(hours > 0 ? "+" : "")}{hours:0.#}h";
            }
        }
    }

    sealed class DateWidget : Widget
    {
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly TextBlock weekday = Ui.Label("", 11, FontWeights.Bold);
        readonly TextBlock day = Ui.Label("", 50, FontWeights.Bold, 1, Ui.Display);
        readonly TextBlock month = Ui.Label("", 10, FontWeights.Medium, 0.55);

        public override FrameworkElement Root => root;

        public DateWidget()
        {
            weekday.Foreground = Ui.Brush(Ui.Red);
            day.Margin = new Thickness(0, -6, 0, -4);
            root.Children.Add(weekday);
            root.Children.Add(day);
            root.Children.Add(month);
        }

        public override void Refresh() => Tick();

        public override void Tick()
        {
            var now = DateTime.Now;
            weekday.Text = now.ToString("dddd").ToUpper();
            day.Text = now.Day.ToString();
            month.Text = now.ToString("MMMM yyyy");
        }
    }

    sealed class MonthWidget : Widget
    {
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        DateTime drawn;

        public override FrameworkElement Root => root;

        public override void Refresh() => Tick();

        public override void Tick()
        {
            var today = DateTime.Today;
            if (today == drawn) return;
            drawn = today;
            root.Children.Clear();

            var title = Ui.Label(today.ToString("MMMM").ToUpper(), 10, FontWeights.Bold);
            title.Foreground = Ui.Brush(Ui.Red);
            title.Margin = new Thickness(1, 0, 0, 5);
            root.Children.Add(title);

            var format = CultureInfo.CurrentCulture.DateTimeFormat;
            var first = (int)format.FirstDayOfWeek;
            var grid = new UniformGrid { Columns = 7 };
            for (var i = 0; i < 7; i++)
                grid.Children.Add(Cell(format.ShortestDayNames[(first + i) % 7].Substring(0, 1), 8, FontWeights.SemiBold, 0.45));
            var start = new DateTime(today.Year, today.Month, 1);
            var offset = ((int)start.DayOfWeek - first + 7) % 7;
            for (var i = 0; i < offset; i++) grid.Children.Add(new Border());
            for (var d = 1; d <= DateTime.DaysInMonth(today.Year, today.Month); d++)
            {
                var isToday = d == today.Day;
                var cell = Cell(d.ToString(), 8.5, isToday ? FontWeights.Bold : FontWeights.Normal, isToday ? 1 : 0.8);
                grid.Children.Add(isToday
                    ? new Border { Width = 14, Height = 14, CornerRadius = new CornerRadius(7), Background = Ui.Brush(Ui.Red), Child = cell, HorizontalAlignment = HorizontalAlignment.Center }
                    : cell);
            }
            root.Children.Add(grid);
        }

        static FrameworkElement Cell(string text, double size, FontWeight weight, double opacity)
        {
            var t = Centered(Ui.Label(text, size, weight, opacity));
            t.VerticalAlignment = VerticalAlignment.Center;
            t.TextTrimming = TextTrimming.None;
            t.Margin = new Thickness(0, 1.5, 0, 1.5);
            return t;
        }
    }

    sealed class ProgressWidget : Widget
    {
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly List<(Func<DateTime, double> fraction, TextBlock percent, Bar bar)> rows = new();

        public override FrameworkElement Root => root;

        public ProgressWidget()
        {
            Add("Day", now => now.TimeOfDay.TotalDays, Ui.Orange);
            Add("Week", now =>
            {
                var first = (int)CultureInfo.CurrentCulture.DateTimeFormat.FirstDayOfWeek;
                var start = now.Date.AddDays(-(((int)now.DayOfWeek - first + 7) % 7));
                return (now - start).TotalDays / 7;
            }, Ui.Yellow);
            Add("Month", now => (now - new DateTime(now.Year, now.Month, 1)).TotalDays / DateTime.DaysInMonth(now.Year, now.Month), Ui.Green);
            Add("Year", now =>
            {
                var start = new DateTime(now.Year, 1, 1);
                return (now - start).TotalDays / (start.AddYears(1) - start).TotalDays;
            }, Ui.Purple);
        }

        void Add(string title, Func<DateTime, double> fraction, Color color)
        {
            var head = new DockPanel { Margin = new Thickness(0, rows.Count > 0 ? 7 : 0, 0, 3) };
            var percent = Ui.Label("", 9.5, FontWeights.Bold);
            DockPanel.SetDock(percent, Dock.Right);
            head.Children.Add(percent);
            head.Children.Add(Ui.Label(title, 9.5, FontWeights.SemiBold, 0.6));
            root.Children.Add(head);
            var bar = new Bar(Ui.Brush(color), 4);
            root.Children.Add(bar);
            rows.Add((fraction, percent, bar));
        }

        public override void Refresh() => Tick();

        public override void Tick()
        {
            var now = DateTime.Now;
            foreach (var (fraction, percent, bar) in rows)
            {
                var value = Math.Clamp(fraction(now), 0, 1);
                percent.Text = $"{(int)(value * 100)}%";
                bar.Set(value);
            }
        }
    }

    sealed class UptimeWidget : Widget
    {
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly TextBlock value = Ui.Label("", 20, FontWeights.Bold, 1, Ui.Display);
        readonly TextBlock since = Ui.Label("", 10, FontWeights.Normal, 0.55);

        public override FrameworkElement Root => root;

        public UptimeWidget()
        {
            var icon = Ui.Glyph("", 18, Ui.Brush(Ui.Green));
            icon.HorizontalAlignment = HorizontalAlignment.Left;
            root.Children.Add(icon);
            value.Margin = new Thickness(0, 4, 0, 0);
            root.Children.Add(value);
            root.Children.Add(since);
        }

        public override void Refresh() => Tick();

        public override void Tick()
        {
            var uptime = TimeSpan.FromMilliseconds(Environment.TickCount64);
            value.Text = Format(uptime);
            since.Text = "since " + (DateTime.Now - uptime).ToString("ddd t");
        }

        public static string Format(TimeSpan t)
        {
            if (t.TotalDays >= 1) return $"{(int)t.TotalDays}d {t.Hours}h";
            if (t.TotalHours >= 1) return $"{t.Hours}h {t.Minutes}m";
            return $"{t.Minutes}m";
        }
    }

    // Media and system

    sealed class MediaWidget : Widget
    {
        readonly MediaService media;
        readonly Grid root = new();
        readonly Bar progress = new(Brushes.White, 3);
        readonly TextBlock elapsed = Ui.Label("", 9, FontWeights.Normal, 0.5);
        readonly TextBlock remaining = Ui.Label("", 9, FontWeights.Normal, 0.5);
        NowPlayer? player;
        string shownKey = "\0";

        public override FrameworkElement Root => root;

        public MediaWidget(MediaService media) => this.media = media;

        public override void Refresh() => MediaChanged();

        public override void MediaChanged()
        {
            player = media.Primary;
            var key = player is null ? "" : $"{player.Id}|{player.Title}|{player.Artist}|{player.IsPlaying}|{player.Artwork?.GetHashCode()}";
            if (key == shownKey) return;
            shownKey = key;
            root.Children.Clear();

            if (player is null)
            {
                root.Children.Add(Hint(Ui.Music, "Nothing playing", "Play music or a video in any app."));
                return;
            }

            var p = player;
            var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            var top = new DockPanel();
            var art = Ui.Artwork(p.Artwork, 56, 10);
            art.Margin = new Thickness(0, 0, 10, 0);
            DockPanel.SetDock(art, Dock.Left);
            top.Children.Add(art);
            var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            text.Children.Add(Ui.Label(string.IsNullOrEmpty(p.Title) ? "Unknown" : p.Title, 13, FontWeights.SemiBold));
            text.Children.Add(Ui.Label(p.Artist, 11, FontWeights.Normal, 0.6));
            var source = Ui.Label(p.AppName, 9.5, FontWeights.Normal, 0.4);
            source.Margin = new Thickness(0, 2, 0, 0);
            text.Children.Add(source);
            top.Children.Add(text);
            stack.Children.Add(top);

            progress.Margin = new Thickness(0, 12, 0, 3);
            stack.Children.Add(progress);
            var times = new DockPanel();
            DockPanel.SetDock(remaining, Dock.Right);
            times.Children.Add(remaining);
            times.Children.Add(elapsed);
            stack.Children.Add(times);
            progress.Visibility = times.Visibility = p.Duration > 0 ? Visibility.Visible : Visibility.Collapsed;

            var play = Ui.Round(p.IsPlaying ? Ui.Pause : Ui.Play, 34, p.TogglePlayPause, 13);
            var controls = Buttons(Ui.Round(Ui.Previous, 28, p.Previous), play, Ui.Round(Ui.Next, 28, p.Next));
            controls.Margin = new Thickness(0, 6, 0, 0);
            stack.Children.Add(controls);
            root.Children.Add(stack);
            Tick();
        }

        public override void Tick()
        {
            if (player is not { Duration: > 0 } p) return;
            var position = p.LivePosition;
            progress.Set(position / p.Duration);
            elapsed.Text = Format(position);
            remaining.Text = "-" + Format(p.Duration - position);
        }

        static string Format(double seconds)
        {
            var t = TimeSpan.FromSeconds(Math.Max(seconds, 0));
            return t.TotalHours >= 1 ? t.ToString(@"h\:mm\:ss") : t.ToString(@"m\:ss");
        }
    }

    sealed class BatteryWidget : Widget
    {
        readonly SystemStats stats;
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly Ring ring = new(66, 6);
        readonly TextBlock bolt = Ui.Glyph(Ui.Bolt, 10, Ui.Brush(Ui.Green));
        readonly TextBlock percent = Centered(Ui.Label("", 15, FontWeights.Bold, 1, Ui.Display));
        readonly TextBlock status = Centered(Ui.Label("", 11, FontWeights.SemiBold, 0.9));
        readonly TextBlock detail = Centered(Ui.Label("", 10, FontWeights.Normal, 0.5));

        public override FrameworkElement Root => root;

        public BatteryWidget(SystemStats stats)
        {
            this.stats = stats;
            var middle = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Children = { bolt, percent } };
            ring.Children.Add(middle);
            root.Children.Add(ring);
            status.Margin = new Thickness(0, 10, 0, 1);
            root.Children.Add(status);
            root.Children.Add(detail);
        }

        public override void Refresh() => StatsChanged();

        public override void StatsChanged()
        {
            if (stats.Battery is { } level)
            {
                var low = level <= 20 && !stats.Charging;
                ring.Set(level / 100.0, low ? Ui.Red : Ui.Green, low ? Ui.Orange : Ui.Mint);
                percent.Text = $"{level}%";
                bolt.FontSize = 10;
                bolt.Visibility = stats.Charging ? Visibility.Visible : Visibility.Collapsed;
                status.Text = stats.Charging ? (level >= 100 ? "Charged" : "Charging") : low ? "Low battery" : "On battery";
                detail.Text = stats.Charging ? "Plugged in" : "";
            }
            else
            {
                ring.Set(1, Ui.Green, Ui.Mint);
                percent.Text = "";
                bolt.Visibility = Visibility.Visible;
                bolt.FontSize = 20;
                status.Text = "On power";
                detail.Text = "No battery";
            }
        }
    }

    sealed class SystemWidget : Widget
    {
        readonly SystemStats stats;
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly TextBlock cpu = Ui.Label("", 12, FontWeights.Bold, 1, Ui.Display);
        readonly TextBlock memory = Ui.Label("", 12, FontWeights.Bold, 1, Ui.Display);
        readonly Sparkline cpuGraph = new(Ui.Mint, 26);
        readonly Sparkline memoryGraph = new(Ui.Yellow, 26);

        public override FrameworkElement Root => root;

        public SystemWidget(SystemStats stats)
        {
            this.stats = stats;
            Add("CPU", cpu, cpuGraph, false);
            Add("Memory", memory, memoryGraph, true);
        }

        void Add(string title, TextBlock value, Sparkline graph, bool spaced)
        {
            var head = new DockPanel { Margin = new Thickness(0, spaced ? 10 : 0, 0, 3) };
            DockPanel.SetDock(value, Dock.Right);
            head.Children.Add(value);
            head.Children.Add(Ui.Label(title, 11, FontWeights.SemiBold, 0.7));
            root.Children.Add(head);
            root.Children.Add(graph);
        }

        public override void Refresh() => StatsChanged();

        public override void StatsChanged()
        {
            cpu.Text = $"{stats.Cpu * 100:0}%";
            memory.Text = $"{stats.Memory * 100:0}%";
            cpuGraph.Set(stats.CpuHistory);
            memoryGraph.Set(stats.MemoryHistory);
        }
    }

    sealed class NetworkWidget : Widget
    {
        readonly SystemStats stats;
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly TextBlock down = Ui.Label("", 14, FontWeights.Bold, 1, Ui.Display);
        readonly TextBlock up = Ui.Label("", 14, FontWeights.Bold, 1, Ui.Display);
        readonly Sparkline graph = new(Ui.Blue, 30);

        public override FrameworkElement Root => root;

        public NetworkWidget(SystemStats stats)
        {
            this.stats = stats;
            root.Children.Add(Rate("↓", Ui.Blue, down));
            root.Children.Add(Rate("↑", Ui.Green, up));
            graph.Margin = new Thickness(0, 8, 0, 0);
            root.Children.Add(graph);
        }

        static FrameworkElement Rate(string arrow, Color color, TextBlock value)
        {
            var arrowText = Ui.Label(arrow, 13, FontWeights.Bold);
            arrowText.Foreground = Ui.Brush(color);
            arrowText.Margin = new Thickness(0, 0, 5, 0);
            return new StackPanel { Orientation = Orientation.Horizontal, Children = { arrowText, value } };
        }

        public override void Refresh() => StatsChanged();

        public override void StatsChanged()
        {
            down.Text = Format(stats.NetDown);
            up.Text = Format(stats.NetUp);
            var peak = Math.Max(stats.NetHistory.DefaultIfEmpty(0).Max(), 1);
            graph.Set(stats.NetHistory.Select(v => v / peak).ToList());
        }

        static string Format(double bytes) => bytes >= 1_000_000 ? $"{bytes / 1_000_000:0.0} MB/s" : $"{bytes / 1_000:0} KB/s";
    }

    sealed class DiskWidget : Widget
    {
        readonly SystemStats stats;
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly Ring ring = new(70, 7);
        readonly TextBlock percent = Centered(Ui.Label("", 15, FontWeights.Bold, 1, Ui.Display));
        readonly TextBlock free = Centered(Ui.Label("", 10, FontWeights.Medium, 0.55));

        public override FrameworkElement Root => root;

        public DiskWidget(SystemStats stats)
        {
            this.stats = stats;
            percent.VerticalAlignment = VerticalAlignment.Center;
            ring.Children.Add(percent);
            root.Children.Add(ring);
            free.Margin = new Thickness(0, 10, 0, 0);
            root.Children.Add(free);
        }

        public override void Refresh() => StatsChanged();

        public override void StatsChanged()
        {
            ring.Set(stats.Disk, Ui.Teal, Ui.Rgb(94, 92, 230));
            percent.Text = $"{stats.Disk * 100:0}%";
            free.Text = stats.DiskText;
        }
    }

    // Weather

    sealed class WeatherWidget : Widget
    {
        static readonly FontFamily Emoji = new("Segoe UI Emoji");
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };

        public override FrameworkElement Root => root;

        public override void Refresh()
        {
            WeatherService.Refresh();
            WeatherChanged();
        }

        public override void WeatherChanged()
        {
            root.Children.Clear();
            if (WeatherService.Current is { } report)
            {
                var (emoji, text) = WeatherService.Describe(report.Code, report.IsDay);
                root.Children.Add(Ui.Label(emoji, 24, FontWeights.Normal, 1, Emoji));
                root.Children.Add(Ui.Label($"{Math.Round(report.Temperature)}°", 26, FontWeights.Bold, 1, Ui.Display));
                root.Children.Add(Ui.Label(text, 10, FontWeights.SemiBold));
                root.Children.Add(Ui.Label($"H {Math.Round(report.High)}°  L {Math.Round(report.Low)}°", 9.5, FontWeights.Normal, 0.55));
                if (report.Place.Length > 0) root.Children.Add(Ui.Label(report.Place, 9, FontWeights.Normal, 0.4));
            }
            else if (WeatherService.Failed)
            {
                root.Children.Add(Centered(Ui.Label("Weather unavailable", 10, FontWeights.SemiBold, 0.6)));
                var retry = Link("Try again", () => WeatherService.Refresh(force: true));
                retry.Margin = new Thickness(0, 6, 0, 0);
                root.Children.Add(retry);
            }
            else root.Children.Add(Centered(Ui.Label("Loading…", 10, FontWeights.Normal, 0.5)));
        }
    }

    // Timers

    sealed class TimerWidget : Widget
    {
        static readonly int[] Presets = { 1, 5, 10, 25 };
        readonly Grid root = new();
        readonly Ring ring = new(64, 6);
        readonly TextBlock time = Centered(Ui.Label("", 14, FontWeights.Bold, 1, Ui.Display));
        (bool active, bool running) drawn = (true, true);

        public override FrameworkElement Root => root;

        public TimerWidget()
        {
            time.VerticalAlignment = VerticalAlignment.Center;
            ring.Children.Add(time);
        }

        public override void Refresh()
        {
            drawn = (!Countdown.Timer.Active, !Countdown.Timer.Running);
            Tick();
        }

        public override void Tick()
        {
            var timer = Countdown.Timer;
            if (drawn != (timer.Active, timer.Running))
            {
                drawn = (timer.Active, timer.Running);
                root.Children.Clear();
                if (timer.Active)
                {
                    var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
                    if (ring.Parent is Panel old) old.Children.Remove(ring);
                    stack.Children.Add(ring);
                    stack.Children.Add(Buttons(
                        Tinted(timer.Running ? Ui.Pause : Ui.Play, Ui.Orange, () => { if (timer.Running) timer.Pause(); else timer.Resume(); Tick(); }),
                        Tinted(Ui.Close, Colors.White, () => { timer.Cancel(); Tick(); })));
                    root.Children.Add(stack);
                }
                else
                {
                    var grid = new UniformGrid { Columns = 2, VerticalAlignment = VerticalAlignment.Center };
                    foreach (var minutes in Presets)
                    {
                        var chip = new Border
                        {
                            Height = 30, Margin = new Thickness(3), CornerRadius = new CornerRadius(9), Cursor = Cursors.Hand,
                            Background = Ui.Brush(Ui.Rgb(255, 159, 10, 46)),
                            Child = Centered(Ui.Label($"{minutes}m", 12, FontWeights.Bold, 1, Ui.Display)),
                        };
                        ((TextBlock)chip.Child).Foreground = Ui.Brush(Ui.Orange);
                        ((TextBlock)chip.Child).VerticalAlignment = VerticalAlignment.Center;
                        Ui.Hover(chip, chip.Background, Ui.Brush(Ui.Rgb(255, 159, 10, 90)));
                        chip.MouseLeftButtonUp += (_, e) => { e.Handled = true; timer.Start(TimeSpan.FromMinutes(minutes)); Tick(); };
                        grid.Children.Add(chip);
                    }
                    var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Children = { grid } };
                    var caption = Centered(Ui.Label("Pick a time", 9.5, FontWeights.Normal, 0.45));
                    caption.Margin = new Thickness(0, 6, 0, 0);
                    stack.Children.Add(caption);
                    root.Children.Add(stack);
                }
            }
            if (!timer.Active) return;
            var left = timer.Remaining;
            time.Text = Countdown.Format(left);
            ring.Set(timer.Total.TotalSeconds > 0 ? left.TotalSeconds / timer.Total.TotalSeconds : 0, Ui.Orange, Ui.Yellow);
        }
    }

    sealed class FocusWidget : Widget
    {
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly Ring ring = new(58, 6);
        readonly TextBlock time = Centered(Ui.Label("", 13, FontWeights.Bold, 1, Ui.Display));
        readonly TextBlock phase = Ui.Label("", 10, FontWeights.Bold);
        readonly Ellipse[] dots = new Ellipse[4];
        readonly Border toggle;

        public override FrameworkElement Root => root;

        public FocusWidget()
        {
            var session = FocusSession.Shared;
            time.VerticalAlignment = VerticalAlignment.Center;
            ring.Children.Add(time);
            root.Children.Add(ring);
            var line = new DockPanel { Margin = new Thickness(0, 8, 0, 0) };
            var dotRow = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            for (var i = 0; i < 4; i++)
            {
                dots[i] = new Ellipse { Width = 5, Height = 5, Margin = new Thickness(3, 0, 0, 0) };
                dotRow.Children.Add(dots[i]);
            }
            DockPanel.SetDock(dotRow, Dock.Right);
            line.Children.Add(dotRow);
            line.Children.Add(phase);
            root.Children.Add(line);
            toggle = Tinted(Ui.Play, Ui.Red, () => { session.Toggle(); Tick(); }, 28);
            root.Children.Add(Buttons(toggle, Tinted(Ui.Reset, Colors.White, () => { session.Reset(); Tick(); }, 28)));
        }

        public override void Refresh() => Tick();

        public override void Tick()
        {
            var session = FocusSession.Shared;
            var clock = session.Clock;
            var (a, b) = session.Resting ? (Ui.Green, Ui.Mint) : (Ui.Red, Ui.Orange);
            var left = clock.Active ? clock.Remaining : session.Resting ? FocusSession.RestLength : FocusSession.FocusLength;
            time.Text = Countdown.Format(left);
            ring.Set(clock.Active && clock.Total.TotalSeconds > 0 ? left.TotalSeconds / clock.Total.TotalSeconds : 1, a, b);
            phase.Text = session.Resting ? "Break" : "Focus";
            phase.Foreground = Ui.Brush(a);
            for (var i = 0; i < 4; i++) dots[i].Fill = i < session.Completed % 4 ? Ui.Brush(a) : Ui.White(0.2);
            toggle.Child = Ui.Glyph(clock.Running ? Ui.Pause : Ui.Play, 10, Ui.Brush(a));
        }
    }

    /// <summary>Keeps running while the island is closed or the tab changes.</summary>
    static class Stopwatch
    {
        static DateTime? startedAt;
        static TimeSpan banked;

        public static bool Running => startedAt is not null;
        public static TimeSpan Elapsed => banked + (startedAt is { } s ? DateTime.UtcNow - s : TimeSpan.Zero);

        public static void Toggle()
        {
            if (startedAt is { } s)
            {
                banked += DateTime.UtcNow - s;
                startedAt = null;
            }
            else startedAt = DateTime.UtcNow;
            Sync();
        }

        public static void Reset()
        {
            banked = TimeSpan.Zero;
            startedAt = Running ? DateTime.UtcNow : null;
            Sync();
        }

        /// <summary>Running, it counts up in the ears.</summary>
        static void Sync()
        {
            if (startedAt is { } s)
                Activities.Set(new LiveActivity("isola.stopwatch", Ui.Stopwatch, Ui.Yellow, "Stopwatch") { Since = s - banked, Priority = 1 });
            else Activities.End("isola.stopwatch");
        }
    }

    sealed class StopwatchWidget : Widget
    {
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly TextBlock time = Centered(Ui.Label("", 22, FontWeights.SemiBold, 1, Ui.Mono));
        readonly StackPanel buttons = new();

        public override FrameworkElement Root => root;

        public StopwatchWidget()
        {
            root.Children.Add(time);
            buttons.Margin = new Thickness(0, 6, 0, 0);
            root.Children.Add(buttons);
        }

        public override void Refresh()
        {
            buttons.Children.Clear();
            buttons.Children.Add(Buttons(
                Tinted(Ui.Reset, Colors.White, () => { Stopwatch.Reset(); Refresh(); }),
                Tinted(Stopwatch.Running ? Ui.Pause : Ui.Play, Stopwatch.Running ? Ui.Orange : Ui.Green, () => { Stopwatch.Toggle(); Refresh(); })));
            Tick();
        }

        public override void Tick()
        {
            var t = Stopwatch.Elapsed;
            time.Text = t.TotalHours >= 1 ? t.ToString(@"h\:mm\:ss") : t.ToString(@"m\:ss\.f");
            time.Foreground = Stopwatch.Running ? Ui.Brush(Ui.Orange) : Brushes.White;
        }
    }

    // Files and clipboard

    sealed class ClipboardWidget : Widget
    {
        readonly ClipboardService clipboard;
        readonly Border root = new() { Background = Brushes.Transparent, Cursor = Cursors.Hand, ToolTip = "Copy again" };
        readonly DispatcherTimer copiedTimer = new() { Interval = TimeSpan.FromSeconds(1.2) };
        ClipEntry? entry;

        public override FrameworkElement Root => root;

        public ClipboardWidget(ClipboardService clipboard)
        {
            this.clipboard = clipboard;
            copiedTimer.Tick += (_, _) => { copiedTimer.Stop(); Refresh(); };
            root.MouseLeftButtonUp += (_, e) =>
            {
                if (entry is null) return;
                e.Handled = true;
                clipboard.Copy(entry);
                Copied();
            };
        }

        public override void Refresh() => ClipboardChanged();

        public override void ClipboardChanged()
        {
            if (copiedTimer.IsEnabled) return;
            entry = clipboard.Entries.FirstOrDefault();
            if (entry is null)
            {
                var empty = Centered(Ui.Label("Nothing copied yet", 11, FontWeights.Normal, 0.5));
                empty.VerticalAlignment = VerticalAlignment.Center;
                root.Child = empty;
                return;
            }

            var stack = new DockPanel();
            var when = Ui.Label(Ago(entry.Date), 9.5, FontWeights.Normal, 0.45);
            when.Margin = new Thickness(0, 6, 0, 0);
            DockPanel.SetDock(when, Dock.Bottom);
            stack.Children.Add(when);
            if (entry.Kind == ClipKind.Image && entry.ImageFile is not null)
            {
                FrameworkElement image;
                try { image = new Image { Source = ClipboardService.LoadImage(entry.ImageFile, 200), Stretch = Stretch.Uniform }; }
                catch { image = Ui.Glyph(Ui.Picture, 26, Ui.White(0.7)); }
                stack.Children.Add(new Border { Child = image, CornerRadius = new CornerRadius(8), ClipToBounds = true });
            }
            else
            {
                var body = new StackPanel();
                if (entry.Kind == ClipKind.Color && ClipboardService.ParseColor(entry.Text) is { } color)
                    body.Children.Add(new Border
                    {
                        Height = 30, CornerRadius = new CornerRadius(8), Background = Ui.Brush(color), Margin = new Thickness(0, 0, 0, 6),
                        BorderBrush = Ui.White(0.2), BorderThickness = new Thickness(0.5),
                    });
                var text = Ui.Label(entry.Text.Trim(), 11.5, FontWeights.Medium, 0.9, entry.Kind == ClipKind.Color ? Ui.Mono : null);
                text.TextWrapping = TextWrapping.Wrap;
                text.MaxHeight = entry.Kind == ClipKind.Color ? 32 : 110;
                if (entry.Kind == ClipKind.Link) text.Foreground = Ui.Brush(Ui.Rgb(100, 210, 255));
                body.Children.Add(text);
                stack.Children.Add(body);
            }
            root.Child = stack;
        }

        void Copied()
        {
            var done = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            done.Children.Add(Ui.Glyph(Ui.Check, 22, Ui.Brush(Ui.Green)));
            var label = Centered(Ui.Label("Copied", 12, FontWeights.SemiBold));
            label.Margin = new Thickness(0, 6, 0, 0);
            done.Children.Add(label);
            root.Child = done;
            copiedTimer.Stop();
            copiedTimer.Start();
        }

        static string Ago(DateTime date)
        {
            var span = DateTime.Now - date;
            if (span.TotalMinutes < 1) return "Just now";
            if (span.TotalHours < 1) return $"{(int)span.TotalMinutes} min ago";
            if (span.TotalDays < 1) return $"{(int)span.TotalHours} hr ago";
            return date.ToString("MMM d");
        }
    }

    sealed class TrayWidget : Widget
    {
        readonly FileTray tray;
        readonly Action openTray;
        readonly Grid root = new() { Background = Brushes.Transparent, AllowDrop = true };
        readonly Rectangle target = new()
        {
            RadiusX = 10, RadiusY = 10, Stroke = Ui.Brush(Ui.Blue), StrokeThickness = 1.5, StrokeDashArray = new DoubleCollection { 4, 3 },
            Margin = new Thickness(-6), Opacity = 0, IsHitTestVisible = false,
        };
        readonly ContentControl body = new();

        public override FrameworkElement Root => root;

        public TrayWidget(FileTray tray, Action openTray)
        {
            this.tray = tray;
            this.openTray = openTray;
            root.Children.Add(body);
            root.Children.Add(target);
            root.DragEnter += (_, e) => Targeted(e, true);
            root.DragOver += (_, e) => Targeted(e, true);
            root.DragLeave += (_, e) => target.Opacity = 0;
            root.Drop += (_, e) =>
            {
                target.Opacity = 0;
                if (e.Data.GetData(DataFormats.FileDrop) is not string[] files) return;
                tray.Add(files);
                e.Handled = true;
            };
        }

        void Targeted(DragEventArgs e, bool on)
        {
            var files = e.Data.GetDataPresent(DataFormats.FileDrop);
            e.Effects = files ? DragDropEffects.Copy : DragDropEffects.None;
            target.Opacity = on && files ? 1 : 0;
            e.Handled = true;
        }

        public override void Refresh() => TrayChanged();

        public override void TrayChanged()
        {
            var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            if (tray.Items.Count == 0)
            {
                stack.Children.Add(Ui.Glyph(Ui.Download, 24, Ui.White(0.6)));
                var hint = Centered(Ui.Label("Drop files here", 10, FontWeights.SemiBold, 0.6));
                hint.Margin = new Thickness(0, 6, 0, 0);
                stack.Children.Add(hint);
            }
            else
            {
                var icons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
                foreach (var path in tray.Items.TakeLast(3))
                {
                    var icon = FileActions.IconFor(path);
                    FrameworkElement shown = icon is null
                        ? Ui.Glyph(Ui.Folder, 30)
                        : new Image { Source = icon, Width = 38, Height = 38, Stretch = Stretch.Uniform };
                    shown.Margin = new Thickness(icons.Children.Count > 0 ? -14 : 0, 0, 0, 0);
                    icons.Children.Add(shown);
                }
                stack.Children.Add(icons);
                var count = Centered(Ui.Label($"{tray.Items.Count} file{(tray.Items.Count == 1 ? "" : "s")}", 12, FontWeights.Bold));
                count.Margin = new Thickness(0, 6, 0, 2);
                stack.Children.Add(count);
                stack.Children.Add(Link("Open tray", openTray));
            }
            body.Content = stack;
        }
    }

    // Shortcuts and toggles

    sealed class ShortcutsWidget : Widget
    {
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        static extern bool LockWorkStation();

        readonly UniformGrid root = new() { Columns = 2, VerticalAlignment = VerticalAlignment.Center };

        public override FrameworkElement Root => root;

        public ShortcutsWidget()
        {
            Add("Explorer", Ui.Folder, Ui.Blue, () => Run("explorer.exe"));
            Add("Snip", "", Ui.Gray, () => Run("ms-screenclip:"));
            Add("Tasks", Ui.Gauge, Ui.Green, () => Run("taskmgr.exe"));
            Add("Lock", "", Ui.Rgb(94, 92, 230), () => LockWorkStation());
        }

        void Add(string title, string glyph, Color color, Action run)
        {
            var normal = Ui.Brush(Ui.Rgb(color.R, color.G, color.B, 140));
            var icon = new Border { Width = 34, Height = 34, CornerRadius = new CornerRadius(9), Background = normal, Child = Ui.Glyph(glyph, 14) };
            Ui.Hover(icon, normal, Ui.Brush(Ui.Rgb(color.R, color.G, color.B, 210)));
            var label = Centered(Ui.Label(title, 8.5, FontWeights.Medium, 0.7));
            label.Margin = new Thickness(0, 3, 0, 0);
            var tile = new StackPanel { Margin = new Thickness(0, 4, 0, 4), Background = Brushes.Transparent, Cursor = Cursors.Hand, Children = { icon, label } };
            tile.MouseLeftButtonUp += (_, e) => { e.Handled = true; run(); };
            root.Children.Add(tile);
        }

        static void Run(string target)
        {
            try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); } catch { }
        }
    }

    /// <summary>Keeps the display (and so the PC) awake while it is on.</summary>
    static class KeepAwake
    {
        [System.Runtime.InteropServices.DllImport("kernel32.dll")]
        static extern uint SetThreadExecutionState(uint flags);

        const uint Continuous = 0x80000000, SystemRequired = 0x1, DisplayRequired = 0x2;

        public static DateTime? Since { get; private set; }

        public static void Toggle()
        {
            if (Since is null)
            {
                if (SetThreadExecutionState(Continuous | SystemRequired | DisplayRequired) != 0) Since = DateTime.Now;
            }
            else
            {
                SetThreadExecutionState(Continuous);
                Since = null;
            }
        }
    }

    sealed class AwakeWidget : Widget
    {
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly Border button = new() { Width = 56, Height = 56, CornerRadius = new CornerRadius(28), Cursor = Cursors.Hand, HorizontalAlignment = HorizontalAlignment.Center };
        readonly TextBlock status = Centered(Ui.Label("", 10, FontWeights.SemiBold));
        readonly TextBlock since = Centered(Ui.Label("", 9.5, FontWeights.Normal, 0.5));

        public override FrameworkElement Root => root;

        public AwakeWidget()
        {
            button.MouseLeftButtonUp += (_, e) => { e.Handled = true; KeepAwake.Toggle(); Refresh(); };
            root.Children.Add(button);
            status.Margin = new Thickness(0, 8, 0, 1);
            root.Children.Add(status);
            root.Children.Add(since);
        }

        public override void Refresh()
        {
            var on = KeepAwake.Since is not null;
            button.Background = on ? Ui.Brush(Ui.Yellow) : Ui.White(0.1);
            button.Effect = on ? Ui.Glow(Ui.Yellow, 14, 0.5) : null;
            button.Child = Ui.Glyph(Ui.Brightness, 22, on ? Brushes.Black : Ui.White(0.8));
            status.Text = on ? "Staying awake" : "Sleeps as usual";
            Tick();
        }

        public override void Tick() =>
            since.Text = KeepAwake.Since is { } at ? "for " + UptimeWidget.Format(DateTime.Now - at) : "";
    }

    // Fun

    sealed class MoonWidget : Widget
    {
        const double Cycle = 29.530588853, Size = 52;
        static readonly DateTime NewMoon = new(2000, 1, 6, 18, 14, 0, DateTimeKind.Utc);
        static readonly string[] Names =
            { "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous", "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent" };

        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly Path lit = new() { Fill = Ui.Brush(Ui.Rgb(236, 236, 240)), Effect = Ui.Glow(Colors.White, 12, 0.35) };
        readonly TextBlock name = Centered(Ui.Label("", 11, FontWeights.SemiBold));
        readonly TextBlock percent = Centered(Ui.Label("", 10, FontWeights.Normal, 0.55));
        readonly TextBlock next = Centered(Ui.Label("", 9, FontWeights.Normal, 0.4));
        DateTime drawn;

        public override FrameworkElement Root => root;

        public MoonWidget()
        {
            var disc = new Grid { Width = Size, Height = Size, HorizontalAlignment = HorizontalAlignment.Center };
            disc.Children.Add(new Ellipse { Fill = Ui.Brush(Ui.Rgb(58, 58, 68)) });
            disc.Children.Add(lit);
            root.Children.Add(disc);
            name.Margin = new Thickness(0, 8, 0, 1);
            root.Children.Add(name);
            root.Children.Add(percent);
            root.Children.Add(next);
        }

        public override void Refresh()
        {
            drawn = default;
            Tick();
        }

        public override void Tick()
        {
            var now = DateTime.UtcNow;
            if ((now - drawn).TotalMinutes < 10) return;
            drawn = now;
            var age = (((now - NewMoon).TotalDays % Cycle) + Cycle) % Cycle;
            var phase = age / Cycle;
            lit.Data = Lit(phase, Size / 2);
            name.Text = Names[(int)Math.Round(phase * 8) % 8];
            percent.Text = $"{Math.Round((1 - Math.Cos(2 * Math.PI * phase)) / 2 * 100)}% lit";
            var days = Cycle / 2 - age;
            if (days < 0) days += Cycle;
            var whole = (int)Math.Round(days);
            next.Text = whole == 0 ? "Full moon tonight" : $"Full in {whole} day{(whole == 1 ? "" : "s")}";
        }

        /// <summary>The lit part: half the disc on the sunny side, then the terminator, an ellipse, back to the top.</summary>
        static Geometry Lit(double phase, double r)
        {
            var waxing = phase < 0.5;
            var k = Math.Cos(2 * Math.PI * phase);
            var crescent = k > 0;
            Point top = new(r, 0), bottom = new(r, 2 * r);
            var figure = new PathFigure { StartPoint = top, IsClosed = true };
            figure.Segments.Add(new ArcSegment(bottom, new Size(r, r), 0, false, waxing ? SweepDirection.Clockwise : SweepDirection.Counterclockwise, true));
            figure.Segments.Add(new ArcSegment(top, new Size(Math.Max(Math.Abs(k) * r, 0.01), r), 0, false,
                waxing == crescent ? SweepDirection.Counterclockwise : SweepDirection.Clockwise, true));
            return new PathGeometry(new[] { figure });
        }
    }

    sealed class DiceWidget : Widget
    {
        static readonly int[][] Faces =
        {
            new[] { 4 }, new[] { 0, 8 }, new[] { 0, 4, 8 }, new[] { 0, 2, 6, 8 }, new[] { 0, 2, 4, 6, 8 }, new[] { 0, 2, 3, 5, 6, 8 },
        };

        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly Ellipse[] pips = new Ellipse[9];
        readonly RotateTransform spin = new(0, 30, 30);
        readonly Random random = new();

        public override FrameworkElement Root => root;

        public DiceWidget()
        {
            var grid = new UniformGrid { Columns = 3, Rows = 3, Margin = new Thickness(9) };
            for (var i = 0; i < 9; i++)
            {
                pips[i] = new Ellipse { Width = 9, Height = 9, Fill = Ui.Brush(Ui.Rgb(28, 28, 32)) };
                grid.Children.Add(pips[i]);
            }
            var die = new Border
            {
                Width = 60, Height = 60, CornerRadius = new CornerRadius(14), Background = Brushes.White, Child = grid, Cursor = Cursors.Hand,
                HorizontalAlignment = HorizontalAlignment.Center, RenderTransform = spin, Effect = Ui.Glow(Colors.White, 12, 0.25),
            };
            die.MouseLeftButtonUp += (_, e) => { e.Handled = true; Roll(); };
            root.Children.Add(die);
            var hint = Centered(Ui.Label("Click to roll", 9.5, FontWeights.Normal, 0.45));
            hint.Margin = new Thickness(0, 10, 0, 0);
            root.Children.Add(hint);
            Show(random.Next(1, 7));
        }

        void Roll()
        {
            spin.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromMilliseconds(450))
            {
                EasingFunction = new BackEase { Amplitude = 0.3, EasingMode = EasingMode.EaseOut },
            });
            Show(random.Next(1, 7));
        }

        void Show(int value)
        {
            for (var i = 0; i < 9; i++) pips[i].Visibility = Faces[value - 1].Contains(i) ? Visibility.Visible : Visibility.Hidden;
        }
    }

    sealed class ColorPickerWidget : Widget
    {
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };

        public override FrameworkElement Root => root;

        public override void Refresh()
        {
            root.Children.Clear();
            var colors = Settings.Current.PickedColors;
            if (colors.Count > 0)
            {
                var latest = colors[0];
                var swatch = new Border
                {
                    Height = 38, CornerRadius = new CornerRadius(10), Background = Ui.Brush(Hex(latest)), Cursor = Cursors.Hand,
                    BorderBrush = Ui.White(0.2), BorderThickness = new Thickness(1), ToolTip = "Copy " + latest,
                };
                var label = Centered(Ui.Label(latest, 10, FontWeights.Bold, 1, Ui.Mono));
                label.VerticalAlignment = VerticalAlignment.Center;
                label.Effect = new DropShadowEffect { BlurRadius = 3, ShadowDepth = 0, Opacity = 0.8 };
                swatch.Child = label;
                swatch.MouseLeftButtonUp += (_, e) => { e.Handled = true; Copy(latest); label.Text = "Copied"; };
                root.Children.Add(swatch);
                var older = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
                foreach (var hex in colors.Skip(1))
                {
                    var dot = new Ellipse { Width = 14, Height = 14, Fill = Ui.Brush(Hex(hex)), Stroke = Ui.White(0.25), Margin = new Thickness(0, 0, 5, 0), Cursor = Cursors.Hand, ToolTip = hex };
                    dot.MouseLeftButtonUp += (_, e) => { e.Handled = true; Copy(hex); };
                    older.Children.Add(dot);
                }
                root.Children.Add(older);
            }
            else
            {
                var hint = Ui.Label("Pick any colour on screen and its hex code is copied.", 10, FontWeights.Normal, 0.5);
                hint.TextWrapping = TextWrapping.Wrap;
                root.Children.Add(hint);
            }
            var pick = Ui.Capsule(new Border
            {
                Background = Brushes.White, Padding = new Thickness(0, 6, 0, 6), Margin = new Thickness(0, 10, 0, 0), Cursor = Cursors.Hand,
                Child = new StackPanel
                {
                    Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center,
                    Children = { Ui.Glyph("\uEF3C", 11, Brushes.Black), new TextBlock { Text = "Pick", FontFamily = Ui.Text, FontSize = 11, FontWeight = FontWeights.SemiBold, Margin = new Thickness(6, 0, 0, 0) } },
                },
            });
            Ui.Hover(pick, Brushes.White, Ui.White(0.85));
            pick.MouseLeftButtonUp += (_, e) =>
            {
                e.Handled = true;
                new ColorSampler(color =>
                {
                    var hex = $"#{color.R:X2}{color.G:X2}{color.B:X2}";
                    Copy(hex);
                    var list = Settings.Current.PickedColors.Where(c => c != hex).Prepend(hex).Take(5).ToList();
                    Settings.Current.PickedColors = list;
                    Settings.SaveQuietly();
                    Refresh();
                }).Show();
            };
            root.Children.Add(pick);
        }

        static Color Hex(string hex) =>
            int.TryParse(hex.TrimStart('#'), System.Globalization.NumberStyles.HexNumber, null, out var n)
                ? Ui.Rgb((byte)(n >> 16), (byte)(n >> 8), (byte)n) : Ui.Gray;

        static void Copy(string hex)
        {
            try { Clipboard.SetText(hex); } catch { }
        }
    }

    sealed class CounterWidget : Widget
    {
        readonly StackPanel root = new() { VerticalAlignment = VerticalAlignment.Center };
        readonly TextBlock number = Centered(Ui.Label("", 38, FontWeights.Bold, 1, Ui.Display));
        readonly TextBlock reset;

        public override FrameworkElement Root => root;

        public CounterWidget()
        {
            root.Children.Add(number);
            var pink = Ui.Rgb(255, 55, 135);
            root.Children.Add(Buttons(Tinted("", pink, () => Change(-1)), Tinted("", pink, () => Change(1))));
            reset = Link("Reset", () => Set(0));
            reset.Margin = new Thickness(0, 8, 0, 0);
            root.Children.Add(reset);
        }

        void Change(int by) => Set(Settings.Current.HomeCounter + by);

        void Set(int value)
        {
            Settings.Current.HomeCounter = value;
            Settings.SaveQuietly();
            Refresh();
        }

        public override void Refresh()
        {
            number.Text = Settings.Current.HomeCounter.ToString();
            reset.Opacity = Settings.Current.HomeCounter == 0 ? 0.3 : 1;
        }
    }

    /// <summary>
    /// A volume slider for every app playing sound, so the music can go down without touching the call. Clicking an
    /// app's icon mutes it. The apps are looked at again every two seconds; a slider being dragged is left alone.
    /// </summary>
    sealed class MixerWidget : Widget
    {
        const int MostRows = 3;
        readonly Grid root = new();
        readonly List<Row> rows = new();
        MMDeviceEnumerator? enumerator;
        string shownKey = "\0";
        int ticks;

        public override FrameworkElement Root => root;

        sealed class Row
        {
            public required AudioSessionControl Session;
            public required Bar Level;
            public required TextBlock Icon;
            public bool Dragging;
        }

        public override void Refresh()
        {
            ticks = 0;
            Look();
        }

        public override void Tick()
        {
            if (++ticks % 10 == 0) Look();
        }

        static (uint Id, string Name, string? File) Who(AudioSessionControl session)
        {
            var id = session.GetProcessID;
            try
            {
                using var process = Process.GetProcessById((int)id);
                string? file = null;
                try { file = process.MainModule?.FileName; } catch { }
                var name = file is null ? null : FileVersionInfo.GetVersionInfo(file).FileDescription;
                return (id, string.IsNullOrWhiteSpace(name) ? process.ProcessName : name!, file);
            }
            catch
            {
                return (id, string.IsNullOrWhiteSpace(session.DisplayName) ? "App" : session.DisplayName, null);
            }
        }

        void Look()
        {
            if (rows.Any(r => r.Dragging)) return;
            List<AudioSessionControl> sessions;
            try
            {
                enumerator ??= new MMDeviceEnumerator();
                var device = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
                device.AudioSessionManager.RefreshSessions();
                var all = device.AudioSessionManager.Sessions;
                sessions = Enumerable.Range(0, all.Count).Select(i => all[i])
                    .Where(x => !x.IsSystemSoundsSession && x.State != NAudio.CoreAudioApi.Interfaces.AudioSessionState.AudioSessionStateExpired)
                    .OrderBy(x => x.State == NAudio.CoreAudioApi.Interfaces.AudioSessionState.AudioSessionStateActive ? 0 : 1)
                    .Take(MostRows).ToList();
            }
            catch
            {
                sessions = new List<AudioSessionControl>();
            }

            var key = string.Join("|", sessions.Select(x => x.GetProcessID));
            if (key != shownKey)
            {
                shownKey = key;
                Build(sessions);
            }
            foreach (var row in rows) Show(row);
        }

        void Build(List<AudioSessionControl> sessions)
        {
            root.Children.Clear();
            rows.Clear();
            if (sessions.Count == 0)
            {
                root.Children.Add(Hint(Ui.Volume, "Nothing playing", "Apps making sound show up here."));
                return;
            }
            var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            foreach (var session in sessions)
            {
                var (_, name, file) = Who(session);
                var line = new DockPanel { Margin = new Thickness(0, 4, 0, 4) };
                var picture = file is null ? null : FileActions.IconFor(file);
                FrameworkElement icon = picture is null
                    ? Ui.Glyph(Ui.Volume, 14, Ui.White(0.8))
                    : new Image { Source = picture, Width = 18, Height = 18 };
                var mute = Ui.Glyph(Ui.Mute, 10, Ui.Brush(Ui.Rgb(255, 69, 58)));
                var badge = new Grid { Width = 22, Height = 22, Cursor = Cursors.Hand, Margin = new Thickness(0, 0, 8, 0) };
                badge.Children.Add(icon);
                mute.HorizontalAlignment = HorizontalAlignment.Right;
                mute.VerticalAlignment = VerticalAlignment.Bottom;
                badge.Children.Add(mute);
                DockPanel.SetDock(badge, Dock.Left);
                line.Children.Add(badge);

                var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
                text.Children.Add(Ui.Label(name, 10.5, FontWeights.SemiBold, 0.85));
                var level = new Bar(Brushes.White, 5) { Margin = new Thickness(0, 4, 0, 0) };
                var track = new Grid { Background = Brushes.Transparent, Height = 13, Cursor = Cursors.Hand };
                track.Children.Add(level);
                text.Children.Add(track);
                line.Children.Add(text);
                stack.Children.Add(line);

                var row = new Row { Session = session, Level = level, Icon = mute };
                rows.Add(row);
                badge.MouseLeftButtonUp += (_, e) =>
                {
                    e.Handled = true;
                    try { session.SimpleAudioVolume.Mute = !session.SimpleAudioVolume.Mute; } catch { }
                    Show(row);
                };
                void Set(Point at)
                {
                    var fraction = Math.Clamp(at.X / Math.Max(track.ActualWidth, 1), 0, 1);
                    try
                    {
                        session.SimpleAudioVolume.Volume = (float)fraction;
                        if (fraction > 0 && session.SimpleAudioVolume.Mute) session.SimpleAudioVolume.Mute = false;
                    }
                    catch { }
                    Show(row);
                }
                track.MouseLeftButtonDown += (_, e) => { e.Handled = true; row.Dragging = true; track.CaptureMouse(); Set(e.GetPosition(track)); };
                track.MouseMove += (_, e) => { if (row.Dragging) Set(e.GetPosition(track)); };
                track.MouseLeftButtonUp += (_, e) => { e.Handled = true; row.Dragging = false; track.ReleaseMouseCapture(); };
                track.LostMouseCapture += (_, _) => row.Dragging = false;
            }
            root.Children.Add(stack);
        }

        static void Show(Row row)
        {
            try
            {
                var muted = row.Session.SimpleAudioVolume.Mute;
                row.Level.Set(muted ? 0 : row.Session.SimpleAudioVolume.Volume);
                row.Icon.Visibility = muted ? Visibility.Visible : Visibility.Collapsed;
            }
            catch { }
        }
    }
}

/// <summary>A countdown that keeps going while the island is closed, sits in the ears while it runs, and rings when done.</summary>
sealed class Countdown
{
    public static readonly Countdown Timer = new(c =>
    {
        var total = c.Total;
        var minutes = (int)Math.Round(total.TotalMinutes);
        Ringer.Start();
        Hub.Island.ShowBanner(new Banner("\uE823", Ui.Orange, "Timer done", $"{minutes} minute{(minutes == 1 ? "" : "s")} are up",
            new BannerAction("Stop", "\uE71A", () => { }))
        {
            SecondAction = new BannerAction("Repeat", Ui.Sync, () => c.Start(total)),
            Ringing = true,
            OnDismiss = Ringer.Stop,
        }, 60);
    }) { Look = ("isola.timer", "\uE823", Ui.Orange, "Timer") };

    readonly DispatcherTimer done = new();
    DateTime? endsAt;
    TimeSpan? paused;
    public Action<Countdown>? Finished;
    (string Id, string Glyph, Color Tint, string Title)? look;

    public TimeSpan Total { get; private set; }
    public bool Running => endsAt is not null;
    public bool Active => endsAt is not null || paused is not null;
    public TimeSpan Remaining => endsAt is { } end
        ? (end > DateTime.UtcNow ? end - DateTime.UtcNow : TimeSpan.Zero)
        : paused ?? Total;

    /// <summary>How it shows in the ears while it runs. Null keeps it out of the island.</summary>
    public (string Id, string Glyph, Color Tint, string Title)? Look
    {
        get => look;
        set
        {
            look = value;
            Sync();
        }
    }

    public Countdown(Action<Countdown>? finished = null)
    {
        Finished = finished;
        done.Tick += (_, _) =>
        {
            done.Stop();
            endsAt = null;
            paused = null;
            Sync();
            Finished?.Invoke(this);
        };
    }

    public void Start(TimeSpan length)
    {
        Total = length;
        paused = null;
        Schedule(length);
    }

    public void Pause()
    {
        if (endsAt is null) return;
        paused = Remaining;
        endsAt = null;
        done.Stop();
        Sync();
    }

    public void Resume()
    {
        if (paused is not { } left) return;
        paused = null;
        Schedule(left);
    }

    public void Cancel()
    {
        done.Stop();
        endsAt = null;
        paused = null;
        Sync();
    }

    void Schedule(TimeSpan left)
    {
        done.Stop();
        endsAt = DateTime.UtcNow + left;
        done.Interval = left > TimeSpan.Zero ? left : TimeSpan.FromMilliseconds(1);
        done.Start();
        Sync();
    }

    /// <summary>Running, it counts down in the ears; paused, it shows the time left; stopped, it leaves.</summary>
    void Sync()
    {
        if (look is not { } l) return;
        if (Active)
            Activities.Set(new LiveActivity(l.Id, l.Glyph, l.Tint, l.Title)
            {
                EndsAt = endsAt, Trailing = endsAt is null ? Format(Remaining) : "", Priority = 1,
            });
        else Activities.End(l.Id);
    }

    public static string Format(TimeSpan t)
    {
        var s = (int)Math.Ceiling(t.TotalSeconds);
        return s >= 3600 ? $"{s / 3600}:{s / 60 % 60:00}:{s % 60:00}" : $"{s / 60}:{s % 60:00}";
    }
}

/// <summary>
/// Pomodoro: 25 minutes of focus, then a 5 minute break (15 after every fourth). Each session ends by ringing in the
/// island, and the next starts when you say so.
/// </summary>
sealed class FocusSession
{
    public static readonly FocusSession Shared = new();
    public static readonly TimeSpan FocusLength = TimeSpan.FromMinutes(25), RestLength = TimeSpan.FromMinutes(5);

    public readonly Countdown Clock;
    public bool Resting { get; private set; }
    public int Completed { get; private set; }

    FocusSession()
    {
        Clock = new Countdown(_ => Advance());
        UpdateLook();
    }

    TimeSpan BreakLength => Completed > 0 && Completed % 4 == 0 ? TimeSpan.FromMinutes(15) : RestLength;

    public void Toggle()
    {
        if (Clock.Running) Clock.Pause();
        else if (Clock.Active) Clock.Resume();
        else Clock.Start(Resting ? BreakLength : FocusLength);
    }

    public void Reset()
    {
        Clock.Cancel();
        Resting = false;
        Completed = 0;
        UpdateLook();
    }

    public void SkipBreak()
    {
        Clock.Cancel();
        Resting = false;
        UpdateLook();
    }

    void UpdateLook() => Clock.Look = Resting
        ? ("isola.focus", Ui.Heart, Ui.Green, "Break")
        : ("isola.focus", "\uE7C1", Ui.Red, "Focus");

    void Advance()
    {
        Ringer.Start();
        if (!Resting)
        {
            Completed++;
            Resting = true;
            UpdateLook();
            var length = BreakLength;
            Hub.Island.ShowBanner(new Banner(Ui.Heart, Ui.Green, "Time for a break", length > RestLength ? "15 minutes. You've earned it." : "5 minutes",
                new BannerAction("Start break", Ui.Play, () => Clock.Start(length)))
            {
                SecondAction = new BannerAction("Skip", Ui.Next, SkipBreak),
                Ringing = true,
                OnDismiss = Ringer.Stop,
            }, 60);
        }
        else
        {
            Resting = false;
            UpdateLook();
            Hub.Island.ShowBanner(new Banner("\uE7C1", Ui.Red, "Break's over", "Ready for the next session?",
                new BannerAction("Start focus", Ui.Play, () => Clock.Start(FocusLength)))
            {
                SecondAction = new BannerAction("Later", "\uE823", () => { }),
                Ringing = true,
                OnDismiss = Ringer.Stop,
            }, 60);
        }
    }
}

/// <summary>
/// Today's weather where you are: a rough location from your network address (so no location permission), then the
/// forecast from Open-Meteo. Fetched when the widget shows, at most every 15 minutes.
/// </summary>
static class WeatherService
{
    public sealed record Report(double Temperature, double High, double Low, int Code, bool IsDay, string Place);

    static readonly System.Net.Http.HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(10) };
    static DateTime fetchedAt;
    static bool loading;

    public static Report? Current { get; private set; }
    public static bool Failed { get; private set; }
    public static event Action? Changed;

    public static async void Refresh(bool force = false)
    {
        if (!force && Current is not null && DateTime.UtcNow - fetchedAt < TimeSpan.FromMinutes(15)) return;
        if (loading) return;
        loading = true;
        Failed = false;
        try
        {
            using var geo = System.Text.Json.JsonDocument.Parse(await Http.GetStringAsync("https://get.geojs.io/v1/ip/geo.json"));
            var latitude = Number(geo.RootElement.GetProperty("latitude"));
            var longitude = Number(geo.RootElement.GetProperty("longitude"));
            var place = geo.RootElement.TryGetProperty("city", out var city) ? city.GetString() ?? "" : "";
            var unit = RegionInfo.CurrentRegion.IsMetric ? "celsius" : "fahrenheit";
            var url = string.Create(CultureInfo.InvariantCulture,
                $"https://api.open-meteo.com/v1/forecast?latitude={latitude}&longitude={longitude}&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1&temperature_unit={unit}");
            using var forecast = System.Text.Json.JsonDocument.Parse(await Http.GetStringAsync(url));
            var current = forecast.RootElement.GetProperty("current");
            var daily = forecast.RootElement.GetProperty("daily");
            var temperature = current.GetProperty("temperature_2m").GetDouble();
            Current = new Report(
                temperature,
                daily.GetProperty("temperature_2m_max")[0].GetDouble(),
                daily.GetProperty("temperature_2m_min")[0].GetDouble(),
                current.GetProperty("weather_code").GetInt32(),
                current.GetProperty("is_day").GetInt32() == 1,
                place);
            fetchedAt = DateTime.UtcNow;
        }
        catch
        {
            if (Current is null) Failed = true;
        }
        loading = false;
        Changed?.Invoke();
    }

    static double Number(System.Text.Json.JsonElement e) =>
        e.ValueKind == System.Text.Json.JsonValueKind.String ? double.Parse(e.GetString()!, CultureInfo.InvariantCulture) : e.GetDouble();

    /// <summary>A symbol and words for a WMO weather code.</summary>
    public static (string Emoji, string Text) Describe(int code, bool day) => code switch
    {
        0 => (day ? "☀" : "\U0001F319", "Clear"),
        1 or 2 => (day ? "⛅" : "☁", "Partly cloudy"),
        3 => ("☁", "Cloudy"),
        45 or 48 => ("\U0001F32B", "Fog"),
        >= 51 and <= 57 => ("\U0001F326", "Drizzle"),
        >= 61 and <= 67 => ("\U0001F327", "Rain"),
        (>= 71 and <= 77) or 85 or 86 => ("\U0001F328", "Snow"),
        >= 80 and <= 82 => ("\U0001F327", "Showers"),
        >= 95 => ("⛈", "Thunderstorm"),
        _ => ("☁", "Cloudy"),
    };
}
