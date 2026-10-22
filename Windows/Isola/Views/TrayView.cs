using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using Isola.Services;

namespace Isola.Views;

/// <summary>What each tab of the open island provides.</summary>
interface ITabView
{
    FrameworkElement Root { get; }
    void Shown();
    void Hidden();
}

/// <summary>The File Tray: drop files on the island, drag them back out whenever you need them.</summary>
sealed class TrayView : ITabView
{
    readonly FileTray tray;
    readonly Window owner;
    readonly Grid root = new();
    readonly Rectangle dash;
    readonly Grid zone = new();
    readonly TextBlock status = Ui.Label("", 11, FontWeights.Normal, 0.6);
    readonly StackPanel actions = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };

    public FrameworkElement Root => root;

    public TrayView(FileTray tray, Window owner)
    {
        this.tray = tray;
        this.owner = owner;
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(32) });

        dash = new Rectangle
        {
            RadiusX = 18, RadiusY = 18, Stroke = Ui.White(0.25), StrokeThickness = 1.5,
            StrokeDashArray = new DoubleCollection { 4, 3.3 },
        };
        zone.Children.Add(dash);
        root.Children.Add(zone);

        var bottom = new Grid { VerticalAlignment = VerticalAlignment.Bottom, Height = 22 };
        Grid.SetRow(bottom, 1);
        status.VerticalAlignment = VerticalAlignment.Center;
        bottom.Children.Add(status);
        bottom.Children.Add(actions);
        root.Children.Add(bottom);

        actions.Children.Add(Spaced(Ui.Pill(Ui.Share, "Share", () => FileActions.Share(owner, tray.Items))));
        actions.Children.Add(Spaced(Ui.Pill(Ui.Package, "Zip all", tray.ZipAll)));
        actions.Children.Add(Spaced(Ui.Pill(Ui.Close, "Clear", tray.Clear)));

        root.AllowDrop = true;
        root.DragEnter += (_, e) => Targeted(e, true);
        root.DragOver += (_, e) => Targeted(e, true);
        root.DragLeave += (_, _) => dash.Stroke = Ui.White(0.25);
        root.Drop += (_, e) =>
        {
            dash.Stroke = Ui.White(0.25);
            if (e.Data.GetData(DataFormats.FileDrop) is string[] files) tray.Add(files);
            e.Handled = true;
        };
        tray.Changed += Rebuild;
        Rebuild();
    }

    static FrameworkElement Spaced(FrameworkElement e)
    {
        e.Margin = new Thickness(8, 0, 0, 0);
        return e;
    }

    void Targeted(DragEventArgs e, bool on)
    {
        var files = e.Data.GetDataPresent(DataFormats.FileDrop);
        e.Effects = files ? DragDropEffects.Copy : DragDropEffects.None;
        dash.Stroke = on && files ? Ui.Brush(Ui.Blue) : Ui.White(0.25);
        e.Handled = true;
    }

    public void Shown() { }
    public void Hidden() { }

    void Rebuild()
    {
        while (zone.Children.Count > 1) zone.Children.RemoveAt(1);
        status.Text = tray.Status ?? "";
        actions.Visibility = tray.Items.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

        if (tray.Items.Count == 0)
        {
            var empty = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            empty.Children.Add(Ui.Glyph(Ui.Download, 26, Ui.White(0.8)));
            var title = Ui.Label("Drop files here", 14, FontWeights.SemiBold, 0.85);
            title.HorizontalAlignment = HorizontalAlignment.Center;
            title.Margin = new Thickness(0, 6, 0, 2);
            empty.Children.Add(title);
            var detail = Ui.Label("Drag them back out whenever you need them.", 11, FontWeights.Normal, 0.5);
            detail.HorizontalAlignment = HorizontalAlignment.Center;
            empty.Children.Add(detail);
            zone.Children.Add(empty);
            return;
        }

        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(12), VerticalAlignment = VerticalAlignment.Center };
        foreach (var path in tray.Items) row.Children.Add(Tile(path));
        zone.Children.Add(new ScrollViewer
        {
            Content = row,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            PanningMode = PanningMode.HorizontalOnly,
        });
    }

    FrameworkElement Tile(string path)
    {
        var stack = new StackPanel { Width = 70 };
        var icon = FileActions.IconFor(path);
        stack.Children.Add(icon is null
            ? Ui.Glyph(Ui.Folder, 34)
            : new Image { Source = icon, Width = 52, Height = 52, Stretch = Stretch.Uniform });
        var name = new TextBlock
        {
            Text = System.IO.Path.GetFileName(path), FontFamily = Ui.Text, FontSize = 10, Foreground = Brushes.White,
            TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, TextTrimming = TextTrimming.CharacterEllipsis,
            MaxHeight = 28, Margin = new Thickness(0, 4, 0, 0),
        };
        stack.Children.Add(name);

        var tile = new Border
        {
            Child = stack, Padding = new Thickness(8), Margin = new Thickness(0, 0, 12, 0), CornerRadius = new CornerRadius(12),
            Background = Ui.White(0.07), Cursor = Cursors.Hand, ToolTip = path,
        };
        Ui.Hover(tile, Ui.White(0.07), Ui.White(0.14));

        // Drag it back out, to wherever it is needed.
        Point? start = null;
        tile.PreviewMouseLeftButtonDown += (_, e) => start = e.GetPosition(tile);
        tile.PreviewMouseMove += (_, e) =>
        {
            if (start is not { } s || e.LeftButton != MouseButtonState.Pressed) return;
            var p = e.GetPosition(tile);
            if (Math.Abs(p.X - s.X) + Math.Abs(p.Y - s.Y) < 5) return;
            start = null;
            DragDrop.DoDragDrop(tile, new DataObject(DataFormats.FileDrop, new[] { path }), DragDropEffects.Copy | DragDropEffects.Move);
        };
        tile.MouseLeftButtonUp += (_, e) => start = null;
        tile.MouseLeftButtonDown += (_, e) => { if (e.ClickCount == 2) FileActions.Open(path); };

        var menu = new ContextMenu();
        menu.Items.Add(Item("Open", () => FileActions.Open(path)));
        menu.Items.Add(Item("Show in File Explorer", () => FileActions.Reveal(path)));
        menu.Items.Add(Item("Share…", () => FileActions.Share(owner, new[] { path })));
        if (FileActions.IsImage(path))
        {
            var format = FileActions.ConversionTarget(path) == ".png" ? "PNG" : "JPEG";
            menu.Items.Add(Item($"Convert to {format}", () => tray.Convert(path)));
        }
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Remove from Tray", () => tray.Remove(path)));
        tile.ContextMenu = menu;
        return tile;
    }

    static MenuItem Item(string header, Action action)
    {
        var item = new MenuItem { Header = header };
        item.Click += (_, _) => action();
        return item;
    }
}
