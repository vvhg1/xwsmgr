## xwsmgr - a Per-Monitor Workspace Manager

xwsmgr is a bash script that allows to manage workspaces on different monitors. The workspaces are handled independently per monitor. It is designed to be used with the mate-marco window manager. This script has not been tested with other window managers.
Requires the following dependencies: wmctrl, xdotool, xprop, xrandr, and bc.

To use xwsmgr, you will need to set up keybindings to switch workspaces and move windows between workspaces. Here are the commands you can use:

- move_to_workspace_up
- move_to_workspace_down
- move_window_to_workspace_up
- move_window_to_workspace_down
- switch_to_monitor_workspace:[monitordigit][workspacedigit]

For example, to switch to workspace 1 on monitor 1, you would use the command `path/to/xwsfifowriter.sh switch_to_monitor_workspace:11`. The communication for switching between workspaces on different monitors is handled by a separate script called xwsfifowriter.sh. You should use this script to send the appropriate command to the workspace manager.

Please note that xwsmgr is a pretty **hacky** and **rudimentary** solution, and there may (read: will) be bugs or unexpected behavior. Always grateful for feedback/bug reports/issues/pull requests... **Use at your own risk, hack on it, and have fun!**
