using System.Collections.Specialized;

namespace ClipStack.Win;

/// <summary>
/// The history switcher: search box on top, list left, preview right.
/// Enter copies and hides; the form deactivates away like a popover.
/// </summary>
public class SwitcherForm : Form
{
    private readonly HistoryStore _store;
    private readonly TextBox _search = new();
    private readonly ListBox _list = new();
    private readonly TextBox _previewText = new();
    private readonly PictureBox _previewImage = new();
    private readonly Label _countLabel = new();
    private readonly Label _hints = new();
    private List<ClipItem> _filtered = new();

    public Action<ClipItem>? OnCopied;

    public SwitcherForm(HistoryStore store)
    {
        _store = store;

        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        KeyPreview = true;
        Size = new Size(780, 460);
        Padding = new Padding(1);
        BackColor = Color.FromArgb(70, 70, 75);

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            BackColor = Color.FromArgb(32, 32, 36),
            ColumnCount = 2,
            RowCount = 3,
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 320));
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        _search.PlaceholderText = Strings.T("search_placeholder");
        _search.BorderStyle = BorderStyle.None;
        _search.BackColor = Color.FromArgb(32, 32, 36);
        _search.ForeColor = Color.White;
        _search.Font = new Font("Segoe UI", 12f);
        _search.Dock = DockStyle.Fill;
        _search.Margin = new Padding(12, 10, 4, 4);
        _search.TextChanged += (_, _) => Refilter();

        _countLabel.Dock = DockStyle.Fill;
        _countLabel.ForeColor = Color.Gray;
        _countLabel.TextAlign = ContentAlignment.MiddleRight;
        _countLabel.Margin = new Padding(0, 10, 12, 0);

        _list.Dock = DockStyle.Fill;
        _list.BorderStyle = BorderStyle.None;
        _list.BackColor = Color.FromArgb(38, 38, 43);
        _list.ForeColor = Color.White;
        _list.Font = new Font("Segoe UI", 10f);
        _list.IntegralHeight = false;
        _list.SelectedIndexChanged += (_, _) => UpdatePreview();
        _list.DoubleClick += (_, _) => CommitSelection();

        var previewPanel = new Panel { Dock = DockStyle.Fill, BackColor = Color.FromArgb(30, 30, 34) };
        _previewText.Multiline = true;
        _previewText.ReadOnly = true;
        _previewText.ScrollBars = ScrollBars.Vertical;
        _previewText.BorderStyle = BorderStyle.None;
        _previewText.BackColor = Color.FromArgb(30, 30, 34);
        _previewText.ForeColor = Color.Gainsboro;
        _previewText.Font = new Font("Consolas", 10f);
        _previewText.Dock = DockStyle.Fill;
        _previewImage.SizeMode = PictureBoxSizeMode.Zoom;
        _previewImage.Dock = DockStyle.Fill;
        _previewImage.Visible = false;
        previewPanel.Controls.Add(_previewText);
        previewPanel.Controls.Add(_previewImage);

        _hints.Text = Strings.T("hints");
        _hints.ForeColor = Color.Gray;
        _hints.Dock = DockStyle.Fill;
        _hints.TextAlign = ContentAlignment.MiddleLeft;
        _hints.Margin = new Padding(12, 0, 0, 0);

        root.Controls.Add(_search, 0, 0);
        root.Controls.Add(_countLabel, 1, 0);
        root.Controls.Add(_list, 0, 1);
        root.Controls.Add(previewPanel, 1, 1);
        root.Controls.Add(_hints, 0, 2);
        root.SetColumnSpan(_hints, 2);
        Controls.Add(root);

        Deactivate += (_, _) => Hide();
    }

    protected override bool ShowWithoutActivation => false;

    public void ShowSwitcher()
    {
        _search.Text = "";
        Refilter();
        var screen = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(
            screen.Left + (screen.Width - Width) / 2,
            screen.Top + (screen.Height - Height) / 2);
        Show();
        Activate();
        _search.Focus();
    }

    private void Refilter()
    {
        var query = _search.Text.Trim();
        _filtered = query.Length == 0
            ? _store.Items.ToList()
            : _store.Items.Where(i =>
                i.SearchText.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                (i.SourceApp?.Contains(query, StringComparison.OrdinalIgnoreCase) ?? false)).ToList();

        _list.BeginUpdate();
        _list.Items.Clear();
        foreach (var item in _filtered)
            _list.Items.Add(RowText(item));
        _list.EndUpdate();
        if (_list.Items.Count > 0) _list.SelectedIndex = 0;
        _countLabel.Text = string.Format(Strings.T("items_count"), _filtered.Count);
        UpdatePreview();
    }

    private static string RowText(ClipItem item)
    {
        var icon = item.Kind switch
        {
            ClipKind.Image => "🖼",
            ClipKind.File => "📄",
            _ => "📋",
        };
        var pin = item.Pinned ? "📌" : "";
        return $"{pin}{icon} {item.PreviewLine}";
    }

    private ClipItem? Selected =>
        _list.SelectedIndex >= 0 && _list.SelectedIndex < _filtered.Count
            ? _filtered[_list.SelectedIndex]
            : null;

    private void UpdatePreview()
    {
        var item = Selected;
        if (item == null)
        {
            _previewImage.Visible = false;
            _previewText.Visible = true;
            _previewText.Text = Strings.T("empty_history");
            return;
        }
        if (item.Kind == ClipKind.Image)
        {
            var data = _store.ImageData(item);
            if (data != null)
            {
                using var ms = new MemoryStream(data);
                using var img = Image.FromStream(ms);
                var old = _previewImage.Image;
                _previewImage.Image = new Bitmap(img);
                old?.Dispose();
                _previewImage.Visible = true;
                _previewText.Visible = false;
                return;
            }
        }
        _previewImage.Visible = false;
        _previewText.Visible = true;
        _previewText.Text = item.Kind == ClipKind.File
            ? string.Join(Environment.NewLine, item.FilePaths ?? new())
            : item.PlainText ?? "";
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        switch (keyData)
        {
            case Keys.Escape:
                Hide();
                return true;
            case Keys.Enter:
                CommitSelection();
                return true;
            case Keys.Down:
                MoveSelection(1);
                return true;
            case Keys.Up:
                MoveSelection(-1);
                return true;
            case Keys.Control | Keys.P:
                if (Selected is { } pinItem) { _store.TogglePin(pinItem.Id); Refilter(); }
                return true;
            case Keys.Control | Keys.Delete:
                if (Selected is { } delItem) { _store.Delete(delItem.Id); Refilter(); }
                return true;
        }
        // Ctrl+1..9 quick copy
        if ((keyData & Keys.Control) == Keys.Control)
        {
            var key = keyData & Keys.KeyCode;
            if (key is >= Keys.D1 and <= Keys.D9)
            {
                var index = key - Keys.D1;
                if (index < _filtered.Count) Commit(_filtered[index]);
                return true;
            }
        }
        return base.ProcessCmdKey(ref msg, keyData);
    }

    private void MoveSelection(int delta)
    {
        if (_list.Items.Count == 0) return;
        var next = Math.Clamp(_list.SelectedIndex + delta, 0, _list.Items.Count - 1);
        _list.SelectedIndex = next;
    }

    private void CommitSelection()
    {
        if (Selected is { } item) Commit(item);
    }

    private void Commit(ClipItem item)
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
                    {
                        Clipboard.SetImage(new Bitmap(img));
                    }
                    break;
                case ClipKind.File:
                    var files = new StringCollection();
                    files.AddRange((item.FilePaths ?? new()).ToArray());
                    Clipboard.SetFileDropList(files);
                    break;
            }
            _store.PromoteIfExists(item.ContentHash);
            Hide();
            OnCopied?.Invoke(item);
        }
        catch
        {
            ClipboardMonitor.SuppressNextCapture = false;
        }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        // Tray app: closing the window just hides it.
        if (e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
        }
        base.OnFormClosing(e);
    }
}
