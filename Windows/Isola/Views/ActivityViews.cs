using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using Isola.Services;

namespace Isola.Views;

/// <summary>
/// The closed island's ears for a Live Activity: its icon (or live bars while it listens) on the left, and on the right
/// a countdown, a count up, a progress ring, a short label or a pulsing dot.
/// </summary>
sealed class CompactActivityView : Grid
{
    readonly TextBlock glyph = Ui.Glyph(Ui.Clock, 13);
    readonly Grid left = new();
    readonly Grid right = new();
    readonly DispatcherTimer clock = new() { Interval = TimeSpan.FromSeconds(1) };
    LiveActivity? activity;
    TextBlock? counter;

    public CompactActivityView()
    {
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(50) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(50) });
        left.Children.Add(glyph);
        Children.Add(left);
        SetColumn(right, 2);
        Children.Add(right);
        clock.Tick += (_, _) => Count();
    }

    public void Show(LiveActivity? next, bool dots)
    {
        right.Margin = new Thickness(0, 0, dots ? 8 : 0, 0);
        if (next == activity) return;
        activity = next;
        right.Children.Clear();
        left.Children.Clear();
        left.Children.Add(glyph);
        counter = null;
        clock.Stop();
        if (next is null)
        {
            glyph.Text = "";
            return;
        }
        glyph.Text = next.Glyph;
        glyph.Foreground = Ui.Brush(next.Tint);
        glyph.Effect = Ui.Glow(next.Tint, 8, 0.6);
        if (next.Mic is MicUse.Listening or MicUse.Talking)
        {
            left.Children.Clear();
            var bars = ListeningBars(next.Tint, next.Mic == MicUse.Talking, 14);
            bars.Effect = Ui.Glow(next.Tint, 8, 0.6);
            left.Children.Add(bars);
        }
        if (next.Progress is { } progress && next.EndsAt is null)
        {
            right.Children.Add(Ring(progress, next.Tint, 15, 2.5));
        }
        else if (next.EndsAt is not null || next.Since is not null)
        {
            counter = Label(next.Tint);
            right.Children.Add(counter);
            Count();
            clock.Start();
        }
        else if (next.Trailing.Length > 0)
        {
            var label = Label(next.Tint);
            label.Text = next.Trailing;
            right.Children.Add(label);
        }
        else right.Children.Add(PulsingDot(next.Tint));
    }

    void Count()
    {
        if (counter is null || activity is null) return;
        var now = DateTime.UtcNow;
        var seconds = activity.EndsAt is { } end ? (end - now).TotalSeconds : activity.Since is { } since ? (now - since).TotalSeconds : 0;
        counter.Text = Countdown.Format(TimeSpan.FromSeconds(Math.Max(seconds, 0)));
    }

    static TextBlock Label(Color tint)
    {
        var label = Ui.Label("", 11, FontWeights.SemiBold, 1, Ui.Display);
        label.Foreground = Ui.Brush(tint);
        label.HorizontalAlignment = HorizontalAlignment.Center;
        label.VerticalAlignment = VerticalAlignment.Center;
        label.Typography.NumeralAlignment = FontNumeralAlignment.Tabular;
        return label;
    }

    public static FrameworkElement PulsingDot(Color tint)
    {
        var dot = new Ellipse
        {
            Width = 7, Height = 7, Fill = Ui.Brush(tint), Effect = Ui.Glow(tint, 6, 0.8),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        };
        var pulse = new DoubleAnimation(1, 0.45, TimeSpan.FromSeconds(0.9)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever };
        Timeline.SetDesiredFrameRate(pulse, 30);
        dot.BeginAnimation(OpacityProperty, pulse);
        return dot;
    }

    /// <summary>Bars like a voice, tallest in the middle: lively while you talk, barely stirring while it waits for you.</summary>
    public static FrameworkElement ListeningBars(Color tint, bool talking, double height)
    {
        var panel = new StackPanel
        {
            Orientation = Orientation.Horizontal, Height = height,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        };
        double[] shape = { 0.55, 0.8, 1, 0.8, 0.55 };
        // Each bar at its own pace, so together they move like speech rather than a metronome.
        double[] pace = { 0.31, 0.24, 0.2, 0.27, 0.35 };
        for (var i = 0; i < shape.Length; i++)
        {
            var scale = new ScaleTransform(1, talking ? 0.5 : 0.3);
            panel.Children.Add(new Rectangle
            {
                Width = 2.5, Height = height * shape[i], RadiusX = 1.25, RadiusY = 1.25, Fill = Ui.Brush(tint),
                Margin = new Thickness(i == 0 ? 0 : 2, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center,
                RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = scale,
            });
            var move = talking
                ? new DoubleAnimation(0.3, 1, TimeSpan.FromSeconds(pace[i]))
                : new DoubleAnimation(0.25, 0.4, TimeSpan.FromSeconds(1.1 + i * 0.13));
            move.AutoReverse = true;
            move.RepeatBehavior = RepeatBehavior.Forever;
            move.EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut };
            Timeline.SetDesiredFrameRate(move, 30);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, move);
        }
        return panel;
    }

    public static FrameworkElement Ring(double value, Color tint, double size, double line)
    {
        var grid = new Grid { Width = size, Height = size, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        grid.Children.Add(new Ellipse { Stroke = Ui.White(0.15), StrokeThickness = line });
        value = Math.Clamp(value, 0.001, 0.9999);
        double r = (size - line) / 2, c = size / 2, angle = value * 2 * Math.PI;
        var figure = new PathFigure { StartPoint = new Point(c, c - r) };
        figure.Segments.Add(new ArcSegment(new Point(c + r * Math.Sin(angle), c - r * Math.Cos(angle)), new Size(r, r), 0, value > 0.5, SweepDirection.Clockwise, true));
        grid.Children.Add(new Path
        {
            Data = new PathGeometry(new[] { figure }), Stroke = Ui.Brush(tint), StrokeThickness = line,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
        });
        return grid;
    }
}

/// <summary>Green for the camera, orange for the microphone, as on iPhone, at the far right of the closed island.</summary>
sealed class PrivacyDotsView : StackPanel
{
    public PrivacyDotsView()
    {
        VerticalAlignment = VerticalAlignment.Center;
        HorizontalAlignment = HorizontalAlignment.Right;
        Margin = new Thickness(0, 0, 8, 0);
        IsHitTestVisible = false;
    }

    public void Show(IReadOnlyCollection<Privacy> on)
    {
        Children.Clear();
        foreach (var p in on.OrderBy(p => p))
        {
            var color = p == Privacy.Camera ? Ui.Green : Ui.Orange;
            Children.Add(new Ellipse { Width = 5, Height = 5, Fill = Ui.Brush(color), Effect = Ui.Glow(color, 5, 0.9), Margin = new Thickness(0, 1.5, 0, 1.5) });
        }
    }
}

/// <summary>
/// An activity grown into a card: its icon, title and subtitle on top, then its conversation as it goes, its steps as
/// a checklist that updates in place (done ones ticked, the current one playing), or its progress.
/// </summary>
sealed class ActivityCardView : Grid
{
    public const double Width_ = 400;

    /// <summary>At most four steps: the latest finished ones, the current one and the next.</summary>
    public static IReadOnlyList<ActivityStep> VisibleSteps(IReadOnlyList<ActivityStep> steps)
    {
        if (steps.Count <= 4) return steps;
        var anchor = -1;
        for (var i = 0; i < steps.Count; i++)
            if (steps[i].State is StepState.Active or StepState.Failed) { anchor = i; break; }
        if (anchor < 0)
            for (var i = steps.Count - 1; i >= 0; i--)
                if (steps[i].State == StepState.Done) { anchor = i; break; }
        anchor = Math.Max(anchor, 0);
        var end = Math.Min(steps.Count, Math.Max(anchor + 2, 4));
        return steps.Skip(end - 4).Take(4).ToList();
    }

    /// <summary>The latest three lines of a conversation.</summary>
    public static IReadOnlyList<DialogueLine> VisibleLines(IReadOnlyList<DialogueLine> lines) =>
        lines.Skip(Math.Max(0, lines.Count - 3)).ToList();

    /// <summary>One line of text, or two for a long one: the card fits about 44 characters a line beside the speaker.</summary>
    public static double LineHeight(DialogueLine line) => line.Text.Length > 44 ? 34 : 18;

    /// <summary>The header alone is as tall as a banner's content; the conversation, steps or progress go below it.</summary>
    public static double HeightFor(LiveActivity a)
    {
        const double header = 14 + 28 + 14;
        if (a.Lines.Count > 0) return header + 8 + VisibleLines(a.Lines).Sum(LineHeight) + (VisibleLines(a.Lines).Count - 1) * 6;
        if (a.Steps.Count > 0) return header + 8 + VisibleSteps(a.Steps).Count * 24 - 6;
        return a.Progress is null ? header : header + 14;
    }

    public void Show(LiveActivity a)
    {
        Children.Clear();
        // Centred top to bottom, so a card with only its header sits in the middle.
        var stack = new StackPanel { Margin = new Thickness(20, 14, 20, 14), VerticalAlignment = VerticalAlignment.Center };

        var header = new DockPanel();
        var icon = new Border
        {
            Width = 28, Height = 28, CornerRadius = new CornerRadius(8),
            Child = a.Mic is MicUse.Listening or MicUse.Talking
                ? CompactActivityView.ListeningBars(Colors.White, a.Mic == MicUse.Talking, 15)
                : Ui.Glyph(a.Glyph, 14),
            Background = new LinearGradientBrush(a.Tint, Ui.Rgb((byte)(a.Tint.R * 0.75), (byte)(a.Tint.G * 0.75), (byte)(a.Tint.B * 0.75)), 90),
            Effect = Ui.Glow(a.Tint, 12, 0.5), Margin = new Thickness(0, 0, 10, 0),
        };
        DockPanel.SetDock(icon, Dock.Left);
        header.Children.Add(icon);
        var titles = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        titles.Children.Add(Ui.Label(a.Title, 14, FontWeights.Bold));
        if (a.Subtitle.Length > 0)
        {
            titles.Children.Add(new Ellipse { Width = 5, Height = 5, Fill = Ui.Brush(a.Tint), Margin = new Thickness(8, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center });
            var sub = Ui.Label(a.Subtitle, 13, FontWeights.SemiBold);
            sub.Foreground = Ui.Brush(a.Tint);
            sub.MaxWidth = 220;
            titles.Children.Add(sub);
        }
        header.Children.Add(titles);
        stack.Children.Add(header);

        if (a.Lines.Count > 0)
        {
            // The conversation: each line its speaker, then what they said, the activity's own speaker (the one its
            // title names) in its colour, and the newest line brightest.
            var talk = new StackPanel { Margin = new Thickness(6, 8, 0, 0) };
            var shown = VisibleLines(a.Lines);
            for (var i = 0; i < shown.Count; i++)
            {
                var line = shown[i];
                var own = string.Equals(line.Speaker, a.Title, StringComparison.OrdinalIgnoreCase);
                var row = new DockPanel { Margin = new Thickness(0, i == 0 ? 0 : 6, 0, 0), MinHeight = 18 };
                var who = new TextBlock
                {
                    Text = line.Speaker, FontFamily = Ui.Text, FontSize = 11, FontWeight = FontWeights.Bold, Width = 46,
                    Foreground = own ? Ui.Brush(a.Tint) : Ui.White(0.55), TextTrimming = TextTrimming.CharacterEllipsis,
                    Margin = new Thickness(0, 1, 8, 0),
                };
                DockPanel.SetDock(who, Dock.Left);
                row.Children.Add(who);
                row.Children.Add(new TextBlock
                {
                    Text = line.Text, FontFamily = Ui.Text, FontSize = 12.5, FontWeight = FontWeights.Medium,
                    Foreground = Ui.White(i == shown.Count - 1 ? 0.95 : 0.62), TextWrapping = TextWrapping.Wrap,
                    MaxHeight = 34, TextTrimming = TextTrimming.CharacterEllipsis,
                });
                talk.Children.Add(row);
            }
            stack.Children.Add(talk);
        }
        else if (a.Steps.Count > 0)
        {
            var list = new StackPanel { Margin = new Thickness(6, 8, 0, 0) };
            foreach (var step in VisibleSteps(a.Steps))
            {
                var row = new DockPanel { Height = 18, Margin = new Thickness(0, list.Children.Count == 0 ? 0 : 6, 0, 0) };
                var mark = StepIcon(step.State, a.Tint);
                mark.Width = 16;
                DockPanel.SetDock(mark, Dock.Left);
                row.Children.Add(mark);
                var text = new TextBlock
                {
                    Text = MiddleTruncate(step.Text, 46), FontFamily = Ui.Text, FontSize = 12.5, FontWeight = FontWeights.Medium,
                    Foreground = Ui.White(step.State == StepState.Pending ? 0.45 : 0.92), Margin = new Thickness(9, 0, 0, 0),
                    VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis,
                };
                row.Children.Add(text);
                list.Children.Add(row);
            }
            stack.Children.Add(list);
        }
        else if (a.Progress is { } progress)
        {
            var bar = new Grid { Height = 4, Margin = new Thickness(0, 10, 0, 0) };
            bar.Children.Add(new Border { Background = Ui.White(0.14), CornerRadius = new CornerRadius(2) });
            var fill = new Border { Background = Ui.Brush(a.Tint), CornerRadius = new CornerRadius(2), HorizontalAlignment = HorizontalAlignment.Left };
            bar.SizeChanged += (_, _) => fill.Width = bar.ActualWidth * Math.Clamp(progress, 0, 1);
            bar.Children.Add(fill);
            stack.Children.Add(bar);
        }
        Children.Add(stack);
    }

    static TextBlock StepIcon(StepState state, Color tint) => state switch
    {
        StepState.Done => Ui.Glyph(Ui.Check, 12, Ui.Brush(tint)),
        StepState.Active => Ui.Glyph(Ui.Play, 10, Ui.Brush(tint)),
        StepState.Failed => Ui.Glyph(Ui.Close, 11, Ui.Brush(Ui.Red)),
        _ => Ui.Glyph("", 8, Ui.White(0.35)),
    };

    /// <summary>Keeps both ends of a long line, like "Searched for...form padding".</summary>
    public static string MiddleTruncate(string text, int max)
    {
        if (text.Length <= max) return text;
        var keep = max - 3;
        return text[..(keep / 2)] + "..." + text[^(keep - keep / 2)..];
    }
}
