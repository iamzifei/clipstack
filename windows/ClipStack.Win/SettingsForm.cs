using System.Diagnostics;
using Microsoft.Win32;

namespace ClipStack.Win;

/// <summary>
/// Settings: launch-at-startup toggle (HKCU Run key), fixed-hotkey note,
/// GitHub link and version — mirroring the macOS settings window.
/// </summary>
public class SettingsForm : Form
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "ClipStack";
    private const string GitHubUrl = "https://github.com/iamzifei/clipstack";

    public SettingsForm()
    {
        Text = Strings.T("settings_title");
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(420, 200);

        var launchToggle = new CheckBox
        {
            Text = Strings.T("login_toggle"),
            Location = new Point(20, 20),
            AutoSize = true,
            Checked = IsLaunchAtStartupEnabled(),
        };
        launchToggle.CheckedChanged += (_, _) => SetLaunchAtStartup(launchToggle.Checked);

        var hotkeyNote = new Label
        {
            Text = Strings.T("hotkeys_note"),
            Location = new Point(20, 55),
            Size = new Size(380, 40),
            ForeColor = Color.DimGray,
        };

        var githubLabel = new Label { Text = "GitHub", Location = new Point(20, 105), AutoSize = true };
        var githubLink = new LinkLabel
        {
            Text = "github.com/iamzifei/clipstack",
            Location = new Point(90, 105),
            AutoSize = true,
        };
        githubLink.LinkClicked += (_, _) =>
            Process.Start(new ProcessStartInfo { FileName = GitHubUrl, UseShellExecute = true });

        var versionLabel = new Label
        {
            Text = $"{Strings.T("version")}  {Application.ProductVersion.Split('+')[0]}",
            Location = new Point(20, 140),
            AutoSize = true,
            ForeColor = Color.DimGray,
        };

        Controls.AddRange(new Control[] { launchToggle, hotkeyNote, githubLabel, githubLink, versionLabel });
    }

    private static bool IsLaunchAtStartupEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, false);
        return key?.GetValue(RunValueName) != null;
    }

    private static void SetLaunchAtStartup(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, true)
                            ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);
            if (enabled)
                key.SetValue(RunValueName, $"\"{Application.ExecutablePath}\"");
            else
                key.DeleteValue(RunValueName, false);
        }
        catch { /* registry unavailable: ignore */ }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
        }
        base.OnFormClosing(e);
    }
}
