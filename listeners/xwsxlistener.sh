#!/bin/bash

# xwsxlistener.sh for xwsmgr
# This script listens for window events and writes them to the xwsmgr fifo
# This script is called by xwsmgr.sh

last_window_list=""
last_focused_window=""

xprop -spy -root _NET_CLIENT_LIST _NET_ACTIVE_WINDOW _NET_MOVERESIZE_WINDOW | while read -r line; do
    case "${line}" in
    # window list changed
    *_NET_CLIENT_LIST*) #TODO this is working
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
                    echo "window_removed: $i" >/tmp/xwsmgr_fifo
                else
                    echo "window_added: $i" >/tmp/xwsmgr_fifo
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
            echo "focus_change: $wid" >/tmp/xwsmgr_fifo
        fi
        ;;
    *)
        # echo "other message" >/tmp/xwsmgr_fifo
        ;;
    esac
done
echo "xprop_listener_exit" >/tmp/xwsmgr_fifo
