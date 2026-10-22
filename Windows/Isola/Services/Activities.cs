using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Media;
using System.Windows.Media;
using System.Windows.Threading;

namespace Isola.Services;

public enum StepState { Done, Active, Pending, Failed }

public sealed record ActivityStep(string Text, StepState State);

/// <summary>What an activity is doing with the microphone. On: using it. Listening: waiting for you to speak.
/// Talking: hearing you now.</summary>
public enum MicUse { Off, On, Listening, Talking }

/// <summary>One line of a conversation: who said it, and what.</summary>
public sealed record DialogueLine(string Speaker, string Text);

/// <summary>
/// A Live Activity that stays in the island while it runs: a timer counting down, an app's progress. The highest
/// priority one sits in the ears, and one with steps grows into a card when it changes.
/// </summary>
public sealed record LiveActivity(string Id, string Glyph, Color Tint, string Title)
{
    public string Subtitle { get; init; } = "";
    /// <summary>Short text for the right ear, such as "2/5", when it is not counting.</summary>
    public string Trailing { get; init; } = "";
    /// <summary>Counts down to this moment (UTC) in the right ear, like a timer.</summary>
    public DateTime? EndsAt { get; init; }
    /// <summary>Counts up from this moment (UTC) in the right ear, like a stopwatch.</summary>
    public DateTime? Since { get; init; }
    public double? Progress { get; init; }
    public IReadOnlyList<ActivityStep> Steps { get; init; } = Array.Empty<ActivityStep>();
    /// <summary>A conversation, as it goes: who said what, oldest first.</summary>
    public IReadOnlyList<DialogueLine> Lines { get; init; } = Array.Empty<DialogueLine>();
    /// <summary>Media playing counts as 1: an activity above that takes the ears from it.</summary>
    public int Priority { get; init; } = 2;
    /// <summary>Anything but Off stands in for Isola's own microphone dot and banner.</summary>
    public MicUse Mic { get; init; } = MicUse.Off;
}

public enum Privacy { Camera, Microphone }

/// <summary>Every running Live Activity, the one grown into a card, and the privacy dots.</summary>
public static class Activities
{
    static readonly List<LiveActivity> list = new();
    static readonly HashSet<Privacy> privacy = new();
    static readonly DispatcherTimer peekTimer = new();

    public static IReadOnlyList<LiveActivity> All => list;
    public static IReadOnlyCollection<Privacy> PrivacyOn => privacy;
    /// <summary>Whether a Live Activity already shows the microphone in use, so Isola's own dot and banner stay away.</summary>
    public static bool MicrophoneShown => list.Any(a => a.Mic != MicUse.Off);
    /// <summary>The privacy dots to show: the microphone's only when no Live Activity shows it already.</summary>
    public static IReadOnlyCollection<Privacy> ShownPrivacy =>
        MicrophoneShown ? privacy.Where(p => p != Privacy.Microphone).ToList() : privacy;
    public static string? PeekId { get; private set; }
    public static event Action? Changed;

    static Activities()
    {
        peekTimer.Tick += (_, _) => DismissPeek();
    }

    public static LiveActivity? Peeked => PeekId is null ? null : list.FirstOrDefault(a => a.Id == PeekId);

    /// <summary>The activity for the ears, or null for media (or nothing).</summary>
    public static LiveActivity? Compact(bool mediaPlaying)
    {
        LiveActivity? best = null;
        foreach (var a in list) if (best is null || a.Priority > best.Priority) best = a;
        return best is not null && mediaPlaying && best.Priority <= 1 ? null : best;
    }

    public static LiveActivity? Find(string id) => list.FirstOrDefault(a => a.Id == id);

    /// <summary>Starts an activity, or updates the one with the same id in place.</summary>
    public static void Set(LiveActivity activity, bool peek = false)
    {
        var index = list.FindIndex(a => a.Id == activity.Id);
        if (index >= 0) list[index] = activity; else list.Insert(0, activity);
        if (peek) Peek(activity.Id); else Changed?.Invoke();
    }

    public static void End(string id)
    {
        list.RemoveAll(a => a.Id == id);
        if (PeekId == id) PeekId = null;
        Changed?.Invoke();
    }

    /// <summary>Grows the activity into its card for a few seconds.</summary>
    public static void Peek(string id, double seconds = 5)
    {
        if (list.All(a => a.Id != id)) return;
        PeekId = id;
        peekTimer.Stop();
        peekTimer.Interval = TimeSpan.FromSeconds(seconds);
        peekTimer.Start();
        Changed?.Invoke();
    }

    public static void DismissPeek()
    {
        peekTimer.Stop();
        if (PeekId is null) return;
        PeekId = null;
        Changed?.Invoke();
    }

    public static void SetPrivacy(Privacy indicator, bool on)
    {
        if (on ? privacy.Add(indicator) : privacy.Remove(indicator)) Changed?.Invoke();
    }
}

/// <summary>Plays an alarm over and over until it is answered, for a minute at most.</summary>
public static class Ringer
{
    static SoundPlayer? player;
    static readonly DispatcherTimer limit = new() { Interval = TimeSpan.FromSeconds(60) };

    static Ringer()
    {
        limit.Tick += (_, _) => Stop();
    }

    public static void Start(string sound = "Alarm01")
    {
        Stop();
        if (!Settings.Current.LiveTimers)
        {
            Notify.Play(sound);
            return;
        }
        try
        {
            var file = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Media", sound + ".wav");
            if (!File.Exists(file))
            {
                SystemSounds.Exclamation.Play();
                return;
            }
            player = new SoundPlayer(file);
            player.PlayLooping();
            limit.Start();
        }
        catch { }
    }

    public static void Stop()
    {
        limit.Stop();
        try { player?.Stop(); } catch { }
        player = null;
    }
}
