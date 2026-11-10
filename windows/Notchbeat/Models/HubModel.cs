using System.Windows.Media;
using System.Windows.Threading;
using Notchbeat.Core;

namespace Notchbeat.Models;

public enum IslandTab
{
    Music,
    Files,
    Clipboard,
    Calendar,
    Stats,
    Notes,
    Agents
}

public sealed class Toast : ObservableObject
{
    public string Icon { get; set; } = string.Empty;
    public Color Tint { get; set; } = Colors.White;
    public SolidColorBrush TintBrush => new(Tint);
    public string Title { get; set; } = string.Empty;
    public string Detail { get; set; } = string.Empty;
    public DateTime Until { get; set; }
}

public sealed class HubModel : ObservableObject
{
    private IslandTab _currentTab = IslandTab.Music;
    private bool _musicShowsQueue;
    private Toast? _currentToast;

    public IslandTab CurrentTab
    {
        get => _currentTab;
        set => SetProperty(ref _currentTab, value);
    }

    public bool MusicShowsQueue
    {
        get => _musicShowsQueue;
        set => SetProperty(ref _musicShowsQueue, value);
    }

    public Toast? CurrentToast
    {
        get => _currentToast;
        private set => SetProperty(ref _currentToast, value);
    }

    public PlayerModel Player { get; }
    public MediaBridge MediaBridge { get; }
    public ClipboardHistory Clips { get; }
    public CalendarModel Calendar { get; }
    public SystemStats Stats { get; }
    public DeviceMonitor Devices { get; }
    public NotesModel Notes { get; }
    public ScreenRecorder Recorder { get; }
    public AgentMonitor Agents { get; }
    public ShelfModel Shelf { get; }
    public AppSwitcher Switcher { get; }
    public AppSettings Settings { get; }

    public HubModel()
    {
        Settings = AppSettings.Load();
        Player = new PlayerModel();
        MediaBridge = new MediaBridge(Player);
        Clips = new ClipboardHistory();
        Calendar = new CalendarModel();
        Stats = new SystemStats();
        Devices = new DeviceMonitor();
        Notes = new NotesModel();
        Recorder = new ScreenRecorder();
        Agents = new AgentMonitor();
        Shelf = new ShelfModel();
        Switcher = new AppSwitcher();

        _ = MediaBridge.StartAsync();

        // Device alerts
        Devices.DeviceConnected += dev =>
        {
            if (Settings.DeviceAlerts)
                ShowToast("🎧", Color.FromRgb(0, 122, 255), dev.ShortName, "Connected", 3);
        };

        Devices.DeviceLowBattery += dev =>
        {
            if (Settings.DeviceAlerts)
                ShowToast("🪫", Color.FromRgb(255, 69, 58), dev.ShortName, $"Low battery ({dev.BatteryLevel}%)", 4);
        };

        // Battery / Power alerts
        Stats.PowerChanged += (pct, ac) =>
        {
            ShowToast(ac ? "⚡" : "🔋", Color.FromRgb(52, 199, 89), ac ? "Charging" : "On Battery", $"{pct}%", 3);
        };

        Stats.LowBattery += pct =>
        {
            ShowToast("🪫", Color.FromRgb(255, 69, 58), "Battery Low", $"{pct}% remaining", 4);
        };

        // Agent completion alerts
        Agents.SessionStateChanged += s =>
        {
            if (s.State == AgentState.Done && Settings.AgentsEnabled)
            {
                ShowToast("✨", Color.FromRgb(255, 159, 10), $"{s.Tool} Finished", s.Project, 4);
                if (Settings.AgentSound) System.Media.SystemSounds.Asterisk.Play();
            }
        };
    }

    public void ShowToast(string icon, Color tint, string title, string detail, int seconds)
    {
        CurrentToast = new Toast
        {
            Icon = icon,
            Tint = tint,
            Title = title,
            Detail = detail,
            Until = DateTime.UtcNow.AddSeconds(seconds)
        };

        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(seconds) };
        timer.Tick += (_, _) =>
        {
            if (CurrentToast?.Until <= DateTime.UtcNow)
                CurrentToast = null;
            timer.Stop();
        };
        timer.Start();
    }
}

