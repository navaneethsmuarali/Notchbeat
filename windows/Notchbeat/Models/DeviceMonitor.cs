using System.Collections.ObjectModel;
using System.Windows.Threading;
using Notchbeat.Core;

namespace Notchbeat.Models;

public sealed class BTDevice : ObservableObject, IEquatable<BTDevice>
{
    private string _id = string.Empty;
    private string _kind = string.Empty;
    private int _batteryLevel = 100;

    public string Id { get => _id; set => SetProperty(ref _id, value); }
    public string Kind { get => _kind; set => SetProperty(ref _kind, value); }
    public int BatteryLevel { get => _batteryLevel; set => SetProperty(ref _batteryLevel, value); }

    public string ShortName => Id.Length > 16 ? Id[..15] + "…" : Id;
    public string LevelText => $"{BatteryLevel}%";

    public string Symbol
    {
        get
        {
            var k = Kind.ToLowerInvariant();
            var n = Id.ToLowerInvariant();
            if (n.Contains("airpods max")) return "🎧";
            if (n.Contains("airpods pro") || n.Contains("airpods")) return "🎧";
            if (k.Contains("headphone") || k.Contains("headset")) return "🎧";
            if (k.Contains("keyboard")) return "⌨️";
            if (k.Contains("mouse")) return "🖱️";
            if (k.Contains("speaker")) return "🔊";
            if (k.Contains("gamepad") || k.Contains("controller")) return "🎮";
            return "📶";
        }
    }

    public bool Equals(BTDevice? other) => other != null && Id == other.Id && BatteryLevel == other.BatteryLevel;
    public override bool Equals(object? obj) => Equals(obj as BTDevice);
    public override int GetHashCode() => HashCode.Combine(Id, BatteryLevel);
}

public sealed class DeviceMonitor : ObservableObject
{
    private readonly DispatcherTimer _timer;
    private readonly HashSet<string> _warnedLow = [];
    private HashSet<string>? _known;

    public ObservableCollection<BTDevice> Devices { get; } = [];

    public event Action<BTDevice>? DeviceConnected;
    public event Action<BTDevice>? DeviceLowBattery;

    public DeviceMonitor()
    {
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(10) };
        _timer.Tick += async (_, _) => await ScanAsync();
        _ = ScanAsync();
        _timer.Start();
    }

    public async Task ScanAsync()
    {
        try
        {
            // Query Windows Bluetooth devices via Windows.Devices.Enumeration
            var selector = Windows.Devices.Bluetooth.BluetoothDevice.GetDeviceSelectorFromPairingState(true);
            var devices = await Windows.Devices.Enumeration.DeviceInformation.FindAllAsync(selector);

            var found = new List<BTDevice>();
            foreach (var d in devices)
            {
                if (d.IsEnabled)
                {
                    found.Add(new BTDevice
                    {
                        Id = d.Name,
                        Kind = "Device",
                        BatteryLevel = 85
                    });
                }
            }

            var currentIds = found.Select(d => d.Id).ToHashSet();
            if (_known != null)
            {
                foreach (var d in found)
                {
                    if (!_known.Contains(d.Id))
                    {
                        DeviceConnected?.Invoke(d);
                    }
                    if (d.BatteryLevel <= 20 && !_warnedLow.Contains(d.Id))
                    {
                        _warnedLow.Add(d.Id);
                        DeviceLowBattery?.Invoke(d);
                    }
                }
            }
            _known = currentIds;

            Devices.Clear();
            foreach (var d in found) Devices.Add(d);
        }
        catch
        {
            // Device enumeration catch
        }
    }
}

