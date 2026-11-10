using System.Windows;
using System.Windows.Input;
using Notchbeat.Models;

namespace Notchbeat.Views;

public partial class MiniPlayerWindow : Window
{
    private HubModel? Hub => DataContext as HubModel;

    public MiniPlayerWindow(HubModel hub)
    {
        InitializeComponent();
        DataContext = hub;
    }

    private void Window_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left)
            DragMove();
    }

    private void PlayPause_Click(object sender, RoutedEventArgs e) => Hub?.Player.Toggle();
    private void Next_Click(object sender, RoutedEventArgs e) => Hub?.Player.Next();
    private void Prev_Click(object sender, RoutedEventArgs e) => Hub?.Player.Previous();
}
