using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Notchbeat.Helpers;
using Notchbeat.Models;

namespace Notchbeat.Views;

public partial class IslandWindow : Window
{
    private const double CompactWidth = 240;
    private const double CompactHeight = 40;
    private const double ExpandedWidth = 420;
    private const double ExpandedHeight = 360;

    private readonly DispatcherTimer _expandTimer;
    private readonly DispatcherTimer _collapseTimer;
    private bool _isExpanded;
    private HwndSource? _hwndSource;

    private readonly MusicTab _musicTab = new();
    private readonly FilesTab _filesTab = new();
    private readonly ClipboardTab _clipboardTab = new();
    private readonly CalendarTab _calendarTab = new();
    private readonly StatsTab _statsTab = new();
    private readonly NotesTab _notesTab = new();
    private readonly AgentsTab _agentsTab = new();

    private HubModel? Hub => DataContext as HubModel;

    public IslandWindow(HubModel hub)
    {
        InitializeComponent();
        DataContext = hub;

        _expandTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) };
        _expandTimer.Tick += (_, _) =>
        {
            _expandTimer.Stop();
            Expand();
        };

        _collapseTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        _collapseTimer.Tick += (_, _) =>
        {
            _collapseTimer.Stop();
            Collapse();
        };

        MouseEnter += (_, _) =>
        {
            _collapseTimer.Stop();
            if (!_isExpanded) _expandTimer.Start();
        };

        MouseLeave += (_, _) =>
        {
            _expandTimer.Stop();
            if (_isExpanded) _collapseTimer.Start();
        };

        Loaded += IslandWindow_Loaded;
    }

    private void IslandWindow_Loaded(object sender, RoutedEventArgs e)
    {
        PositionTopCenter();
        TabContentHost.Content = _musicTab;

        var helper = new WindowInteropHelper(this);
        _hwndSource = HwndSource.FromHwnd(helper.Handle);
        _hwndSource?.AddHook(WndProc);

        NativeMethods.AddClipboardFormatListener(helper.Handle);
        HotKeyManager.Register(helper.Handle, HotKeyManager.HOTKEY_CLIPBOARD, HotKeyManager.MOD_CONTROL | HotKeyManager.MOD_SHIFT, HotKeyManager.VK_V);
    }

    protected override void OnClosed(EventArgs e)
    {
        var helper = new WindowInteropHelper(this);
        HotKeyManager.UnregisterAll(helper.Handle);
        NativeMethods.RemoveClipboardFormatListener(helper.Handle);
        _hwndSource?.RemoveHook(WndProc);
        base.OnClosed(e);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == NativeMethods.WM_CLIPBOARDUPDATE)
        {
            Hub?.Clips.OnClipboardUpdated();
            handled = true;
        }
        else if (msg == NativeMethods.WM_HOTKEY)
        {
            if (wParam.ToInt32() == HotKeyManager.HOTKEY_CLIPBOARD)
            {
                TabContentHost.Content = _clipboardTab;
                Expand();
                handled = true;
            }
        }
        return IntPtr.Zero;
    }

    private void PositionTopCenter()
    {
        var screenWidth = SystemParameters.PrimaryScreenWidth;
        Left = (screenWidth - Width) / 2;
        Top = 8;
    }

    public void Expand()
    {
        if (_isExpanded) return;
        _isExpanded = true;

        CompactGrid.Visibility = Visibility.Collapsed;
        ExpandedGrid.Visibility = Visibility.Visible;
        IslandBorder.CornerRadius = new CornerRadius(24);

        AnimateSize(ExpandedWidth, ExpandedHeight);
    }

    public void Collapse()
    {
        if (!_isExpanded) return;
        _isExpanded = false;

        ExpandedGrid.Visibility = Visibility.Collapsed;
        CompactGrid.Visibility = Visibility.Visible;
        IslandBorder.CornerRadius = new CornerRadius(18);

        AnimateSize(CompactWidth, CompactHeight);
    }

    private void AnimateSize(double targetW, double targetH)
    {
        var screenWidth = SystemParameters.PrimaryScreenWidth;
        var targetLeft = (screenWidth - targetW) / 2;

        var animW = new DoubleAnimation(targetW, TimeSpan.FromMilliseconds(200)) { EasingFunction = new QuadraticEase() };
        var animH = new DoubleAnimation(targetH, TimeSpan.FromMilliseconds(200)) { EasingFunction = new QuadraticEase() };
        var animL = new DoubleAnimation(targetLeft, TimeSpan.FromMilliseconds(200)) { EasingFunction = new QuadraticEase() };

        BeginAnimation(WidthProperty, animW);
        BeginAnimation(HeightProperty, animH);
        BeginAnimation(LeftProperty, animL);
    }

    private void Tab_Click(object sender, RoutedEventArgs e)
    {
        if (sender is RadioButton { Tag: string tag })
        {
            TabContentHost.Content = tag switch
            {
                "Music" => _musicTab,
                "Files" => _filesTab,
                "Clipboard" => _clipboardTab,
                "Calendar" => _calendarTab,
                "Stats" => _statsTab,
                "Notes" => _notesTab,
                "Agents" => _agentsTab,
                _ => _musicTab
            };
        }
    }

    private void Bubble_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: AppBubble bubble })
        {
            Hub?.Switcher.SwitchTo(bubble);
            Collapse();
        }
    }
}

