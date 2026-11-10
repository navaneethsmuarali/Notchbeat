using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Hardcodet.Wpf.TaskbarNotification;
using Notchbeat.Models;
using Notchbeat.Views;

namespace Notchbeat;

public partial class App : Application
{
    public static HubModel Hub { get; private set; } = null!;
    public static IslandWindow? Island { get; private set; }

    private static readonly string LogDir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Notchbeat");
    private static readonly string LogPath = Path.Combine(LogDir, "crash.log");

    private TaskbarIcon? _tray;
    private Mutex? _singleInstance;
    private static bool _shownNonFatal;

    protected override void OnStartup(StartupEventArgs e)
    {
        // Without these, any startup error closes the app silently.
        DispatcherUnhandledException += OnDispatcherException;
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            Report(args.ExceptionObject as Exception, fatal: true);
        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            Log(args.Exception);
            args.SetObserved();
        };

        _singleInstance = new Mutex(true, "Notchbeat.SingleInstance", out var isFirst);
        if (!isFirst)
        {
            MessageBox.Show("Notchbeat is already running. Look for its icon in the system tray.",
                "Notchbeat", MessageBoxButton.OK, MessageBoxImage.Information);
            Shutdown();
            return;
        }

        base.OnStartup(e);

        try
        {
            CreateTrayIcon();
            Hub = new HubModel();
            Island = new IslandWindow(Hub);
            Island.Show();
        }
        catch (Exception ex)
        {
            Report(ex, fatal: true);
            Shutdown(1);
        }
    }

    private void CreateTrayIcon()
    {
        var menu = new ContextMenu();

        var show = new MenuItem { Header = "Show island" };
        show.Click += (_, _) => { Island?.Show(); Island?.Activate(); };

        var log = new MenuItem { Header = "Open crash log" };
        log.Click += (_, _) =>
        {
            if (File.Exists(LogPath))
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(LogPath) { UseShellExecute = true });
            else
                MessageBox.Show("No errors logged.", "Notchbeat");
        };

        var quit = new MenuItem { Header = "Quit Notchbeat" };
        quit.Click += (_, _) => Shutdown();

        menu.Items.Add(show);
        menu.Items.Add(log);
        menu.Items.Add(new Separator());
        menu.Items.Add(quit);

        _tray = new TaskbarIcon
        {
            Icon = LoadAppIcon(),
            ToolTipText = "Notchbeat",
            ContextMenu = menu,
        };
        _tray.TrayMouseDoubleClick += (_, _) => Island?.Show();
    }

    private static System.Drawing.Icon LoadAppIcon()
    {
        try
        {
            var exe = Environment.ProcessPath;
            if (exe != null && System.Drawing.Icon.ExtractAssociatedIcon(exe) is { } icon)
                return icon;
        }
        catch { /* fall back below */ }
        return System.Drawing.SystemIcons.Application;
    }

    private void OnDispatcherException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        // Keep running after an error in one feature: log it and tell the user once.
        e.Handled = true;
        Report(e.Exception, fatal: false);
    }

    private static void Report(Exception? ex, bool fatal)
    {
        Log(ex);
        if (!fatal && _shownNonFatal) return;
        if (!fatal) _shownNonFatal = true;

        var msg = (fatal ? "Notchbeat couldn't start.\n\n" : "Notchbeat hit an error but is still running.\n\n")
                  + (ex?.GetBaseException().Message ?? "Unknown error")
                  + $"\n\nDetails saved to:\n{LogPath}";
        MessageBox.Show(msg, "Notchbeat", MessageBoxButton.OK,
            fatal ? MessageBoxImage.Error : MessageBoxImage.Warning);
    }

    private static void Log(Exception? ex)
    {
        try
        {
            Directory.CreateDirectory(LogDir);
            File.AppendAllText(LogPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {ex}\n\n");
        }
        catch { /* nothing else we can do */ }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        _singleInstance?.Dispose();
        base.OnExit(e);
    }
}
