using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;

namespace Isola.Services;

/// <summary>What the File Tray and the Basket can do with files: share, convert images, zip.</summary>
static class FileActions
{
    static readonly HashSet<string> imageTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tif", ".tiff", ".heic", ".heif", ".webp", ".ico", ".jxr",
    };

    public static bool IsImage(string path) => imageTypes.Contains(Path.GetExtension(path));

    /// <summary>JPEGs become PNGs; every other image becomes a JPEG.</summary>
    public static string ConversionTarget(string path)
    {
        var ext = Path.GetExtension(path).ToLowerInvariant();
        return ext is ".jpg" or ".jpeg" ? ".png" : ".jpg";
    }

    /// <summary>Converts the images among PATHS into Downloads. Hands back the new files, on the UI thread.</summary>
    public static void ConvertImages(IEnumerable<string> paths, Action<List<string>> done)
    {
        var images = paths.Where(IsImage).ToList();
        var dispatcher = Application.Current.Dispatcher;
        // WPF imaging wants an STA thread of its own.
        var thread = new Thread(() =>
        {
            var made = new List<string>();
            foreach (var path in images)
            {
                try
                {
                    var target = ConversionTarget(path);
                    var decoder = BitmapDecoder.Create(new Uri(path), BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
                    BitmapSource frame = decoder.Frames[0];
                    BitmapEncoder encoder;
                    if (target == ".jpg")
                    {
                        frame = Flattened(frame);
                        encoder = new JpegBitmapEncoder { QualityLevel = 90 };
                    }
                    else encoder = new PngBitmapEncoder();
                    encoder.Frames.Add(BitmapFrame.Create(frame));
                    var output = UniquePath(Native.DownloadsFolder(), Path.GetFileNameWithoutExtension(path), target);
                    using var stream = File.Create(output);
                    encoder.Save(stream);
                    made.Add(output);
                }
                catch { }
            }
            dispatcher.BeginInvoke(() => done(made));
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.IsBackground = true;
        thread.Start();
    }

    /// <summary>JPEG has no transparency: lay the image on white rather than let transparent areas turn black.</summary>
    static BitmapSource Flattened(BitmapSource source)
    {
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            var rect = new Rect(0, 0, source.PixelWidth, source.PixelHeight);
            dc.DrawRectangle(Brushes.White, null, rect);
            dc.DrawImage(source, rect);
        }
        var bitmap = new RenderTargetBitmap(source.PixelWidth, source.PixelHeight, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        return new FormatConvertedBitmap(bitmap, PixelFormats.Bgr24, null, 0);
    }

    /// <summary>Zips PATHS into Downloads. Hands back the archive, or null.</summary>
    public static async Task<string?> Zip(IReadOnlyList<string> paths)
    {
        if (paths.Count == 0) return null;
        var archive = UniquePath(Native.DownloadsFolder(), $"Isola-{DateTime.Now:yyyyMMdd-HHmmss}", ".zip");
        try
        {
            await Task.Run(() =>
            {
                using var zip = ZipFile.Open(archive, ZipArchiveMode.Create);
                var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var path in paths)
                {
                    var name = Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar));
                    var n = 1;
                    while (!used.Add(name)) name = $"{++n}-{Path.GetFileName(path)}";
                    if (Directory.Exists(path))
                    {
                        foreach (var file in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
                            zip.CreateEntryFromFile(file, Path.Combine(name, Path.GetRelativePath(path, file)));
                    }
                    else if (File.Exists(path)) zip.CreateEntryFromFile(path, name);
                }
            });
            return archive;
        }
        catch
        {
            return null;
        }
    }

    public static void Reveal(string path)
    {
        try { Process.Start("explorer.exe", $"/select,\"{path}\""); } catch { }
    }

    public static void Open(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch { }
    }

    /// <summary>Opens Windows' share sheet (Nearby Sharing, Mail, Teams…) for PATHS, anchored to WINDOW.</summary>
    public static void Share(Window window, IReadOnlyList<string> paths)
    {
        if (paths.Count == 0) return;
        try
        {
            var hwnd = new WindowInteropHelper(window).Handle;
            var manager = DataTransferManagerInterop.GetForWindow(hwnd);
            void OnRequested(DataTransferManager sender, DataRequestedEventArgs args)
            {
                sender.DataRequested -= OnRequested;
                var deferral = args.Request.GetDeferral();
                _ = Fill(args.Request, paths, deferral);
            }
            manager.DataRequested += OnRequested;
            DataTransferManagerInterop.ShowShareUIForWindow(hwnd);
        }
        catch { }
    }

    static async Task Fill(DataRequest request, IReadOnlyList<string> paths, DataRequestDeferral deferral)
    {
        try
        {
            var items = new List<IStorageItem>();
            foreach (var path in paths)
            {
                if (File.Exists(path)) items.Add(await StorageFile.GetFileFromPathAsync(path));
                else if (Directory.Exists(path)) items.Add(await StorageFolder.GetFolderFromPathAsync(path));
            }
            request.Data.Properties.Title = paths.Count == 1 ? Path.GetFileName(paths[0]) : $"{paths.Count} files";
            request.Data.SetStorageItems(items);
        }
        catch { }
        finally
        {
            deferral.Complete();
        }
    }

    public static string UniquePath(string folder, string name, string ext)
    {
        var candidate = Path.Combine(folder, name + ext);
        for (var n = 2; File.Exists(candidate); n++) candidate = Path.Combine(folder, $"{name} {n}{ext}");
        return candidate;
    }

    /// <summary>The shell's icon for a file or folder.</summary>
    public static ImageSource? IconFor(string path)
    {
        try
        {
            if (IsImage(path)) return ClipboardService.LoadImage(path, 96);
            using var icon = System.Drawing.Icon.ExtractAssociatedIcon(path);
            if (icon is null) return null;
            var source = Imaging.CreateBitmapSourceFromHIcon(icon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            source.Freeze();
            return source;
        }
        catch
        {
            return null;
        }
    }
}

/// <summary>Files dropped on the island, kept until you drag them out or clear them.</summary>
public sealed class FileTray
{
    readonly List<string> items = new();
    public IReadOnlyList<string> Items => items;
    public event Action? Changed;
    public string? Status { get; private set; }

    public void Add(IEnumerable<string> paths)
    {
        var added = 0;
        foreach (var p in paths)
        {
            if (items.Contains(p, StringComparer.OrdinalIgnoreCase)) continue;
            items.Add(p);
            added++;
        }
        Status = added == 1 ? $"Added {Path.GetFileName(items[^1])}" : added > 1 ? $"Added {added} files" : Status;
        Changed?.Invoke();
    }

    public void Remove(string path)
    {
        items.Remove(path);
        Changed?.Invoke();
    }

    public void Clear()
    {
        items.Clear();
        Status = null;
        Changed?.Invoke();
    }

    public async void ZipAll()
    {
        var archive = await FileActions.Zip(items);
        Status = archive is null ? "Could not zip the files" : $"Zipped to {Path.GetFileName(archive)}";
        if (archive is not null) FileActions.Reveal(archive);
        Changed?.Invoke();
    }

    public void Convert(string path)
    {
        FileActions.ConvertImages(new[] { path }, made =>
        {
            Status = made.Count > 0 ? $"Saved {Path.GetFileName(made[0])} to Downloads" : "Could not convert the image";
            Add(made);
        });
    }
}
