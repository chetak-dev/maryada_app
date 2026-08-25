// See https://aka.ms/new-console-template for more information
using GuardNest.Core.Apps;

var apps = InstalledApps.Enumerate();
Console.WriteLine($"Reported app count: {apps.Count}");
foreach (var app in apps)
{
	Console.WriteLine($"{app.Key}\t{app.Name}");
}
