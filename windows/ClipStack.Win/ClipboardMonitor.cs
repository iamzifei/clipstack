using System.Diagnostics;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace ClipStack.Win;

/// <summary>
/// Event-driven clipboard listener (no polling needed on Windows):
/// AddClipboardFormatListener delivers WM_CLIPBOARDUPDATE to a hidden window.
/// </summary>
public class ClipboardMonitor : NativeWindow, IDisposable
{
    private const int WM_CLIPBOARDUPDATE = 0x031D;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool AddClipboardFormatListener(IntPtr hwnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RemoveClipboardFormatListener(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    /// <summary>Set before writing the clipboard ourselves so the restore
    /// is not re-captured as a new entry (the item gets promoted instead).</summary>
    public static bool SuppressNextCapture;

    public bool IsPaused;

    private readonly HistoryStore _store;
    private const long MaxTextBytes = 5_000_000;
    private const long MaxImageBytes = 40_000_000;

    public ClipboardMonitor(HistoryStore store)
    {
        _store = store;
        CreateHandle(new CreateParams());
        AddClipboardFormatListener(Handle);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_CLIPBOARDUPDATE)
        {
            if (SuppressNextCapture) SuppressNextCapture = false;
            else if (!IsPaused) Capture();
        }
        base.WndProc(ref m);
    }

    private void Capture()
    {
        // The clipboard can still be locked by the writing app; retry briefly.
        for (var attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                CaptureOnce();
                return;
            }
            catch (ExternalException)
            {
                Thread.Sleep(60);
            }
            catch
            {
                return; // anything else: skip this update
            }
        }
    }

    private void CaptureOnce()
    {
        var source = ForegroundProcessName();

        if (Clipboard.ContainsFileDropList())
        {
            var paths = Clipboard.GetFileDropList().Cast<string>().ToList();
            if (paths.Count == 0) return;
            _store.Add(new ClipItem
            {
                Kind = ClipKind.File,
                ContentHash = ClipItem.HashOfFiles(paths),
                PlainText = string.Join("\n", paths),
                FilePaths = paths,
                SourceApp = source,
                ByteSize = paths.Sum(p => (long)p.Length),
            });
            return;
        }

        if (Clipboard.ContainsImage())
        {
            using var image = Clipboard.GetImage();
            if (image == null) return;
            using var ms = new MemoryStream();
            image.Save(ms, ImageFormat.Png);
            var png = ms.ToArray();
            if (png.Length > MaxImageBytes) return;
            var hash = ClipItem.HashOfImage(png);
            if (_store.PromoteIfExists(hash)) return;
            var fileName = _store.StoreImagePng(png);
            _store.Add(new ClipItem
            {
                Kind = ClipKind.Image,
                ContentHash = hash,
                ImageFileName = fileName,
                ImagePixelWidth = image.Width,
                ImagePixelHeight = image.Height,
                SourceApp = source,
                ByteSize = png.Length,
            });
            return;
        }

        if (Clipboard.ContainsText())
        {
            var text = Clipboard.GetText(TextDataFormat.UnicodeText);
            if (string.IsNullOrWhiteSpace(text)) return;
            if (System.Text.Encoding.UTF8.GetByteCount(text) > MaxTextBytes) return;
            _store.Add(new ClipItem
            {
                Kind = ClipKind.Text,
                ContentHash = ClipItem.HashOfText(text),
                PlainText = text,
                SourceApp = source,
                ByteSize = System.Text.Encoding.UTF8.GetByteCount(text),
            });
        }
    }

    private static string? ForegroundProcessName()
    {
        try
        {
            GetWindowThreadProcessId(GetForegroundWindow(), out var pid);
            if (pid == 0) return null;
            using var process = Process.GetProcessById((int)pid);
            return process.ProcessName;
        }
        catch
        {
            return null;
        }
    }

    public void Dispose()
    {
        if (Handle != IntPtr.Zero)
        {
            RemoveClipboardFormatListener(Handle);
            DestroyHandle();
        }
        GC.SuppressFinalize(this);
    }
}
