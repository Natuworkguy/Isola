using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32;

namespace Isola;

public enum IslandStyle { Floating, Attached }
public enum IslandMaterial { Glass, Solid }
/// <summary>How close the pointer has to come for the island to open: near it, or over the island itself.</summary>
public enum HoverArea { Near, On }
/// <summary>What opens the closed island. A click opens it with Hover and Scroll too, unless ClickOpens is off.</summary>
public enum OpenWith { Hover, Click, Scroll }

/// <summary>Everything the Settings window changes, saved as JSON in %AppData%\Isola.</summary>
public sealed class Settings
{
    public static readonly string Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Isola");
    static readonly string File = Path.Combine(Folder, "settings.json");

    public static Settings Current { get; private set; } = Load();
    public static event Action? Changed;

    // Opening
    public OpenWith OpenWith { get; set; } = OpenWith.Hover;
    /// <summary>Read from settings saved before there was a choice: off meant opening with a click.</summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public bool? ExpandOnHover { get => null; set { if (value == false) OpenWith = OpenWith.Click; } }
    public double HoverDelay { get; set; } = 0.12;
    public HoverArea HoverArea { get; set; } = HoverArea.Near;
    /// <summary>
    /// With Hover or Scroll: whether a click on the closed island opens it too. Off, clicks go through it.
    /// </summary>
    public bool ClickOpens { get; set; } = true;
    public bool ExpandOnFileDrag { get; set; } = true;
    public bool ShakeBasket { get; set; } = true;

    // Look
    public IslandStyle Style { get; set; } = IslandStyle.Floating;
    public IslandMaterial Material { get; set; } = IslandMaterial.Glass;
    public bool TintFromArtwork { get; set; } = true;
    public bool HideWhenIdle { get; set; } = false;
    public bool HideInFullScreen { get; set; } = true;
    public double IdleWidth { get; set; } = 150;
    public double IdleHeight { get; set; } = 28;
    public double TopGap { get; set; } = 8;

    // Tabs
    public bool TabHome { get; set; } = true;
    public bool TabMedia { get; set; } = true;
    public bool TabTray { get; set; } = true;
    public bool TabClipboard { get; set; } = true;
    public bool TabSystem { get; set; } = true;

    /// <summary>The Home tab's widgets, in order. The pencil on the Home tab arranges them.</summary>
    public List<string> HomeWidgets { get; set; } = new() { "clock", "media", "battery", "system" };
    public int HomeCounter { get; set; }
    /// <summary>Colours picked with the Color Picker widget, newest first.</summary>
    public List<string> PickedColors { get; set; } = new();

    // Live Activities
    public bool LiveVolume { get; set; } = true;
    public bool LiveBrightness { get; set; } = true;
    public bool LiveCharging { get; set; } = true;
    public bool LiveHeadphones { get; set; } = true;
    public bool LiveDrives { get; set; } = true;
    public bool LiveVpn { get; set; } = true;
    public bool HideSystemOverlay { get; set; } = true;
    public bool LiveTimers { get; set; } = true;
    public bool LiveClockApp { get; set; } = true;
    public bool LivePrivacy { get; set; } = true;
    public bool LiveDownloads { get; set; } = true;
    public bool LiveScreenshots { get; set; } = true;
    public bool LiveNetwork { get; set; } = true;
    public bool LiveDisplays { get; set; } = true;
    public bool LiveCapsLock { get; set; } = true;
    public bool LiveKeyboard { get; set; } = true;
    public bool LiveDiskSpace { get; set; } = true;
    public bool LiveDoNotDisturb { get; set; } = true;

    // Other
    public bool NotifyLinks { get; set; } = true;
    public bool ActivityLinks { get; set; } = true;
    public bool Gestures { get; set; } = true;
    public bool HotKey { get; set; } = true;
    public int ClipboardLimit { get; set; } = 50;
    public bool LaunchAtLogin { get; set; } = true;

    static Settings Load()
    {
        try
        {
            if (System.IO.File.Exists(File))
                return JsonSerializer.Deserialize<Settings>(System.IO.File.ReadAllText(File)) ?? new Settings();
        }
        catch { }
        return new Settings();
    }

    public static void Save()
    {
        SaveQuietly();
        ApplyStartup();
        Changed?.Invoke();
    }

    /// <summary>Writes the settings without telling anyone, for things only their own view shows (the Home tab's layout).</summary>
    public static void SaveQuietly()
    {
        try
        {
            Directory.CreateDirectory(Folder);
            System.IO.File.WriteAllText(File, JsonSerializer.Serialize(Current, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    /// <summary>Adds or removes Isola from the programs Windows starts at sign-in.</summary>
    public static void ApplyStartup()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            if (key is null) return;
            if (Current.LaunchAtLogin) key.SetValue("Isola", $"\"{Environment.ProcessPath}\"");
            else key.DeleteValue("Isola", throwOnMissingValue: false);
        }
        catch { }
    }

    /// <summary>Points isola:// links at this copy of Isola, for the current user only.</summary>
    public static void RegisterUrlScheme()
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(@"Software\Classes\isola");
            key.SetValue("", "URL:Isola");
            key.SetValue("URL Protocol", "");
            using var command = key.CreateSubKey(@"shell\open\command");
            command.SetValue("", $"\"{Environment.ProcessPath}\" \"%1\"");
        }
        catch { }
    }
}
