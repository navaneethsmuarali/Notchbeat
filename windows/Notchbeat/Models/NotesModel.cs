using System.IO;
using System.Windows;
using System.Windows.Threading;
using Notchbeat.Core;

namespace Notchbeat.Models;

public sealed class NotesModel : ObservableObject
{
    private static readonly string s_directory =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Notchbeat");

    private static readonly string s_filePath = Path.Combine(s_directory, "notes.txt");

    private readonly DispatcherTimer _debounce;

    public NotesModel()
    {
        _debounce = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(500)
        };
        _debounce.Tick += (_, _) =>
        {
            _debounce.Stop();
            SaveToFile();
        };

        Load();
    }

    // ── Observable Property ─────────────────────────────────────────────

    private string _text = string.Empty;
    public string Text
    {
        get => _text;
        set
        {
            if (!SetProperty(ref _text, value)) return;
            _debounce.Stop();
            _debounce.Start();
        }
    }

    // ── Actions ─────────────────────────────────────────────────────────

    /// <summary>Copies the current note text to the system clipboard.</summary>
    public void Copy()
    {
        if (!string.IsNullOrEmpty(Text))
            Clipboard.SetText(Text);
    }

    /// <summary>Clears the note text and persists the empty state.</summary>
    public void Clear()
    {
        Text = string.Empty;
        _debounce.Stop();
        SaveToFile();
    }

    /// <summary>Persists the current text to disk.</summary>
    public void SaveToFile()
    {
        try
        {
            Directory.CreateDirectory(s_directory);
            File.WriteAllText(s_filePath, _text);
        }
        catch
        {
            // Non-critical — notes will be lost if this fails
        }
    }

    // ── Load ────────────────────────────────────────────────────────────

    private void Load()
    {
        try
        {
            if (File.Exists(s_filePath))
                _text = File.ReadAllText(s_filePath);
        }
        catch
        {
            _text = string.Empty;
        }
    }
}

