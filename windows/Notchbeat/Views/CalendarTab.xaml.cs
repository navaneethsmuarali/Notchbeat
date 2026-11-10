using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using Notchbeat.Models;

namespace Notchbeat.Views;

public partial class CalendarTab : UserControl
{
    public CalendarTab()
    {
        InitializeComponent();
    }

    private void Join_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: EventItem { JoinUrl: not null } item })
        {
            try
            {
                Process.Start(new ProcessStartInfo(item.JoinUrl.AbsoluteUri) { UseShellExecute = true });
            }
            catch { }
        }
    }
}

