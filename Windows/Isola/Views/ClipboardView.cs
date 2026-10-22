using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Isola.Services;

namespace Isola.Views;

/// <summary>The Clipboard: everything you copied, as cards. Click one to copy it again; search to find one.</summary>
sealed class ClipboardView : ITabView
{
    readonly ClipboardService clipboard;
    readonly Action<bool> keyboard;
    readonly Grid root = new();
    readonly TextBlock count = Ui.Label("", 11, FontWeights.SemiBold, 0.5);
    readonly Border searchButton;
    readonly Border searchBar;
    readonly TextBox query;
    readonly Grid strip = new();
    Guid? copied;

    public FrameworkElement Root => root;

    /// <param name="keyboard">Asks the island to take, or give back, the keyboard for the search field.</param>
    public ClipboardView(ClipboardService clipboard, Action<bool> keyboard)
    {
        this.clipboard = clipboard;
        this.keyboard = keyboard;
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(24) });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var header = new Grid();
        count.VerticalAlignment = VerticalAlignment.Center;
        header.Children.Add(count);
        searchButton = Ui.Round(Ui.Search, 24, StartSearch);
        searchButton.HorizontalAlignment = HorizontalAlignment.Right;
        header.Children.Add(searchButton);

        query = new TextBox
        {
            Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = Brushes.White,
            CaretBrush = Brushes.White, FontFamily = Ui.Text, FontSize = 12, VerticalContentAlignment = VerticalAlignment.Center,
        };
        query.TextChanged += (_, _) => Rebuild();
        query.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) EndSearch();
            else if (e.Key == Key.Enter) { var first = Matches().FirstOrDefault(); if (first is not null) Copy(first); }
        };
        var bar = new Grid();
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bar.Children.Add(Ui.Glyph(Ui.Search, 11, Ui.White(0.6)));
        Grid.SetColumn(query, 1);
        query.Margin = new Thickness(6, 0, 6, 0);
        bar.Children.Add(query);
        var close = Ui.Glyph(Ui.Close, 10, Ui.White(0.5));
        close.Cursor = Cursors.Hand;
        close.MouseLeftButtonUp += (_, e) => { e.Handled = true; EndSearch(); };
        Grid.SetColumn(close, 2);
        bar.Children.Add(close);
        searchBar = Ui.Capsule(new Border
        {
            Child = bar, Background = Ui.White(0.12), Padding = new Thickness(10, 0, 10, 0), Height = 24,
            Visibility = Visibility.Collapsed,
        });
        header.Children.Add(searchBar);
        root.Children.Add(header);

        Grid.SetRow(strip, 1);
        strip.Margin = new Thickness(0, 8, 0, 0);
        root.Children.Add(strip);
        clipboard.Changed += Rebuild;
        Rebuild();
    }

    public void Shown() => Rebuild();
    public void Hidden() => EndSearch();

    void StartSearch()
    {
        searchBar.Visibility = Visibility.Visible;
        searchButton.Visibility = Visibility.Collapsed;
        count.Visibility = Visibility.Collapsed;
        keyboard(true);
        root.Dispatcher.BeginInvoke(DispatcherPriority.Input, () => { query.Focus(); Keyboard.Focus(query); });
    }

    void EndSearch()
    {
        if (searchBar.Visibility != Visibility.Visible) return;
        query.Text = "";
        searchBar.Visibility = Visibility.Collapsed;
        searchButton.Visibility = Visibility.Visible;
        count.Visibility = Visibility.Visible;
        keyboard(false);
    }

    public bool Searching => searchBar.Visibility == Visibility.Visible;

    ClipEntry[] Matches()
    {
        var words = query.Text.ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return clipboard.Entries.Where(e => words.All(w => e.SearchText.ToLowerInvariant().Contains(w))).ToArray();
    }

    void Rebuild()
    {
        strip.Children.Clear();
        var n = clipboard.Entries.Count;
        count.Text = n == 1 ? "1 item" : $"{n} items";
        if (n == 0)
        {
            var empty = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            empty.Children.Add(Ui.Glyph(Ui.Paste, 26, Ui.White(0.8)));
            var title = Ui.Label("Clipboard is empty", 14, FontWeights.SemiBold, 0.85);
            title.HorizontalAlignment = HorizontalAlignment.Center;
            title.Margin = new Thickness(0, 6, 0, 2);
            empty.Children.Add(title);
            var detail = Ui.Label("Copy text, links, colours or images and they will show up here.", 11, FontWeights.Normal, 0.5);
            detail.HorizontalAlignment = HorizontalAlignment.Center;
            empty.Children.Add(detail);
            strip.Children.Add(empty);
            return;
        }
        var shown = Matches();
        if (shown.Length == 0)
        {
            var none = Ui.Label($"Nothing matches “{query.Text}”", 12, FontWeights.Normal, 0.5);
            none.HorizontalAlignment = HorizontalAlignment.Center;
            none.VerticalAlignment = VerticalAlignment.Center;
            strip.Children.Add(none);
            return;
        }
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var entry in shown.Take(60)) row.Children.Add(Card(entry));
        var scroll = new ScrollViewer
        {
            Content = row, HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, PanningMode = PanningMode.HorizontalOnly,
        };
        // The wheel scrolls sideways, as there is nothing to scroll up and down.
        scroll.PreviewMouseWheel += (_, e) => { scroll.ScrollToHorizontalOffset(scroll.HorizontalOffset - e.Delta); e.Handled = true; };
        strip.Children.Add(scroll);
    }

    FrameworkElement Card(ClipEntry entry)
    {
        var grid = new Grid { Width = 132 };
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(24) });
        grid.Children.Add(Preview(entry));

        var (glyph, label) = entry.Kind switch
        {
            ClipKind.Link => (Ui.Link, "Link"),
            ClipKind.Color => (Ui.Color, "Colour"),
            ClipKind.Image => (Ui.Picture, "Image"),
            _ => (Ui.Font, "Text"),
        };
        var foot = new DockPanel { Background = Ui.Black(0.3), LastChildFill = false };
        var icon = Ui.Glyph(glyph, 9, Ui.White(0.8));
        icon.Margin = new Thickness(10, 0, 5, 0);
        foot.Children.Add(icon);
        var name = Ui.Label(label, 10, FontWeights.SemiBold, 0.8);
        name.VerticalAlignment = VerticalAlignment.Center;
        foot.Children.Add(name);
        if (entry.Kind == ClipKind.Image && entry.PixelSize is not null)
        {
            var size = Ui.Label(entry.PixelSize, 9, FontWeights.Normal, 0.5);
            size.VerticalAlignment = VerticalAlignment.Center;
            size.Margin = new Thickness(0, 0, 10, 0);
            DockPanel.SetDock(size, Dock.Right);
            foot.Children.Add(size);
        }
        Grid.SetRow(foot, 1);
        grid.Children.Add(foot);

        if (copied == entry.Id)
        {
            var overlay = new Grid { Background = Ui.Black(0.55) };
            Grid.SetRowSpan(overlay, 2);
            var text = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            text.Children.Add(Ui.Glyph("", 13, Ui.Brush(Ui.Green)));
            var c = Ui.Label("Copied", 12, FontWeights.SemiBold);
            c.Foreground = Ui.Brush(Ui.Green);
            c.Margin = new Thickness(6, 0, 0, 0);
            text.Children.Add(c);
            overlay.Children.Add(text);
            grid.Children.Add(overlay);
        }

        var card = new Border
        {
            Child = grid, CornerRadius = new CornerRadius(14), ClipToBounds = true, Background = Ui.White(0.08),
            BorderBrush = Ui.White(0.1), BorderThickness = new Thickness(1), Margin = new Thickness(0, 0, 10, 0),
            Cursor = Cursors.Hand,
        };
        card.MouseEnter += (_, _) => card.BorderBrush = Ui.White(0.35);
        card.MouseLeave += (_, _) => card.BorderBrush = Ui.White(0.1);
        card.MouseLeftButtonUp += (_, e) => { e.Handled = true; Copy(entry); };

        var menu = new ContextMenu();
        menu.Items.Add(Item("Copy", () => Copy(entry)));
        if (entry.Kind == ClipKind.Link) menu.Items.Add(Item("Open Link", () => FileActions.Open(entry.Text.Trim())));
        if (entry.ImageFile is not null) menu.Items.Add(Item("Show in File Explorer", () => FileActions.Reveal(entry.ImageFile)));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Delete", () => clipboard.Remove(entry)));
        card.ContextMenu = menu;
        return card;
    }

    static FrameworkElement Preview(ClipEntry entry)
    {
        switch (entry.Kind)
        {
            case ClipKind.Link:
            {
                Uri.TryCreate(entry.Text.Trim(), UriKind.Absolute, out var uri);
                var stack = new StackPanel { Margin = new Thickness(10) };
                stack.Children.Add(new TextBlock { Text = Ui.Link, FontFamily = Ui.Icons, FontSize = 18, Foreground = Ui.Brush(Ui.Rgb(100, 210, 255)) });
                var host = Ui.Label(uri?.Host ?? entry.Text, 12, FontWeights.SemiBold);
                host.Margin = new Thickness(0, 4, 0, 0);
                stack.Children.Add(host);
                stack.Children.Add(Ui.Label(uri?.AbsolutePath ?? "", 10, FontWeights.Normal, 0.5));
                return stack;
            }
            case ClipKind.Color:
            {
                var color = ClipboardService.ParseColor(entry.Text) ?? Ui.Gray;
                var light = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B > 153;
                var g = new Grid { Background = new SolidColorBrush(color) };
                var t = new TextBlock
                {
                    Text = entry.Text.Trim().ToUpperInvariant(), FontFamily = Ui.Mono, FontSize = 13, FontWeight = FontWeights.SemiBold,
                    Foreground = light ? Brushes.Black : Brushes.White, HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                };
                g.Children.Add(t);
                return g;
            }
            case ClipKind.Image when entry.ImageFile is not null && System.IO.File.Exists(entry.ImageFile):
                try
                {
                    return new Border { Background = new ImageBrush(ClipboardService.LoadImage(entry.ImageFile, 264)) { Stretch = Stretch.UniformToFill } };
                }
                catch { return Ui.Glyph(Ui.Picture, 24, Ui.White(0.4)); }
            case ClipKind.Image:
                return Ui.Glyph(Ui.Picture, 24, Ui.White(0.4));
            default:
                return new TextBlock
                {
                    Text = entry.Text.Trim(), FontFamily = Ui.Text, FontSize = 11, Foreground = Ui.White(0.9),
                    TextWrapping = TextWrapping.Wrap, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(10),
                };
        }
    }

    void Copy(ClipEntry entry)
    {
        clipboard.Copy(entry);
        copied = entry.Id;
        Rebuild();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.2) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (copied == entry.Id) { copied = null; Rebuild(); }
        };
        timer.Start();
    }

    static MenuItem Item(string header, Action action)
    {
        var item = new MenuItem { Header = header };
        item.Click += (_, _) => action();
        return item;
    }
}
