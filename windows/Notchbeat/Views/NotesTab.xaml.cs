using System.Windows;
using System.Windows.Controls;
using Notchbeat.Models;

namespace Notchbeat.Views;

public partial class NotesTab : UserControl
{
    private HubModel? Hub => DataContext as HubModel;

    public NotesTab()
    {
        InitializeComponent();
    }

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        Hub?.Notes.Copy();
        Hub?.ShowToast("📝", System.Windows.Media.Colors.White, "Copied", "Notes copied to clipboard", 2);
    }

    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        Hub?.Notes.Clear();
    }
}

