using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Windows.Media.Imaging;
using Notchbeat.Core;
using Notchbeat.Helpers;

namespace Notchbeat.Models;

public sealed class ShelfItem : ObservableObject
{
    public string Path { get; set; } = string.Empty;
    public string FileName => System.IO.Path.GetFileName(Path);
    public BitmapSource? Thumbnail { get; set; }
}

public sealed class ShelfModel : ObservableObject
{
    private readonly string _filePath;
    public ObservableCollection<ShelfItem> Items { get; } = [];

    public ShelfModel()
    {
        var appData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Notchbeat");
        Directory.CreateDirectory(appData);
        _filePath = Path.Combine(appData, "shelf.json");
        Load();
    }

    public void Add(IEnumerable<string> paths)
    {
        foreach (var p in paths)
        {
            if (File.Exists(p) && Items.All(i => i.Path != p))
            {
                Items.Add(new ShelfItem
                {
                    Path = p,
                    Thumbnail = GetFileIcon(p)
                });
            }
        }
        Save();
    }

    public void Remove(ShelfItem item)
    {
        Items.Remove(item);
        Save();
    }

    public void Clear()
    {
        Items.Clear();
        Save();
    }

    private static BitmapSource? GetFileIcon(string path)
    {
        try
        {
            var shinfo = new NativeMethods.SHFILEINFO();
            var res = NativeMethods.SHGetFileInfo(path, 0, ref shinfo, (uint)System.Runtime.InteropServices.Marshal.SizeOf(shinfo), NativeMethods.SHGFI_ICON | NativeMethods.SHGFI_LARGEICON);
            if (res != IntPtr.Zero && shinfo.hIcon != IntPtr.Zero)
            {
                var img = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(shinfo.hIcon, System.Windows.Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                img.Freeze();
                NativeMethods.DestroyIcon(shinfo.hIcon);
                return img;
            }
        }
        catch { }
        return null;
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(_filePath)) return;
            var json = File.ReadAllText(_filePath);
            var paths = JsonSerializer.Deserialize<List<string>>(json);
            if (paths != null)
            {
                foreach (var p in paths.Where(File.Exists))
                {
                    Items.Add(new ShelfItem { Path = p, Thumbnail = GetFileIcon(p) });
                }
            }
        }
        catch { }
    }

    private void Save()
    {
        try
        {
            var paths = Items.Select(i => i.Path).ToList();
            var json = JsonSerializer.Serialize(paths);
            File.WriteAllText(_filePath, json);
        }
        catch { }
    }
}

