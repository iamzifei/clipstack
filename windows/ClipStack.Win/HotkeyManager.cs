using System.Runtime.InteropServices;

namespace ClipStack.Win;

/// <summary>
/// Global hotkeys via RegisterHotKey on a hidden window.
/// Ctrl+Shift+V opens the switcher (macOS ⇧⌘V), Ctrl+. opens settings (⌘.).
/// </summary>
public class HotkeyManager : NativeWindow, IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_SHIFT = 0x0004;
    private const uint MOD_NOREPEAT = 0x4000;
    private const uint VK_V = 0x56;
    private const uint VK_OEM_PERIOD = 0xBE;

    private const int SwitcherId = 1;
    private const int SettingsId = 2;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public Action? OpenSwitcher;
    public Action? OpenSettings;

    /// <summary>True when the switcher hotkey registered successfully.</summary>
    public bool SwitcherRegistered { get; }
    public bool SettingsRegistered { get; }

    public HotkeyManager()
    {
        CreateHandle(new CreateParams());
        SwitcherRegistered = RegisterHotKey(Handle, SwitcherId, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, VK_V);
        SettingsRegistered = RegisterHotKey(Handle, SettingsId, MOD_CONTROL | MOD_NOREPEAT, VK_OEM_PERIOD);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY)
        {
            switch (m.WParam.ToInt32())
            {
                case SwitcherId: OpenSwitcher?.Invoke(); break;
                case SettingsId: OpenSettings?.Invoke(); break;
            }
        }
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        if (Handle != IntPtr.Zero)
        {
            UnregisterHotKey(Handle, SwitcherId);
            UnregisterHotKey(Handle, SettingsId);
            DestroyHandle();
        }
        GC.SuppressFinalize(this);
    }
}
