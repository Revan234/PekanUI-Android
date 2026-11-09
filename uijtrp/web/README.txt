San Andreas Online - Browser
============================

This folder is the Browser of San Andreas Online's phone. It was downloaded by the game when the Browser was
installed from the phone's App Store. Remove the Browser from the App Store to delete it (or delete this folder
while the game is closed).

The PekanBaru Lua PKU updater can also download the distributable Browser files from its update manifest.
The profile folder is local user data and is intentionally excluded from updater downloads.

It shows web pages on the phone and on the big screen. It runs only while the game runs, never shows a window, and
closes by itself with the game. Pages are fetched straight from your own internet connection: nothing you browse
goes through San Andreas Online's servers. Their sound plays only in the game.

The web engine is Microsoft Edge WebView2, a part of Windows that Microsoft keeps up to date (it is not in this
folder). Microsoft Defender SmartScreen stays on in it, as in Windows, to warn about dangerous sites.

profile\ holds the Browser's cookies and cache (Settings > Browser > Clear History and Data empties it).

sao_web.exe includes the Microsoft WebView2 loader (LICENSE_WebView2_SDK.txt, NOTICE_WebView2_SDK.txt).
San Andreas Online by [TFM]Sparko75.
