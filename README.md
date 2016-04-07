# CheckValve Chat Relay SourceMod Plugin

This plugin eliminates the need for an extra Chat Relay server from CheckValve. 
If you have SourceMod and use CheckValve app often, it's almost a must to get.

# Requirements
1. SourceMod 1.7 or above
2. [Socket](https://forums.alliedmods.net/showthread.php?t=67640)
3. [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556)

# Installation
1. Drop the `chatrelay.smx` file into the `plugins` folder.
2. Load the plugin and change the CVAR to your desire in `../cfg/sourcemod/CheckValve.ChatRelay.cfg` config file.
3. Note that if you run multiple servers at the same time, you must change the port on either of the server.
4. Reload the plugin and it should just work right away.

# Known issues
1. Content Length of sent chat data is fixed to 230. It's a temprorary workaround.
