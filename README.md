Halo CE SAPP scripts
====================

Scripts for customizing a Halo CE dedicated server running SAPP.


Setup
-----
In `%USERPROFILE%\Documents\My Games\Halo CE\sapp\init.txt` add the following
lines:
```
lua 1
lua_load script_manager
```
This will tell SAPP to enable lua and load the script manager.

For other scripts there are 2 ways to load them:
1. Add more `lua_load` lines in `init.txt`:
   Use this when a script needs to be loaded once when starting the server and
   only unloaded when the server exits.
2. Configure the script manager to load the script:
   Use this for scripts that should be loaded per-game depending on the map,
   game mode, etc.


Addresses and offsets
---------------------
 - https://pastebin.com/Sm2Pf7V5
 - https://pastebin.com/QUWTMuKg (original: https://pastebin.com/z4eqrjVN )


Links
-----
 - SAPP: http://halo.isimaginary.com/
 - SAPP docs: http://halo.isimaginary.com/SAPP%20Documentation%20Revision%202.5.pdf
 - SAPP dev forum: https://opencarnage.net/index.php?/forum/76-server-app-sapp/


License
=======

Except where otherwise noted, all content is licensed under the [GNU GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html)
