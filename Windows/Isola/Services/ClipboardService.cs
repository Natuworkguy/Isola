using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Isola.Services;

public enum ClipKind { Text, Link, Color, Image }

public sealed class ClipEntry
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public ClipKind Kind { get; set; }
    public string Text { get; set; } = "";
    public string? ImageFile { get; set; }
    public string? PixelSize { get; set; }
    public DateTime Date { get; set; } = DateTime.Now;

    public string SearchText => Kind switch
    {
        ClipKind.Image => "image picture " + PixelSize,
        ClipKind.Color => "colour color " + Text,
        ClipKind.Link => "link url " + Text,
        _ => Text,
    };
}

/// <summary>Remembers what was copied: text, links, colours and images, kept between launches.</summary>
public sealed class ClipboardService
{
    static readonly string Store = Path.Combine(Settings.Folder, "clipboard.json");
    static readonly string Images = Path.Combine(Settings.Folder, "clips");
    static readonly Regex HexColor = new(@"^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$");
    static readonly Regex RgbColor = new(@"^rgba?\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*(,\s*[\d.]+\s*)?\)$", RegexOptions.IgnoreCase);

    readonly List<ClipEntry> entries;
    HwndSource? listener;
    DateTime ignoreUntil = DateTime.MinValue;

    public event Action? Changed;
    public IReadOnlyList<ClipEntry> Entries => entries;

    public ClipboardService()
    {
        try
        {
            entries = File.Exists(Store)
                ? JsonSerializer.Deserialize<List<ClipEntry>>(File.ReadAllText(Store)) ?? new()
                : new();
        }
        catch
        {
            entries = new();
        }
    }

    public void Start()
    {
        // A message-only window that Windows tells about every clipboard change.
        listener = new HwndSource(new HwndSourceParameters("IsolaClipboard") { ParentWindow = new IntPtr(-3), Width = 0, Height = 0 });
        listener.AddHook(Hook);
        Native.AddClipboardFormatListener(listener.Handle);
    }

    IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == Native.WM_CLIPBOARDUPDATE && DateTime.Now > ignoreUntil)
            Application.Current.Dispatcher.BeginInvoke(DispatcherPriority.Background, () => Read(3));
        return IntPtr.Zero;
    }

    void Read(int attempts)
    {
        try
        {
            // Password managers mark their copies to stay out of clipboard history; respect that.
            if (Clipboard.ContainsData("ExcludeClipboardContentFromMonitorProcessing") ||
                Clipboard.GetData("CanIncludeInClipboardHistory") is System.IO.MemoryStream { Length: >= 4 } allow &&
                BitConverter.ToInt32(allow.ToArray(), 0) == 0)
                return;
            if (Clipboard.ContainsImage())
            {
                var image = Clipboard.GetImage();
                if (image is not null) AddImage(image);
            }
            else if (Clipboard.ContainsText())
            {
                var text = Clipboard.GetText();
                if (!string.IsNullOrWhiteSpace(text)) AddText(text);
            }
        }
        catch
        {
            // Another app may still hold the clipboard open: try again shortly.
            if (attempts > 1)
            {
                var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(120) };
                timer.Tick += (_, _) => { timer.Stop(); Read(attempts - 1); };
                timer.Start();
            }
        }
    }

    void AddText(string text)
    {
        var trimmed = text.Trim();
        var kind = ClipKind.Text;
        if (trimmed.Length < 2048 && Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) &&
            (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps) && !trimmed.Contains(' '))
            kind = ClipKind.Link;
        else if (HexColor.IsMatch(trimmed) || RgbColor.IsMatch(trimmed))
            kind = ClipKind.Color;

        entries.RemoveAll(e => e.Kind != ClipKind.Image && e.Text == text);
        entries.Insert(0, new ClipEntry { Kind = kind, Text = text });
        Trim();
    }

    void AddImage(BitmapSource image)
    {
        try
        {
            Directory.CreateDirectory(Images);
            var entry = new ClipEntry { Kind = ClipKind.Image, PixelSize = $"{image.PixelWidth}×{image.PixelHeight}" };
            var file = Path.Combine(Images, entry.Id + ".png");
            using (var stream = File.Create(file))
            {
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(image));
                encoder.Save(stream);
            }
            entry.ImageFile = file;
            entries.Insert(0, entry);
            Trim();
        }
        catch { }
    }

    void Trim()
    {
        var limit = Math.Max(Settings.Current.ClipboardLimit, 5);
        foreach (var old in entries.Skip(limit).ToList()) Remove(old, save: false);
        Save();
    }

    public void Remove(ClipEntry entry, bool save = true)
    {
        entries.Remove(entry);
        if (entry.ImageFile is not null) try { File.Delete(entry.ImageFile); } catch { }
        if (save) Save();
    }

    public void Copy(ClipEntry entry)
    {
        ignoreUntil = DateTime.Now.AddMilliseconds(500);
        try
        {
            if (entry.Kind == ClipKind.Image && entry.ImageFile is not null && File.Exists(entry.ImageFile))
                Clipboard.SetImage(LoadImage(entry.ImageFile));
            else
                Clipboard.SetText(entry.Text);
        }
        catch { }
        // Move it to the front, as the most recent copy.
        entries.Remove(entry);
        entries.Insert(0, entry);
        Save();
    }

    public static BitmapImage LoadImage(string file, int decodeWidth = 0)
    {
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.UriSource = new Uri(file);
        if (decodeWidth > 0) image.DecodePixelWidth = decodeWidth;
        image.EndInit();
        image.Freeze();
        return image;
    }

    void Save()
    {
        try
        {
            Directory.CreateDirectory(Settings.Folder);
            File.WriteAllText(Store, JsonSerializer.Serialize(entries));
        }
        catch { }
        Changed?.Invoke();
    }

    /// <summary>The RGB of a colour clip, if it parses.</summary>
    public static System.Windows.Media.Color? ParseColor(string text)
    {
        var t = text.Trim();
        var hex = HexColor.Match(t);
        if (hex.Success)
        {
            var h = hex.Groups[1].Value;
            if (h.Length == 3) h = string.Concat(h.Select(c => $"{c}{c}"));
            var n = Convert.ToInt32(h, 16);
            return Ui.Rgb((byte)(n >> 16), (byte)(n >> 8), (byte)n);
        }
        var nums = Regex.Matches(t, @"\d{1,3}").Take(3).Select(m => (byte)Math.Min(255, int.Parse(m.Value))).ToArray();
        return nums.Length == 3 ? Ui.Rgb(nums[0], nums[1], nums[2]) : null;
    }
}
