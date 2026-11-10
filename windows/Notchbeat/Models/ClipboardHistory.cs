using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media.Imaging;
using Notchbeat.Core;

namespace Notchbeat.Models;

public enum ClipKind
{
    Text,
    Files,
    Image
}

public sealed class Clip
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public ClipKind Kind { get; set; }
    public string? Text { get; set; }
    public List<string>? Paths { get; set; }
    public DateTime Date { get; set; } = DateTime.UtcNow;

    public string Preview => Kind switch
    {
        ClipKind.Text => (Text ?? string.Empty).Replace("\r", " ").Replace("\n", " ").Trim(),
        ClipKind.Files => Paths is { Count: > 1 } ? $"{Path.GetFileName(Paths[0])} + {Paths.Count - 1} more" : (Paths?.Count > 0 ? Path.GetFileName(Paths[0]) : string.Empty),
        ClipKind.Image => "Image",
        _ => string.Empty
    };

    public bool IsLink => Kind == ClipKind.Text && (Text?.StartsWith("http://") == true || Text?.StartsWith("https://") == true);
}

public sealed class ClipboardHistory : ObservableObject
{
    private const int MaxClips = 60;
    private readonly string _filePath;
    private bool _enabled = true;

    public ObservableCollection<Clip> Clips { get; } = [];
    public Dictionary<Guid, BitmapSource> Images { get; } = [];

    public bool Enabled
    {
        get => _enabled;
        set => SetProperty(ref _enabled, value);
    }

    public ClipboardHistory()
    {
        var appData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Notchbeat");
        Directory.CreateDirectory(appData);
        _filePath = Path.Combine(appData, "clipboard.json");
        Load();
    }

    public void OnClipboardUpdated()
    {
        if (!Enabled) return;

        try
        {
            var data = Clipboard.GetDataObject();
            if (data == null) return;

            // Password managers skip formats
            if (data.GetDataPresent("ExcludeClipboardContentFromMonitorProcessing") ||
                data.GetDataPresent("CanIncludeInClipboardHistory") && (bool?)data.GetData("CanIncludeInClipboardHistory") == false)
            {
                return;
            }

            if (Clipboard.ContainsFileDropList())
            {
                var files = Clipboard.GetFileDropList().Cast<string>().ToList();
                if (files.Count > 0)
                {
                    AddClip(new Clip { Kind = ClipKind.Files, Paths = files });
                }
            }
            else if (Clipboard.ContainsImage())
            {
                var img = Clipboard.GetImage();
                if (img != null)
                {
                    var clip = new Clip { Kind = ClipKind.Image };
                    Images[clip.Id] = img;
                    AddClip(clip);
                }
            }
            else if (Clipboard.ContainsText())
            {
                var text = Clipboard.GetText();
                if (!string.IsNullOrWhiteSpace(text))
                {
                    if (Clips.Count > 0 && Clips[0].Kind == ClipKind.Text && Clips[0].Text == text)
                        return;

                    AddClip(new Clip { Kind = ClipKind.Text, Text = text });
                }
            }
        }
        catch
        {
            // Clipboard access can throw if locked by another app
        }
    }

    private void AddClip(Clip clip)
    {
        Clips.Insert(0, clip);
        while (Clips.Count > MaxClips)
        {
            var old = Clips[^1];
            Images.Remove(old.Id);
            Clips.RemoveAt(Clips.Count - 1);
        }
        Save();
    }

    public void Copy(Clip clip)
    {
        try
        {
            if (clip.Kind == ClipKind.Text && clip.Text != null)
            {
                Clipboard.SetText(clip.Text);
            }
            else if (clip.Kind == ClipKind.Files && clip.Paths != null)
            {
                var sc = new System.Collections.Specialized.StringCollection();
                sc.AddRange(clip.Paths.ToArray());
                Clipboard.SetFileDropList(sc);
            }
            else if (clip.Kind == ClipKind.Image && Images.TryGetValue(clip.Id, out var img))
            {
                Clipboard.SetImage(img);
            }
        }
        catch
        {
            // Clipboard locking
        }
    }

    public void Delete(Clip clip)
    {
        Images.Remove(clip.Id);
        Clips.Remove(clip);
        Save();
    }

    public void Clear()
    {
        Images.Clear();
        Clips.Clear();
        Save();
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(_filePath)) return;
            var json = File.ReadAllText(_filePath);
            var items = JsonSerializer.Deserialize<List<Clip>>(json);
            if (items != null)
            {
                foreach (var item in items)
                {
                    if (item.Kind != ClipKind.Image)
                        Clips.Add(item);
                }
            }
        }
        catch
        {
            // Ignore load failure
        }
    }

    private void Save()
    {
        try
        {
            var serializable = Clips.Where(c => c.Kind != ClipKind.Image).ToList();
            var json = JsonSerializer.Serialize(serializable, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_filePath, json);
        }
        catch
        {
            // Ignore save failure
        }
    }
}

