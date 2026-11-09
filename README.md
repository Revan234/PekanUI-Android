# PekanBaru Android UI

This is the Android/MonetLoader build of the PekanBaru roleplay UI. It is
separate from the Windows PC script and uses MonetLoader's Android-native
`mimgui` renderer; it does not load `cimguidx9.dll`, Windows APIs, or the
WebView2 executable.

## Install

1. Use MonetLoader 2.6.0 or newer.
2. Install `uijtrp.lua` in the MonetLoader scripts folder.
3. Copy the `uijtrp`, `assets`, and `jtrp_phone` folders beside `uijtrp.lua`.
   Keep the folder names unchanged; the script loads its modules and images
   from these paths.
4. Copy the files in `lib/mimgui` to `monetloader/lib/mimgui`. MonetLoader
   provides the native renderer; never install the PC `cimguidx9.dll` on
   Android.
5. Connect to PekanBaru, then open the UI using `/rpui` or the on-screen
   **PBRP UI** button. `/lradial` opens the touch-operated radial menu.

The Android layout switches to a page selector in portrait mode and retains
the sidebar in landscape. The port contains the roleplay hub, HUD, radial menu,
inventory, phone, vehicles, login/character selection, faction and business
panels, notifications, and the other Lua UI modules in `uijtrp`. Features
that require server commands, permissions, streamed textdraws, or a specific
location still depend on the gamemode and server.

Some MonetLoader Android builds do not include the `samp.events` Lua module.
The main UI remains available without it, but event-driven textdraw features
such as custom server notifications and textdraw inventory interception need a
compatible `samp.events` module installed in MonetLoader's `lib` folder.

Windows-only browser launching is unavailable on Android. Discord and website
buttons copy their URL so it can be pasted into the Android browser. The phone
media album can read screenshots from Android's `Pictures/Screenshots` or
`DCIM/Screenshots` folders when MonetLoader has storage access.

## Automatic updates

The updater checks `Revan234/PekanUI-Android` on branch `main` while connected
to the configured PekanBaru server, then checks again every 10 minutes. Keep
`update-manifest.txt` at the repository root. It lists the main script,
compatible Lua modules, and UI assets updated by the updater. Changes to
`uijtrp.lua`, `uijtrp`, and `assets` should be added to that manifest.
Downloads use MonetLoader's native downloader when available, then fall back
to its `requests` or LuaSocket/LuaSec HTTP modules. The corresponding MonetLoader
libraries must be installed for automatic updates to work.

The updater does not replace MonetLoader's native renderer or update the
large notification/ringtone files in `jtrp_phone`; those files must be
included when installing the repository. Never add Windows-only browser
executables or DLLs to the Android manifest.
