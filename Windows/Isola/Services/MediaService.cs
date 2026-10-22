using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Windows.Media.Control;

namespace Isola.Services;

/// <summary>One app playing media, from Windows' media sessions (the ones the volume flyout shows).</summary>
public sealed class NowPlayer
{
    internal GlobalSystemMediaTransportControlsSession Session { get; }
    public string Id { get; }
    public string AppName { get; }
    public ImageSource? AppIcon { get; }
    public string Title { get; internal set; } = "";
    public string Artist { get; internal set; } = "";
    public ImageSource? Artwork { get; internal set; }
    public Color Tint { get; internal set; } = Ui.Rgb(180, 180, 180);
    public bool IsPlaying { get; internal set; }
    public double Duration { get; internal set; }
    public bool CanSeek { get; internal set; }
    internal double Position;
    internal DateTime PositionAt = DateTime.UtcNow;
    internal string ArtworkKey = "";

    internal NowPlayer(GlobalSystemMediaTransportControlsSession session)
    {
        Session = session;
        Id = session.SourceAppUserModelId;
        (AppName, AppIcon) = AppIdentity.For(Id);
    }

    /// <summary>Where the track is now, counting on from the last report while it plays.</summary>
    public double LivePosition
    {
        get
        {
            var p = Position + (IsPlaying ? (DateTime.UtcNow - PositionAt).TotalSeconds : 0);
            return Duration > 0 ? Math.Clamp(p, 0, Duration) : Math.Max(p, 0);
        }
    }

    public async void TogglePlayPause() { try { await Session.TryTogglePlayPauseAsync(); } catch { } }
    public async void Next() { try { await Session.TrySkipNextAsync(); } catch { } }
    public async void Previous() { try { await Session.TrySkipPreviousAsync(); } catch { } }

    public async void Seek(double seconds)
    {
        Position = seconds;
        PositionAt = DateTime.UtcNow;
        try { await Session.TryChangePlaybackPositionAsync(TimeSpan.FromSeconds(seconds).Ticks); } catch { }
    }
}

/// <summary>
/// Every media session Windows knows about. Unlike macOS, Windows reports them all and each one takes commands, so the
/// Media tab can stack them, each with its own controls.
/// </summary>
public sealed class MediaService
{
    GlobalSystemMediaTransportControlsSessionManager? manager;
    readonly Dictionary<string, NowPlayer> players = new();
    readonly Dispatcher dispatcher = Application.Current.Dispatcher;

    /// <summary>Raised on the UI thread whenever anything about any player changes.</summary>
    public event Action? Changed;

    /// <summary>All players: the one the island shows first, then the others playing, then the paused ones.</summary>
    public IReadOnlyList<NowPlayer> Players { get; private set; } = Array.Empty<NowPlayer>();
    public NowPlayer? Primary => Players.Count > 0 ? Players[0] : null;

    public async Task StartAsync()
    {
        try
        {
            manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
        }
        catch
        {
            return;
        }
        manager.SessionsChanged += (_, _) => dispatcher.BeginInvoke(SyncSessions);
        manager.CurrentSessionChanged += (_, _) => dispatcher.BeginInvoke(Reorder);
        SyncSessions();
    }

    void SyncSessions()
    {
        if (manager is null) return;
        IReadOnlyList<GlobalSystemMediaTransportControlsSession> sessions;
        try { sessions = manager.GetSessions(); } catch { return; }

        var ids = new HashSet<string>();
        foreach (var session in sessions)
        {
            var id = session.SourceAppUserModelId;
            ids.Add(id);
            if (players.ContainsKey(id)) continue;
            var player = new NowPlayer(session);
            players[id] = player;
            session.MediaPropertiesChanged += (_, _) => dispatcher.BeginInvoke(() => _ = LoadProperties(player));
            session.PlaybackInfoChanged += (_, _) => dispatcher.BeginInvoke(() => LoadPlayback(player));
            session.TimelinePropertiesChanged += (_, _) => dispatcher.BeginInvoke(() => LoadTimeline(player));
            _ = LoadProperties(player);
            LoadPlayback(player);
            LoadTimeline(player);
        }
        foreach (var gone in players.Keys.Where(k => !ids.Contains(k)).ToList()) players.Remove(gone);
        Reorder();
    }

    async Task LoadProperties(NowPlayer player)
    {
        try
        {
            var props = await player.Session.TryGetMediaPropertiesAsync();
            if (props is null) return;
            player.Title = props.Title ?? "";
            player.Artist = string.IsNullOrEmpty(props.Artist) ? props.AlbumArtist ?? "" : props.Artist;
            var key = $"{player.Title}|{player.Artist}";
            if (key != player.ArtworkKey)
            {
                player.ArtworkKey = key;
                player.Artwork = props.Thumbnail is null ? null : await LoadThumbnail(props.Thumbnail);
                player.Tint = Ui.VibrantColor(player.Artwork);
            }
        }
        catch { }
        Reorder();
    }

    static async Task<ImageSource?> LoadThumbnail(Windows.Storage.Streams.IRandomAccessStreamReference reference)
    {
        try
        {
            using var stream = await reference.OpenReadAsync();
            using var input = stream.AsStreamForRead();
            var memory = new MemoryStream();
            await input.CopyToAsync(memory);
            memory.Position = 0;
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.StreamSource = memory;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch
        {
            return null;
        }
    }

    void LoadPlayback(NowPlayer player)
    {
        try
        {
            var info = player.Session.GetPlaybackInfo();
            var playing = info.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
            if (playing != player.IsPlaying)
            {
                // Freeze the position where it stopped, or restart the clock where it starts.
                player.Position = player.LivePosition;
                player.PositionAt = DateTime.UtcNow;
                player.IsPlaying = playing;
            }
            player.CanSeek = info.Controls.IsPlaybackPositionEnabled;
        }
        catch { }
        Reorder();
    }

    void LoadTimeline(NowPlayer player)
    {
        try
        {
            var t = player.Session.GetTimelineProperties();
            player.Duration = Math.Max((t.EndTime - t.StartTime).TotalSeconds, 0);
            player.Position = (t.Position - t.StartTime).TotalSeconds;
            // The timeline says when it was measured; count on from then.
            player.PositionAt = t.LastUpdatedTime.UtcDateTime > DateTime.UnixEpoch ? t.LastUpdatedTime.UtcDateTime : DateTime.UtcNow;
        }
        catch { }
        Reorder();
    }

    void Reorder()
    {
        string? current = null;
        try { current = manager?.GetCurrentSession()?.SourceAppUserModelId; } catch { }
        Players = players.Values
            .Where(p => !string.IsNullOrEmpty(p.Title) || p.IsPlaying)
            .OrderByDescending(p => p.IsPlaying)
            .ThenByDescending(p => p.Id == current)
            .ThenBy(p => p.AppName)
            .ToList();
        Changed?.Invoke();
    }
}

/// <summary>A friendly name and icon for a media session's app, from its app user model ID.</summary>
static class AppIdentity
{
    static readonly Dictionary<string, (string, ImageSource?)> cache = new();
    static readonly Dictionary<string, string> names = new(StringComparer.OrdinalIgnoreCase)
    {
        ["spotify"] = "Spotify", ["chrome"] = "Google Chrome", ["msedge"] = "Microsoft Edge", ["firefox"] = "Firefox",
        ["zunemusic"] = "Media Player", ["zunevideo"] = "Movies & TV", ["vlc"] = "VLC", ["brave"] = "Brave",
        ["opera"] = "Opera", ["applemusic"] = "Apple Music", ["itunes"] = "iTunes", ["discord"] = "Discord",
        ["tidal"] = "TIDAL", ["amazonmusic"] = "Amazon Music", ["deezer"] = "Deezer", ["wallpaper32"] = "Wallpaper Engine",
        ["wallpaper64"] = "Wallpaper Engine",
    };

    public static (string, ImageSource?) For(string aumid)
    {
        if (cache.TryGetValue(aumid, out var hit)) return hit;
        var key = aumid;
        if (key.Contains('!')) key = key[..key.IndexOf('!')];
        if (key.Contains('_')) key = key[..key.IndexOf('_')];
        if (key.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) key = key[..^4];
        var shortName = key.Contains('.') ? key[(key.LastIndexOf('.') + 1)..] : key;
        if (!names.TryGetValue(shortName, out var name))
            name = shortName.Length > 0 ? char.ToUpperInvariant(shortName[0]) + shortName[1..] : aumid;

        ImageSource? icon = null;
        try
        {
            var process = Process.GetProcessesByName(shortName).FirstOrDefault();
            var path = process?.MainModule?.FileName;
            if (path is not null)
            {
                var name2 = process!.MainModule!.FileVersionInfo.FileDescription;
                if (!names.ContainsKey(shortName) && !string.IsNullOrWhiteSpace(name2)) name = name2!;
                using var ico = System.Drawing.Icon.ExtractAssociatedIcon(path);
                if (ico is not null)
                {
                    var source = Imaging.CreateBitmapSourceFromHIcon(ico.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                    source.Freeze();
                    icon = source;
                }
            }
        }
        catch { }
        return cache[aumid] = (name, icon);
    }
}
