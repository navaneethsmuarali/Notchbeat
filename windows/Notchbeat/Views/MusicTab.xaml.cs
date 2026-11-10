using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using Notchbeat.Models;

namespace Notchbeat.Views;

public partial class MusicTab : UserControl
{
    private HubModel? Hub => DataContext as HubModel;

    public MusicTab()
    {
        InitializeComponent();
        Loaded += (_, _) => UpdateButtonText();
        DataContextChanged += (_, _) =>
        {
            if (Hub != null)
            {
                Hub.Player.PropertyChanged += (_, e) =>
                {
                    if (e.PropertyName == nameof(PlayerModel.IsPlaying))
                        UpdateButtonText();
                };
            }
            UpdateButtonText();
        };
    }

    private void UpdateButtonText()
    {
        if (PlayPauseBtn != null)
        {
            PlayPauseBtn.Content = Hub?.Player.IsPlaying == true ? "⏸" : "▶";
        }
    }

    private void PlayPause_Click(object sender, RoutedEventArgs e) => Hub?.Player.Toggle();
    private void Next_Click(object sender, RoutedEventArgs e) => Hub?.Player.Next();
    private void Prev_Click(object sender, RoutedEventArgs e) => Hub?.Player.Previous();

    private void Slider_DragCompleted(object sender, DragCompletedEventArgs e)
    {
        if (sender is Slider slider)
        {
            Hub?.Player.Seek(TimeSpan.FromSeconds(slider.Value));
        }
    }
}

