using System;
using System.Drawing;
using System.Windows.Forms;

namespace Isola;

/// <summary>Isola's icon in the notification area, with Settings and Quit.</summary>
sealed class TrayIcon : IDisposable
{
    readonly NotifyIcon icon;

    public TrayIcon(Action openSettings, Action quit)
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("Settings…", null, (_, _) => openSettings());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit Isola", null, (_, _) => quit());

        using var stream = typeof(TrayIcon).Assembly.GetManifestResourceStream("Isola.ico");
        icon = new NotifyIcon
        {
            Icon = stream is null ? SystemIcons.Application : new Icon(stream, SystemInformation.SmallIconSize),
            Text = "Isola",
            ContextMenuStrip = menu,
            Visible = true,
        };
        icon.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) openSettings(); };
    }

    public void Dispose()
    {
        icon.Visible = false;
        icon.Dispose();
    }
}
