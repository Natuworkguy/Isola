using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using Isola.Services;
using Isola.Views;

namespace Isola;

public enum IslandTab { Home, Media, Tray, Clipboard, System }

/// <summary>
/// The island: a transparent, always-on-top window at the top of the screen holding one shape that springs between
/// its states (idle, playing, volume, banner, open). Windows lets clicks through the window's transparent pixels, so
/// only the island itself takes the mouse.
/// </summary>
sealed class IslandWindow : Window
{
    const double Pad = 40;
    public static readonly Size OpenSize = new(640, 290);

    readonly MediaService media;
    readonly FileTray tray;

    readonly Canvas canvas = new();
    readonly Canvas shadowHost = new() { IsHitTestVisible = false };
    readonly Path shadow = new() { Fill = Brushes.Black };
    readonly DropShadowEffect shadowEffect = new() { Color = Colors.Black, Direction = 270 };
    readonly Grid island = new() { Background = Brushes.Transparent };
    readonly Border solid = new() { Background = Brushes.Black };
    readonly Grid glass = new();
    // Dynamic Glass, over the blur from the backdrop: a tint that takes on the colour of what is behind the island, a
    // sheen, a glow in the top corner, the light that follows the pointer, a wide soft lens inside the edge where real
    // glass bends the light, shading at the bottom for depth, and a bright line just inside the rim.
    readonly Border glassTint = new(), glassSheen = new(), glassCorner = new(), glassHighlight = new() { Opacity = 0 };
    readonly GradientStop tintTop = new(Ui.Rgb(14, 14, 20, 138), 0), tintBottom = new(Ui.Rgb(8, 8, 12, 164), 1);
    readonly Path glassLens = new() { StrokeThickness = 14, IsHitTestVisible = false, Effect = new BlurEffect { Radius = 10 } };
    readonly Path glassDepth = new() { StrokeThickness = 12, IsHitTestVisible = false, Effect = new BlurEffect { Radius = 9 } };
    readonly DispatcherTimer tintTimer = new() { Interval = TimeSpan.FromMilliseconds(400) };
    Color shownTint = Ui.Rgb(14, 14, 20, 138);
    readonly RadialGradientBrush highlightBrush = new(Color.FromArgb(34, 255, 255, 255), Colors.Transparent) { RadiusX = 0.55, RadiusY = 1.1 };
    readonly Path glassEdge = new() { StrokeThickness = 3, IsHitTestVisible = false, Effect = new BlurEffect { Radius = 4 } };
    GlassBackdrop? backdrop;
    readonly Grid glow = new() { IsHitTestVisible = false };
    readonly Path rim = new() { StrokeThickness = 1, IsHitTestVisible = false };
    readonly CollapsedView collapsed = new();
    readonly HudView hudView = new();
    readonly BannerView bannerView = new();
    readonly CompactActivityView compactView = new();
    readonly ActivityCardView cardView = new();
    readonly PrivacyDotsView privacyDots = new();
    readonly Canvas stage = new() { ClipToBounds = false };
    readonly Grid expanded = new() { Width = OpenSize.Width, Height = OpenSize.Height };
    readonly ScaleTransform expandedScale = new(0.96, 0.96);
    readonly TabBar tabBar = new();
    readonly Grid content = new();
    readonly Border pinButton;
    readonly Border editButton;
    readonly HomeView homeView;
    readonly Dictionary<IslandTab, ITabView> views = new();
    readonly ClipboardView clipboardView;

    readonly DispatcherTimer hoverTimer = new();
    readonly DispatcherTimer leaveTimer = new() { Interval = TimeSpan.FromMilliseconds(350) };
    readonly DispatcherTimer bannerTimer = new();
    readonly DispatcherTimer hudTimer = new() { Interval = TimeSpan.FromSeconds(1.6) };
    readonly DispatcherTimer fullScreenTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    Native.WinEventProc? raised;
    IntPtr foregroundHook, restoreHook;
    readonly DispatcherTimer nearTimer = new() { Interval = TimeSpan.FromMilliseconds(50) };
    /// <summary>How far around the island the pointer counts as near it, in device-independent pixels.</summary>
    const double NearMargin = 12;
    bool pointerNear;
    bool clickThrough;
    readonly WheelWatcher wheel = new();
    double scrollToOpen;
    DateTime lastScrollToOpen;

    bool open, pinned, keyboardMode, hudShown, dragInside;
    // Opened from the keyboard: stays open until the pointer has visited it, or the shortcut is pressed again.
    bool heldOpen;
    bool hotKeyOn;
    double swipeX, swipeY;
    DateTime lastSwipe;
    bool swipeFired;
    Banner? banner;
    IslandTab tab = IslandTab.Home;

    // The shape, sprung: width, height, top, top radius, bottom radius; and the glass amount.
    readonly Spring w = new(150), h = new(30), top = new(8), rt = new(15), rb = new(15), glassAmount = new(0);
    TimeSpan lastFrame;
    bool animating;

    public Action<IntPtr, IntPtr>? DeviceChanged;

    public IslandWindow(MediaService media, FileTray tray, ClipboardService clipboard, SystemStats stats)
    {
        this.media = media;
        this.tray = tray;

        Title = "Isola";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ResizeMode = ResizeMode.NoResize;
        ShowActivated = false;
        Width = OpenSize.Width + Pad * 2;
        Height = OpenSize.Height + Pad + 12;
        FontFamily = Ui.Text;
        Place();

        // Shadow, drawn only outside the island so it never shows through the glass.
        shadow.Effect = shadowEffect;
        shadowHost.Children.Add(shadow);
        canvas.Children.Add(shadowHost);

        glass.Children.Add(glassTint);
        glass.Children.Add(glassDepth);
        glass.Children.Add(glassSheen);
        glass.Children.Add(glassCorner);
        glass.Children.Add(glassLens);
        glass.Children.Add(glassHighlight);
        glass.Children.Add(glassEdge);
        glassHighlight.Background = highlightBrush;
        glass.IsHitTestVisible = false;
        // The blur goes in a window of its own, just under this one. Made here, after this window, so that it is not
        // taken for the app's main window.
        backdrop = new GlassBackdrop();
        backdrop.Show();
        PaintGlass(backdrop.Available);
        tintTimer.Tick += (_, _) => UpdateTint();
        if (backdrop.Available) tintTimer.Start();
        glow.Effect = new BlurEffect { Radius = 28 };
        island.Children.Add(solid);
        island.Children.Add(glass);
        island.Children.Add(glow);
        island.Children.Add(collapsed);
        island.Children.Add(compactView);
        island.Children.Add(privacyDots);
        island.Children.Add(hudView);
        island.Children.Add(bannerView);
        island.Children.Add(cardView);
        island.Children.Add(stage);
        stage.Children.Add(expanded);
        expanded.RenderTransformOrigin = new Point(0.5, 0);
        expanded.RenderTransform = expandedScale;
        canvas.Children.Add(island);
        // Light catching the edge from the top left, and a fainter reflection of it at the bottom right.
        rim.Stroke = new LinearGradientBrush(new GradientStopCollection
        {
            new(Ui.Rgb(255, 255, 255, 170), 0), new(Ui.Rgb(255, 255, 255, 34), 0.3),
            new(Ui.Rgb(255, 255, 255, 14), 0.65), new(Ui.Rgb(255, 255, 255, 96), 1),
        }, new Point(0, 0), new Point(1, 1));
        canvas.Children.Add(rim);
        Content = canvas;

        homeView = new HomeView(media, clipboard, stats, tray, t => SelectTab(t, true));

        // The open island: tab bar with pin and settings (and on Home, the pencil), then the current tab.
        expanded.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        expanded.RowDefinitions.Add(new RowDefinition { Height = new GridLength(33) });
        expanded.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var header = new Grid();
        Grid.SetRow(header, 1);
        tabBar.HorizontalAlignment = HorizontalAlignment.Center;
        tabBar.Selected += t => SelectTab(t, true);
        header.Children.Add(tabBar);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 0, 22, 0), VerticalAlignment = VerticalAlignment.Center };
        pinButton = Ui.Round(Ui.Pin, 26, TogglePin);
        buttons.Children.Add(pinButton);
        var gear = Ui.Round(Ui.Gear, 26, () => Hub.OpenSettings());
        gear.Margin = new Thickness(6, 0, 0, 0);
        buttons.Children.Add(gear);
        header.Children.Add(buttons);
        editButton = Ui.Round(Ui.Edit, 26, () => homeView.ToggleEditing());
        editButton.HorizontalAlignment = HorizontalAlignment.Left;
        editButton.VerticalAlignment = VerticalAlignment.Center;
        editButton.Margin = new Thickness(22, 0, 0, 0);
        editButton.ToolTip = "Arrange widgets";
        header.Children.Add(editButton);
        expanded.Children.Add(header);
        Grid.SetRow(content, 2);
        content.Margin = new Thickness(30, 12, 30, 24);
        expanded.Children.Add(content);

        clipboardView = new ClipboardView(clipboard, SetKeyboard);
        homeView.EditingChanged += editing =>
        {
            editButton.Child = Ui.Glyph(Ui.Edit, 11, editing ? Brushes.Black : Ui.White(0.8));
            editButton.Background = editing ? Brushes.White : Ui.White(0.1);
            editButton.ToolTip = editing ? "Done" : "Arrange widgets";
            if (!editing && open && !pinned && !island.IsMouseOver) leaveTimer.Start();
        };
        views[IslandTab.Home] = homeView;
        views[IslandTab.Media] = new MediaView(media);
        views[IslandTab.Tray] = new TrayView(tray, this);
        views[IslandTab.Clipboard] = clipboardView;
        views[IslandTab.System] = new SystemView(stats);
        foreach (var v in views.Values)
        {
            v.Root.Opacity = 0;
            v.Root.Visibility = Visibility.Collapsed;
            content.Children.Add(v.Root);
        }

        foreach (var layer in new UIElement[] { collapsed, compactView, privacyDots, hudView, bannerView, cardView, expanded, glow }) { layer.Opacity = 0; layer.IsHitTestVisible = false; }

        // Pointer and drags.
        island.MouseEnter += (_, _) => PointerEntered();
        island.MouseLeave += (_, _) => PointerLeft();
        island.MouseLeftButtonUp += (_, _) =>
        {
            // A click on a banner or card puts it away. A click on an activity with steps shows its card; anywhere
            // else opens the island, unless clicks are turned off (then they go through it, and never get here).
            if (open) return;
            if (banner is not null) DismissBanner();
            else if (Activities.PeekId is not null) Activities.DismissPeek();
            else if (Activities.Compact(media.Primary?.IsPlaying == true) is { Steps.Count: > 0 } activity) Activities.Peek(activity.Id, 8);
            else if (Settings.Current.OpenWith == OpenWith.Click || Settings.Current.ClickOpens) Expand();
        };
        // Vertical swipes on a touchpad arrive as the mouse wheel. Inside the open island they only count on its top
        // edge, so lists and rows still scroll.
        island.PreviewMouseWheel += (_, e) =>
        {
            if (!open || Mouse.GetPosition(island).Y < 60) e.Handled = Swipe(0, e.Delta);
        };
        island.AllowDrop = true;
        island.DragEnter += OnDragEnter;
        island.DragLeave += (_, _) => { dragInside = false; PointerLeft(); };
        island.Drop += OnDrop;

        hoverTimer.Tick += (_, _) => { hoverTimer.Stop(); Expand(); };
        leaveTimer.Tick += (_, _) => { leaveTimer.Stop(); if (!island.IsMouseOver && !pinned && !keyboardMode && !dragInside && !homeView.Editing && !heldOpen) Collapse(); };
        bannerTimer.Tick += (_, _) => { bannerTimer.Stop(); DismissBanner(); };
        hudTimer.Tick += (_, _) => { hudTimer.Stop(); hudShown = false; Refresh(); };
        // Once a second too, for whatever raises itself without coming to the front.
        fullScreenTimer.Tick += (_, _) => { CheckFullScreen(); KeepOnTop(); };
        nearTimer.Tick += (_, _) => CheckNear();
        nearTimer.Start();
        wheel.Turned += WheelTurned;

        media.Changed += Refresh;
        Activities.Changed += Refresh;
        Settings.Changed += ApplySettings;
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += (_, _) => Dispatcher.BeginInvoke(Place);

        SourceInitialized += (_, _) =>
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            Native.SetWindowLong(hwnd, Native.GWL_EXSTYLE,
                Native.GetWindowLong(hwnd, Native.GWL_EXSTYLE) | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE);
            HwndSource.FromHwnd(hwnd)?.AddHook(Hook);
            // Whenever another window comes to the front (the taskbar, or an app that keeps itself on top), the island
            // goes back above it. Kept in a field so the collector never takes it while Windows still calls it.
            raised = (_, _, _, _, _, _, _) => Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(KeepOnTop));
            foregroundHook = Native.SetWinEventHook(Native.EVENT_SYSTEM_FOREGROUND, Native.EVENT_SYSTEM_FOREGROUND,
                IntPtr.Zero, raised, 0, 0, Native.WINEVENT_OUTOFCONTEXT | Native.WINEVENT_SKIPOWNPROCESS);
            restoreHook = Native.SetWinEventHook(Native.EVENT_SYSTEM_MINIMIZEEND, Native.EVENT_SYSTEM_MINIMIZEEND,
                IntPtr.Zero, raised, 0, 0, Native.WINEVENT_OUTOFCONTEXT | Native.WINEVENT_SKIPOWNPROCESS);
        };
        IsVisibleChanged += (_, _) => { UpdateBackdrop(); KeepOnTop(); };
        LocationChanged += (_, _) => UpdateBackdrop();
        Closed += (_, _) =>
        {
            if (foregroundHook != IntPtr.Zero) Native.UnhookWinEvent(foregroundHook);
            if (restoreHook != IntPtr.Zero) Native.UnhookWinEvent(restoreHook);
            backdrop?.Close();
            wheel.Dispose();
        };
        // The light on the glass follows the pointer.
        island.MouseMove += (_, e) =>
        {
            var p = e.GetPosition(island);
            var at = new Point(p.X / Math.Max(island.ActualWidth, 1), p.Y / Math.Max(island.ActualHeight, 1));
            highlightBrush.Center = at;
            highlightBrush.GradientOrigin = at;
        };
        island.MouseEnter += (_, _) => Ui.FadeTo(glassHighlight, 1, 250);
        island.MouseLeave += (_, _) => Ui.FadeTo(glassHighlight, 0, 400);
        Loaded += (_, _) =>
        {
            ApplySettings();
            fullScreenTimer.Start();
            SnapShape();
            SlideIn();
        };
    }

    /// At launch the island waits above the top edge of the screen, then slides down into place.
    void SlideIn()
    {
        var slide = new TranslateTransform(0, -(h.Value + top.Value + Pad));
        canvas.RenderTransform = slide;
        var down = new DoubleAnimation(0, TimeSpan.FromMilliseconds(650))
        {
            BeginTime = TimeSpan.FromMilliseconds(300),
            EasingFunction = new BackEase { Amplitude = 0.35, EasingMode = EasingMode.EaseOut },
        };
        // The blur follows the island down.
        EventHandler follow = (_, _) => UpdateBackdrop();
        CompositionTarget.Rendering += follow;
        down.Completed += (_, _) =>
        {
            CompositionTarget.Rendering -= follow;
            UpdateBackdrop();
        };
        slide.BeginAnimation(TranslateTransform.YProperty, down);
    }

    // MARK: Placement

    void Place()
    {
        var area = SystemParameters.WorkArea;
        Left = area.Left + (area.Width - Width) / 2;
        Top = area.Top;
    }

    IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == Native.WM_DEVICECHANGE) DeviceChanged?.Invoke(wParam, lParam);
        else if (msg == Native.WM_HOTKEY && wParam.ToInt64() == HotKeyId) ToggleFromKeyboard();
        else if (msg == Native.WM_MOUSEHWHEEL && island.IsMouseOver)
            handled = Swipe((short)((wParam.ToInt64() >> 16) & 0xFFFF), 0);
        return IntPtr.Zero;
    }

    const int HotKeyId = 1;
    public const string HotKeyText = "Ctrl+Alt+A";

    /// <summary>Ctrl+Alt+A opens and closes the island from anywhere, when switched on in Settings.</summary>
    void ApplyHotKey()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero || hotKeyOn == Settings.Current.HotKey) return;
        const uint alt = 0x1, control = 0x2, noRepeat = 0x4000;
        if (Settings.Current.HotKey)
            hotKeyOn = Native.RegisterHotKey(hwnd, HotKeyId, control | alt | noRepeat, 0x41);
        else
        {
            Native.UnregisterHotKey(hwnd, HotKeyId);
            hotKeyOn = false;
        }
    }

    void ToggleFromKeyboard()
    {
        if (open)
        {
            heldOpen = false;
            Collapse();
        }
        else
        {
            heldOpen = true;
            Expand();
        }
    }

    /// <summary>
    /// Swipes over the island, from a touchpad or a mouse wheel: down opens it, up on its top edge closes it, and
    /// sideways skips to the next or previous track while music plays. True when the swipe was used.
    /// </summary>
    bool Swipe(double dx, double dy)
    {
        if (!Settings.Current.Gestures) return false;
        if (DateTime.UtcNow - lastSwipe > TimeSpan.FromMilliseconds(350))
        {
            swipeX = swipeY = 0;
            swipeFired = false;
        }
        lastSwipe = DateTime.UtcNow;
        swipeX += dx;
        swipeY += dy;
        if (swipeFired) return true;
        var vertical = Math.Abs(swipeY) > Math.Abs(swipeX);
        var player = media.Primary;
        if (!open)
        {
            if (vertical && swipeY < -60) { swipeFired = true; Expand(); return true; }
            if (!vertical && Math.Abs(swipeX) >= 120 && player?.IsPlaying == true)
            {
                swipeFired = true;
                if (swipeX > 0) player.Next(); else player.Previous();
                return true;
            }
            return false;
        }
        var onTopEdge = Mouse.GetPosition(island).Y < 60;
        if (vertical && swipeY > 60 && onTopEdge && !pinned && !homeView.Editing)
        {
            swipeFired = true;
            heldOpen = false;
            Collapse();
            return true;
        }
        if (!vertical && Math.Abs(swipeX) >= 120 && tab == IslandTab.Media && player is not null)
        {
            swipeFired = true;
            if (swipeX > 0) player.Next(); else player.Previous();
            return true;
        }
        return false;
    }

    void ApplySettings()
    {
        ApplyHotKey();
        if (Settings.Current.OpenWith == OpenWith.Scroll) wheel.Start(); else wheel.Dispose();
        var tabs = new List<IslandTab>();
        if (Settings.Current.TabHome) tabs.Add(IslandTab.Home);
        if (Settings.Current.TabMedia) tabs.Add(IslandTab.Media);
        if (Settings.Current.TabTray) tabs.Add(IslandTab.Tray);
        if (Settings.Current.TabClipboard) tabs.Add(IslandTab.Clipboard);
        if (Settings.Current.TabSystem) tabs.Add(IslandTab.System);
        if (tabs.Count == 0) tabs.Add(IslandTab.Media);
        if (!tabs.Contains(tab)) tab = tabs[0];
        tabBar.SetTabs(tabs, tab);
        SelectTab(tab, false);
        Refresh();
    }

    /// <summary>
    /// Puts the island back at the top of the always-on-top windows, without taking the focus, and its blur just under
    /// it. Only the Start menu and the like, which Windows keeps above every app, still come over it.
    /// </summary>
    void KeepOnTop()
    {
        if (!IsVisible) return;
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero) return;
        Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, 0, 0, 0, 0,
            Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE | Native.SWP_NOOWNERZORDER);
        UpdateBackdrop();
    }

    void CheckFullScreen()
    {
        var hide = Settings.Current.HideInFullScreen && !open && Native.ForegroundIsFullScreen();
        var want = hide ? Visibility.Hidden : Visibility.Visible;
        if (Visibility != want) Visibility = want;
    }

    // MARK: Opening and closing

    void PointerEntered()
    {
        heldOpen = false;
        leaveTimer.Stop();
        if (Settings.Current.HideWhenIdle) Refresh();
        if (open || banner is not null || Settings.Current.OpenWith != OpenWith.Hover) return;
        hoverTimer.Interval = TimeSpan.FromSeconds(Math.Clamp(Settings.Current.HoverDelay, 0, 2));
        hoverTimer.Start();
    }

    /// <summary>
    /// With Near, the pointer only has to come within a few pixels of the island for it to open, as on the Mac. With
    /// either, the strip above the island up to the top of the screen counts too: aiming at the top of the screen,
    /// the pointer runs on to its edge. The island's own MouseEnter only sees the pointer once it is over the island,
    /// so this looks at the pointer itself.
    /// </summary>
    void CheckNear()
    {
        UpdateClickThrough();
        var s = Settings.Current;
        if (s.OpenWith == OpenWith.Click || !IsVisible)
        {
            pointerNear = false;
            return;
        }
        // Open, or showing a banner: counted as near, so an island closed under the pointer waits for it to leave
        // and come back before opening again.
        if (open || banner is not null)
        {
            pointerNear = true;
            return;
        }
        if (island.IsMouseOver || !Native.GetCursorPos(out var cursor)) return;
        var source = PresentationSource.FromVisual(island);
        if (source?.CompositionTarget is null) return;
        var scale = source.CompositionTarget.TransformToDevice;
        var margin = s.HoverArea == HoverArea.Near ? NearMargin : 0;
        var corner = island.PointToScreen(new Point(0, 0));
        var top = Math.Min(corner.Y - margin * scale.M22, PointToScreen(new Point(0, 0)).Y);
        var bottom = corner.Y + (island.ActualHeight + margin) * scale.M22;
        var near = new Rect(
            corner.X - margin * scale.M11, top,
            (island.ActualWidth + margin * 2) * scale.M11, bottom - top
        ).Contains(new Point(cursor.X, cursor.Y));
        if (near == pointerNear) return;
        pointerNear = near;
        if (near) PointerEntered();
        else hoverTimer.Stop();
    }

    /// <summary>
    /// With clicks turned off, a click on the closed island goes through to whatever is under it, unless a banner or
    /// card is up to be put away. CheckNear tells hovering from the pointer's place, and the wheel is watched from a
    /// hook, so hovering or scrolling still opens it.
    /// </summary>
    void UpdateClickThrough()
    {
        var s = Settings.Current;
        var through = !open && banner is null && Activities.PeekId is null
            && s.OpenWith != OpenWith.Click && !s.ClickOpens;
        if (through == clickThrough) return;
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero) return;
        clickThrough = through;
        var style = Native.GetWindowLong(hwnd, Native.GWL_EXSTYLE);
        Native.SetWindowLong(hwnd, Native.GWL_EXSTYLE,
            through ? style | Native.WS_EX_TRANSPARENT : style & ~Native.WS_EX_TRANSPARENT);
    }

    /// <summary>Set to open by scrolling: the wheel turned either way, or a swipe, near the closed island opens it.</summary>
    void WheelTurned(int delta)
    {
        if (open || Settings.Current.OpenWith != OpenWith.Scroll || !(pointerNear || island.IsMouseOver)) return;
        if (DateTime.UtcNow - lastScrollToOpen > TimeSpan.FromMilliseconds(350)) scrollToOpen = 0;
        lastScrollToOpen = DateTime.UtcNow;
        scrollToOpen += delta;
        if (Math.Abs(scrollToOpen) >= 60) Expand();
    }

    void PointerLeft()
    {
        hoverTimer.Stop();
        if (Settings.Current.HideWhenIdle) Refresh();
        if (open && !pinned && !keyboardMode && !homeView.Editing) leaveTimer.Start();
    }

    public void Expand()
    {
        if (open) return;
        open = true;
        UpdateClickThrough();
        views[tab].Shown();
        Refresh();
    }

    public void Collapse()
    {
        if (!open) return;
        open = false;
        UpdateClickThrough();
        SetKeyboard(false);
        views[tab].Hidden();
        Refresh();
    }

    void TogglePin()
    {
        pinned = !pinned;
        pinButton.Child = Ui.Glyph(pinned ? Ui.Pinned : Ui.Pin, 11, pinned ? Brushes.Black : Ui.White(0.8));
        pinButton.Background = pinned ? Brushes.White : Ui.White(0.1);
        if (!pinned && !island.IsMouseOver) leaveTimer.Start();
    }

    /// <summary>The clipboard search field needs the keyboard; the island otherwise never takes it from other apps.</summary>
    void SetKeyboard(bool on)
    {
        if (keyboardMode == on) return;
        keyboardMode = on;
        var hwnd = new WindowInteropHelper(this).Handle;
        var style = Native.GetWindowLong(hwnd, Native.GWL_EXSTYLE);
        Native.SetWindowLong(hwnd, Native.GWL_EXSTYLE, on ? style & ~Native.WS_EX_NOACTIVATE : style | Native.WS_EX_NOACTIVATE);
        if (on)
        {
            Activate();
            Native.SetForegroundWindow(hwnd);
        }
        else if (!island.IsMouseOver && !pinned) leaveTimer.Start();
    }

    void SelectTab(IslandTab next, bool animate)
    {
        var previous = tab;
        tab = next;
        tabBar.Select(next, animate);
        Ui.FadeTo(editButton, next == IslandTab.Home ? 1 : 0, animate ? 200 : 0);
        foreach (var (t, view) in views)
        {
            var on = t == next;
            if (on)
            {
                view.Root.Visibility = Visibility.Visible;
                view.Root.Effect = animate ? new BlurEffect { Radius = 10 } : null;
                view.Root.BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(animate ? 350 : 0)));
                if (view.Root.Effect is BlurEffect blur)
                    blur.BeginAnimation(BlurEffect.RadiusProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(350)));
                if (open) view.Shown();
            }
            else if (view.Root.Visibility == Visibility.Visible)
            {
                var fade = new DoubleAnimation(0, TimeSpan.FromMilliseconds(animate ? 200 : 0));
                var root = view.Root;
                fade.Completed += (_, _) => { if (tab != t) root.Visibility = Visibility.Collapsed; };
                root.BeginAnimation(OpacityProperty, fade);
                if (t == previous && open) view.Hidden();
            }
        }
        Refresh();
    }

    // MARK: Drags

    void OnDragEnter(object sender, DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(DataFormats.FileDrop)) return;
        dragInside = true;
        e.Effects = DragDropEffects.Copy;
        if (!open && Settings.Current.ExpandOnFileDrag && Settings.Current.TabTray)
        {
            SelectTab(IslandTab.Tray, false);
            Expand();
        }
    }

    void OnDrop(object sender, DragEventArgs e)
    {
        dragInside = false;
        if (e.Handled || e.Data.GetData(DataFormats.FileDrop) is not string[] files) return;
        tray.Add(files);
        if (!open) ShowBanner(new Banner(Ui.Download, Ui.Blue, "Added to the tray",
            files.Length == 1 ? System.IO.Path.GetFileName(files[0]) : $"{files.Length} files"), 3);
    }

    // MARK: Banners and the HUD

    public void ShowBanner(Banner b, double seconds)
    {
        if (banner is { } old && old.Id != b.Id) old.OnDismiss?.Invoke();
        banner = b;
        bannerView.Show(b, DismissBanner);
        bannerTimer.Stop();
        bannerTimer.Interval = TimeSpan.FromSeconds(seconds);
        bannerTimer.Start();
        Refresh();
    }

    void DismissBanner()
    {
        banner?.OnDismiss?.Invoke();
        banner = null;
        bannerTimer.Stop();
        Refresh();
    }

    public void ShowHud(HudKind kind, double level, bool muted)
    {
        hudView.Show(kind, level, muted);
        hudShown = true;
        hudTimer.Stop();
        hudTimer.Start();
        Refresh();
    }

    // MARK: State to shape

    enum Mode { Idle, Playing, Activity, Hud, Banner, Card, Open }

    Mode Current =>
        open ? Mode.Open
        : banner is not null ? Mode.Banner
        : Activities.Peeked is not null ? Mode.Card
        : hudShown ? Mode.Hud
        : Activities.Compact(media.Primary?.IsPlaying == true) is not null ? Mode.Activity
        : media.Primary?.IsPlaying == true ? Mode.Playing
        : Activities.ShownPrivacy.Count > 0 ? Mode.Activity
        : Mode.Idle;

    void Refresh()
    {
        var mode = Current;
        var floating = Settings.Current.Style == IslandStyle.Floating;
        var glassy = Settings.Current.Material == IslandMaterial.Glass;
        double width, height, bottom;
        switch (mode)
        {
            case Mode.Open: (width, height, bottom) = (OpenSize.Width, OpenSize.Height, 32); break;
            case Mode.Banner:
                var buttons = (banner!.Action is null ? 0 : 1) + (banner.SecondAction is null ? 0 : 1);
                (width, height, bottom) = (buttons > 1 ? 460 : buttons == 1 ? 400 : 360, 64, 26);
                break;
            case Mode.Card: (width, height, bottom) = (ActivityCardView.Width_, ActivityCardView.HeightFor(Activities.Peeked!), 26); break;
            case Mode.Hud: (width, height, bottom) = (300, 36, 18); break;
            case Mode.Playing or Mode.Activity: (width, height, bottom) = (230, 34, 17); break;
            default: (width, height, bottom) = (Math.Clamp(Settings.Current.IdleWidth, 80, 260), Math.Clamp(Settings.Current.IdleHeight, 20, 44), 14); break;
        }
        var collapsedShape = mode is Mode.Idle or Mode.Playing or Mode.Activity or Mode.Hud;
        w.Target = width;
        h.Target = height;
        top.Target = floating ? Math.Clamp(Settings.Current.TopGap, 0, 12) : 0;
        rb.Target = floating && collapsedShape ? height / 2 : (collapsedShape ? 12 : bottom);
        rt.Target = floating ? rb.Target : 0;
        // Glass or solid black in every style, floating or attached to the top edge.
        glassAmount.Target = glassy ? 1 : 0;

        if (mode == Mode.Playing || mode == Mode.Open) collapsed.Show(media.Primary);
        collapsed.Active(mode == Mode.Playing);
        Ui.FadeTo(collapsed, mode == Mode.Playing ? 1 : 0, mode == Mode.Playing ? 300 : 150);
        var shownPrivacy = Activities.ShownPrivacy;
        var dots = shownPrivacy.Count > 0 && mode is Mode.Playing or Mode.Activity;
        compactView.Show(mode == Mode.Activity ? Activities.Compact(media.Primary?.IsPlaying == true) : null, dots);
        Ui.FadeTo(compactView, mode == Mode.Activity ? 1 : 0, mode == Mode.Activity ? 300 : 150);
        privacyDots.Show(shownPrivacy);
        Ui.FadeTo(privacyDots, dots ? 1 : 0, 250);
        privacyDots.IsHitTestVisible = false;
        if (mode == Mode.Card) cardView.Show(Activities.Peeked!);
        Ui.FadeTo(cardView, mode == Mode.Card ? 1 : 0, mode == Mode.Card ? 300 : 150);
        Ui.FadeTo(hudView, mode == Mode.Hud ? 1 : 0, 200);
        Ui.FadeTo(bannerView, mode == Mode.Banner ? 1 : 0, mode == Mode.Banner ? 300 : 150);
        Ui.FadeTo(expanded, mode == Mode.Open ? 1 : 0, mode == Mode.Open ? 300 : 180);
        expandedScale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(mode == Mode.Open ? 1 : 0.96, TimeSpan.FromMilliseconds(400)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        expandedScale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(mode == Mode.Open ? 1 : 0.96, TimeSpan.FromMilliseconds(400)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        expanded.Margin = new Thickness(0, floating ? 2 : 0, 0, 0);
        expanded.RowDefinitions[0].Height = new GridLength(floating ? 14 : 12);

        // Ambient glow from the artwork, on the Media tab.
        var p = media.Primary;
        var glowOn = mode == Mode.Open && tab == IslandTab.Media && Settings.Current.TintFromArtwork && p?.Artwork is not null;
        if (p is not null) PaintGlow(p.Tint);
        Ui.FadeTo(glow, glowOn ? 1 : 0, 500);
        glow.IsHitTestVisible = false;

        var hidden = mode == Mode.Idle && Settings.Current.HideWhenIdle && !island.IsMouseOver;
        island.Opacity = 1;
        canvas.Opacity = hidden ? 0.02 : 1;
        UpdateBackdrop();
        StartAnimating();
    }

    /// <summary>
    /// Dynamic Glass. Over the real blur, a tint that follows what is behind (UpdateTint), a sheen from the top and a
    /// glow in the top corner as on the Mac, a lens of light inside the edge and shading at the bottom. Without the
    /// blur, a deeper, fixed tint stands in for it.
    /// </summary>
    void PaintGlass(bool blurred)
    {
        glassTint.Background = new LinearGradientBrush(blurred
            ? new GradientStopCollection { tintTop, tintBottom }
            : new GradientStopCollection { new(Ui.Rgb(38, 38, 46, 214), 0), new(Ui.Rgb(16, 16, 20, 230), 1) }, 90);
        glassLens.Stroke = new LinearGradientBrush(new GradientStopCollection
        {
            new(Ui.Rgb(255, 255, 255, blurred ? (byte)30 : (byte)14), 0), new(Ui.Rgb(255, 255, 255, blurred ? (byte)12 : (byte)6), 1),
        }, 90);
        glassDepth.Stroke = new LinearGradientBrush(new GradientStopCollection
        {
            new(Ui.Rgb(0, 0, 0, 0), 0), new(Ui.Rgb(0, 0, 0, 0), 0.55), new(Ui.Rgb(0, 0, 0, 70), 1),
        }, 90);
        glassSheen.Background = new LinearGradientBrush(new GradientStopCollection
        {
            new(Ui.Rgb(255, 255, 255, 46), 0), new(Ui.Rgb(255, 255, 255, 8), 0.35), new(Ui.Rgb(255, 255, 255, 0), 0.5),
        }, 90);
        glassCorner.Background = new RadialGradientBrush(Ui.Rgb(255, 255, 255, 26), Colors.Transparent)
        {
            Center = new Point(0, 0), GradientOrigin = new Point(0, 0), RadiusX = 0.7, RadiusY = 1.4,
        };
        glassEdge.Stroke = new LinearGradientBrush(new GradientStopCollection
        {
            new(Ui.Rgb(255, 255, 255, blurred ? (byte)80 : (byte)40), 0), new(Ui.Rgb(255, 255, 255, blurred ? (byte)22 : (byte)10), 1),
        }, 90);
    }

    /// <summary>Keeps the blur exactly under the island, or takes it away when the island is solid, hidden or gone.</summary>
    void UpdateBackdrop()
    {
        if (backdrop is not { Available: true }) return;
        var show = IsVisible && glassAmount.Value >= 0.5 && canvas.Opacity > 0.5;
        var source = show ? PresentationSource.FromVisual(island) : null;
        if (source?.CompositionTarget is null)
        {
            backdrop.Conceal();
            return;
        }
        var toDevice = source.CompositionTarget.TransformToDevice;
        var corner = island.PointToScreen(new Point(0, 0));
        backdrop.Cover(new WindowInteropHelper(this).Handle,
            (int)Math.Round(corner.X), (int)Math.Round(corner.Y),
            (int)Math.Round(w.Value * toDevice.M11), (int)Math.Round(h.Value * toDevice.M22),
            rt.Value * toDevice.M11, rb.Value * toDevice.M11);
    }

    /// <summary>
    /// Reads the colours just outside the island, beyond its shadow, and lets the tint drift towards them: the glass
    /// takes on a deep shade of what is under it, denser over bright windows so white text stays clear, and clearer
    /// over dark ones.
    /// </summary>
    void UpdateTint()
    {
        if (backdrop is not { Available: true } || !IsVisible || glassAmount.Value < 0.5 || canvas.Opacity < 0.5) return;
        var source = PresentationSource.FromVisual(island);
        if (source?.CompositionTarget is null) return;
        var toDevice = source.CompositionTarget.TransformToDevice;
        var corner = island.PointToScreen(new Point(0, 0));
        int x = (int)Math.Round(corner.X), y = (int)Math.Round(corner.Y);
        int width = (int)Math.Round(w.Value * toDevice.M11), height = (int)Math.Round(h.Value * toDevice.M22);
        var reach = (int)Math.Ceiling((shadowEffect.BlurRadius + shadowEffect.ShadowDepth + 6) * toDevice.M11);
        var band = Math.Max((int)Math.Round(4 * toDevice.M11), 2);
        var behind = GlassBackdrop.SampleAround(new[]
        {
            new Int32Rect(x, y + height + reach, width, band),
            new Int32Rect(x - reach - band, y, band, height),
            new Int32Rect(x + width + reach, y, band, height),
        });
        if (behind is not { } seen) return;
        var (top, bottom) = DynamicTint(seen);
        if (Math.Abs(top.R - shownTint.R) + Math.Abs(top.G - shownTint.G) + Math.Abs(top.B - shownTint.B) + Math.Abs(top.A - shownTint.A) < 8) return;
        shownTint = top;
        var ease = new SineEase { EasingMode = EasingMode.EaseInOut };
        tintTop.BeginAnimation(GradientStop.ColorProperty, new ColorAnimation(top, TimeSpan.FromMilliseconds(700)) { EasingFunction = ease });
        tintBottom.BeginAnimation(GradientStop.ColorProperty, new ColorAnimation(bottom, TimeSpan.FromMilliseconds(700)) { EasingFunction = ease });
    }

    /// <summary>The glass's tint over a background of colour BEHIND: its top and bottom.</summary>
    public static (Color Top, Color Bottom) DynamicTint(Color behind)
    {
        double r = behind.R / 255.0, g = behind.G / 255.0, b = behind.B / 255.0;
        var light = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        // How much of the background's colour the glass keeps: plenty over dark colours, little over bright ones,
        // where the tint has to stay dark for white text to read.
        var keep = 0.12 + 0.30 * (1 - light);
        byte Mix(double c, double dark) => (byte)Math.Round(Math.Clamp(c * 255 * keep + dark * (1 - keep), 0, 255));
        var alpha = 0.42 + 0.24 * light;
        var top = Color.FromArgb((byte)Math.Round(alpha * 255), Mix(r, 14), Mix(g, 14), Mix(b, 20));
        var bottom = Color.FromArgb((byte)Math.Round(Math.Min(alpha + 0.09, 0.8) * 255), Mix(r, 8), Mix(g, 8), Mix(b, 12));
        return (top, bottom);
    }

    void PaintGlow(Color tint)
    {
        glow.Background = null;
        glow.Children.Clear();
        glow.Children.Add(new Border
        {
            Background = new RadialGradientBrush(Color.FromArgb(140, tint.R, tint.G, tint.B), Colors.Transparent)
            {
                Center = new Point(0, 1), GradientOrigin = new Point(0, 1), RadiusX = 0.8, RadiusY = 1.2,
            },
        });
        glow.Children.Add(new Border
        {
            Background = new RadialGradientBrush(Color.FromArgb(70, tint.R, tint.G, tint.B), Colors.Transparent)
            {
                Center = new Point(1, 0), GradientOrigin = new Point(1, 0), RadiusX = 0.6, RadiusY = 0.9,
            },
        });
    }

    void StartAnimating()
    {
        if (animating) return;
        animating = true;
        lastFrame = TimeSpan.Zero;
        CompositionTarget.Rendering += OnFrame;
    }

    void OnFrame(object? sender, EventArgs e)
    {
        var now = ((RenderingEventArgs)e).RenderingTime;
        var dt = lastFrame == TimeSpan.Zero ? 1 / 60.0 : Math.Clamp((now - lastFrame).TotalSeconds, 0, 0.05);
        lastFrame = now;
        if (dt <= 0) return;
        var moving = false;
        foreach (var s in new[] { w, h, top, rt, rb }) moving |= s.Step(dt, 0.5, 0.8);
        moving |= glassAmount.Step(dt, 0.3, 1);
        ApplyShape();
        if (!moving)
        {
            CompositionTarget.Rendering -= OnFrame;
            animating = false;
        }
    }

    void SnapShape()
    {
        Refresh();
        foreach (var s in new[] { w, h, top, rt, rb, glassAmount }) s.Snap();
        ApplyShape();
    }

    void ApplyShape()
    {
        var x = (Width - w.Value) / 2;
        Canvas.SetLeft(island, x);
        Canvas.SetTop(island, top.Value);
        island.Width = Math.Max(w.Value, 1);
        island.Height = Math.Max(h.Value, 1);
        island.Clip = Ui.Outline(0, 0, w.Value, h.Value, rt.Value, rb.Value);
        Canvas.SetLeft(expanded, (w.Value - OpenSize.Width) / 2);

        var g = Math.Clamp(glassAmount.Value, 0, 1);
        glass.Opacity = g;
        solid.Opacity = 1 - g;
        glassEdge.Data = Ui.Outline(1.5, 1.5, w.Value - 3, h.Value - 3, Math.Max(rt.Value - 1.5, 0), Math.Max(rb.Value - 1.5, 0));
        glassLens.Data = glassDepth.Data = Ui.Outline(0, 0, w.Value, h.Value, rt.Value, rb.Value);
        UpdateBackdrop();

        var outline = Ui.Outline(x, top.Value, w.Value, h.Value, rt.Value, rb.Value);
        rim.Data = Ui.Outline(x + 0.5, top.Value + 0.5, w.Value - 1, h.Value - 1, rt.Value, rb.Value);
        var big = Math.Clamp((h.Value - 36) / 30, 0, 1);
        var floating = Settings.Current.Style == IslandStyle.Floating ? 1.0 : Math.Clamp(top.Value / 4, 0, 1);
        rim.Opacity = Math.Max(Math.Max(big, floating), 0.7 * g) * (0.35 + 0.65 * g);
        // Attached to the top edge, the island's top is the screen's edge, so the rim leaves it out.
        rim.Clip = floating >= 1 ? null : new RectangleGeometry(new Rect(0, top.Value + 1.5, Width, Height));

        shadow.Data = outline;
        shadowEffect.BlurRadius = 10 + 26 * big;
        shadowEffect.ShadowDepth = 2 + 8 * big;
        shadowEffect.Opacity = Math.Max(floating * 0.25, 0.42 * big);
        var everything = new RectangleGeometry(new Rect(0, 0, Width, Height));
        shadowHost.Clip = new CombinedGeometry(GeometryCombineMode.Exclude, everything, outline);
    }

    sealed class Spring
    {
        public double Value, Velocity, Target;
        public Spring(double v) { Value = Target = v; }

        /// <summary>One step of SwiftUI's spring(response:dampingFraction:). True while still moving.</summary>
        public bool Step(double dt, double response, double damping)
        {
            var omega = 2 * Math.PI / response;
            const int sub = 4;
            var d = dt / sub;
            for (var i = 0; i < sub; i++)
            {
                var accel = -2 * damping * omega * Velocity - omega * omega * (Value - Target);
                Velocity += accel * d;
                Value += Velocity * d;
            }
            if (Math.Abs(Value - Target) < 0.05 && Math.Abs(Velocity) < 0.5)
            {
                Value = Target;
                Velocity = 0;
                return false;
            }
            return true;
        }

        public void Snap() { Value = Target; Velocity = 0; }
    }
}

/// <summary>The open island's tabs, with a white highlight that glides to the chosen one.</summary>
sealed class TabBar : Border
{
    readonly Canvas layer = new() { IsHitTestVisible = false };
    readonly Border highlight = new() { Background = Brushes.White, CornerRadius = new CornerRadius(13.5), Height = 27 };
    readonly StackPanel row = new() { Orientation = Orientation.Horizontal };
    readonly List<(IslandTab tab, Border button, TextBlock icon, TextBlock label)> items = new();
    IslandTab current;

    public event Action<IslandTab>? Selected;

    static (string glyph, string title) Describe(IslandTab t) => t switch
    {
        IslandTab.Home => (Ui.Home, "Home"),
        IslandTab.Media => (Ui.Media, "Media"),
        IslandTab.Tray => (Ui.Folder, "File Tray"),
        IslandTab.Clipboard => (Ui.Paste, "Clipboard"),
        _ => (Ui.Gauge, "System"),
    };

    public TabBar()
    {
        Background = Ui.White(0.1);
        BorderBrush = Ui.White(0.1);
        BorderThickness = new Thickness(0.5);
        Padding = new Thickness(3);
        Ui.Capsule(this);
        VerticalAlignment = VerticalAlignment.Center;
        highlight.Effect = Ui.Glow(Colors.White, 12, 0.35);
        Canvas.SetLeft(highlight, 0);
        highlight.Width = 0;
        layer.Children.Add(highlight);
        var stack = new Grid();
        stack.Children.Add(layer);
        stack.Children.Add(row);
        Child = stack;
    }

    public void SetTabs(IReadOnlyList<IslandTab> tabs, IslandTab selected)
    {
        row.Children.Clear();
        items.Clear();
        foreach (var t in tabs)
        {
            var (glyph, title) = Describe(t);
            var icon = Ui.Glyph(glyph, 12);
            var label = new TextBlock
            {
                Text = title, FontFamily = Ui.Text, FontSize = 12, FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(5, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center,
            };
            var content = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            content.Children.Add(icon);
            content.Children.Add(label);
            var button = new Border
            {
                Child = content, Padding = new Thickness(11, 0, 11, 0), Height = 27, Background = Brushes.Transparent,
                Cursor = Cursors.Hand, Margin = new Thickness(0, 0, 2, 0),
            };
            var captured = t;
            button.MouseLeftButtonUp += (_, e) => { e.Handled = true; Selected?.Invoke(captured); };
            row.Children.Add(button);
            items.Add((t, button, icon, label));
        }
        Select(selected, false);
    }

    public void Select(IslandTab tab, bool animate)
    {
        current = tab;
        foreach (var (t, _, icon, label) in items)
        {
            var on = t == tab;
            label.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
            icon.Foreground = on ? Brushes.Black : Ui.White(0.72);
            label.Foreground = Brushes.Black;
        }
        // Glide once the new widths are laid out.
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, () => Glide(animate));
    }

    void Glide(bool animate)
    {
        var item = items.FirstOrDefault(i => i.tab == current);
        if (item.button is null || !item.button.IsLoaded) return;
        var x = item.button.TranslatePoint(new Point(0, 0), row).X;
        var width = item.button.ActualWidth;
        var ease = new BackEase { Amplitude = 0.25, EasingMode = EasingMode.EaseOut };
        var ms = TimeSpan.FromMilliseconds(animate ? 420 : 0);
        highlight.BeginAnimation(Canvas.LeftProperty, new DoubleAnimation(x, ms) { EasingFunction = ease });
        highlight.BeginAnimation(WidthProperty, new DoubleAnimation(width, ms) { EasingFunction = ease });
    }
}
