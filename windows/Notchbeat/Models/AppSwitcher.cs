using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Notchbeat.Core;
using Notchbeat.Helpers;

namespace Notchbeat.Models;

public sealed class WindowEntry
{
    public IntPtr Handle { get; set; }
    public string Title { get; set; } = string.Empty;
}

public sealed class AppBubble : ObservableObject
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public BitmapSource? Icon { get; set; }
    public int WindowCount => Windows.Count;
    public bool IsPinned { get; set; }
    public List<WindowEntry> Windows { get; set; } = [];
}

public sealed class AppSwitcher : ObservableObject
{
    private const int MaxBubbles = 10;
    private readonly DispatcherTimer _timer;

    public ObservableCollection<AppBubble> Bubbles { get; } = [];
    public List<string> PinnedPaths { get; } = [];

    public AppSwitcher()
    {
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _timer.Tick += (_, _) => Refresh();
        Refresh();
        _timer.Start();
    }

    public void Refresh()
    {
        var currentPid = (uint)Process.GetCurrentProcess().Id;
        var windowsByProcess = new Dictionary<uint, List<WindowEntry>>();

        NativeMethods.EnumWindows((hWnd, _) =>
        {
            if (!NativeMethods.IsWindowVisible(hWnd)) return true;
            if (NativeMethods.GetWindowTextLength(hWnd) == 0) return true;

            var sb = new StringBuilder(256);
            NativeMethods.GetWindowText(hWnd, sb, 256);
            var title = sb.ToString().Trim();
            if (string.IsNullOrEmpty(title)) return true;

            NativeMethods.GetWindowThreadProcessId(hWnd, out var pid);
            if (pid == 0 || pid == currentPid) return true;

            if (!windowsByProcess.TryGetValue(pid, out var list))
            {
                list = [];
                windowsByProcess[pid] = list;
            }
            list.Add(new WindowEntry { Handle = hWnd, Title = title });

            return true;
        }, IntPtr.Zero);

        var bubbles = new List<AppBubble>();
        foreach (var (pid, winList) in windowsByProcess.Take(MaxBubbles))
        {
            try
            {
                using var proc = Process.GetProcessById((int)pid);
                var exePath = proc.MainModule?.FileName;
                var procName = proc.ProcessName;

                BitmapSource? icon = null;
                if (!string.IsNullOrEmpty(exePath) && File.Exists(exePath))
                {
                    using var sysIcon = System.Drawing.Icon.ExtractAssociatedIcon(exePath);
                    if (sysIcon != null)
                    {
                        icon = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(sysIcon.Handle, System.Windows.Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                        icon.Freeze();
                    }
                }

                bubbles.Add(new AppBubble
                {
                    Id = exePath ?? procName,
                    Name = procName,
                    Icon = icon,
                    Windows = winList,
                    IsPinned = PinnedPaths.Contains(exePath ?? string.Empty)
                });
            }
            catch { }
        }

        Bubbles.Clear();
        foreach (var b in bubbles) Bubbles.Add(b);
    }

    public void SwitchTo(AppBubble bubble)
    {
        if (bubble.Windows.Count == 0) return;
        SwitchTo(bubble.Windows[0]);
    }

    public void SwitchTo(WindowEntry window)
    {
        if (NativeMethods.IsIconic(window.Handle))
        {
            NativeMethods.ShowWindow(window.Handle, NativeMethods.SW_RESTORE);
        }
        NativeMethods.SetForegroundWindow(window.Handle);
    }
}

