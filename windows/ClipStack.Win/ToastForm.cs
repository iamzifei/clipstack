namespace ClipStack.Win;

/// <summary>
/// Transient "Copied" toast, top-center of the active screen, non-activating.
/// </summary>
public class ToastForm : Form
{
    private readonly System.Windows.Forms.Timer _timer = new();

    private ToastForm(string title, string? detail)
    {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = Color.FromArgb(45, 45, 50);
        Padding = new Padding(14, 9, 14, 9);
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;

        var layout = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            BackColor = Color.Transparent,
        };
        layout.Controls.Add(new Label
        {
            Text = "✓ " + title,
            ForeColor = Color.LightGreen,
            Font = new Font("Segoe UI", 10f, FontStyle.Bold),
            AutoSize = true,
        });
        if (!string.IsNullOrEmpty(detail))
        {
            layout.Controls.Add(new Label
            {
                Text = detail.Length > 48 ? detail[..48] : detail,
                ForeColor = Color.Silver,
                Font = new Font("Segoe UI", 8.5f),
                AutoSize = true,
            });
        }
        Controls.Add(layout);

        _timer.Interval = 1300;
        _timer.Tick += (_, _) => Close();
    }

    protected override bool ShowWithoutActivation => true;

    public static void ShowCopied(string? detail)
    {
        var toast = new ToastForm(Strings.T("toast_copied"), detail);
        var screen = Screen.FromPoint(Cursor.Position).WorkingArea;
        toast.Load += (_, _) =>
        {
            toast.Location = new Point(
                screen.Left + (screen.Width - toast.Width) / 2,
                screen.Top + 24);
            toast._timer.Start();
        };
        toast.FormClosed += (_, _) => toast.Dispose();
        toast.Show();
    }
}
