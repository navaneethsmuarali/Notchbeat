using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Windows.Threading;
using Notchbeat.Core;

namespace Notchbeat.Models;

public enum AgentState
{
    Working,
    Waiting,
    Done
}

public sealed class AgentSession : ObservableObject, IEquatable<AgentSession>
{
    public string Id { get; set; } = string.Empty;
    public string Tool { get; set; } = "Claude Code";
    public string Project { get; set; } = string.Empty;
    public string? Title { get; set; }
    public AgentState State { get; set; }
    public string Detail { get; set; } = string.Empty;
    public DateTime Updated { get; set; } = DateTime.UtcNow;

    public bool Equals(AgentSession? other) => other != null && Id == other.Id && State == other.State && Updated == other.Updated;
    public override bool Equals(object? obj) => Equals(obj as AgentSession);
    public override int GetHashCode() => HashCode.Combine(Id, State, Updated);
}

public sealed class AgentMonitor : ObservableObject
{
    private readonly DispatcherTimer _timer;
    private readonly Dictionary<string, AgentState> _previous = [];

    public ObservableCollection<AgentSession> Sessions { get; } = [];
    public AgentSession? Working => Sessions.FirstOrDefault(s => s.State == AgentState.Working);

    public event Action<AgentSession>? SessionStateChanged;

    public AgentMonitor()
    {
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _timer.Tick += (_, _) => Scan();
        Scan();
        _timer.Start();
    }

    public void Scan()
    {
        var found = new List<AgentSession>();
        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

        // Scan Claude Code projects
        try
        {
            var claudeDir = Path.Combine(userProfile, ".claude");
            if (Directory.Exists(claudeDir))
            {
                var files = Directory.GetFiles(claudeDir, "*.json", SearchOption.AllDirectories)
                    .Select(f => new FileInfo(f))
                    .OrderByDescending(f => f.LastWriteTimeUtc)
                    .Take(5);

                foreach (var f in files)
                {
                    found.Add(new AgentSession
                    {
                        Id = f.FullName,
                        Tool = "Claude Code",
                        Project = Path.GetFileName(Path.GetDirectoryName(f.FullName) ?? "Project"),
                        State = (DateTime.UtcNow - f.LastWriteTimeUtc).TotalMinutes < 2 ? AgentState.Working : AgentState.Done,
                        Detail = "Active task session",
                        Updated = f.LastWriteTimeUtc
                    });
                }
            }
        }
        catch { }

        // Scan Codex projects
        try
        {
            var codexDir = Path.Combine(userProfile, ".codex");
            if (Directory.Exists(codexDir))
            {
                var files = Directory.GetFiles(codexDir, "*.json", SearchOption.AllDirectories)
                    .Select(f => new FileInfo(f))
                    .OrderByDescending(f => f.LastWriteTimeUtc)
                    .Take(5);

                foreach (var f in files)
                {
                    found.Add(new AgentSession
                    {
                        Id = f.FullName,
                        Tool = "Codex",
                        Project = Path.GetFileName(Path.GetDirectoryName(f.FullName) ?? "Project"),
                        State = (DateTime.UtcNow - f.LastWriteTimeUtc).TotalMinutes < 2 ? AgentState.Working : AgentState.Done,
                        Detail = "Working on codebase",
                        Updated = f.LastWriteTimeUtc
                    });
                }
            }
        }
        catch { }

        foreach (var s in found)
        {
            if (_previous.TryGetValue(s.Id, out var prevState) && prevState == AgentState.Working && s.State != AgentState.Working)
            {
                SessionStateChanged?.Invoke(s);
            }
            _previous[s.Id] = s.State;
        }

        Sessions.Clear();
        foreach (var s in found.OrderByDescending(s => s.Updated)) Sessions.Add(s);
        OnPropertyChanged(nameof(Working));
    }
}

