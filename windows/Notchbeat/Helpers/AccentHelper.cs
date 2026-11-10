using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Notchbeat.Helpers;

public static class AccentHelper
{
    /// <summary>
    /// Extracts the dominant color from a BitmapImage by scaling it down to 1×1 pixel,
    /// then boosting saturation and brightness to produce a vivid accent color.
    /// </summary>
    public static Color GetAccentColor(BitmapImage? image)
    {
        if (image is null || image.PixelWidth == 0 || image.PixelHeight == 0)
            return Colors.White;

        try
        {
            // Draw the image into a 1×1 RenderTargetBitmap to average all pixels
            var visual = new DrawingVisual();
            using (var ctx = visual.RenderOpen())
            {
                ctx.DrawImage(image, new Rect(0, 0, 1, 1));
            }

            var rtb = new RenderTargetBitmap(1, 1, 96, 96, PixelFormats.Pbgra32);
            rtb.Render(visual);

            var pixels = new byte[4];
            rtb.CopyPixels(pixels, 4, 0);

            byte b = pixels[0];
            byte g = pixels[1];
            byte r = pixels[2];
            byte a = pixels[3];

            // Handle pre-multiplied alpha
            if (a > 0 && a < 255)
            {
                r = (byte)(r * 255 / a);
                g = (byte)(g * 255 / a);
                b = (byte)(b * 255 / a);
            }

            // Convert to HSL, boost saturation and lightness, convert back
            RgbToHsl(r, g, b, out double h, out double s, out double l);

            // Boost saturation: push toward at least 0.6
            s = Math.Max(s, 0.6);
            s = Math.Min(s * 1.3, 1.0);

            // Boost lightness: keep in a vivid range (0.45–0.65)
            l = Math.Clamp(l, 0.45, 0.65);

            HslToRgb(h, s, l, out byte rr, out byte gg, out byte bb);

            return Color.FromRgb(rr, gg, bb);
        }
        catch
        {
            return Colors.White;
        }
    }

    /// <summary>
    /// Returns a frozen SolidColorBrush for the accent color of the given image.
    /// </summary>
    public static SolidColorBrush GetAccentBrush(BitmapImage? image)
    {
        var brush = new SolidColorBrush(GetAccentColor(image));
        brush.Freeze();
        return brush;
    }

    // ── HSL Conversion ───────────────────────────────────────────────────

    private static void RgbToHsl(byte r, byte g, byte b, out double h, out double s, out double l)
    {
        double rr = r / 255.0;
        double gg = g / 255.0;
        double bb = b / 255.0;

        double max = Math.Max(rr, Math.Max(gg, bb));
        double min = Math.Min(rr, Math.Min(gg, bb));
        double delta = max - min;

        l = (max + min) / 2.0;

        if (delta < 0.00001)
        {
            h = 0;
            s = 0;
            return;
        }

        s = l > 0.5
            ? delta / (2.0 - max - min)
            : delta / (max + min);

        if (Math.Abs(max - rr) < 0.00001)
            h = ((gg - bb) / delta) + (gg < bb ? 6 : 0);
        else if (Math.Abs(max - gg) < 0.00001)
            h = ((bb - rr) / delta) + 2;
        else
            h = ((rr - gg) / delta) + 4;

        h /= 6.0;
    }

    private static void HslToRgb(double h, double s, double l, out byte r, out byte g, out byte b)
    {
        if (s < 0.00001)
        {
            r = g = b = (byte)(l * 255);
            return;
        }

        double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
        double p = 2 * l - q;

        r = (byte)(HueToRgb(p, q, h + 1.0 / 3.0) * 255);
        g = (byte)(HueToRgb(p, q, h) * 255);
        b = (byte)(HueToRgb(p, q, h - 1.0 / 3.0) * 255);
    }

    private static double HueToRgb(double p, double q, double t)
    {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;

        return t switch
        {
            < 1.0 / 6.0 => p + (q - p) * 6 * t,
            < 1.0 / 2.0 => q,
            < 2.0 / 3.0 => p + (q - p) * (2.0 / 3.0 - t) * 6,
            _ => p
        };
    }
}
