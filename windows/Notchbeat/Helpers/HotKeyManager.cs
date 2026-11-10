namespace Notchbeat.Helpers;

public static class HotKeyManager
{
    // ── Modifier Keys ────────────────────────────────────────────────────

    public const uint MOD_NONE = 0x0000;
    public const uint MOD_ALT = 0x0001;
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_SHIFT = 0x0004;
    public const uint MOD_WIN = 0x0008;
    public const uint MOD_NOREPEAT = 0x4000;

    // ── Virtual Key Codes ────────────────────────────────────────────────

    public const uint VK_V = 0x56;
    public const uint VK_SPACE = 0x20;
    public const uint VK_LEFT = 0x25;
    public const uint VK_RIGHT = 0x27;

    // ── Hotkey IDs ───────────────────────────────────────────────────────

    public const int HOTKEY_CLIPBOARD = 9001;
    public const int HOTKEY_PLAY_PAUSE = 9002;
    public const int HOTKEY_NEXT_TRACK = 9003;
    public const int HOTKEY_PREV_TRACK = 9004;

    /// <summary>
    /// Registers a global hotkey with the operating system.
    /// </summary>
    /// <param name="hwnd">Handle to the window that will receive WM_HOTKEY messages.</param>
    /// <param name="id">Unique identifier for this hotkey registration.</param>
    /// <param name="modifiers">Modifier key flags (MOD_SHIFT, MOD_CONTROL, MOD_ALT, MOD_WIN).</param>
    /// <param name="key">Virtual key code for the hotkey.</param>
    /// <returns>True if registration succeeded; false otherwise.</returns>
    public static bool Register(IntPtr hwnd, int id, uint modifiers, uint key)
    {
        return NativeMethods.RegisterHotKey(hwnd, id, modifiers, key);
    }

    /// <summary>
    /// Unregisters a previously registered global hotkey.
    /// </summary>
    /// <param name="hwnd">Handle to the window that registered the hotkey.</param>
    /// <param name="id">The identifier used during registration.</param>
    /// <returns>True if unregistration succeeded; false otherwise.</returns>
    public static bool Unregister(IntPtr hwnd, int id)
    {
        return NativeMethods.UnregisterHotKey(hwnd, id);
    }

    /// <summary>
    /// Unregisters all known hotkeys for the given window handle.
    /// </summary>
    public static void UnregisterAll(IntPtr hwnd)
    {
        Unregister(hwnd, HOTKEY_CLIPBOARD);
        Unregister(hwnd, HOTKEY_PLAY_PAUSE);
        Unregister(hwnd, HOTKEY_NEXT_TRACK);
        Unregister(hwnd, HOTKEY_PREV_TRACK);
    }
}
