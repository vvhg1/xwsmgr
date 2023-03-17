#!/bin/bash

# xwsxlistener.sh for xwsmgr
# This script listens for window events and writes them to the xwsmgr fifo
# This script is called by xwsmgr.sh

fifo="/tmp/xwsmgr_fifo"
last_window_list=""
last_focused_window=""

xprop -spy -root _NET_CLIENT_LIST _NET_ACTIVE_WINDOW _NET_MOVERESIZE_WINDOW | while read -r line; do
    case "${line}" in
    # window list changed
    *_NET_CLIENT_LIST*)
        wids=$(echo $line | cut -d' ' -f 5- | sed 's/,/ /g')
        if [ "$wids" = "$last_window_list" ]; then
            continue
        else
            old_arr=($last_window_list)
            new_arr=($wids)
            last_window_list=$wids
            difference=($(echo ${new_arr[@]} ${old_arr[@]} | tr ' ' '\n' | sort | uniq -u))
            for i in "${difference[@]}"; do
                if [[ " ${old_arr[@]} " =~ " ${i} " ]]; then
                    flock $fifo echo "window_removed: $i" >$fifo
                else
                    flock $fifo echo "window_added: $i" >$fifo
                fi
            done
        fi
        ;;
    *_NET_ACTIVE_WINDOW*)
        # Handle focus change
        wid=$(echo $line | cut -d' ' -f 5)
        if [ "$wid" = "$last_focused_window" ]; then
            continue
        else
            last_focused_window=$wid
            flock $fifo echo "focus_change: $wid" >$fifo
        fi
        ;;
    *)
        # echo "other message" >/tmp/xwsmgr_fifo
        ;;
    esac
done
flock $fifo echo "xprop_listener_exit" >$fifo
