using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using Isola.Services;

namespace Isola.Views;

/// <summary>The System tab: CPU, memory, disk and battery as rings.</summary>
sealed class SystemView : ITabView
{
    readonly SystemStats stats;
    readonly StackPanel root = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    readonly Gauge cpu = new("CPU", Ui.Mint, Ui.Green);
    readonly Gauge memory = new("Memory", Ui.Yellow, Ui.Orange);
    readonly Gauge disk = new("Disk", Ui.Rgb(100, 210, 255), Ui.Blue);
    readonly Gauge battery = new("Battery", Ui.Green, Ui.Mint);

    public FrameworkElement Root => root;

    public SystemView(SystemStats stats)
    {
        this.stats = stats;
        foreach (var g in new[] { cpu, memory, disk, battery }) root.Children.Add(g);
        stats.Changed += Update;
    }

    bool shown;

    public void Shown()
    {
        if (shown) return;
        shown = true;
        stats.Start();
    }

    public void Hidden()
    {
        if (!shown) return;
        shown = false;
        stats.Stop();
    }

    void Update()
    {
        cpu.Set(stats.Cpu, $"{stats.Cpu * 100:0}%");
        memory.Set(stats.Memory, stats.MemoryText);
        disk.Set(stats.Disk, stats.DiskText);
        if (stats.Battery is { } level)
        {
            battery.Visibility = Visibility.Visible;
            battery.Title = stats.Charging ? "Charging" : "Battery";
            battery.Colors(level <= 20 && !stats.Charging ? Ui.Red : Ui.Green, level <= 20 && !stats.Charging ? Ui.Orange : Ui.Mint);
            battery.Set(level / 100.0, $"{level}%");
        }
        else battery.Visibility = Visibility.Collapsed;
    }

    sealed class Gauge : StackPanel
    {
        const double Size = 82, Line = 7;
        readonly Path arc = new() { StrokeThickness = Line, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
        readonly TextBlock number = Ui.Label("0", 20, FontWeights.SemiBold);
        readonly TextBlock title;
        readonly TextBlock detail = Ui.Label("", 10, FontWeights.Normal, 0.5);

        public string Title { set => title.Text = value; }

        public Gauge(string name, Color a, Color b)
        {
            Margin = new Thickness(13, 0, 13, 0);
            MinWidth = 90;
            var ring = new Grid { Width = Size, Height = Size, HorizontalAlignment = HorizontalAlignment.Center };
            ring.Children.Add(new Ellipse { Stroke = Ui.White(0.12), StrokeThickness = Line });
            ring.Children.Add(arc);
            number.HorizontalAlignment = HorizontalAlignment.Center;
            number.VerticalAlignment = VerticalAlignment.Center;
            ring.Children.Add(number);
            Children.Add(ring);
            title = Ui.Label(name, 12, FontWeights.SemiBold);
            title.HorizontalAlignment = HorizontalAlignment.Center;
            title.Margin = new Thickness(0, 8, 0, 1);
            Children.Add(title);
            detail.HorizontalAlignment = HorizontalAlignment.Center;
            Children.Add(detail);
            Colors(a, b);
        }

        public void Colors(Color a, Color b)
        {
            arc.Stroke = new LinearGradientBrush(a, b, 45);
            arc.Effect = Ui.Glow(a, 10, 0.5);
        }

        public void Set(double value, string text)
        {
            value = Math.Clamp(value, 0.001, 0.9999);
            number.Text = $"{value * 100:0}";
            detail.Text = text;
            double r = (Size - Line) / 2, c = Size / 2;
            var angle = value * 2 * Math.PI;
            var end = new Point(c + r * Math.Sin(angle), c - r * Math.Cos(angle));
            var figure = new PathFigure { StartPoint = new Point(c, c - r) };
            figure.Segments.Add(new ArcSegment(end, new Size(r, r), 0, value > 0.5, SweepDirection.Clockwise, true));
            arc.Data = new PathGeometry(new[] { figure });
        }
    }
}
