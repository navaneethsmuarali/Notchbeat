using System.IO;
using System.Text.Json;

namespace Notchbeat.Models;

/// <summary>
/// Persisted application settings. Serialized as JSON to the user's AppData folder.
/// </summary>
public sealed class AppSettings
{
    private static readonly string SettingsDir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Notchbeat");

    private static readonly string SettingsPath =
        Path.Combine(SettingsDir, "settings.json");

    public bool LaunchAtLogin { get; set; }
    public bool ClipboardEnabled { get; set; } = true;
    public bool ClipboardHistoryEnabled { get; set; } = true;
    public bool FloatingPlayerEnabled { get; set; }
    public bool ScreenRecordingEnabled { get; set; }
    public bool DeviceAlerts { get; set; } = true;
    public bool AgentsEnabled { get; set; } = true;
    public bool AgentSound { get; set; } = true;
    public bool ShowBubbles { get; set; } = true;
    public double IslandX { get; set; } = double.NaN;
    public double IslandY { get; set; } = double.NaN;

    /// <summary>
    /// Loads settings from disk, or returns defaults if the file does not exist.
    /// </summary>
    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsPath))
            {
                var json = File.ReadAllText(SettingsPath);
                return JsonSerializer.Deserialize<AppSettings>(json) ?? new AppSettings();
            }
        }
        catch
        {
            // Fall through to defaults
        }

        return new AppSettings();
    }

    /// <summary>
    /// Persists current settings to disk.
    /// </summary>
    public void Save()
    {
        try
        {
            Directory.CreateDirectory(SettingsDir);
            var json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(SettingsPath, json);
        }
        catch
        {
            // Silently fail – settings are non-critical
        }
    }
}
