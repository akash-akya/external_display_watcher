# External Display Watcher

> *Look amma, no polling!*

Simple Mac OS command line utility to watch for external display events. Utility takes an executable as argument and for every display event, specified executable will be executed with all currently connected external displays as argument. This can be used to re-actively control settings based on external display connectivity, such as changing font size or changing theme.

### Example

Changing Emacs settings

```
$ cat change_emacs_profile.sh
#!/bin/bash

if [ $# -eq 0 ]; then
    emacsclient --eval "(my/profile-default)" > /dev/null
elif [ "$1" = "LG HDR 4K" ]; then
    emacsclient --eval "(my/profile-high-res)" > /dev/null
fi


# watch for dispaly events
$ ./bin/external_display_watcher -w change_emacs_profile.sh
```

### License

```
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```
