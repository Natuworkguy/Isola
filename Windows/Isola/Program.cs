using System;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;

namespace Isola;

static class Program
{
    const string InstanceName = "Isola.Windows.Instance";
    const string PipeName = "Isola.Windows.Links";
    const string QuitMessage = "isola-internal:quit";
    const string TrayMessage = "isola-internal:tray";

    [STAThread]
    static void Main(string[] args)
    {
        var link = args.FirstOrDefault(a => a.StartsWith("isola:", StringComparison.OrdinalIgnoreCase));
        // Files given on the command line (Isola.exe report.pdf, or "Open with") go to the File Tray.
        var files = args.Where(a => !a.StartsWith("isola:", StringComparison.OrdinalIgnoreCase) && (File.Exists(a) || Directory.Exists(a)))
            .Select(Path.GetFullPath).ToArray();
        using var mutex = new Mutex(false, InstanceName);
        if (!Acquire(mutex, 0))
        {
            // An isola:// link or files go to the running copy, so a script's notification never restarts Isola.
            if (link is not null || files.Length > 0)
            {
                if (link is not null) Send(link);
                if (files.Length > 0) Send(TrayMessage + "\t" + string.Join("\t", files));
                return;
            }
            // Only one Isola runs at a time: this new copy replaces the running one.
            ReplaceRunningCopy();
            if (!Acquire(mutex, 5000)) return;
        }

        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += async (_, _) =>
        {
            await Hub.Start();
            Listen(app);
            if (link is not null) Hub.HandleLink(link);
            if (files.Length > 0) Hub.AddToTray(files);
        };
        app.DispatcherUnhandledException += (_, e) =>
        {
            // Keep the island alive through a bad frame or a misbehaving system API.
            try { File.AppendAllText(Path.Combine(Settings.Folder, "errors.log"), $"{DateTime.Now:u} {e.Exception}\n"); } catch { }
            e.Handled = true;
        };
        app.Run();
        try { mutex.ReleaseMutex(); } catch { }
    }

    static bool Acquire(Mutex mutex, int milliseconds)
    {
        try { return mutex.WaitOne(milliseconds); }
        catch (AbandonedMutexException) { return true; } // the previous copy ended without letting go
    }

    /// <summary>Asks the running copy to quit (so it can tidy up), and ends it if it has not after a few seconds.</summary>
    static void ReplaceRunningCopy()
    {
        Send(QuitMessage);
        var me = Environment.ProcessId;
        foreach (var other in System.Diagnostics.Process.GetProcessesByName("Isola").Where(p => p.Id != me))
        {
            try
            {
                if (!other.WaitForExit(3000)) other.Kill(entireProcessTree: true);
                other.WaitForExit(2000);
            }
            catch { }
        }
    }

    static void Send(string link)
    {
        try
        {
            using var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
            client.Connect(2000);
            using var writer = new StreamWriter(client) { AutoFlush = true };
            writer.WriteLine(link);
        }
        catch { }
    }

    /// <summary>Takes links from later launches (a script running `start isola://notify?…`), and the request to quit
    /// from a newer copy taking over.</summary>
    static void Listen(Application app)
    {
        Task.Run(async () =>
        {
            while (true)
            {
                try
                {
                    using var server = new NamedPipeServerStream(PipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
                    await server.WaitForConnectionAsync();
                    using var reader = new StreamReader(server);
                    var line = await reader.ReadLineAsync();
                    if (line?.Trim() == QuitMessage) _ = app.Dispatcher.BeginInvoke(Hub.Quit);
                    else if (line?.StartsWith(TrayMessage + "\t") == true)
                    {
                        var paths = line[(TrayMessage.Length + 1)..].Split('\t', StringSplitOptions.RemoveEmptyEntries);
                        _ = app.Dispatcher.BeginInvoke(() => Hub.AddToTray(paths));
                    }
                    else if (!string.IsNullOrWhiteSpace(line)) _ = app.Dispatcher.BeginInvoke(() => Hub.HandleLink(line.Trim()));
                }
                catch
                {
                    await Task.Delay(500);
                }
            }
        });
    }
}
