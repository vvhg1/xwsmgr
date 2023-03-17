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
fifo="/tmp/xwsmgr_fifo"
case "$1" in
"switch_to_next_window")
    flock $fifo echo "switch_to_next_window" >$fifo
    ;;
"move_to_workspace_up")
    flock $fifo echo "move_up" >$fifo
    ;;
"move_to_workspace_down")
    flock $fifo echo "move_down" >$fifo
    ;;
"move_window_to_workspace_up")
    flock $fifo echo "move_window_up" >$fifo
    ;;
"move_window_to_workspace_down")
    flock $fifo echo "move_window_down" >$fifo
    ;;
switch_to_monitor_workspace*)
    flock $fifo echo $@ >$fifo
    ;;
switch_to_index_monitor*)
    flock $fifo echo $@ >$fifo
    ;;
    # that's all folks
*) ;;
esac
