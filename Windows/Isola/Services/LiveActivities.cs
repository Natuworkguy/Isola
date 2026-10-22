using System;
using System.IO;
using System.Linq;
using System.Management;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;

namespace Isola.Services;

/// <summary>A button on one of Isola's own banners (isola://notify banners never get one).</summary>
public sealed record BannerAction(string Title, string Glyph, Action Perform);

/// <summary>A short message the island grows to show, then shrinks back from.</summary>
public sealed record Banner(string Glyph, Color Tint, string Title, string Subtitle, BannerAction? Action = null)
{
    public Guid Id { get; } = Guid.NewGuid();
    /// <summary>A second, quieter button, such as Snooze beside Stop.</summary>
    public BannerAction? SecondAction { get; init; }
    /// <summary>An alarm or timer going off: the icon shakes like a bell until the banner goes.</summary>
    public bool Ringing { get; init; }
    /// <summary>Runs however the banner goes: a button, a click, its time running out, or another banner replacing it.</summary>
    public Action? OnDismiss { get; init; }
}

public enum HudKind { Volume, Brightness }

/// <summary>
/// System events the island shows as they happen: volume and brightness in a bar, and banners for charging, headphones,
/// drives and VPNs.
/// </summary>
public sealed class LiveActivities : IMMNotificationClient
{
    readonly Dispatcher dispatcher = Application.Current.Dispatcher;
    readonly Action<Banner, double> showBanner;
    readonly Action<HudKind, double, bool> showHud;

    MMDeviceEnumerator? enumerator;
    MMDevice? output;
    ManagementEventWatcher? brightness;
    readonly DispatcherTimer batteryTimer = new() { Interval = TimeSpan.FromSeconds(30) };
    bool? lastOnPower;
    int lastWarned = 101;
    bool sawFull;
    bool? lastVpn;
    DateTime quietUntil = DateTime.Now.AddSeconds(3);
    string? ejecting;

    public LiveActivities(Action<Banner, double> showBanner, Action<HudKind, double, bool> showHud)
    {
        this.showBanner = showBanner;
        this.showHud = showHud;
    }

    public void Start()
    {
        StartVolume();
        StartBrightness();
        SystemEvents.PowerModeChanged += (_, e) =>
        {
            if (e.Mode == PowerModes.StatusChange) dispatcher.BeginInvoke(CheckPower);
        };
        batteryTimer.Tick += (_, _) => CheckPower();
        batteryTimer.Start();
        CheckPower();
        NetworkChange.NetworkAddressChanged += (_, _) => dispatcher.BeginInvoke(CheckVpn);
        lastVpn = VpnActive();
    }

    public void Stop()
    {
        try { enumerator?.UnregisterEndpointNotificationCallback(this); } catch { }
        try { brightness?.Stop(); } catch { }
        RestoreSystemOverlay();
    }

    // MARK: Volume

    void StartVolume()
    {
        try
        {
            enumerator = new MMDeviceEnumerator();
            enumerator.RegisterEndpointNotificationCallback(this);
            AttachOutput();
        }
        catch { }
    }

    void AttachOutput()
    {
        try
        {
            if (output is not null) output.AudioEndpointVolume.OnVolumeNotification -= OnVolume;
            output = enumerator?.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            if (output is not null) output.AudioEndpointVolume.OnVolumeNotification += OnVolume;
        }
        catch { }
    }

    void OnVolume(AudioVolumeNotificationData data)
    {
        dispatcher.BeginInvoke(() =>
        {
            if (!Settings.Current.LiveVolume || DateTime.Now < quietUntil) return;
            HideSystemOverlay();
            showHud(HudKind.Volume, data.MasterVolume, data.Muted);
        });
    }

    // IMMNotificationClient: audio devices coming and going.
    public void OnDefaultDeviceChanged(DataFlow flow, Role role, string defaultDeviceId)
    {
        if (flow != DataFlow.Render || role != Role.Multimedia) return;
        dispatcher.BeginInvoke(() =>
        {
            AttachOutput();
            if (output is null || !Settings.Current.LiveHeadphones || DateTime.Now < quietUntil) return;
            if (IsHeadphones(output))
                showBanner(new Banner(Ui.Headphones, Ui.Blue, output.FriendlyName.Split('(')[0].Trim(), "Connected"), 4);
        });
    }

    static bool IsHeadphones(MMDevice device)
    {
        try
        {
            var value = device.Properties[PropertyKeys.PKEY_AudioEndpoint_FormFactor].Value;
            var formFactor = Convert.ToInt32(value);
            if (formFactor is 3 or 5) return true; // Headphones, Headset
        }
        catch { }
        var name = device.FriendlyName.ToLowerInvariant();
        return new[] { "headphone", "headset", "airpods", "buds", "bose", "beats", "earbud", "wh-", "wf-" }.Any(name.Contains);
    }

    public void OnDeviceStateChanged(string deviceId, DeviceState newState) { }
    public void OnDeviceAdded(string pwstrDeviceId) { }
    public void OnDeviceRemoved(string deviceId) { }
    public void OnPropertyValueChanged(string pwstrDeviceId, PropertyKey key) { }

    // MARK: Brightness (laptop panels report it through WMI; external monitors usually do not)

    void StartBrightness()
    {
        try
        {
            brightness = new ManagementEventWatcher(new ManagementScope(@"root\WMI"),
                new EventQuery("SELECT * FROM WmiMonitorBrightnessEvent"));
            brightness.EventArrived += (_, e) =>
            {
                var level = Convert.ToDouble(e.NewEvent.Properties["Brightness"].Value) / 100.0;
                dispatcher.BeginInvoke(() =>
                {
                    if (Settings.Current.LiveBrightness && DateTime.Now >= quietUntil) showHud(HudKind.Brightness, level, false);
                });
            };
            brightness.Start();
        }
        catch { brightness = null; }
    }

    // MARK: The Windows volume overlay

    /// <summary>
    /// Windows 10's volume overlay is a window of its own; minimising it keeps it out of sight. Windows 11 draws its
    /// overlay differently and cannot be hidden this way, so there the setting does nothing.
    /// </summary>
    void HideSystemOverlay()
    {
        if (!Settings.Current.HideSystemOverlay || Environment.OSVersion.Version.Build >= 22000) return;
        var host = FindOverlay();
        if (host != IntPtr.Zero) Native.ShowWindow(host, 6);
    }

    public void RestoreSystemOverlay()
    {
        if (Environment.OSVersion.Version.Build >= 22000) return;
        var host = FindOverlay();
        if (host != IntPtr.Zero) Native.ShowWindow(host, 9);
    }

    static IntPtr FindOverlay()
    {
        var host = IntPtr.Zero;
        while ((host = Native.FindWindowEx(IntPtr.Zero, host, "NativeHWNDHost", "")) != IntPtr.Zero)
            if (Native.FindWindowEx(host, IntPtr.Zero, "DirectUIHWND", "") != IntPtr.Zero) return host;
        return IntPtr.Zero;
    }

    // MARK: Power

    void CheckPower()
    {
        if (!Native.GetSystemPowerStatus(out var s) || s.BatteryFlag == 128 || s.BatteryLifePercent > 100) return;
        var onPower = s.ACLineStatus == 1;
        int percent = s.BatteryLifePercent;
        if (Settings.Current.LiveCharging && lastOnPower is { } was && was != onPower)
        {
            showBanner(onPower
                ? new Banner(Ui.Charging, Ui.Green, "Charging", $"{percent}%")
                : new Banner(Ui.Battery, percent <= 20 ? Ui.Orange : Ui.Gray, "On battery", $"{percent}%"), 3);
        }
        lastOnPower = onPower;

        if (onPower)
        {
            lastWarned = 101;
            if (percent >= 100 && !sawFull && Settings.Current.LiveCharging)
            {
                sawFull = true;
                showBanner(new Banner(Ui.Battery, Ui.Green, "Fully charged", "You can unplug"), 4);
            }
        }
        else
        {
            sawFull = false;
            foreach (var level in new[] { 20, 10 })
            {
                if (percent <= level && lastWarned > level && Settings.Current.LiveCharging)
                {
                    lastWarned = level;
                    showBanner(new Banner(Ui.BatteryLow, Ui.Red, "Low battery", $"{percent}% left. Plug in soon."), 5);
                    break;
                }
            }
        }
    }

    // MARK: Drives

    /// <summary>Handles WM_DEVICECHANGE, which only top-level windows receive; the island forwards it here.</summary>
    public void HandleDeviceChange(IntPtr wParam, IntPtr lParam)
    {
        var evt = wParam.ToInt32();
        if ((evt != Native.DBT_DEVICEARRIVAL && evt != Native.DBT_DEVICEREMOVECOMPLETE) || lParam == IntPtr.Zero) return;
        var header = Marshal.PtrToStructure<Native.DEV_BROADCAST_HDR>(lParam);
        if (header.dbch_devicetype != Native.DBT_DEVTYP_VOLUME) return;
        var volume = Marshal.PtrToStructure<Native.DEV_BROADCAST_VOLUME>(lParam);
        for (var i = 0; i < 26; i++)
        {
            if ((volume.dbcv_unitmask & (1 << i)) == 0) continue;
            var letter = $"{(char)('A' + i)}:\\";
            if (evt == Native.DBT_DEVICEARRIVAL) dispatcher.BeginInvoke(() => Mounted(letter));
            else dispatcher.BeginInvoke(() => Removed(letter));
        }
    }

    void Mounted(string root)
    {
        if (!Settings.Current.LiveDrives) return;
        try
        {
            var drive = new DriveInfo(root);
            if (drive.DriveType is not (DriveType.Removable or DriveType.Fixed or DriveType.CDRom)) return;
            var name = string.IsNullOrWhiteSpace(drive.VolumeLabel) ? "USB Drive" : drive.VolumeLabel;
            var detail = drive.IsReady
                ? $"{root.TrimEnd('\\')} · {drive.AvailableFreeSpace / 1073741824.0:0} GB free"
                : root.TrimEnd('\\');
            showBanner(new Banner(Ui.Drive, Ui.Orange, name, detail, new BannerAction("Eject", "", () => Eject(root, name))), 6);
        }
        catch { }
    }

    void Removed(string root)
    {
        if (!Settings.Current.LiveDrives) return;
        var name = ejecting ?? root.TrimEnd('\\');
        var safe = ejecting is not null;
        ejecting = null;
        showBanner(new Banner("", Ui.Gray, safe ? $"{name} ejected" : $"{name} removed",
            safe ? "Safe to remove" : "Eject drives first next time"), 3);
    }

    void Eject(string root, string name)
    {
        try
        {
            // The shell's own Eject, as in File Explorer.
            var type = Type.GetTypeFromProgID("Shell.Application");
            dynamic? shell = type is null ? null : Activator.CreateInstance(type);
            dynamic? computer = shell?.Namespace(17);
            dynamic? item = computer?.ParseName(root);
            if (item is null) throw new InvalidOperationException();
            ejecting = name;
            item.InvokeVerb("Eject");
        }
        catch
        {
            showBanner(new Banner(Ui.Warning, Ui.Red, $"Could not eject {name}", "Close any files open on it and try again"), 4);
        }
    }

    // MARK: VPN

    static bool VpnActive()
    {
        try
        {
            string[] skip = { "teredo", "isatap", "6to4", "loopback", "hyper-v", "virtualbox", "vmware", "wsl" };
            string[] vpn = { "vpn", "wireguard", "wintun", "tap-", "openvpn", "tunnel", "nordlynx", "tailscale", "zerotier" };
            return NetworkInterface.GetAllNetworkInterfaces().Any(n =>
            {
                if (n.OperationalStatus != OperationalStatus.Up) return false;
                var d = (n.Description + " " + n.Name).ToLowerInvariant();
                if (skip.Any(d.Contains)) return false;
                return n.NetworkInterfaceType == NetworkInterfaceType.Ppp || vpn.Any(d.Contains);
            });
        }
        catch
        {
            return false;
        }
    }

    void CheckVpn()
    {
        var now = VpnActive();
        if (lastVpn is { } was && was != now && Settings.Current.LiveVpn)
        {
            showBanner(now
                ? new Banner(Ui.Vpn, Ui.Green, "VPN connected", "Your traffic goes through the VPN")
                : new Banner(Ui.Unlock, Ui.Gray, "VPN disconnected", "Back on your normal connection"), 3);
        }
        lastVpn = now;
    }
}
