using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using Notchbeat.Core;
using Notchbeat.Helpers;

namespace Notchbeat.Models;

public sealed class SystemStats : ObservableObject
{
    private const int HistoryLength = 40;
    private readonly DispatcherTimer _timer;

    private double _cpuUsage;
    private long _memUsed;
    private long _memTotal;
    private double _netIn;
    private double _netOut;
    private int? _battery;
    private bool _isCharging;
    private bool _isOnAc = true;

    private long _lastBytesReceived;
    private long _lastBytesSent;
    private DateTime _lastNetTime = DateTime.UtcNow;

    private NativeMethods.FILETIME _prevSysKernel;
    private NativeMethods.FILETIME _prevSysUser;
    private NativeMethods.FILETIME _prevSysIdle;

    public double CpuUsage { get => _cpuUsage; private set => SetProperty(ref _cpuUsage, value); }
    public long MemUsed { get => _memUsed; private set => SetProperty(ref _memUsed, value); }
    public long MemTotal { get => _memTotal; private set => SetProperty(ref _memTotal, value); }
    public double MemFraction => MemTotal > 0 ? (double)MemUsed / MemTotal : 0;
    public double NetIn { get => _netIn; private set => SetProperty(ref _netIn, value); }
    public double NetOut { get => _netOut; private set => SetProperty(ref _netOut, value); }
    public int? Battery { get => _battery; private set => SetProperty(ref _battery, value); }
    public bool IsCharging { get => _isCharging; private set => SetProperty(ref _isCharging, value); }
    public bool IsOnAc { get => _isOnAc; private set => SetProperty(ref _isOnAc, value); }

    public List<double> CpuHistory { get; } = [];
    public List<double> MemHistory { get; } = [];
    public List<double> NetHistory { get; } = [];

    public event Action<int, bool>? PowerChanged;
    public event Action<int>? LowBattery;

    public SystemStats()
    {
        Sample();
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _timer.Tick += (_, _) => Sample();
        _timer.Start();
    }

    public void Sample()
    {
        SampleCpu();
        SampleMemory();
        SampleNetwork();
        SampleBattery();
    }

    private void SampleCpu()
    {
        if (NativeMethods.GetSystemTimes(out var idle, out var kernel, out var user))
        {
            var uIdle = ToUInt64(idle);
            var uKernel = ToUInt64(kernel);
            var uUser = ToUInt64(user);

            var uPrevIdle = ToUInt64(_prevSysIdle);
            var uPrevKernel = ToUInt64(_prevSysKernel);
            var uPrevUser = ToUInt64(_prevSysUser);

            var diffIdle = uIdle - uPrevIdle;
            var diffKernel = uKernel - uPrevKernel;
            var diffUser = uUser - uPrevUser;
            var total = diffKernel + diffUser;

            if (total > 0 && uPrevKernel > 0)
            {
                var busy = total - diffIdle;
                CpuUsage = Math.Clamp((double)busy / total, 0, 1);
                PushHistory(CpuUsage, CpuHistory);
                OnPropertyChanged(nameof(CpuHistory));
            }

            _prevSysIdle = idle;
            _prevSysKernel = kernel;
            _prevSysUser = user;
        }
    }

    private static ulong ToUInt64(NativeMethods.FILETIME ft) => ((ulong)ft.dwHighDateTime << 32) | ft.dwLowDateTime;

    private void SampleMemory()
    {
        var memStatus = new NativeMethods.MEMORYSTATUSEX();
        memStatus.dwLength = (uint)Marshal.SizeOf(typeof(NativeMethods.MEMORYSTATUSEX));
        if (NativeMethods.GlobalMemoryStatusEx(ref memStatus))
        {
            MemTotal = (long)memStatus.ullTotalPhys;
            MemUsed = (long)(memStatus.ullTotalPhys - memStatus.ullAvailPhys);
            PushHistory(MemFraction, MemHistory);
            OnPropertyChanged(nameof(MemFraction));
            OnPropertyChanged(nameof(MemHistory));
        }
    }

    private void SampleNetwork()
    {
        try
        {
            long rx = 0;
            long tx = 0;
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus == OperationalStatus.Up && ni.NetworkInterfaceType != NetworkInterfaceType.Loopback)
                {
                    var stats = ni.GetIPStatistics();
                    rx += stats.BytesReceived;
                    tx += stats.BytesSent;
                }
            }

            var now = DateTime.UtcNow;
            var dt = (now - _lastNetTime).TotalSeconds;
            if (dt > 0 && _lastBytesReceived > 0)
            {
                NetIn = Math.Max(0, (rx - _lastBytesReceived) / dt);
                NetOut = Math.Max(0, (tx - _lastBytesSent) / dt);
                PushHistory(NetIn + NetOut, NetHistory);
                OnPropertyChanged(nameof(NetHistory));
            }

            _lastBytesReceived = rx;
            _lastBytesSent = tx;
            _lastNetTime = now;
        }
        catch
        {
            // Network interface access
        }
    }

    private void SampleBattery()
    {
        var sp = new NativeMethods.SYSTEM_POWER_STATUS();
        if (NativeMethods.GetSystemPowerStatus(ref sp))
        {
            var oldCharging = IsCharging;
            var oldAc = IsOnAc;

            IsOnAc = sp.ACLineStatus == 1;
            IsCharging = (sp.BatteryFlag & 8) != 0;
            var pct = sp.BatteryLifePercent <= 100 ? (int?)sp.BatteryLifePercent : null;

            if (pct.HasValue)
            {
                Battery = pct.Value;
                if (!IsOnAc && Battery <= 20)
                {
                    LowBattery?.Invoke(Battery.Value);
                }
            }
            else
            {
                Battery = null;
            }

            if (oldAc != IsOnAc || oldCharging != IsCharging)
            {
                PowerChanged?.Invoke(Battery ?? 100, IsOnAc);
            }
        }
    }

    private static void PushHistory(double val, List<double> history)
    {
        history.Add(val);
        if (history.Count > HistoryLength)
            history.RemoveRange(0, history.Count - HistoryLength);
    }
}

