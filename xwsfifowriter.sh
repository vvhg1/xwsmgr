#!/bin/bash

# xwsfifowriter.sh for xwsmgr
# this script is used by the keyboard shortcuts to communicate with xwsmgr
# commands are written to the xwsmgr fifo
# commads:
# move_to_workspace_up
# move_to_workspace_down
# move_window_to_workspace_up
# move_window_to_workspace_down
# switch_to_monitor_workspace:[monitor_number][workspace_number]
# example: path/to/xwsfifowriter.sh move_to_workspace_up

case "$1" in
"move_to_workspace_up")
    echo "move_up" >/tmp/xwsmgr_fifo
    ;;
"move_to_workspace_down")
    echo "move_down" >/tmp/xwsmgr_fifo
    ;;
"move_window_to_workspace_up")
    echo "move_window_up" >/tmp/xwsmgr_fifo
    ;;
"move_window_to_workspace_down")
    echo "move_window_down" >/tmp/xwsmgr_fifo
    ;;
switch_to_monitor_workspace*)
    echo $@ >/tmp/xwsmgr_fifo
    ;;
    # that's all folks
*) ;;
esac
