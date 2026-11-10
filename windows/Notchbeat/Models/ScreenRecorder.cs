using System.Diagnostics;
using System.IO;
using Notchbeat.Core;

namespace Notchbeat.Models;

public sealed class ScreenRecorder : ObservableObject
{
    private bool _isRecording;
    private DateTime? _startedAt;
    private string? _lastError;
    private Process? _ffmpegProcess;
    private string? _currentOutputFile;

    public bool IsRecording { get => _isRecording; private set => SetProperty(ref _isRecording, value); }
    public DateTime? StartedAt { get => _startedAt; private set => SetProperty(ref _startedAt, value); }
    public string? LastError { get => _lastError; private set => SetProperty(ref _lastError, value); }
    public bool IsSupported => true;

    public static string OutputFolder
    {
        get
        {
            var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), "Notchbeat Recordings");
            Directory.CreateDirectory(path);
            return path;
        }
    }

    public event Action<string>? Finished;

    public void Toggle()
    {
        if (IsRecording) Stop();
        else Start();
    }

    public void Start()
    {
        if (IsRecording) return;
        LastError = null;

        try
        {
            var fileName = $"Recording {DateTime.Now:yyyy-MM-dd 'at' HH.mm.ss}.mp4";
            _currentOutputFile = Path.Combine(OutputFolder, fileName);

            // Attempt launch ffmpeg if available in PATH
            var psi = new ProcessStartInfo
            {
                FileName = "ffmpeg",
                Arguments = $"-f gdigrab -framerate 30 -i desktop -c:v libx264 -pix_fmt yuv420p \"{_currentOutputFile}\"",
                CreateNoWindow = true,
                UseShellExecute = false
            };

            _ffmpegProcess = Process.Start(psi);
            StartedAt = DateTime.UtcNow;
            IsRecording = true;
        }
        catch (Exception)
        {
            LastError = "FFmpeg not detected in PATH. Install ffmpeg to enable screen recording.";
            IsRecording = false;
        }
    }

    public void Stop()
    {
        if (!IsRecording) return;

        try
        {
            if (_ffmpegProcess != null && !_ffmpegProcess.HasExited)
            {
                _ffmpegProcess.StandardInput.WriteLine("q");
                _ffmpegProcess.WaitForExit(3000);
            }
        }
        catch { }

        IsRecording = false;
        StartedAt = null;

        if (_currentOutputFile != null && File.Exists(_currentOutputFile))
        {
            Finished?.Invoke(_currentOutputFile);
        }
    }

    public static string FormatElapsed(DateTime? started, DateTime now)
    {
        if (!started.HasValue) return "0:00";
        var s = (int)(now - started.Value).TotalSeconds;
        return $"{s / 60}:{s % 60:D2}";
    }
}

