namespace ClipStack.Win;

/// <summary>
/// Tray-only application shell: NotifyIcon menu, clipboard monitor,
/// global hotkeys, switcher + settings windows.
/// </summary>
public class TrayApplicationContext : ApplicationContext
{
    private readonly NotifyIcon _tray;
    private readonly HistoryStore _store;
    private readonly ClipboardMonitor _monitor;
    private readonly HotkeyManager _hotkeys;
    private readonly SwitcherForm _switcher;
    private SettingsForm? _settings;

    public TrayApplicationContext()
    {
        var dataDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ClipStack");
        _store = new HistoryStore(dataDir);
        _monitor = new ClipboardMonitor(_store);
        _switcher = new SwitcherForm(_store)
        {
            OnCopied = item => ToastForm.ShowCopied(item.PreviewLine),
        };

        _hotkeys = new HotkeyManager
        {
            OpenSwitcher = () => _switcher.ShowSwitcher(),
            OpenSettings = OpenSettings,
        };

        var menu = new ContextMenuStrip();
        menu.Opening += (_, _) => RebuildMenu(menu);

        _tray = new NotifyIcon
        {
            Icon = LoadIcon(),
            Text = "ClipStack — Ctrl+Shift+V",
            Visible = true,
            ContextMenuStrip = menu,
        };
        _tray.DoubleClick += (_, _) => _switcher.ShowSwitcher();
    }

    private static Icon LoadIcon()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "app.ico");
        return File.Exists(path) ? new Icon(path) : SystemIcons.Application;
    }

    private void RebuildMenu(ContextMenuStrip menu)
    {
        menu.Items.Clear();
        menu.Items.Add(Strings.T("menu_open"), null, (_, _) => _switcher.ShowSwitcher());
        menu.Items.Add(Strings.T("menu_settings"), null, (_, _) => OpenSettings());
        menu.Items.Add(new ToolStripSeparator());

        foreach (var item in _store.Items.Take(10))
        {
            var captured = item;
            var title = captured.PreviewLine;
            if (title.Length > 50) title = title[..50];
            menu.Items.Add(title, null, (_, _) => CopyFromMenu(captured));
        }
        if (_store.Items.Count > 0) menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(
            _monitor.IsPaused ? Strings.T("menu_resume") : Strings.T("menu_pause"),
            null,
            (_, _) => _monitor.IsPaused = !_monitor.IsPaused);
        menu.Items.Add(Strings.T("menu_clear"), null, (_, _) => ClearHistory());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Strings.T("menu_quit"), null, (_, _) => ExitThread());
    }

    private void CopyFromMenu(ClipItem item)
    {
        try
        {
            ClipboardMonitor.SuppressNextCapture = true;
            switch (item.Kind)
            {
                case ClipKind.Text:
                    Clipboard.SetText(item.PlainText ?? "", TextDataFormat.UnicodeText);
                    break;
                case ClipKind.Image:
                    var data = _store.ImageData(item);
                    if (data == null) return;
                    using (var ms = new MemoryStream(data))
                    using (var img = Image.FromStream(ms))
                        Clipboard.SetImage(new Bitmap(img));
                    break;
                case ClipKind.File:
                    var files = new System.Collections.Specialized.StringCollection();
                    files.AddRange((item.FilePaths ?? new()).ToArray());
                    Clipboard.SetFileDropList(files);
                    break;
            }
            _store.PromoteIfExists(item.ContentHash);
            ToastForm.ShowCopied(item.PreviewLine);
        }
        catch
        {
            ClipboardMonitor.SuppressNextCapture = false;
        }
    }

    private void ClearHistory()
    {
        var result = MessageBox.Show(
            Strings.T("clear_msg"), Strings.T("clear_title"),
            MessageBoxButtons.OKCancel, MessageBoxIcon.Warning);
        if (result == DialogResult.OK) _store.Clear(keepPinned: true);
    }

    private void OpenSettings()
    {
        _settings ??= new SettingsForm();
        _settings.Show();
        _settings.Activate();
    }

    protected override void ExitThreadCore()
    {
        _store.Save();
        _tray.Visible = false;
        _tray.Dispose();
        _hotkeys.Dispose();
        _monitor.Dispose();
        base.ExitThreadCore();
    }
}
