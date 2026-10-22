using System;
using System.Collections.Generic;
using System.IO;
using System.Net.NetworkInformation;
using System.Windows.Threading;

namespace Isola.Services;

/// <summary>CPU, memory, disk and battery, sampled while the System or Home tab is open.</summary>
public sealed class SystemStats
{
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1.5) };
    long lastIdle, lastKernel, lastUser;
    // How many views are showing the stats. Home and System overlap while switching tabs, so sampling stops only when
    // the last one goes.
    int users;
    readonly List<double> cpuHistory = new(), memoryHistory = new(), netHistory = new();
    long lastRx, lastTx;
    DateTime lastNetAt;

    public double Cpu { get; private set; }
    public double Memory { get; private set; }
    public string MemoryText { get; private set; } = "";
    public double Disk { get; private set; }
    public string DiskText { get; private set; } = "";
    public int? Battery { get; private set; }
    public bool Charging { get; private set; }
    /// <summary>The last minute or so of CPU and memory use, oldest first, for the Home tab's graphs.</summary>
    public IReadOnlyList<double> CpuHistory => cpuHistory;
    public IReadOnlyList<double> MemoryHistory => memoryHistory;
    /// <summary>Bytes a second, down and up, across the network adapters that are up.</summary>
    public double NetDown { get; private set; }
    public double NetUp { get; private set; }
    public IReadOnlyList<double> NetHistory => netHistory;
    public event Action? Changed;

    public SystemStats()
    {
        timer.Tick += (_, _) => Sample();
    }

    public void Start()
    {
        users++;
        if (timer.IsEnabled) return;
        Sample();
        timer.Start();
    }

    public void Stop()
    {
        users = Math.Max(users - 1, 0);
        if (users > 0) return;
        timer.Stop();
        lastNetAt = default;
    }

    void SampleNetwork()
    {
        try
        {
            long rx = 0, tx = 0;
            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (nic.OperationalStatus != OperationalStatus.Up) continue;
                if (nic.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel) continue;
                var stats = nic.GetIPStatistics();
                rx += stats.BytesReceived;
                tx += stats.BytesSent;
            }
            var now = DateTime.UtcNow;
            var seconds = (now - lastNetAt).TotalSeconds;
            // An adapter going away makes the totals drop; skip that sample rather than show a negative rate.
            if (lastNetAt != default && seconds > 0 && rx >= lastRx && tx >= lastTx)
            {
                NetDown = (rx - lastRx) / seconds;
                NetUp = (tx - lastTx) / seconds;
                Record(netHistory, NetDown);
            }
            (lastRx, lastTx, lastNetAt) = (rx, tx, now);
        }
        catch { }
    }

    static void Record(List<double> history, double value)
    {
        history.Add(value);
        if (history.Count > 40) history.RemoveAt(0);
    }

    void Sample()
    {
        if (Native.GetSystemTimes(out var idle, out var kernel, out var user))
        {
            long di = idle - lastIdle, dk = kernel - lastKernel, du = user - lastUser;
            if (lastKernel != 0 && dk + du > 0) Cpu = Math.Clamp(1 - (double)di / (dk + du), 0, 1);
            (lastIdle, lastKernel, lastUser) = (idle, kernel, user);
        }

        var mem = new Native.MEMORYSTATUSEX { dwLength = (uint)System.Runtime.InteropServices.Marshal.SizeOf<Native.MEMORYSTATUSEX>() };
        if (Native.GlobalMemoryStatusEx(ref mem) && mem.ullTotalPhys > 0)
        {
            var used = mem.ullTotalPhys - mem.ullAvailPhys;
            Memory = (double)used / mem.ullTotalPhys;
            MemoryText = $"{used / 1073741824.0:0.0} of {mem.ullTotalPhys / 1073741824.0:0} GB";
        }

        try
        {
            var drive = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\");
            Disk = 1 - (double)drive.AvailableFreeSpace / drive.TotalSize;
            DiskText = $"{drive.AvailableFreeSpace / 1073741824.0:0} GB free";
        }
        catch { }

        if (Native.GetSystemPowerStatus(out var power) && power.BatteryFlag != 128 && power.BatteryLifePercent <= 100)
        {
            Battery = power.BatteryLifePercent;
            Charging = power.ACLineStatus == 1;
        }
        else Battery = null;

        SampleNetwork();
        Record(cpuHistory, Cpu);
        Record(memoryHistory, Memory);
        Changed?.Invoke();
    }
}
