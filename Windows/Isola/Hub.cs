using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using Isola.Services;

namespace Isola;

/// <summary>Starts everything and connects the pieces: services, the island, the Basket, the tray icon.</summary>
static class Hub
{
    public static MediaService Media { get; private set; } = null!;
    public static FileTray Tray { get; } = new();
    public static ClipboardService Clipboard { get; private set; } = null!;
    public static SystemStats Stats { get; } = new();
    public static IslandWindow Island { get; private set; } = null!;
    static LiveActivities? live;
    static SystemActivities? systemActivities;
    static ShakeDetector? shake;
    static BasketWindow? basket;
    static TrayIcon? trayIcon;
    static SettingsWindow? settings;

    public static async Task Start()
    {
        Settings.RegisterUrlScheme();
        Settings.ApplyStartup();

        Media = new MediaService();
        Clipboard = new ClipboardService();
        Island = new IslandWindow(Media, Tray, Clipboard, Stats);
        Island.Show();

        Clipboard.Start();
        live = new LiveActivities(Island.ShowBanner, Island.ShowHud);
        Island.DeviceChanged = live.HandleDeviceChange;
        live.Start();
        systemActivities = new SystemActivities(Island.ShowBanner);
        systemActivities.Start();

        basket = new BasketWindow(Perform);
        shake = new ShakeDetector();
        shake.Shaken += (x, y) => basket.ShowAt(x, y);
        shake.Released += () => basket.Released();
        shake.Start();

        trayIcon = new TrayIcon(OpenSettings, Quit);
        await Media.StartAsync();
    }

    public static void Quit()
    {
        live?.Stop();
        shake?.Dispose();
        trayIcon?.Dispose();
        Application.Current.Shutdown();
    }

    public static void OpenSettings()
    {
        settings ??= new SettingsWindow();
        settings.Closed += (_, _) => settings = null;
        settings.Show();
        settings.Activate();
    }

    /// <summary>Files from the command line or a second launch, added to the File Tray with a banner.</summary>
    public static void AddToTray(string[] paths)
    {
        var files = paths.Where(p => File.Exists(p) || Directory.Exists(p)).ToArray();
        if (files.Length == 0) return;
        Tray.Add(files);
        Island.ShowBanner(new Banner(Ui.Download, Ui.Blue, "Added to the tray",
            files.Length == 1 ? Path.GetFileName(files[0]) : $"{files.Length} files"), 3);
    }

    /// <summary>An isola:// link, from the command line or a second launch.</summary>
    public static void HandleLink(string url)
    {
        if (ActivityLinks.Handle(url)) return;
        if (!Settings.Current.NotifyLinks) return;
        var banner = Notify.Parse(url, out var seconds, out var sound);
        if (banner is null) return;
        Island.ShowBanner(banner, seconds);
        Notify.Play(sound);
    }

    static void Perform(BasketWindow.Target target, string[] files)
    {
        var count = files.Length == 1 ? Path.GetFileName(files[0]) : $"{files.Length} files";
        switch (target)
        {
            case BasketWindow.Target.Tray:
                Tray.Add(files);
                Island.ShowBanner(new Banner(Ui.Download, Ui.Blue, "Added to the tray", count), 3);
                break;
            case BasketWindow.Target.Share:
                FileActions.Share(Island, files);
                break;
            case BasketWindow.Target.Convert:
                if (!files.Any(FileActions.IsImage))
                {
                    Island.ShowBanner(new Banner(Ui.Warning, Ui.Orange, "Nothing to convert", "Only images can be converted"), 3);
                    return;
                }
                FileActions.ConvertImages(files, made =>
                {
                    if (made.Count == 0)
                    {
                        Island.ShowBanner(new Banner(Ui.Warning, Ui.Orange, $"Could not convert {count}", "Windows could not read the image"), 4);
                        return;
                    }
                    Tray.Add(made);
                    Island.ShowBanner(new Banner(Ui.Sync, Ui.Purple,
                        made.Count == 1 ? $"Converted {Path.GetFileName(made[0])}" : $"Converted {made.Count} images",
                        "Saved to Downloads and added to the tray"), 4);
                });
                break;
            case BasketWindow.Target.Zip:
                _ = ZipAndReveal(files, count);
                break;
        }
    }

    static async Task ZipAndReveal(string[] files, string count)
    {
        var archive = await FileActions.Zip(files);
        if (archive is null)
        {
            Island.ShowBanner(new Banner(Ui.Warning, Ui.Red, "Could not zip", count), 4);
            return;
        }
        FileActions.Reveal(archive);
        Island.ShowBanner(new Banner(Ui.Package, Ui.Rgb(172, 142, 104), $"Zipped {count}", Path.GetFileName(archive)), 4);
    }
}
