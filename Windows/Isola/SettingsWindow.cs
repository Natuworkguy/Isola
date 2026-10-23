using System;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;

namespace Isola;

/// <summary>
/// Isola's settings, laid out like the Mac version: General, Display and Island along a toolbar, and grouped sections of
/// rows (a label on the left, its control on the right). Every change is saved at once.
/// </summary>
sealed class SettingsWindow : Window
{
    static readonly Color Background_ = Ui.Rgb(30, 30, 32);
    static readonly Brush Card = Ui.White(0.05);
    static readonly Brush CardEdge = Ui.White(0.07);
    static readonly Brush Divider = Ui.White(0.07);
    static readonly Brush Secondary = Ui.White(0.55);
    static readonly Color Accent = Ui.Rgb(10, 132, 255);

    readonly Grid page = new();
    readonly StackPanel toolbar = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
    readonly List<(Border button, TextBlock icon, TextBlock label)> tabs = new();
    StackPanel list = new();
    int current = -1;

    public SettingsWindow()
    {
        Title = "Isola Settings";
        Width = 540;
        Height = 660;
        MinHeight = 420;
        ResizeMode = ResizeMode.CanMinimize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Ui.Brush(Background_);
        Foreground = Brushes.White;
        FontFamily = Ui.Text;
        FontSize = 13;
        UseLayoutRounding = true;
        TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
        using (var stream = typeof(SettingsWindow).Assembly.GetManifestResourceStream("Isola.ico"))
            if (stream is not null)
                Icon = System.Windows.Media.Imaging.BitmapFrame.Create(stream, System.Windows.Media.Imaging.BitmapCreateOptions.None,
                    System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);

        var root = new DockPanel();
        var bar = new Border
        {
            Child = toolbar, Padding = new Thickness(0, 10, 0, 10), BorderBrush = Ui.White(0.08),
            BorderThickness = new Thickness(0, 0, 0, 1), Background = Ui.Brush(Ui.Rgb(36, 36, 39)),
        };
        DockPanel.SetDock(bar, Dock.Top);
        root.Children.Add(bar);
        root.Children.Add(page);
        Content = root;

        AddTab("", "General");
        AddTab("", "Display");
        AddTab("", "Island");
        Show(0);

        SourceInitialized += (_, _) => DarkTitleBar();
    }

    // MARK: Toolbar

    void AddTab(string glyph, string title)
    {
        var index = tabs.Count;
        var icon = Ui.Glyph(glyph, 20, Secondary);
        var label = new TextBlock { Text = title, FontSize = 11, Foreground = Secondary, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 0) };
        var stack = new StackPanel();
        stack.Children.Add(icon);
        stack.Children.Add(label);
        var button = new Border
        {
            Child = stack, Width = 76, Padding = new Thickness(0, 6, 0, 5), Margin = new Thickness(2, 0, 2, 0),
            CornerRadius = new CornerRadius(8), Background = Brushes.Transparent, Cursor = Cursors.Hand,
        };
        button.MouseEnter += (_, _) => { if (current != index) button.Background = Ui.White(0.05); };
        button.MouseLeave += (_, _) => { if (current != index) button.Background = Brushes.Transparent; };
        button.MouseLeftButtonUp += (_, _) => Show(index);
        toolbar.Children.Add(button);
        tabs.Add((button, icon, label));
    }

    void Show(int index)
    {
        if (index == current) return;
        current = index;
        for (var i = 0; i < tabs.Count; i++)
        {
            var on = i == index;
            tabs[i].button.Background = on ? Ui.White(0.09) : Brushes.Transparent;
            tabs[i].icon.Foreground = on ? Ui.Brush(Accent) : Secondary;
            tabs[i].label.Foreground = on ? Brushes.White : Secondary;
        }
        list = new StackPanel { Margin = new Thickness(24, 6, 24, 26) };
        switch (index)
        {
            case 0: General(); break;
            case 1: Display(); break;
            default: Island(); break;
        }
        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Opacity = 0 };
        page.Children.Clear();
        page.Children.Add(scroll);
        scroll.BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(180)));
    }

    // MARK: Pages

    void General()
    {
        var s = Settings.Current;
        Section("Startup",
            Row("Launch at login", Switch(s.LaunchAtLogin, v => s.LaunchAtLogin = v)));
        var version = Assembly.GetExecutingAssembly().GetName().Version;
        Section("About",
            Row("Isola", Value($"Version {version?.ToString(3) ?? "1.0.0"}")),
            Row("Made by", Value("Natuworkguy")));
        var quit = new Border
        {
            Child = new TextBlock { Text = "Quit Isola", FontSize = 13 }, Padding = new Thickness(14, 6, 14, 6),
            CornerRadius = new CornerRadius(6), Background = Ui.White(0.1), HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 18, 0, 0), Cursor = Cursors.Hand,
        };
        Ui.Hover(quit, Ui.White(0.1), Ui.White(0.16));
        quit.MouseLeftButtonUp += (_, _) => Hub.Quit();
        list.Children.Add(quit);
    }

    void Display()
    {
        var s = Settings.Current;
        Section("Where",
            Row("Style", Picker(new[] { "Floating capsule", "Attached to the top edge" }, (int)s.Style, i => s.Style = (IslandStyle)i)));
        Section("Look",
            Row("Material", Picker(new[] { "Dynamic Glass", "Solid black" }, (int)s.Material, i => s.Material = (IslandMaterial)i)),
            Row("Tint with album artwork", Switch(s.TintFromArtwork, v => s.TintFromArtwork = v)),
            Caption("Both materials work in either style: glass or solid black, floating below the top edge or attached to it."));
        Section("Idle",
            Row("When idle", Picker(new[] { "Show a small pill", "Hide until the pointer arrives" }, s.HideWhenIdle ? 1 : 0, i => s.HideWhenIdle = i == 1)),
            SliderRow("Idle width", s.IdleWidth, 80, 260, 1, v => s.IdleWidth = v, v => $"{v:0} px"),
            SliderRow("Idle height", s.IdleHeight, 20, 44, 1, v => s.IdleHeight = v, v => $"{v:0} px"),
            SliderRow("Gap from the top edge", s.TopGap, 0, 12, 1, v => s.TopGap = v, v => $"{v:0} px"),
            Row("Hide during full-screen apps", Switch(s.HideInFullScreen, v => s.HideInFullScreen = v)));
    }

    void Island()
    {
        var s = Settings.Current;
        Section("Opening",
            Row("Open the island by", Picker(new[] { "Hovering over it", "Clicking it", "Scrolling over it" }, (int)s.OpenWith, i => s.OpenWith = (OpenWith)i)),
            Row("Open when the pointer is", Picker(new[] { "Near the island", "On the island" }, (int)s.HoverArea, i => s.HoverArea = (HoverArea)i)),
            SliderRow("Hover delay", s.HoverDelay, 0, 0.6, 0.02, v => s.HoverDelay = v, v => $"{v:0.00}s"),
            Row("Clicking it opens it too, when it opens by hovering", Switch(s.ClickOpens, v => s.ClickOpens = v)),
            Caption("Off, a click on the closed island goes through to whatever is under it."),
            Row("Open when dragging files toward it", Switch(s.ExpandOnFileDrag, v => s.ExpandOnFileDrag = v)),
            Row("Shake a dragged file to bring up the Basket", Switch(s.ShakeBasket, v => s.ShakeBasket = v)));
        Section("Gestures and keyboard",
            Row("Swipe down on the island to open it, up on its top edge to close it", Switch(s.Gestures, v => s.Gestures = v)),
            Caption("Swiping sideways over the music skips to the next or previous track. A mouse wheel works too."),
            Row($"Open and close the island with {IslandWindow.HotKeyText}", Switch(s.HotKey, v => s.HotKey = v)));
        Section("Tabs",
            Row("Home", Switch(s.TabHome, v => s.TabHome = v), Ui.Home),
            Row("Media", Switch(s.TabMedia, v => s.TabMedia = v), Ui.Media),
            Row("File Tray", Switch(s.TabTray, v => s.TabTray = v), Ui.Folder),
            Row("Clipboard", Switch(s.TabClipboard, v => s.TabClipboard = v), Ui.Paste),
            Row("System", Switch(s.TabSystem, v => s.TabSystem = v), Ui.Gauge));
        Section("Live Activities",
            Row("Volume", Switch(s.LiveVolume, v => s.LiveVolume = v)),
            Row("Brightness", Switch(s.LiveBrightness, v => s.LiveBrightness = v)),
            Row("Charging and low battery", Switch(s.LiveCharging, v => s.LiveCharging = v)),
            Row("Headphones connecting", Switch(s.LiveHeadphones, v => s.LiveHeadphones = v)),
            Row("Drives, with an Eject button", Switch(s.LiveDrives, v => s.LiveDrives = v)),
            Row("VPN connecting and disconnecting", Switch(s.LiveVpn, v => s.LiveVpn = v)),
            Caption("Brightness works on laptop screens; most external monitors do not report it."));
        Section("More Live Activities",
            Row("Timers ring in the island, with Stop and Repeat", Switch(s.LiveTimers, v => s.LiveTimers = v)),
            Row("Alarms and timers from the Clock app", Switch(s.LiveClockApp, v => s.LiveClockApp = v)),
            Row("Camera and microphone in use, with privacy dots", Switch(s.LivePrivacy, v => s.LivePrivacy = v)),
            Row("Downloads finishing", Switch(s.LiveDownloads, v => s.LiveDownloads = v)),
            Row("Screenshots and screen recordings saved", Switch(s.LiveScreenshots, v => s.LiveScreenshots = v)),
            Row("Going offline and coming back", Switch(s.LiveNetwork, v => s.LiveNetwork = v)),
            Row("Displays connecting", Switch(s.LiveDisplays, v => s.LiveDisplays = v)),
            Row("Caps Lock", Switch(s.LiveCapsLock, v => s.LiveCapsLock = v)),
            Row("Keyboard layout changing", Switch(s.LiveKeyboard, v => s.LiveKeyboard = v)),
            Row("Running low on storage", Switch(s.LiveDiskSpace, v => s.LiveDiskSpace = v)),
            Row("Do not disturb turning on and off", Switch(s.LiveDoNotDisturb, v => s.LiveDoNotDisturb = v)),
            Caption(Services.SystemActivities.NotificationAccess == false
                ? "Windows has not let Isola read notifications, so Clock alerts stay as Windows shows them. Windows grants this to some apps only. Where it does, Isola shows the alert in the island and removes Windows' own copy; Windows offers no way to press Clock's Snooze, so the second button opens Clock."
                : "Clock alerts appear in the island and Windows' own copy is removed. Windows offers no way to press Clock's Snooze button, so the second button opens Clock. Screenshots are watched in Pictures\\Screenshots and Videos\\Captures."));
        Section("Windows volume overlay",
            Row("Hide it and show only Isola's bar", Switch(s.HideSystemOverlay, v => s.HideSystemOverlay = v)),
            Caption("Works on Windows 10. Windows 11 draws its overlay in a way apps cannot hide."));
        Section("Notifications",
            Row("Show banners from other apps and scripts", Switch(s.NotifyLinks, v => s.NotifyLinks = v)),
            Caption("Anything can show a banner in the island by opening an isola://notify link, for example:"),
            Code("start isola://notify?title=Done^&text=Build%20finished^&color=green"),
            Row("Let apps and scripts show Live Activities", Switch(s.ActivityLinks, v => s.ActivityLinks = v)),
            Caption("An isola://activity link starts a Live Activity with a checklist that updates in place, and ends it:"),
            Code("start \"\" \"isola://activity?id=build&title=Build&steps=done:Fetch|active:Compile|todo:Test\"\nstart \"\" \"isola://activity/end?id=build\""));
        Section("Clipboard",
            Row($"Keep {s.ClipboardLimit} items", Stepper(s.ClipboardLimit, 10, 200, 10, v => s.ClipboardLimit = v)),
            Caption("Copies from password managers are never recorded."));
    }

    // MARK: Building blocks

    void Section(string title, params FrameworkElement[] rows)
    {
        list.Children.Add(new TextBlock
        {
            Text = title, FontSize = 13, FontWeight = FontWeights.SemiBold, Foreground = Ui.White(0.85),
            Margin = new Thickness(4, 18, 0, 7),
        });
        var stack = new StackPanel();
        for (var i = 0; i < rows.Length; i++)
        {
            if (i > 0) stack.Children.Add(new Border { Height = 1, Background = Divider, Margin = new Thickness(12, 0, 12, 0) });
            stack.Children.Add(rows[i]);
        }
        list.Children.Add(new Border
        {
            Child = stack, Background = Card, BorderBrush = CardEdge, BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
        });
    }

    static FrameworkElement Row(string title, FrameworkElement control, string? glyph = null)
    {
        var row = new DockPanel { Margin = new Thickness(12, 0, 12, 0), MinHeight = 40, LastChildFill = false };
        control.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(control, Dock.Right);
        row.Children.Add(control);
        var label = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 9, 12, 9) };
        if (glyph is not null)
        {
            var icon = Ui.Glyph(glyph, 13, Ui.Brush(Accent));
            icon.Width = 20;
            icon.Margin = new Thickness(0, 0, 8, 0);
            label.Children.Add(icon);
        }
        label.Children.Add(new TextBlock { Text = title, FontSize = 13, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap, MaxWidth = 300 });
        row.Children.Add(label);
        return row;
    }

    static FrameworkElement Caption(string text) => new TextBlock
    {
        Text = text, FontSize = 11.5, Foreground = Secondary, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(12, 9, 12, 10),
    };

    static FrameworkElement Code(string text) => new TextBox
    {
        Text = text, IsReadOnly = true, FontFamily = Ui.Mono, FontSize = 11.5, Foreground = Ui.White(0.85),
        Background = Brushes.Transparent, BorderThickness = new Thickness(0), Margin = new Thickness(10, 0, 12, 10), TextWrapping = TextWrapping.Wrap,
    };

    static FrameworkElement Value(string text) => new TextBlock { Text = text, FontSize = 13, Foreground = Secondary };

    static void Save() => Settings.Save();

    /// <summary>A Mac switch: a capsule that slides its knob across and fills with the accent colour.</summary>
    static FrameworkElement Switch(bool value, Action<bool> set)
    {
        const double W = 38, H = 22, Knob = 18;
        var on = value;
        var track = new Border { Width = W, Height = H, CornerRadius = new CornerRadius(H / 2), Cursor = Cursors.Hand };
        var knob = new Border
        {
            Width = Knob, Height = Knob, CornerRadius = new CornerRadius(Knob / 2), Background = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(2, 0, 0, 0),
            Effect = new DropShadowEffect { BlurRadius = 4, ShadowDepth = 1, Opacity = 0.35, Direction = 270 },
            RenderTransform = new TranslateTransform(),
        };
        track.Child = knob;
        void Paint(bool animate)
        {
            var color = on ? Accent : Ui.Rgb(255, 255, 255, 40);
            var brush = new SolidColorBrush(((track.Background as SolidColorBrush)?.Color) ?? color);
            track.Background = brush;
            var ms = TimeSpan.FromMilliseconds(animate ? 180 : 0);
            brush.BeginAnimation(SolidColorBrush.ColorProperty, new ColorAnimation(color, ms));
            ((TranslateTransform)knob.RenderTransform).BeginAnimation(TranslateTransform.XProperty,
                new DoubleAnimation(on ? W - Knob - 4 : 0, ms) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        }
        Paint(false);
        track.MouseLeftButtonUp += (_, _) =>
        {
            on = !on;
            Paint(true);
            set(on);
            Save();
        };
        return track;
    }

    /// <summary>A Mac pop-up button: the current choice with up-down chevrons, opening a menu that ticks the current one.</summary>
    static FrameworkElement Picker(string[] options, int selected, Action<int> set)
    {
        var text = new TextBlock { Text = options[Math.Clamp(selected, 0, options.Length - 1)], FontSize = 13, VerticalAlignment = VerticalAlignment.Center };
        var chevrons = Ui.Glyph("", 9, Ui.White(0.8));
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(text);
        var chip = new Border
        {
            Child = chevrons, Width = 16, Height = 16, CornerRadius = new CornerRadius(4), Background = Ui.Brush(Accent),
            Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center,
        };
        row.Children.Add(chip);
        var button = new Border
        {
            Child = row, Padding = new Thickness(10, 3, 3, 3), CornerRadius = new CornerRadius(6), Background = Ui.White(0.1),
            BorderBrush = Ui.White(0.08), BorderThickness = new Thickness(1), Cursor = Cursors.Hand,
        };
        Ui.Hover(button, Ui.White(0.1), Ui.White(0.15));

        var menu = new StackPanel { Margin = new Thickness(5) };
        var popup = new Popup
        {
            PlacementTarget = button, Placement = PlacementMode.Bottom, StaysOpen = false, AllowsTransparency = true,
            PopupAnimation = PopupAnimation.Fade, VerticalOffset = 4,
            Child = new Border
            {
                Child = menu, Background = Ui.Brush(Ui.Rgb(44, 44, 48)), BorderBrush = Ui.White(0.12), BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8), Margin = new Thickness(0, 0, 10, 10),
                Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 4, Opacity = 0.45, Direction = 270 },
            },
        };
        for (var i = 0; i < options.Length; i++)
        {
            var index = i;
            var item = new DockPanel { LastChildFill = true };
            var tick = Ui.Glyph(Ui.Check, 11);
            tick.Width = 18;
            item.Children.Add(tick);
            item.Children.Add(new TextBlock { Text = options[i], FontSize = 13, Margin = new Thickness(4, 0, 12, 0), VerticalAlignment = VerticalAlignment.Center });
            var entry = new Border { Child = item, Padding = new Thickness(6, 4, 6, 4), CornerRadius = new CornerRadius(5), Background = Brushes.Transparent, Cursor = Cursors.Hand, MinWidth = 160 };
            Ui.Hover(entry, Brushes.Transparent, Ui.Brush(Accent));
            entry.MouseLeftButtonUp += (_, _) =>
            {
                popup.IsOpen = false;
                selected = index;
                text.Text = options[index];
                set(index);
                Save();
            };
            menu.Children.Add(entry);
        }
        button.MouseLeftButtonUp += (_, _) =>
        {
            for (var i = 0; i < menu.Children.Count; i++)
                ((TextBlock)((DockPanel)((Border)menu.Children[i]).Child).Children[0]).Opacity = i == selected ? 1 : 0;
            popup.IsOpen = true;
        };
        return button;
    }

    /// <summary>A row with a thin Mac slider between the label and its value.</summary>
    static FrameworkElement SliderRow(string title, double value, double min, double max, double step, Action<double> set, Func<double, string> format)
    {
        var grid = new Grid { Margin = new Thickness(12, 0, 12, 0), MinHeight = 40 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(56) });
        grid.Children.Add(new TextBlock { Text = title, FontSize = 13, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 14, 0) });

        var readout = new TextBlock { Text = format(value), FontSize = 12, Foreground = Secondary, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
        readout.Typography.NumeralAlignment = FontNumeralAlignment.Tabular;
        Grid.SetColumn(readout, 2);
        grid.Children.Add(readout);

        var track = new Grid { Height = 22, Background = Brushes.Transparent, VerticalAlignment = VerticalAlignment.Center, Cursor = Cursors.Hand };
        var rail = new Border { Height = 4, CornerRadius = new CornerRadius(2), Background = Ui.White(0.15), VerticalAlignment = VerticalAlignment.Center };
        var fill = new Border { Height = 4, CornerRadius = new CornerRadius(2), Background = Ui.Brush(Accent), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
        var knob = new Border
        {
            Width = 18, Height = 18, CornerRadius = new CornerRadius(9), Background = Brushes.White, HorizontalAlignment = HorizontalAlignment.Left,
            Effect = new DropShadowEffect { BlurRadius = 4, ShadowDepth = 1, Opacity = 0.4, Direction = 270 },
        };
        track.Children.Add(rail);
        track.Children.Add(fill);
        track.Children.Add(knob);
        Grid.SetColumn(track, 1);
        grid.Children.Add(track);

        void Layout()
        {
            var f = (value - min) / (max - min);
            var usable = Math.Max(track.ActualWidth - 18, 0);
            knob.Margin = new Thickness(usable * f, 0, 0, 0);
            fill.Width = usable * f + 9;
        }
        void Drag(double x)
        {
            var usable = Math.Max(track.ActualWidth - 18, 1);
            var v = min + Math.Clamp((x - 9) / usable, 0, 1) * (max - min);
            v = Math.Round(v / step) * step;
            if (Math.Abs(v - value) < step / 2) return;
            value = Math.Clamp(v, min, max);
            readout.Text = format(value);
            Layout();
            set(value);
        }
        track.SizeChanged += (_, _) => Layout();
        track.MouseLeftButtonDown += (_, e) => { track.CaptureMouse(); Drag(e.GetPosition(track).X); };
        track.MouseMove += (_, e) => { if (track.IsMouseCaptured) Drag(e.GetPosition(track).X); };
        track.MouseLeftButtonUp += (_, _) => { if (track.IsMouseCaptured) { track.ReleaseMouseCapture(); Save(); } };
        return grid;
    }

    /// <summary>A Mac stepper: minus and plus joined in one rounded pill.</summary>
    static FrameworkElement Stepper(int value, int min, int max, int step, Action<int> set)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        var host = new Border
        {
            Child = row, CornerRadius = new CornerRadius(6), Background = Ui.White(0.1), BorderBrush = Ui.White(0.08),
            BorderThickness = new Thickness(1), ClipToBounds = true,
        };
        Border Button(string glyph, int delta)
        {
            var b = new Border { Child = Ui.Glyph(glyph, 10), Width = 28, Height = 24, Background = Brushes.Transparent, Cursor = Cursors.Hand };
            Ui.Hover(b, Brushes.Transparent, Ui.White(0.1));
            b.MouseLeftButtonUp += (_, _) =>
            {
                var next = Math.Clamp(value + delta, min, max);
                if (next == value) return;
                value = next;
                set(value);
                Save();
                // The row's label shows the count: refresh this page.
                if (host.Tag is Action refresh) refresh();
            };
            return b;
        }
        row.Children.Add(Button("", -step));
        row.Children.Add(new Border { Width = 1, Background = Ui.White(0.12) });
        row.Children.Add(Button("", step));
        host.Loaded += (_, _) =>
        {
            // Find the row's label and keep it in step with the value.
            if (host.Parent is DockPanel dock)
                foreach (var child in dock.Children)
                    if (child is StackPanel sp && sp.Children.Count > 0 && sp.Children[^1] is TextBlock label)
                        host.Tag = (Action)(() => label.Text = $"Keep {value} items");
        };
        return host;
    }

    // MARK: Window chrome

    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    /// <summary>A dark title bar, in the window's own colour on Windows 11.</summary>
    void DarkTitleBar()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        var on = 1;
        DwmSetWindowAttribute(hwnd, 20, ref on, sizeof(int)); // DWMWA_USE_IMMERSIVE_DARK_MODE
        var caption = 0x00272424; // COLORREF (BGR) of the toolbar
        DwmSetWindowAttribute(hwnd, 35, ref caption, sizeof(int)); // DWMWA_CAPTION_COLOR (Windows 11)
    }
}
