using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using Windows.UI.Notifications;
using Windows.UI.Notifications.Management;

namespace Isola.Services;

/// <summary>
/// More moments worth a glance, each switched on and off in Settings: the camera and microphone in use, downloads,
/// screenshots, the network, displays, Caps Lock, the keyboard layout, low storage, Do Not Disturb, and alarms and
/// timers from the Clock app.
/// </summary>
public sealed class SystemActivities
{
    [DllImport("user32.dll")] static extern short GetKeyState(int key);
    [DllImport("user32.dll")] static extern IntPtr GetKeyboardLayout(uint thread);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint process);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);

    const int CapitalKey = 0x14, MonitorCount = 80;

    readonly Dispatcher dispatcher = Application.Current.Dispatcher;
    readonly Action<Banner, double> showBanner;
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(250) };
    readonly List<FileSystemWatcher> watchers = new();
    readonly HashSet<string> pendingDownloads = new(), pendingShots = new();
    readonly DispatcherTimer downloadsSettle = new() { Interval = TimeSpan.FromSeconds(1) };
    readonly DispatcherTimer shotsSettle = new() { Interval = TimeSpan.FromSeconds(1) };
    long ticks;

    /// <summary>Whether Windows let Isola read notifications, for the Clock app. Null until it has asked.</summary>
    public static bool? NotificationAccess { get; private set; }

    public SystemActivities(Action<Banner, double> showBanner)
    {
        this.showBanner = showBanner;
    }

    public void Start()
    {
        capsLock = (GetKeyState(CapitalKey) & 1) != 0;
        layout = CurrentLayout();
        monitors = GetSystemMetrics(MonitorCount);
        (online, network) = NetworkState();
        dnd = DoNotDisturb();
        timer.Tick += (_, _) => Tick();
        timer.Start();
        NetworkChange.NetworkAddressChanged += (_, _) => dispatcher.BeginInvoke(NetworkChanged);
        NetworkChange.NetworkAvailabilityChanged += (_, _) => dispatcher.BeginInvoke(NetworkChanged);
        SystemEvents.DisplaySettingsChanged += (_, _) => dispatcher.BeginInvoke(DisplaysChanged);
        downloadsSettle.Tick += (_, _) => Settled(pendingDownloads, downloadsSettle, Downloaded);
        shotsSettle.Tick += (_, _) => Settled(pendingShots, shotsSettle, ScreenshotSaved);
        Settings.Changed += Watch;
        Watch();
        StartClockApp();
    }

    void Banner(string glyph, Color tint, string title, string subtitle, double seconds = 3, BannerAction? action = null) =>
        showBanner(new Banner(glyph, tint, title, subtitle, action), seconds);

    /// <summary>Caps Lock four times a second; the rest every few seconds or minutes.</summary>
    void Tick()
    {
        ticks++;
        CheckCapsLock();
        if (ticks % 2 == 0) CheckLayout();
        if (ticks % 6 == 0) CheckClockApp();
        if (ticks % 8 == 0) CheckPrivacy();
        if (ticks % 12 == 0) CheckDoNotDisturb();
        if (ticks == 40 || ticks % 2400 == 0) CheckDiskSpace();
    }

    // MARK: Caps Lock and the keyboard layout

    bool capsLock;
    string layout = "";

    void CheckCapsLock()
    {
        var now = (GetKeyState(CapitalKey) & 1) != 0;
        if (now == capsLock) return;
        capsLock = now;
        if (Settings.Current.LiveCapsLock)
            Banner("\uE8A2", now ? Ui.Green : Ui.Gray, now ? "Caps Lock on" : "Caps Lock off", "", 1.5);
    }

    static string CurrentLayout()
    {
        try
        {
            var thread = GetWindowThreadProcessId(Native.GetForegroundWindow(), out _);
            var language = (int)(GetKeyboardLayout(thread).ToInt64() & 0xFFFF);
            return language == 0 ? "" : CultureInfo.GetCultureInfo(language).DisplayName;
        }
        catch { return ""; }
    }

    void CheckLayout()
    {
        var now = CurrentLayout();
        if (now.Length == 0 || now == layout) return;
        layout = now;
        if (Settings.Current.LiveKeyboard) Banner("\uE765", Ui.Rgb(94, 92, 230), now, "Keyboard", 1.6);
    }

    // MARK: Camera and microphone

    bool camera, microphone;

    void CheckPrivacy()
    {
        if (!Settings.Current.LivePrivacy)
        {
            camera = microphone = false;
            Activities.SetPrivacy(Privacy.Camera, false);
            Activities.SetPrivacy(Privacy.Microphone, false);
            return;
        }
        var cameraNow = InUse("webcam");
        var micNow = InUse("microphone");
        if (cameraNow != camera)
        {
            camera = cameraNow;
            Activities.SetPrivacy(Privacy.Camera, cameraNow);
            if (cameraNow) Banner("\uE714", Ui.Green, "Camera in use", "The green dot stays while it is on", 2.5);
        }
        if (micNow != microphone)
        {
            microphone = micNow;
            Activities.SetPrivacy(Privacy.Microphone, micNow);
            // A moment's wait first, for the Live Activity of whatever opened it (a voice assistant listening) to arrive
            // and show it instead.
            if (micNow && !cameraNow)
            {
                var wait = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
                wait.Tick += (_, _) =>
                {
                    wait.Stop();
                    if (microphone && !camera && !Activities.MicrophoneShown)
                        Banner("\uE720", Ui.Orange, "Microphone in use", "The orange dot stays while it is on", 2.5);
                };
                wait.Start();
            }
        }
    }

    /// <summary>
    /// Windows records when each app last started and stopped using the camera or microphone. A start with no stop
    /// means it is in use right now. These are the same records the privacy icon in the taskbar comes from.
    /// </summary>
    static bool InUse(string capability)
    {
        try
        {
            using var store = Registry.CurrentUser.OpenSubKey($@"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\{capability}");
            if (store is null) return false;
            return AnyRunning(store) || (store.OpenSubKey("NonPackaged") is { } nonPackaged && Using(nonPackaged, AnyRunning));
        }
        catch { return false; }
    }

    static bool Using(RegistryKey key, Func<RegistryKey, bool> check)
    {
        using (key) return check(key);
    }

    static bool AnyRunning(RegistryKey parent)
    {
        foreach (var name in parent.GetSubKeyNames())
        {
            if (name == "NonPackaged") continue;
            using var app = parent.OpenSubKey(name);
            if (app?.GetValue("LastUsedTimeStart") is long start && start > 0 && app.GetValue("LastUsedTimeStop") is long stop && stop == 0)
                return true;
        }
        return false;
    }

    // MARK: Network and displays

    bool online;
    string network = "";
    int monitors;

    static (bool online, string name) NetworkState()
    {
        var up = NetworkInterface.GetIsNetworkAvailable();
        var name = "";
        try { name = Windows.Networking.Connectivity.NetworkInformation.GetInternetConnectionProfile()?.ProfileName ?? ""; } catch { }
        return (up && name.Length > 0, name);
    }

    void NetworkChanged()
    {
        var (nowOnline, nowName) = NetworkState();
        if (nowOnline == online && nowName == network) return;
        var wasOnline = online;
        (online, network) = (nowOnline, nowName);
        if (!Settings.Current.LiveNetwork) return;
        if (wasOnline && !nowOnline) Banner("\uEB55", Ui.Red, "Offline", "The island will say when you are back");
        else if (!wasOnline && nowOnline) Banner("\uE701", Ui.Green, "Back online", nowName);
        else if (nowOnline) Banner("\uE701", Ui.Blue, "Now on " + nowName, "", 2.5);
    }

    void DisplaysChanged()
    {
        var now = GetSystemMetrics(MonitorCount);
        if (now == monitors) return;
        var more = now > monitors;
        monitors = now;
        if (Settings.Current.LiveDisplays)
            Banner("\uE7F4", more ? Ui.Blue : Ui.Gray, more ? "Display connected" : "Display disconnected",
                now == 1 ? "1 display" : $"{now} displays");
    }

    // MARK: Downloads and screenshots

    static readonly HashSet<string> Partial = new(StringComparer.OrdinalIgnoreCase) { ".crdownload", ".part", ".partial", ".tmp", ".download", ".opdownload" };

    void Watch()
    {
        foreach (var w in watchers) w.Dispose();
        watchers.Clear();
        if (Settings.Current.LiveDownloads) Add(DownloadsFolder(), pendingDownloads, downloadsSettle);
        if (Settings.Current.LiveScreenshots)
        {
            Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots"), pendingShots, shotsSettle);
            Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), "Captures"), pendingShots, shotsSettle);
            Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), "Screen Recordings"), pendingShots, shotsSettle);
        }
    }

    void Add(string folder, HashSet<string> pending, DispatcherTimer settle)
    {
        if (!Directory.Exists(folder)) return;
        try
        {
            var watcher = new FileSystemWatcher(folder) { IncludeSubdirectories = false, EnableRaisingEvents = false };
            void Seen(string path) => dispatcher.BeginInvoke(() =>
            {
                var name = Path.GetFileName(path);
                if (name.StartsWith('.') || name.StartsWith('~') || Partial.Contains(Path.GetExtension(path))) return;
                pending.Add(path);
                settle.Stop();
                settle.Start();
            });
            watcher.Created += (_, e) => Seen(e.FullPath);
            watcher.Renamed += (_, e) => Seen(e.FullPath);
            watcher.EnableRaisingEvents = true;
            watchers.Add(watcher);
        }
        catch { }
    }

    /// <summary>A file often arrives in steps (written, renamed), so wait a moment and look once.</summary>
    static void Settled(HashSet<string> pending, DispatcherTimer settle, Action<string[]> found)
    {
        settle.Stop();
        var files = pending.Where(File.Exists).ToArray();
        pending.Clear();
        if (files.Length > 0) found(files);
    }

    static string DownloadsFolder()
    {
        try
        {
            if (Native.SHGetKnownFolderPath(new Guid("374DE290-123F-4565-9164-39C4925E467B"), 0, IntPtr.Zero, out var path) == 0) return path;
        }
        catch { }
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    }

    void Downloaded(string[] files) =>
        Banner(Ui.Download, Ui.Blue, "Downloaded", files.Length == 1 ? Path.GetFileName(files[0]) : $"{files.Length} files", 4,
            new BannerAction("Show", Ui.Folder, () => FileActions.Reveal(files[0])));

    void ScreenshotSaved(string[] files)
    {
        var video = files.Any(f => Path.GetExtension(f).Equals(".mp4", StringComparison.OrdinalIgnoreCase));
        Banner(video ? "\uE714" : "\uE722", video ? Ui.Red : Ui.Gray, video ? "Screen recording saved" : "Screenshot saved",
            Path.GetFileName(files[0]), 4, new BannerAction("Show", Ui.Folder, () => FileActions.Reveal(files[0])));
    }

    // MARK: Storage and Do Not Disturb

    DateTime warnedDisk = DateTime.MinValue;

    void CheckDiskSpace()
    {
        if (!Settings.Current.LiveDiskSpace || DateTime.Now - warnedDisk < TimeSpan.FromHours(6)) return;
        try
        {
            var drive = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\");
            var gigabytes = drive.AvailableFreeSpace / 1_000_000_000.0;
            if (gigabytes >= 10) return;
            warnedDisk = DateTime.Now;
            Banner(Ui.Drive, Ui.Orange, "Low on storage", $"{gigabytes:0.0} GB left", 6,
                new BannerAction("Manage", Ui.Gear, () => Open("ms-settings:storagesense")));
        }
        catch { }
    }

    bool? dnd;

    /// <summary>Windows 11's Do not disturb turns notification banners off, and records that in this setting.</summary>
    static bool? DoNotDisturb()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Notifications\Settings");
            return key?.GetValue("NOC_GLOBAL_SETTING_TOASTS_ENABLED") is int enabled ? enabled == 0 : false;
        }
        catch { return null; }
    }

    void CheckDoNotDisturb()
    {
        var now = DoNotDisturb();
        if (now is null || now == dnd) return;
        var known = dnd is not null;
        dnd = now;
        if (known && Settings.Current.LiveDoNotDisturb)
            Banner("\uE708", now.Value ? Ui.Rgb(94, 92, 230) : Ui.Gray, now.Value ? "Do not disturb" : "Do not disturb off",
                now.Value ? "Notifications are silenced" : "", 2.5);
    }

    // MARK: Clock app

    UserNotificationListener? listener;
    readonly HashSet<uint> seenToasts = new();
    bool polling, firstPoll = true;

    /// <summary>
    /// Asks Windows for access to notifications. Windows only grants it to some apps (it may need Isola to be installed
    /// as a package); without it, Clock alerts stay as Windows shows them.
    /// </summary>
    async void StartClockApp()
    {
        try
        {
            listener = UserNotificationListener.Current;
            NotificationAccess = await listener.RequestAccessAsync() == UserNotificationListenerAccessStatus.Allowed;
        }
        catch
        {
            NotificationAccess = false;
        }
    }

    /// <summary>
    /// Finds new Clock app alerts, shows them as a ringing island and removes Windows' own copy. Removing it is all
    /// Windows allows: there is no way to press its Snooze button, so the second button opens Clock instead.
    /// </summary>
    async void CheckClockApp()
    {
        if (!Settings.Current.LiveClockApp || listener is null || NotificationAccess != true || polling) return;
        polling = true;
        try
        {
            var toasts = await listener.GetNotificationsAsync(NotificationKinds.Toast);
            foreach (var toast in toasts)
            {
                if (!seenToasts.Add(toast.Id) || firstPoll) continue;
                string app = "", name = "";
                try
                {
                    app = toast.AppInfo.AppUserModelId;
                    name = toast.AppInfo.DisplayInfo.DisplayName;
                }
                catch { }
                if (!app.Contains("WindowsAlarms", StringComparison.OrdinalIgnoreCase) && name is not ("Clock" or "Alarms & Clock")) continue;
                var texts = new List<string>();
                try
                {
                    var binding = toast.Notification.Visual.GetBinding(KnownNotificationBindings.ToastGeneric);
                    if (binding is not null) texts.AddRange(binding.GetTextElements().Select(t => t.Text).Where(t => !string.IsNullOrWhiteSpace(t)));
                }
                catch { }
                var id = toast.Id;
                try { listener.RemoveNotification(id); } catch { }
                var alarm = string.Join(" ", texts).Contains("Alarm", StringComparison.OrdinalIgnoreCase);
                showBanner(new Banner(alarm ? "\uE7ED" : "\uE823", Ui.Orange, texts.FirstOrDefault() ?? (alarm ? "Alarm" : "Timer"),
                    texts.Skip(1).FirstOrDefault() ?? "Clock", new BannerAction("Stop", "\uE71A", () => { }))
                {
                    SecondAction = new BannerAction("Open Clock", "\uE823", () => Open("ms-clock:")),
                    Ringing = true,
                }, 60);
            }
        }
        catch { }
        firstPoll = false;
        polling = false;
    }

    static void Open(string target)
    {
        try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); } catch { }
    }
}
