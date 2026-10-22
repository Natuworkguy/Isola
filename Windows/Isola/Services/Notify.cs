using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Media;
using System.Windows.Media;

namespace Isola.Services;

/// <summary>
/// isola://notify links: any app or script can make the island show a short banner, for example
///
///     start isola://notify?title=Build%20done^&text=All%20tests%20pass^&symbol=checkmark.circle.fill^&color=green
///
/// title, text, symbol (an SF Symbol name from the Mac version, or a Segoe Fluent Icons code point such as E73E),
/// color (a name or hex), duration (1 to 30 seconds), sound (a file in C:\Windows\Media, without .wav).
/// Since anything can open the link, it only ever shows text: no buttons, no links, nothing it runs.
/// </summary>
static class Notify
{
    const int MaxTitle = 80, MaxText = 200;

    static readonly Dictionary<string, Color> colors = new(StringComparer.OrdinalIgnoreCase)
    {
        ["red"] = Ui.Red, ["orange"] = Ui.Orange, ["yellow"] = Ui.Yellow, ["green"] = Ui.Green, ["mint"] = Ui.Mint,
        ["teal"] = Ui.Teal, ["cyan"] = Ui.Rgb(100, 210, 255), ["blue"] = Ui.Blue, ["indigo"] = Ui.Rgb(94, 92, 230),
        ["purple"] = Ui.Purple, ["pink"] = Ui.Rgb(255, 55, 95), ["brown"] = Ui.Rgb(172, 142, 104), ["gray"] = Ui.Gray,
        ["grey"] = Ui.Gray,
    };

    // The Mac version takes SF Symbol names; the common ones map to their Fluent counterparts.
    static readonly (string word, string glyph)[] symbols =
    {
        ("checkmark", Ui.Check), ("xmark", Ui.Close), ("exclamationmark", Ui.Warning), ("warning", Ui.Warning),
        ("info", Ui.Info), ("heart", Ui.Heart), ("star", Ui.Star), ("bolt", Ui.Bolt), ("bell", Ui.Bell),
        ("hammer", "\uE90F"), ("gear", Ui.Gear), ("arrow.down", Ui.Download), ("tray", Ui.Folder), ("music", Ui.Music),
        ("lock", "\uE72E"), ("cloud", "\uE753"), ("envelope", "\uE715"), ("mail", "\uE715"), ("clock", "\uE823"),
        ("trash", Ui.Delete), ("flag", "\uE7C1"), ("terminal", "\uE756"), ("sparkles", "\uE945"),
    };

    public static Banner? Parse(string url, out double seconds, out string? sound)
    {
        seconds = 4;
        sound = null;
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || !uri.Scheme.Equals("isola", StringComparison.OrdinalIgnoreCase)
            || !uri.Host.Equals("notify", StringComparison.OrdinalIgnoreCase)) return null;

        var values = Query(uri);

        var title = Clean(values.GetValueOrDefault("title"), MaxTitle);
        var text = Clean(values.GetValueOrDefault("text") ?? values.GetValueOrDefault("message"), MaxText);
        if (title.Length == 0 && text.Length == 0) return null;

        var glyph = Glyph(values.GetValueOrDefault("symbol")) ?? Ui.Bell;

        if (double.TryParse(values.GetValueOrDefault("duration"), System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out var d))
            seconds = Math.Clamp(d, 1, 30);

        if (values.TryGetValue("sound", out var s) && s.Length is > 0 and <= 32 && s.All(char.IsLetterOrDigit)) sound = s;

        return new Banner(glyph, ParseColor(values.GetValueOrDefault("color")) ?? Ui.Mint,
            title.Length == 0 ? text : title, title.Length == 0 ? "" : text);
    }

    public static void Play(string? sound)
    {
        if (sound is null) return;
        try
        {
            var file = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Media", sound + ".wav");
            if (File.Exists(file)) new SoundPlayer(file).Play();
            else SystemSounds.Asterisk.Play();
        }
        catch { }
    }

    /// <summary>A link's parameters by name (any case), the first of each, decoded.</summary>
    public static Dictionary<string, string> Query(Uri uri)
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var part in uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var kv = part.Split('=', 2);
            var key = Uri.UnescapeDataString(kv[0]);
            if (values.ContainsKey(key)) continue;
            values[key] = kv.Length > 1 ? Uri.UnescapeDataString(kv[1].Replace('+', ' ')) : "";
        }
        return values;
    }

    /// <summary>A Fluent glyph for an SF Symbol name from the Mac version, or a code point such as E73E.</summary>
    public static string? Glyph(string? symbol)
    {
        if (string.IsNullOrEmpty(symbol) || symbol.Length > 64) return null;
        if (symbol.Length == 4 && int.TryParse(symbol, System.Globalization.NumberStyles.HexNumber, null, out var code) && code >= 0xE000)
            return char.ConvertFromUtf32(code);
        return symbols.FirstOrDefault(s => symbol.Contains(s.word, StringComparison.OrdinalIgnoreCase)).glyph;
    }

    public static string Clean(string? value, int limit)
    {
        var words = string.Join(' ', (value ?? "").Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        return words.Length > limit ? words[..limit] : words;
    }

    public static Color? ParseColor(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        value = value.Trim();
        if (colors.TryGetValue(value, out var named)) return named;
        var hex = value.TrimStart('#');
        if (hex.Length == 6 && int.TryParse(hex, System.Globalization.NumberStyles.HexNumber, null, out var n))
            return Ui.Rgb((byte)(n >> 16), (byte)(n >> 8), (byte)n);
        return null;
    }
}

/// <summary>
/// isola://activity links: any app or script can show its own Live Activity, a checklist that updates in place:
///
///     start "" "isola://activity?id=build&amp;title=Build&amp;symbol=hammer&amp;color=orange&amp;steps=done:Fetch|active:Compile|todo:Test"
///     start "" "isola://activity/end?id=build"
///
/// id (required: letters, digits, dot, dash, underscore, up to 64; the same id updates in place), title, subtitle,
/// symbol, color, steps (up to 12, separated by |, each done:, active:, todo: or failed: and its text), lines (a
/// conversation as it goes: up to 6, separated by |, each a speaker, a colon, and what they said), progress (0 to 1),
/// trailing (up to 8 characters), countdown or elapsed (seconds), priority (low lets music keep the ears), mic
/// (talking, listening, on or off: it is using the microphone, in place of Isola's own dot and banner; listening and
/// talking show live bars for its icon), and peek
/// (1 shows its card now, 0 keeps it in the ears; by default the card shows when it starts and when its steps or lines change). Only the parameters
/// given change. An activity ends after two hours without an update, and at most eight from links run at once.
/// </summary>
static class ActivityLinks
{
    const int MaxActivities = 8;
    static readonly Dictionary<string, DateTime> updated = new();
    static System.Windows.Threading.DispatcherTimer? sweeper;

    public static bool Handle(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || !uri.Scheme.Equals("isola", StringComparison.OrdinalIgnoreCase)
            || !uri.Host.Equals("activity", StringComparison.OrdinalIgnoreCase)) return false;
        if (!Settings.Current.ActivityLinks) return true;
        var values = Notify.Query(uri);
        var id = values.GetValueOrDefault("id") ?? "";
        if (id.Length is < 1 or > 64 || id.StartsWith("isola.", StringComparison.OrdinalIgnoreCase)
            || !id.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '-' or '_')) return true;
        if (uri.AbsolutePath.StartsWith("/end", StringComparison.OrdinalIgnoreCase))
        {
            updated.Remove(id);
            Activities.End(id);
            return true;
        }
        var existing = Activities.Find(id);
        if (existing is null && updated.Count >= MaxActivities) return true;
        var activity = Apply(values, existing ?? new LiveActivity(id, Ui.Star, Ui.Mint, ""));
        var stepsChanged = existing is null || !existing.Steps.SequenceEqual(activity.Steps);
        var linesChanged = existing is null || !existing.Lines.SequenceEqual(activity.Lines);
        var peek = values.GetValueOrDefault("peek") == "1"
            || (values.GetValueOrDefault("peek") != "0" && (existing is null || (stepsChanged && activity.Steps.Count > 0)
                || (linesChanged && activity.Lines.Count > 0)));
        updated[id] = DateTime.UtcNow;
        Activities.Set(activity, peek);
        StartSweeping();
        return true;
    }

    static LiveActivity Apply(Dictionary<string, string> values, LiveActivity a)
    {
        if (values.TryGetValue("title", out var title)) a = a with { Title = Notify.Clean(title, 80) };
        if (values.TryGetValue("subtitle", out var subtitle)) a = a with { Subtitle = Notify.Clean(subtitle, 80) };
        if (Notify.Glyph(values.GetValueOrDefault("symbol")) is { } glyph) a = a with { Glyph = glyph };
        if (Notify.ParseColor(values.GetValueOrDefault("color")) is { } tint) a = a with { Tint = tint };
        if (values.TryGetValue("trailing", out var trailing)) a = a with { Trailing = Notify.Clean(trailing, 8) };
        if (values.TryGetValue("steps", out var steps)) a = a with { Steps = Steps(steps) };
        if (values.TryGetValue("lines", out var lines)) a = a with { Lines = Lines(lines) };
        if (values.TryGetValue("progress", out var progress)) a = a with { Progress = Number(progress) is { } p ? Math.Clamp(p, 0, 1) : null };
        if (values.TryGetValue("countdown", out var countdown))
            a = a with { EndsAt = Number(countdown) is { } s ? DateTime.UtcNow.AddSeconds(Math.Clamp(s, 0, 86_400)) : null };
        if (values.TryGetValue("elapsed", out var elapsed))
            a = a with { Since = Number(elapsed) is { } s ? DateTime.UtcNow.AddSeconds(-Math.Clamp(s, 0, 86_400)) : null };
        if (values.TryGetValue("priority", out var priority)) a = a with { Priority = priority.Equals("low", StringComparison.OrdinalIgnoreCase) ? 1 : 2 };
        if (values.TryGetValue("mic", out var mic))
            a = a with { Mic = Enum.TryParse<MicUse>(mic, true, out var use) && Enum.IsDefined(use) ? use : mic == "1" ? MicUse.On : MicUse.Off };
        return a;
    }

    static double? Number(string raw) =>
        double.TryParse(raw, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var n) ? n : null;

    public static IReadOnlyList<ActivityStep> Steps(string raw)
    {
        var known = new Dictionary<string, StepState>(StringComparer.OrdinalIgnoreCase)
        {
            ["done"] = StepState.Done, ["active"] = StepState.Active, ["now"] = StepState.Active, ["todo"] = StepState.Pending,
            ["pending"] = StepState.Pending, ["failed"] = StepState.Failed, ["error"] = StepState.Failed,
        };
        var list = new List<ActivityStep>();
        foreach (var part in raw.Split('|', StringSplitOptions.RemoveEmptyEntries).Take(12))
        {
            var text = part;
            var state = StepState.Pending;
            var colon = part.IndexOf(':');
            if (colon > 0 && known.TryGetValue(part[..colon].Trim(), out var found))
            {
                state = found;
                text = part[(colon + 1)..];
            }
            text = Notify.Clean(text, 100);
            if (text.Length > 0) list.Add(new ActivityStep(text, state));
        }
        return list;
    }

    /// <summary>A conversation: each part a speaker, a colon and what they said. The newest six are kept.</summary>
    public static IReadOnlyList<DialogueLine> Lines(string raw)
    {
        var list = new List<DialogueLine>();
        foreach (var part in raw.Split('|', StringSplitOptions.RemoveEmptyEntries))
        {
            var colon = part.IndexOf(':');
            var speaker = colon > 0 ? Notify.Clean(part[..colon], 24) : "";
            var said = Notify.Clean(colon >= 0 ? part[(colon + 1)..] : part, 200);
            if (said.Length > 0) list.Add(new DialogueLine(speaker, said));
        }
        return list.Skip(Math.Max(0, list.Count - 6)).ToList();
    }

    /// <summary>Ends activities from links that have not been updated for two hours: their app has probably gone.</summary>
    static void StartSweeping()
    {
        if (sweeper is not null) return;
        sweeper = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMinutes(1) };
        sweeper.Tick += (_, _) =>
        {
            foreach (var id in updated.Where(u => DateTime.UtcNow - u.Value > TimeSpan.FromHours(2)).Select(u => u.Key).ToList())
            {
                updated.Remove(id);
                Activities.End(id);
            }
        };
        sweeper.Start();
    }
}
