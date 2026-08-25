using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Automation;

namespace GuardNest.Agent;

/// <summary>
/// Writes the foreground window's UI Automation tree to a file.
///
/// Chat capture depends on how an app happens to expose its message rows, which
/// cannot be guessed from documentation and differs between WhatsApp Desktop and
/// WhatsApp Web. This is how the selectors in <see cref="ChatScanner"/> get
/// tuned against the real thing: run the agent with --dump-uia, switch to the
/// window within the countdown, then read the file.
/// </summary>
internal static class UiaDump
{
    private const int MaxDepth = 24;
    private const int MaxElements = 4000;

    public static void Run(int delaySeconds, string path)
    {
        Console.WriteLine($"Switch to the window to inspect. Capturing in {delaySeconds}s…");
        Thread.Sleep(TimeSpan.FromSeconds(delaySeconds));

        var window = Native.GetForegroundWindow();
        if (window == IntPtr.Zero)
        {
            Console.WriteLine("No foreground window.");
            return;
        }

        var output = new StringBuilder();
        output.AppendLine($"window: {Native.WindowTitle(window)}");

        var written = 0;
        try
        {
            var root = AutomationElement.FromHandle(window);
            Walk(root, 0, output, ref written);
        }
        catch (Exception e) when (e is ElementNotAvailableException or COMException)
        {
            output.AppendLine($"(tree ended early: {e.Message})");
        }

        File.WriteAllText(path, output.ToString());
        Console.WriteLine($"Wrote {written} elements to {path}");
    }

    private static void Walk(AutomationElement element, int depth, StringBuilder output, ref int written)
    {
        if (depth > MaxDepth || written >= MaxElements) return;

        try
        {
            var current = element.Current;
            var rect = current.BoundingRectangle;
            output.Append(new string(' ', depth * 2))
                .Append(current.ControlType.ProgrammaticName.Replace("ControlType.", ""))
                .Append("  name=\"").Append(Clip(current.Name)).Append('"');
            if (current.AutomationId.Length > 0) output.Append("  id=").Append(current.AutomationId);
            if (current.ClassName.Length > 0) output.Append("  class=").Append(current.ClassName);
            if (!rect.IsEmpty)
            {
                output.Append($"  rect=[{rect.Left:0},{rect.Top:0},{rect.Width:0}x{rect.Height:0}]");
            }
            output.AppendLine();
            written++;
        }
        catch (Exception e) when (e is ElementNotAvailableException or COMException)
        {
            return;
        }

        foreach (AutomationElement child in element.FindAll(TreeScope.Children, Condition.TrueCondition))
        {
            Walk(child, depth + 1, output, ref written);
            if (written >= MaxElements) return;
        }
    }

    private static string Clip(string value)
    {
        var single = value.ReplaceLineEndings(" ");
        return single.Length <= 120 ? single : single[..120] + "…";
    }
}
