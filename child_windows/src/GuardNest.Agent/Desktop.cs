using System.Runtime.InteropServices;

namespace GuardNest.Agent;

/// <summary>
/// The two ways out of a block screen: step back in the browser, or clear the
/// screen entirely. Without them the child is left staring at a full-screen
/// message with nothing to press.
/// </summary>
internal static class Desktop
{
    private const byte VkMenu = 0x12;
    private const byte VkLeft = 0x25;
    private const uint KeyUp = 0x0002;

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);

    /// <summary>Sends Alt+Left to whatever the child is looking at.</summary>
    public static void NavigateBack()
    {
        // The overlay has just hidden; let the browser take focus back before
        // the keystroke, or it lands on a window that is going away.
        Thread.Sleep(120);
        keybd_event(VkMenu, 0, 0, UIntPtr.Zero);
        keybd_event(VkLeft, 0, 0, UIntPtr.Zero);
        keybd_event(VkLeft, 0, KeyUp, UIntPtr.Zero);
        keybd_event(VkMenu, 0, KeyUp, UIntPtr.Zero);
    }

    public static void ShowDesktop()
    {
        var shellType = Type.GetTypeFromProgID("Shell.Application");
        if (shellType is null) return;

        dynamic? shell = null;
        try
        {
            shell = Activator.CreateInstance(shellType);
            shell!.MinimizeAll();
        }
        catch (Exception e) when (e is COMException or MissingMemberException)
        {
        }
        finally
        {
            if (shell is not null && Marshal.IsComObject(shell)) Marshal.FinalReleaseComObject(shell);
        }
    }
}
