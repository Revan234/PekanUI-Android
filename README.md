# PekanBaru Android UI

This folder contains a separate Android entry script and the MonetLoader
Android `mimgui` Lua library. The library files are from
[MonetLoaderOSS](https://github.com/xefinity/MonetLoaderOSS), distributed under
the MIT License. MonetLoader supplies the native renderer; this folder does
not include or build a native Android binary.

Install `android/uijtrp.lua` as a separate script (for example
`uijtrp_android.lua`); do not replace the PC `uijtrp.lua`. Copy the files in
`android/lib/mimgui` to the device's `monetloader/lib/mimgui` folder, replacing
the PC versions of `init.lua`, `imgui.lua`, and `cdefs.lua`. Keep
`trebucbd.ttf` in that folder. Do not use the PC `cimguidx9.dll`: the Android
library loads MonetLoader's native renderer instead.

Requires MonetLoader 2.6.0 or newer. Type `/rpui` in game to open the
touch-friendly quick-command menu.

This Android entry currently provides a mobile quick-command menu. It is
separate from the full PC UI and does not yet port the PC-only browser,
Windows integrations, or every specialized UI module.

## Automatic updates

The script checks
`Revan234/PekanUI-Android/main/uijtrp.lua` when it starts and every 10 minutes.
Publish the Android script at the repository root with the exact filename
`uijtrp.lua`. The updater validates the downloaded Lua source, installs it next
to the running script, and asks MonetLoader to reload scripts. It updates only
the Android script; MonetLoader's native renderer and `mimgui` dependencies are
not downloaded or replaced by this updater.
