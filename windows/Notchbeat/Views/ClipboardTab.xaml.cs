using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Notchbeat.Models;

namespace Notchbeat.Views;

public partial class ClipboardTab : UserControl
{
    private HubModel? Hub => DataContext as HubModel;

    public ClipboardTab()
    {
        InitializeComponent();
    }

    private void Clip_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: Clip clip })
        {
            Hub?.Clips.Copy(clip);
            Hub?.ShowToast("📋", System.Windows.Media.Colors.White, "Copied", clip.Preview, 2);
        }
    }

    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        Hub?.Clips.Clear();
    }
}

