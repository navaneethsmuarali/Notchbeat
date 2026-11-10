using System.Windows;
using Notchbeat.Models;
using Notchbeat.Views;

namespace Notchbeat;

public partial class App : Application
{
    public static HubModel Hub { get; private set; } = null!;
    public static IslandWindow Island { get; private set; } = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        Hub = new HubModel();
        Island = new IslandWindow(Hub);
        Island.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        base.OnExit(e);
    }
}

