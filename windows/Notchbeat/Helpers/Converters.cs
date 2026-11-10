using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace Notchbeat.Helpers;

/// <summary>
/// Converts a boolean to Visibility (true → Visible, false → Collapsed).
/// </summary>
public sealed class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return value is true ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return value is Visibility.Visible;
    }
}

/// <summary>
/// Converts a boolean to Visibility (true → Collapsed, false → Visible).
/// </summary>
public sealed class InverseBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return value is true ? Visibility.Collapsed : Visibility.Visible;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return value is Visibility.Collapsed;
    }
}

/// <summary>
/// Converts a boolean to opacity (true → 1.0, false → 0.5).
/// </summary>
public sealed class BoolToOpacityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return value is true ? 1.0 : 0.5;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return value is 1.0;
    }
}

/// <summary>
/// Formats a TimeSpan as mm:ss.
/// </summary>
public sealed class TimeSpanToStringConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is TimeSpan ts)
        {
            int totalMinutes = (int)ts.TotalMinutes;
            return $"{totalMinutes:D2}:{ts.Seconds:D2}";
        }

        if (value is double seconds && !double.IsNaN(seconds))
        {
            var ts2 = TimeSpan.FromSeconds(seconds);
            int totalMinutes = (int)ts2.TotalMinutes;
            return $"{totalMinutes:D2}:{ts2.Seconds:D2}";
        }

        return "00:00";
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return Binding.DoNothing;
    }
}

/// <summary>
/// Multi-value converter: computes percent × actualWidth.
/// Values[0] = progress percent (0.0–1.0), Values[1] = actual width.
/// </summary>
public sealed class PercentToWidthConverter : IMultiValueConverter
{
    public object Convert(object?[] values, Type targetType, object? parameter, CultureInfo culture)
    {
        if (values.Length >= 2
            && values[0] is double percent
            && values[1] is double actualWidth)
        {
            return Math.Max(0, percent * actualWidth);
        }

        return 0.0;
    }

    public object[] ConvertBack(object? value, Type[] targetTypes, object? parameter, CultureInfo culture)
    {
        return [Binding.DoNothing, Binding.DoNothing];
    }
}

/// <summary>
/// Non-null → Visible, null → Collapsed.
/// </summary>
public sealed class NullToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return value is not null ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return Binding.DoNothing;
    }
}

/// <summary>
/// Non-empty string → Visible, null/empty/whitespace → Collapsed.
/// </summary>
public sealed class StringNotEmptyToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return value is string s && !string.IsNullOrWhiteSpace(s)
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        return Binding.DoNothing;
    }
}
