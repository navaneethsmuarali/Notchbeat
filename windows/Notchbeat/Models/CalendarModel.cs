using System.Collections.ObjectModel;
using System.Text.RegularExpressions;
using System.Windows.Media;
using System.Windows.Threading;
using Notchbeat.Core;

namespace Notchbeat.Models;

public sealed class EventItem : ObservableObject
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = string.Empty;
    public DateTime Start { get; set; }
    public DateTime End { get; set; }
    public bool AllDay { get; set; }
    public Color CalendarColor { get; set; } = Color.FromRgb(52, 199, 89);
    public SolidColorBrush ColorBrush => new(CalendarColor);
    public Uri? JoinUrl { get; set; }

    public static Uri? ExtractMeetingUrl(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var match = Regex.Match(text, @"https?://(?:[\w-]+\.)?(?:zoom\.us/j/\S+|meet\.google\.com/\S+|teams\.microsoft\.com/l/meetup-join/\S+|[\w-]+\.webex\.com/\S+)", RegexOptions.IgnoreCase);
        return match.Success && Uri.TryCreate(match.Value, UriKind.Absolute, out var uri) ? uri : null;
    }
}

public sealed class CalendarModel : ObservableObject
{
    private readonly DispatcherTimer _timer;
    private bool _isAuthorized = true;
    private DateTime _now = DateTime.Now;

    public ObservableCollection<EventItem> Events { get; } = [];

    public bool IsAuthorized
    {
        get => _isAuthorized;
        set => SetProperty(ref _isAuthorized, value);
    }

    public DateTime Now
    {
        get => _now;
        private set => SetProperty(ref _now, value);
    }

    public EventItem? Soon
    {
        get
        {
            var now = DateTime.Now;
            return Events.FirstOrDefault(e =>
                !e.AllDay &&
                e.End > now &&
                (e.Start - now).TotalMinutes <= 10 &&
                (now - e.Start).TotalMinutes < 5);
        }
    }

    public CalendarModel()
    {
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(30) };
        _timer.Tick += (_, _) =>
        {
            Now = DateTime.Now;
            OnPropertyChanged(nameof(Soon));
        };
        _timer.Start();

        // Sample upcoming welcome/demo meeting if calendar store is empty
        LoadInitialEvents();
    }

    private void LoadInitialEvents()
    {
        var today = DateTime.Today;
        Events.Add(new EventItem
        {
            Title = "Product Review Sync",
            Start = today.AddHours(14),
            End = today.AddHours(15),
            CalendarColor = Color.FromRgb(0, 122, 255),
            JoinUrl = new Uri("https://meet.google.com/abc-defg-hij")
        });
        Events.Add(new EventItem
        {
            Title = "Architecture Planning",
            Start = today.AddHours(16).AddMinutes(30),
            End = today.AddHours(17).AddMinutes(30),
            CalendarColor = Color.FromRgb(52, 199, 89),
            JoinUrl = new Uri("https://teams.microsoft.com/l/meetup-join/123")
        });
    }

    public string Countdown(EventItem e)
    {
        var diff = e.Start - DateTime.Now;
        if (diff.TotalSeconds <= 0) return "now";
        if (diff.TotalMinutes < 60) return $"in {(int)diff.TotalMinutes}m";
        return $"in {(int)diff.TotalHours}h";
    }
}

