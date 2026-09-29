$source = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class MenuNative {
  [DllImport("user32.dll")] public static extern IntPtr GetMenu(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetSubMenu(IntPtr hMenu, int pos);
  [DllImport("user32.dll")] public static extern int GetMenuItemCount(IntPtr hMenu);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern int GetMenuString(IntPtr hMenu, uint id, StringBuilder text, int max, uint flags);
  [DllImport("user32.dll")] public static extern uint GetMenuItemID(IntPtr hMenu, int pos);
  [DllImport("user32.dll")] public static extern uint GetMenuState(IntPtr hMenu, uint id, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp);
}
'@
Add-Type $source
$h = [IntPtr]::new(526848)
$menu = [MenuNative]::GetMenu($h)
$lines = @("menu=$menu")
for ($m=0; $m -lt [MenuNative]::GetMenuItemCount($menu); $m++) {
  $sub = [MenuNative]::GetSubMenu($menu, $m)
  $heading = [Text.StringBuilder]::new(256)
  [void][MenuNative]::GetMenuString($menu, [uint32]$m, $heading, 256, 0x400)
  $lines += "TOP $m $heading sub=$sub"
  if ($sub -eq [IntPtr]::Zero) { continue }
  for ($i=0; $i -lt [MenuNative]::GetMenuItemCount($sub); $i++) {
    $name = [Text.StringBuilder]::new(256)
    [void][MenuNative]::GetMenuString($sub, [uint32]$i, $name, 256, 0x400)
    $id = [MenuNative]::GetMenuItemID($sub,$i)
    $state = [MenuNative]::GetMenuState($sub,[uint32]$i,0x400)
    $lines += "  $i id=$id state=$state $name"
  }
}
$lines | Set-Content -Encoding UTF8 'C:\Temp\procmon-menu.txt'
