using System.Windows;
using Notchbeat.Models;

namespace Notchbeat.Views;

public partial class SettingsWindow : Window
{
    public SettingsWindow(AppSettings settings)
    {
        InitializeComponent();
        DataContext = settings;
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}

