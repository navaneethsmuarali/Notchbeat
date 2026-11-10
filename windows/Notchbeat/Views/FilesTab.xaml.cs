using System.Windows;
using System.Windows.Controls;
using Notchbeat.Models;

namespace Notchbeat.Views;

public partial class FilesTab : UserControl
{
    private HubModel? Hub => DataContext as HubModel;

    public FilesTab()
    {
        InitializeComponent();
    }

    private void Grid_Drop(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            var files = (string[])e.Data.GetData(DataFormats.FileDrop);
            Hub?.Shelf.Add(files);
        }
    }

    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        Hub?.Shelf.Clear();
    }
}

