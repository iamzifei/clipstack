namespace ClipStack.Win;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        // Single instance: a second launch exits immediately.
        using var mutex = new Mutex(true, "ClipStack.Win.Singleton", out var createdNew);
        if (!createdNew) return;

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApplicationContext());
    }
}
