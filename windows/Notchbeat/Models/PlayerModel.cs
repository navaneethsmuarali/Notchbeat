using System.Net.Http;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Notchbeat.Core;
using Notchbeat.Helpers;

namespace Notchbeat.Models;

public sealed class PlayerModel : ObservableObject
{
    // ── Delegates ────────────────────────────────────────────────────────

    /// <summary>Invoked to send transport commands: "toggle", "next", "previous", "seek:&lt;seconds&gt;".</summary>
    public Action<string>? SendCommand { get; set; }

    /// <summary>Invoked to bring the source media app to the foreground.</summary>
    public Action? OpenApp { get; set; }

    // ── Observable Properties ────────────────────────────────────────────

    private string _title = string.Empty;
    public string Title
    {
        get => _title;
        set
        {
            if (SetProperty(ref _title, value))
                OnPropertyChanged(nameof(HasTrack));
        }
    }

    private string _artist = string.Empty;
    public string Artist
    {
        get => _artist;
        set => SetProperty(ref _artist, value);
    }

    private bool _isPlaying;
    public bool IsPlaying
    {
        get => _isPlaying;
        set => SetProperty(ref _isPlaying, value);
    }

    private TimeSpan _position;
    public TimeSpan Position
    {
        get => _position;
        set => SetProperty(ref _position, value);
    }

    private TimeSpan _duration;
    public TimeSpan Duration
    {
        get => _duration;
        set => SetProperty(ref _duration, value);
    }

    private DateTime _updatedAt = DateTime.UtcNow;
    public DateTime UpdatedAt
    {
        get => _updatedAt;
        set => SetProperty(ref _updatedAt, value);
    }

    private BitmapImage? _artwork;
    public BitmapImage? Artwork
    {
        get => _artwork;
        set
        {
            if (SetProperty(ref _artwork, value))
            {
                AccentColor = AccentHelper.GetAccentColor(value);
                AccentBrush = AccentHelper.GetAccentBrush(value);
            }
        }
    }

    private Color _accentColor = Colors.White;
    public Color AccentColor
    {
        get => _accentColor;
        set => SetProperty(ref _accentColor, value);
    }

    private SolidColorBrush _accentBrush = new(Colors.White);
    public SolidColorBrush AccentBrush
    {
        get => _accentBrush;
        set => SetProperty(ref _accentBrush, value);
    }

    // ── Computed ─────────────────────────────────────────────────────────

    public bool HasTrack => !string.IsNullOrEmpty(Title);

    // ── Live Position ───────────────────────────────────────────────────

    /// <summary>
    /// Returns the estimated current playback position, advancing from the
    /// last known <see cref="Position"/> if the track is playing.
    /// </summary>
    public TimeSpan LivePosition(DateTime now)
    {
        if (!IsPlaying)
            return Position;

        var elapsed = now - UpdatedAt;
        var live = Position + elapsed;
        return live > Duration ? Duration : live;
    }

    // ── Transport Controls ──────────────────────────────────────────────

    public void Toggle() => SendCommand?.Invoke("toggle");
    public void Next() => SendCommand?.Invoke("next");
    public void Previous() => SendCommand?.Invoke("previous");
    public void Seek(TimeSpan position) => SendCommand?.Invoke($"seek:{position.TotalSeconds:F2}");

    // ── Apply State ─────────────────────────────────────────────────────

    /// <summary>
    /// Applies a <see cref="MediaInfo"/> snapshot to this model, updating all
    /// properties and asynchronously loading artwork when the URL changes.
    /// </summary>
    public void Apply(MediaInfo info)
    {
        Title = info.Title;
        Artist = info.Artist;
        IsPlaying = info.IsPlaying;
        Position = TimeSpan.FromSeconds(info.PositionSeconds);
        Duration = TimeSpan.FromSeconds(info.DurationSeconds);
        UpdatedAt = DateTime.UtcNow;

        if (!string.IsNullOrEmpty(info.ArtworkUrl) && info.ArtworkUrl != _lastArtworkUrl)
        {
            _lastArtworkUrl = info.ArtworkUrl;
            _ = LoadArtworkAsync(info.ArtworkUrl);
        }
    }

    // ── Artwork Loading ─────────────────────────────────────────────────

    private static readonly HttpClient s_http = new();
    private string? _lastArtworkUrl;

    public async Task LoadArtworkAsync(string url)
    {
        try
        {
            var bytes = await s_http.GetByteArrayAsync(url).ConfigureAwait(false);

            // BitmapImage must be created and frozen on the UI thread if we use a stream,
            // but we can use BeginInit/StreamSource from any thread when we freeze afterwards.
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.StreamSource = new System.IO.MemoryStream(bytes);
            bmp.DecodePixelWidth = 300; // keep memory usage reasonable
            bmp.EndInit();
            bmp.Freeze();

            // Marshal back to UI thread for property assignment
            System.Windows.Application.Current?.Dispatcher.Invoke(() => Artwork = bmp);
        }
        catch
        {
            // Network errors are expected when offline; silently ignore.
        }
    }

    // ── MediaInfo Record ────────────────────────────────────────────────

    public record MediaInfo(
        string Title,
        string Artist,
        bool IsPlaying,
        double PositionSeconds,
        double DurationSeconds,
        string ArtworkUrl);
}

