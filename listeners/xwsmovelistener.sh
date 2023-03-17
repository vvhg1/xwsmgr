#!/bin/bash

# xwsmovelistener.sh for xwsmgr
# This script listens for window movement events and writes them to the xwsmgr fifo
# This script is called by xwsmgr.sh
fifo="/tmp/xwsmgr_fifo"
previous_windows_list=$(wmctrl -lG | grep -v " -1 " | awk '{print $1, $2, $3, $4, $5, $6}')

while true; do
    new_windows_list=$(wmctrl -lG | grep -v " -1 " | awk '{print $1, $2, $3, $4, $5, $6}')
    if [ "$new_windows_list" != "$previous_windows_list" ]; then
        # Calculate the difference between the previous and new window list
        new_windows=$(comm -23 <(echo "$new_windows_list" | sort) <(echo "$previous_windows_list" | sort))
        while read -r line; do
            flock $fifo echo "window_moved: $line" >$fifo
        done <<<"$new_windows"
        # Update the previous window list
        previous_windows_list=$new_windows_list
    fi
    sleep 0.1
done
flock $fifo echo "move_listener_exit" >$fifo
