using System.IO;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Windows.Media.Control;
using Windows.Storage.Streams;
using Notchbeat.Core;

namespace Notchbeat.Models;

public enum MediaBridgeStatus
{
    Ok,
    NoSession,
    Error
}

public sealed class MediaBridge : ObservableObject
{
    private readonly PlayerModel _player;
    private readonly DispatcherTimer _timer;
    private GlobalSystemMediaTransportControlsSessionManager? _manager;
    private GlobalSystemMediaTransportControlsSession? _currentSession;
    private MediaBridgeStatus _status = MediaBridgeStatus.NoSession;

    public MediaBridgeStatus Status
    {
        get => _status;
        private set => SetProperty(ref _status, value);
    }

    public MediaBridge(PlayerModel player)
    {
        _player = player;
        _player.SendCommand = ExecuteCommand;

        _timer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(1)
        };
        _timer.Tick += async (_, _) => await PollAsync();
    }

    public async Task StartAsync()
    {
        try
        {
            _manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            if (_manager != null)
            {
                _manager.CurrentSessionChanged += async (_, _) => await UpdateSessionAsync();
                await UpdateSessionAsync();
            }
            _timer.Start();
        }
        catch
        {
            Status = MediaBridgeStatus.Error;
        }
    }

    private async Task UpdateSessionAsync()
    {
        if (_manager == null) return;

        try
        {
            _currentSession = _manager.GetCurrentSession();
            if (_currentSession != null)
            {
                Status = MediaBridgeStatus.Ok;
                await PollAsync();
            }
            else
            {
                Status = MediaBridgeStatus.NoSession;
            }
        }
        catch
        {
            Status = MediaBridgeStatus.Error;
        }
    }

    public async Task PollAsync()
    {
        if (_currentSession == null)
        {
            Status = MediaBridgeStatus.NoSession;
            return;
        }

        try
        {
            var mediaProps = await _currentSession.TryGetMediaPropertiesAsync();
            var playbackInfo = _currentSession.GetPlaybackInfo();
            var timeline = _currentSession.GetTimelineProperties();

            if (mediaProps != null)
            {
                _player.Title = mediaProps.Title ?? string.Empty;
                _player.Artist = mediaProps.Artist ?? string.Empty;

                if (mediaProps.Thumbnail != null)
                {
                    try
                    {
                        using var stream = await mediaProps.Thumbnail.OpenReadAsync();
                        var netStream = stream.AsStreamForRead();
                        var bmp = new BitmapImage();
                        bmp.BeginInit();
                        bmp.CacheOption = BitmapCacheOption.OnLoad;
                        bmp.StreamSource = netStream;
                        bmp.EndInit();
                        bmp.Freeze();
                        _player.Artwork = bmp;
                    }
                    catch
                    {
                        // Thumbnail error fallback
                    }
                }
            }

            if (playbackInfo != null)
            {
                _player.IsPlaying = playbackInfo.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
            }

            if (timeline != null)
            {
                _player.Position = timeline.Position;
                _player.Duration = timeline.EndTime;
                _player.UpdatedAt = DateTime.UtcNow;
            }

            Status = MediaBridgeStatus.Ok;
        }
        catch
        {
            Status = MediaBridgeStatus.Error;
        }
    }

    private async void ExecuteCommand(string cmd)
    {
        if (_currentSession == null) return;

        try
        {
            if (cmd == "toggle")
            {
                await _currentSession.TryTogglePlayPauseAsync();
            }
            else if (cmd == "next")
            {
                await _currentSession.TrySkipNextAsync();
            }
            else if (cmd == "previous")
            {
                await _currentSession.TrySkipPreviousAsync();
            }
            else if (cmd.StartsWith("seek:"))
            {
                if (double.TryParse(cmd[5..], out var sec))
                {
                    await _currentSession.TryChangePlaybackPositionAsync((long)(sec * 10_000_000));
                }
            }
        }
        catch
        {
            // Ignore transport errors
        }
    }
}

