#!/bin/bash

# This script manages workspaces per monitor. It is intended to be used with mate-marco.

# based on the content of this script, write a help entry below
# xwsmgr.sh - manage workspaces per monitor
# This script manages workspaces per monitor. It is intended to be used with mate-marco.
# It requires wmctrl, xdotool, xprop, xrandr, and bc.
# It also (probably) requires that the window manager is set to mate-marco, at least I haven't tested it with anything else.
# It is intended to be used with a keybinding to switch workspaces, and a keybinding to move windows between workspaces.
# The keybinding to switch workspaces should be set to the following commands:
# "move_to_workspace_up"
# "move_to_workspace_down"
# "move_window_to_workspace_up"
# "move_window_to_workspace_down"
# "switch_to_monitor_workspace:[monitordigit][workspacedigit]"
# e.g. "switch_to_monitor_workspace:11" will switch to the workspace on monitor 1, workspace 1

# on any kind of exit, gracefully or not, do cleanup
trap cleanup EXIT

cleanup() {
    #cleanup the environment variables
    echo "Cleaning up"
    unset monitors
    unset workspaces
    unset active_workspaces
    unset windows
    unset monitor_centers
    unset windows_to_ignore
    rm -f /tmp/xwsmgr.pid
    rm -f $fifo_path
    # clean up the xprop listener, not sure if this is necessary
    # # in this case the listeners are killed when the script exits
    kill $xprop_listener_pid
    kill $move_listener_pid
}

_initialize() {
    for monitor in "${monitors[@]}"; do
        active_workspaces["$monitor"]=1
        # Set up the workspaces for each monitor
        workspaces["$monitor"]="${monitor}_1"
        # get the center of the monitor
        monitor_geometry=$(xrandr | grep $monitor | awk '{print $3}')
        #if monitor_geometry is "primary", then get the next line
        if [ "$monitor_geometry" == "primary" ]; then
            monitor_geometry=$(xrandr | grep $monitor | awk '{print $4}')
        fi
        mon_X=$(echo "$monitor_geometry" | cut -d+ -f2) #X=100
        mon_Y=$(echo "$monitor_geometry" | cut -d+ -f3) #Y=0
        #set the
        mon_WIDTH=$(echo "$monitor_geometry" | cut -d+ -f1 | cut -d x -f1)  #WIDTH=1920
        mon_HEIGHT=$(echo "$monitor_geometry" | cut -d+ -f1 | cut -d x -f2) #HEIGHT=1080
        #get the smallest dimension of the monitor
        local monitor_min=$(echo "$mon_WIDTH < $mon_HEIGHT" | bc)
        monitor_min=$(echo "($monitor_min / 2)^2" | bc)
        # if must_be_on_monitor_distance is 0 or bigger than this monitor's min distance, then set it to this monitor's min distance
        if [ "$must_be_on_monitor_distance" -eq 0 ] || [ "$must_be_on_monitor_distance" -gt "$monitor_min" ]; then
            must_be_on_monitor_distance=$monitor_min
        fi

        mon_CENTER_X=$((mon_X + mon_WIDTH / 2))
        mon_CENTER_Y=$((mon_Y + mon_HEIGHT / 2))
        monitor_centers["$monitor"]=" ${monitor}:${mon_CENTER_X}:${mon_CENTER_Y}"
        echo "monitor_centers for ${monitor}: ${monitor_centers["$monitor"]}"
    done
    # Initialize the windows array with the windows on each workspace
    local window_list=$(wmctrl -lx)
    # filter out gravity -1 windows
    windows_to_ignore=($(echo "$window_list" | grep " -1 " | cut -d' ' -f1))
    window_list=$(echo "$window_list" | grep -v " -1 ")
    #convert the window_ids to xdotool format
    for window_id in "${windows_to_ignore[@]}"; do
        windows_to_ignore[$window_id]=$(wmctrl_to_xdotool "$window_id")
    done

    local window_ids=($(echo "$window_list" | cut -d' ' -f1))
    start_time=$(date +%s.%N)
    for window_id in "${window_ids[@]}"; do
        window_id=$(wmctrl_to_xdotool "$window_id")
        local monitor_and_workspace=$(get_monitor_for_window "$window_id")
        local monitor=$(echo "$monitor_and_workspace" | cut -d: -f1)
        local workspace=$(echo "$monitor_and_workspace" | cut -d: -f2)
        windows["${monitor}_${workspace}"]+=" $window_id"
    done
    end_time=$(date +%s.%N)
    echo "Total time: $(echo "$end_time - $start_time" | bc) seconds"

    fifo_path="/tmp/xwsmgr_fifo"
    if [ -e "$fifo_path" ]; then
        echo "FIFO already exists, removing it"
        rm "$fifo_path"
    fi
    mkfifo "$fifo_path"
}

check_initialized() {
    echo "checking variables"
    if [ "${#monitors[@]}" -eq 0 ]; then
        echo "Error: monitors not set"
        exit 1
    fi
    if [ "${#workspaces[@]}" -eq 0 ]; then
        echo "Error: workspaces not set"
        exit 1
    fi
    if [ "${#active_workspaces[@]}" -eq 0 ]; then
        echo "Error: active_workspace not set"
        exit 1
    fi
    if [ "${#windows[@]}" -eq 0 ]; then
        echo "Error: windows not set"
        exit 1
    fi
    if [ -z "$active_monitor" ]; then
        echo "Error: active_monitor not set"
        exit 1
    fi
    if [ -z "$fifo_path" ]; then
        echo "Error: fifo_path not set"
        exit 1
    fi
}

########################################################## helpers

wmctrl_to_xdotool() {
    local wmctrl_id=$1
    printf "%d\n" "$((wmctrl_id))"
}

xdotool_to_wmctrl() {
    local xdotool_id=$1
    local hex_window_id=$(printf "%08x\n" "$xdotool_id")
    echo "$hex_window_id"
}

is_window_to_ignore() {
    local window_id=$1
    for window in "${windows_to_ignore[@]}"; do
        if [ "$window" = "$window_id" ]; then
            return 0
        fi
    done
    return 1
}

is_window_gravity_minus_one() {
    local window_id=$1
    window_id=$(xdotool_to_wmctrl "$window_id")
    local window_details=$(wmctrl -lG | grep "$window_id" | grep " -1 ")
    if [[ -z "$window_details" ]]; then
        return 0
    fi
    return 1
}

is_empty_window() {
    local hex_window_id=$(xdotool_to_wmctrl "$1")
    local window_details=$(wmctrl -lG | grep "$hex_window_id")
    if [[ -z "$window_details" ]]; then
        return 0
    fi
    return 1
}

is_window_in_windows_array() {
    local current_window_id=$1
    for i in "${!windows[@]}"; do
        if [[ " ${windows[$i]} " =~ " $current_window_id" ]]; then
            return 0
        fi
    done
    return 1
}

get_active_workspace() {
    monitor=$1
    echo ${active_workspaces[$monitor]}
}

get_active_monitor() {
    echo $active_monitor
}

get_workspace_for_window() {
    local window_id=$1
    for i in "${!windows[@]}"; do
        if [[ " ${windows[$i]} " =~ " $window_id" ]]; then
            # if the window is found, return the workspace
            echo $i
            return
        fi
    done
}

########################################################################## main funcs

move_window_to_ws_by_direction() {
    # * Move a window to the next or previous workspace on the current monitor
    echo "move_window_to_ws_by_direction"
    # creating a new workspace if necessary
    # if the current workspace is the last workspace, then move the window to the first workspace
    local direction=$1
    local current_window_id=$(xdotool getwindowfocus)
    local current_monitor=$(get_monitor_for_window "$current_window_id" | cut -d: -f1)
    local current_workspace="${active_workspaces["$current_monitor"]}"

    # Calculate the index of the new workspace
    local new_workspace_index
    if [ "$direction" = "up" ]; then
        # up to max_workspaces increment by 1, if more than max_workspaces, go back to 1
        if [ $current_workspace -lt $max_workspaces ]; then
            new_workspace_index=$((current_workspace + 1))
        else
            new_workspace_index=1
        fi
    else
        if [ $current_workspace -gt 1 ]; then
            new_workspace_index=$((current_workspace - 1))
        else
            new_workspace_index=$(echo ${workspaces["$current_monitor"]} | wc -w)
            # if there is only one workspace, then set new_workspace_index to 2 and add a new workspace
            if [ $new_workspace_index -eq 1 ]; then
                new_workspace_index=2
            fi
        fi
    fi
    # check if the new_workspace_index is already in the workspaces array
    if [[ ! " ${workspaces["$current_monitor"]} " =~ "${current_monitor}_${new_workspace_index}" ]]; then
        # only add the new workspace if there is more than one window on the current workspace
        if [ $(echo "${windows["$current_monitor"_"$current_workspace"]}" | wc -w) -gt 1 ]; then
            workspaces["$current_monitor"]+=" ${current_monitor}_${new_workspace_index}"
        else
            # loop back to the first workspace
            new_workspace_index=1
        fi
    fi
    if [ $current_workspace -eq $new_workspace_index ]; then
        return
    fi
    # Remove the current window from the windows array of the current workspace
    windows["$current_monitor"_"$current_workspace"]=$(echo "${windows["$current_monitor"_"$current_workspace"]}" | sed "s/ $current_window_id//")
    # Add the current window to the windows array of the new workspace
    windows["$current_monitor"_"$new_workspace_index"]+=" $current_window_id"

    remove_empty_workspace
    switch_to_monitor_workspace "$current_monitor" "$new_workspace_index"
}

move_window_to_monitor_workspace() {
    # * Move a window to the workspace and monitor specified by the index
    # creating a new workspace if necessary
    echo "move_window_to_monitor_workspace"
    local window_id=$1
    local target_monitor=$2
    local target_workspace=$3
    #if the workspace index is greater than the max number of workspaces or less than 1, same if monitor index is greater than the number of monitors or less than 1
    if [ $target_workspace -gt $max_workspaces ] || [ $target_workspace -lt 1 ]; then
        echo "Error: workspace index must be between 1 and $max_workspaces"
        return
    fi
    local current_window_id=$(xdotool getwindowfocus)
    local previous_monitor=$(get_active_monitor)
    local previous_workspace="${active_workspaces["$previous_monitor"]}"

    # check if the target_workspace is already in the workspaces array
    if [[ ! " ${workspaces["$target_monitor"]} " =~ "${target_workspace}" ]]; then
        # add the new workspace to the workspaces array
        workspaces["$target_monitor"]+=" ${target_monitor}_${target_workspace}"
    fi
    # Remove the current window from the windows array of the previous workspace
    windows["$previous_monitor"_"$previous_workspace"]=$(echo "${windows["$previous_monitor"_"$previous_workspace"]}" | sed "s/ $current_window_id//")
    # Add the current window to the windows array of the new workspace
    windows["$target_monitor"_"$target_workspace"]+=" $current_window_id"

    switch_to_monitor_workspace "$target_monitor" "$target_workspace"
    remove_empty_workspace
}

on_window_moved() {
    # * Update the windows array and the active workspace when a window is moved
    echo "on_window_moved"
    # first argument is the window id, rest is the window position and size
    local current_window_id=$1
    local current_monitor_and_workspace=$(get_monitor_for_window $current_window_id $2 $3 $4 $5)
    local current_monitor=$(echo "$current_monitor_and_workspace" | cut -d: -f1)
    local current_workspace=$(echo "$current_monitor_and_workspace" | cut -d: -f2)
    local previous_workspace=${active_workspaces["$active_monitor"]}
    # if the monitor has changed, then remove the window from the windows array of the old monitor and workspace
    if [ "$current_monitor" != "$active_monitor" ]; then
        #check if the window is in the old monitor windows array
        if [[ " ${windows["$active_monitor"_"$previous_workspace"]} " =~ " $current_window_id" ]]; then
            windows["$active_monitor"_"$previous_workspace"]=$(echo "${windows["$active_monitor"_"$previous_workspace"]}" | sed "s/ $current_window_id//")
        else
            echo "on_window_moved, window not in old monitor windows array, BUG?"
        fi
        # add the window to the windows array of the new monitor and workspace
        windows["$current_monitor"_"$current_workspace"]+=" $current_window_id"

        switch_to_monitor_workspace "$current_monitor" "$current_workspace"
        remove_empty_workspace
    fi
}

on_focus_changed() {
    # * on window focus change, update the active workspace, working
    # only proceed if allow_focus_change is true
    if [ "$allow_focus_change" = false ]; then
        return
    fi
    local current_window_id=$1
    #get window details from wmctrl
    # local window_details_from_wmctrl=$(wmctrl -lGx | grep "$(xdotool_to_wmctrl "$current_window_id")")
    # echo "on_focus_changed, window_details_from_wmctrl for window $current_window_id: $window_details_from_wmctrl"
    if is_window_to_ignore "$current_window_id"; then
        # echo "on focus changed, window to ignore"
        return
    fi
    if is_empty_window "$current_window_id"; then
        # echo "on focus changed, empty window"
        return
    fi
    if ! is_window_in_windows_array "$current_window_id"; then
        # get window details
        local window_details_from_wmctrl=$(wmctrl -lGx | grep "$(xdotool_to_wmctrl "$current_window_id")")
        echo "on_window_focus_change, window not in windows array, BUG? window details_from_wmctrl: $window_details_from_wmctrl"
        return
    fi
    # with xdotool, check if the window really has focus
    local focused_window=$(xdotool getwindowfocus)
    if [ "$focused_window" != "$current_window_id" ]; then
        echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXon_focus_changed, window does not have focus, BUG?"
        return
    fi
    local current_monitor_and_workspace=$(get_monitor_for_window "$current_window_id")
    local current_monitor=$(echo "$current_monitor_and_workspace" | cut -d: -f1)
    local current_workspace=$(echo "$current_monitor_and_workspace" | cut -d: -f2)

    if [[ ! " ${windows["$current_monitor"_"$current_workspace"]} " =~ " $current_window_id" ]]; then
        # get the workspace that the window is on, we already know the monitor
        for monitor_workspace in ${workspaces["$current_monitor"]}; do
            if [[ " ${windows["$monitor_workspace"]} " =~ " $current_window_id" ]]; then
                echo "window belongs to monitor_workspace: $monitor_workspace"
                current_workspace=$(echo "$monitor_workspace" | cut -d_ -f2)
                # in this case we have to be naughty and set the active monitor to the current monitor
                # as we are switching to a workspace on a different monitor
                active_monitor="$(echo "$monitor_workspace" | cut -d_ -f1)"
                break
            fi
        done
    fi
    local previous_monitor=$(get_active_monitor)
    local previous_workspace="${active_workspaces["$previous_monitor"]}"
    # reorder the windows array so that the current window is at the end
    windows["$current_monitor"_"$current_workspace"]=$(echo "${windows["$current_monitor"_"$current_workspace"]}" | sed "s/ $current_window_id//")
    windows["$current_monitor"_"$current_workspace"]+=" $current_window_id"
    # check if the current monitor is the same as the previous monitor
    if [ "$previous_monitor" == "$current_monitor" ] && [ "$previous_workspace" == "$current_workspace" ]; then
        # if the window is still on the same monitor and workspace, then just
        return
    fi
    switch_to_monitor_workspace $current_monitor $current_workspace
}

on_window_added() {
    # * on window added, update the windows array, working
    local current_window_id=$1
    echo "on_window_added, current_window_id: $current_window_id"
    if is_window_to_ignore "$current_window_id"; then
        echo "window adding but on ignore list,should only happen on startup!"
        return
    fi
    if is_empty_window "$current_window_id"; then
        echo "window adding but empty, not adding to windows array"
        return
    fi
    if is_window_in_windows_array "$current_window_id"; then
        #maybe we need to check if the window has moved to a different monitor
        echo "window already in windows array, not adding again"
        return
    fi
    # last check is to see if the window is -1 gravity, if so, then we don't want to add it to the windows array
    if is_window_gravity_minus_one "$current_window_id"; then
        echo "window gravity is -1, not adding to windows array"
        return
    fi
    local current_monitor_and_workspace=$(get_monitor_for_window "$current_window_id")
    local current_monitor=$(echo "$current_monitor_and_workspace" | cut -d: -f1)
    local current_workspace=$(echo "$current_monitor_and_workspace" | cut -d: -f2)
    # Add the current window to the windows array of the new workspace
    windows["$current_monitor"_"$current_workspace"]+=" $current_window_id"

    switch_to_monitor_workspace "$current_monitor" "$current_workspace"
}

on_window_removed() {
    # * on window removed, update the windows array, working
    local current_window_id=$1
    echo "on_window_removed, current_window_id: $current_window_id"
    if is_window_to_ignore "$current_window_id"; then
        return
    fi
    #check if the window really is empty
    if is_empty_window "$current_window_id"; then
        # echo "on_window_removed, found empty window: $current_window_id, removing from windows array nontheless"
        for monitor_and_workspace in "${!windows[@]}"; do
            if [[ " ${windows["$monitor_and_workspace"]} " =~ " $current_window_id" ]]; then
                # Remove the current window from the windows array of the current workspace
                windows["$monitor_and_workspace"]=$(echo "${windows["$monitor_and_workspace"]}" | sed "s/ $current_window_id//")
                break
            fi
        done
    fi
    remove_empty_workspace
}

switch_workspace_up_down() {
    # * this function is called when the user presses a key to switch to a workspace
    echo "switch_workspace_up_down"
    local current_monitor=$(get_active_monitor)
    local current_workspace=$(get_active_workspace $current_monitor)
    local workspace_count=$(echo "${workspaces[$current_monitor]}" | wc -w)
    # check if we have more than one workspace
    if [ $workspace_count -gt 1 ]; then
        #check direction
        if [ "$direction" == "up" ]; then
            # check if we are on the last workspace
            if [ "$current_workspace" == "$workspace_count" ]; then
                # switch to the first workspace
                switch_to_monitor_workspace $current_monitor 1
            else
                # switch to the next workspace
                switch_to_monitor_workspace $current_monitor $(($current_workspace + 1))
            fi
        else
            # check if we are on the first workspace
            if [ "$current_workspace" == "1" ]; then
                # switch to the last workspace
                switch_to_monitor_workspace $current_monitor $workspace_count
            else
                # switch to the previous workspace
                switch_to_monitor_workspace $current_monitor $(($current_workspace - 1))
            fi
        fi
    fi
}

remove_empty_workspace() {
    # * this function is called when a window is closed or moved to another workspace, seems to work now
    echo "remove_empty_workspace"
    for monitor_workspace in $(echo "${workspaces[@]}"); do
        # if empty or only contains whitespace of any length
        if [ -z "${windows["$monitor_workspace"]}" ] || [ -z "$(echo "${windows["$monitor_workspace"]}" | sed 's/ //g')" ]; then
            monitor=$(echo "$monitor_workspace" | cut -d_ -f1)
            workspace=$(echo "$monitor_workspace" | cut -d_ -f2)
            # don't remove the last workspace
            if [ "$(echo "${workspaces["$monitor"]}" | wc -w)" -eq 1 ]; then
                return
            fi
            # remove the workspace from the workspaces array
            local old_workspace_count=$(echo "${workspaces["$monitor"]}" | wc -w)
            workspaces["$monitor"]=$(echo "${workspaces["$monitor"]}" | sed "s/ $monitor_workspace//g")
            # split the workspaces string into an array
            IFS=' ' read -r -a workspaces_array <<<"${workspaces["$monitor"]}"
            # renumber the workspaces
            for i in "${!workspaces_array[@]}"; do
                workspaces_array[$i]=$(echo "${workspaces_array[$i]}" | sed "s/$monitor\_//g")
                workspaces_array[$i]="$monitor"_"$(($i + 1))"
                # if workspace is not larger than i+1, it is a removed or renamed workspace
                if [ "$workspace" -gt "$(($i + 1))" ]; then
                    # echo "not shifting windows, workspace $workspace is larger than new index i+1: $(($i + 1))"
                    continue
                fi
                # if the old workspace count is larger than i+1
                if [ "$old_workspace_count" -gt "$(($i + 1))" ]; then
                    # echo "shifting windows, old content: ${windows["$monitor"_"$(($i + 1))"]} to new content: ${windows["$monitor"_"$(($i + 2))"]}"
                    windows["$monitor"_"$(($i + 1))"]="${windows["$monitor"_"$(($i + 2))"]}"
                fi
                # if equal, then the workspace must be removed from the windows array
                if [ "$old_workspace_count" -eq "$(($i + 2))" ]; then
                    # echo "removing windows array entry for old workspace index i+1: $(($i + 2))"
                    unset windows["$monitor"_"$(($i + 2))"]
                    break
                fi
            done
            workspaces["$monitor"]=$(echo "${workspaces_array[@]}" | sed 's/ / /g')
            # if the removed workspace is the active workspace, then switch to a different workspace
            if [ "${active_workspaces["$monitor"]}" == "$workspace" ]; then
                if [ "$workspace" -gt 1 ]; then
                    # echo "workspace is larger than 1, setting previous to the one below workspace"
                    active_workspaces["$monitor"]=$workspace
                    switch_to_monitor_workspace $monitor $(($workspace - 1))
                else
                    # echo "workspace is 1, setting previous to the one above workspace"
                    active_workspaces["$monitor"]=$($workspace + 1)
                    switch_to_monitor_workspace $monitor 1
                fi
            fi
            # echo "from remove_empty_workspace, switching to monitor $monitor, workspace $(get_active_workspace $monitor)"
            switch_to_monitor_workspace $monitor $(get_active_workspace $monitor)
            break
        fi
    done
}

switch_to_monitor_workspace() {
    # * switch to workspace, takes the monitor and workspace as arguments
    monitor=$1
    workspace=$2
    echo "switch_to_monitor_workspace, previous: $active_monitor _${active_workspaces["$active_monitor"]} new monitor_workspace: $monitor _$workspace"
    local current_workspace=$(get_active_workspace $active_monitor)
    allow_focus_change=false
    if [ "$monitor" == "$active_monitor" ]; then
        if [ "$workspace" == "$current_workspace" ]; then
            allow_focus_change=true
            return
        else
            # deactivate the previous workspace windows on the monitor
            previous_workspace=$(get_active_workspace $monitor)
            previous_windows=$(echo "${windows["$monitor"_"$previous_workspace"]}")
            for window in $previous_windows; do
                xdotool windowminimize $window
            done
            #activate the new workspace windows on the monitor
            current_windows=$(echo "${windows["$monitor"_"$workspace"]}")
            for window in $current_windows; do
                #TODO find a way to activate the window without giving it focus
                xdotool windowactivate $window
            done
        fi
    else
        active_monitor=$monitor
        # activate the last window in the windows array
        local last_window=$(echo "${windows["$monitor"_"$workspace"]}" | awk '{print $NF}')
        xdotool windowactivate $last_window
    fi
    active_workspaces["$active_monitor"]=$workspace

    sleep 0.1
    allow_focus_change=true
}

get_monitor_for_window() {
    # * this is the core of the logic locating the window on the correct monitor
    window_id=$1
    center_x=0
    center_y=0
    # if the second argument is not passed
    if [ -z "$2" ]; then
        geometry=$(xdotool getwindowgeometry --shell $window_id)
        eval "$geometry"
        center_x=$(($X + $WIDTH / 2))
        center_y=$(($Y + $HEIGHT / 2))
    else
        center_x=$(($2 + $4 / 2))
        center_y=$(($3 + $5 / 2))
    fi
    # Loop through the monitor centers and find the closest center to center
    local previous_distance=999999999
    #if the distance is less than the squared half height of the monitor, then the window must be on the monitor
    # for that we have the must_be_on_monitor_distance variable
    for monitor_center in "${monitor_centers[@]}"; do
        monitor=$(echo "$monitor_center" | cut -d: -f1 | xargs)
        monitor_center_X=$(echo "$monitor_center" | cut -d: -f2)
        monitor_center_Y=$(echo "$monitor_center" | cut -d: -f3)
        distance=$(echo "($monitor_center_X - $center_x)^2 + ($monitor_center_Y - $center_y)^2" | bc) #what is bc?
        if [ "$distance" -lt "$must_be_on_monitor_distance" ]; then
            closest_monitor=$monitor
            # echo "found closest distance, optimization works"
            break
        fi
        if [ "$distance" -lt "$previous_distance" ]; then
            previous_distance=$distance
            closest_monitor=$monitor
        fi
    done
    current_workspace=$(get_active_workspace $closest_monitor)
    echo "$closest_monitor:$current_workspace"
}

switch_to_monitor_workspace_by_index() {
    # * this takes a two digit number, the first digit is the monitor index, the second digit is the workspace index
    local monitor_workspace_index=$1
    local monitor_index=$(echo "$monitor_workspace_index" | cut -c1)
    # echo "switch_to_monitor_workspace_by_index, monitor_workspace_index: $monitor_workspace_index"
    local monitor=$(echo "${monitors[@]}" | cut -d' ' -f$monitor_index)
    # if the monitor is not found, do nothing
    if [ -z "$monitor" ]; then
        echo "monitor not found, doing nothing"
        return
    fi
    local workspace_index=$(echo "$monitor_workspace_index" | cut -c2)
    monitor_workspace="$monitor"_"$workspace_index"
    # if the monitor_workspace is not found in the workspaces array, then exit
    if [[ ! " ${workspaces[@]} " =~ " ${monitor_workspace} " ]]; then
        echo "monitor_workspace not found, doing nothing"
        return
    fi
    switch_to_monitor_workspace $monitor $workspace_index
}

################################################################# core script

# check that we don't already have a running instance
if [ -f /tmp/xwsmgr.pid ]; then
    pid=$(cat /tmp/xwsmgr.pid)
    if [ -d /proc/$pid ]; then
        echo "xwsmgr.sh is already running, if not, remove /tmp/xwsmgr.pid"
        exit 1
    else
        echo $$ >/tmp/xwsmgr.pid
    fi
fi

declare -a monitors=($(xrandr | grep ' connected' | awk '{print $1}'))
declare -A workspaces
declare -A active_workspaces # the active workspace for each monitor, e.g. active_workspaces["HDMI-1"]=1
declare -A windows
declare -A monitor_centers
declare -a windows_to_ignore
max_workspaces=3
allow_focus_change=true
active_monitor="${monitors[0]}"
must_be_on_monitor_distance=0

_initialize
check_initialized
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# Start the listener in the background
$script_dir/listeners/xwsxlistener.sh &
xprop_listener_pid=$!
echo "xprop_listener_pid: $xprop_listener_pid"
$script_dir/listeners/xwsmovelistener.sh &
move_listener_pid=$!
echo "move_listener_pid: $move_listener_pid"
#changed from 0.5
sleep 0.2

# * call with eg: echo "move_up" > /tmp/xwsmgr_fifo

# loop listening for incoming messages
while true; do
    read message <"$fifo_path"
    wdw_id=$(echo "$message" | cut -d: -f2)
    case "$message" in
    switch_to_monitor_workspace*)
        switch_to_monitor_workspace_by_index "$wdw_id"
        ;;
    move_up)
        switch_workspace_up_down "up"
        ;;
    move_down)
        switch_workspace_up_down "down"
        ;;
    move_window_up)
        move_window_to_ws_by_direction "up"
        ;;
    move_window_down)
        move_window_to_ws_by_direction "down"
        ;;
    focus_change*)
        echo "focus change"
        on_focus_changed "$(wmctrl_to_xdotool "$wdw_id")"
        ;;
    window_removed*)
        on_window_removed "$(wmctrl_to_xdotool "$wdw_id")"
        ;;
    window_added*)
        on_window_added "$(wmctrl_to_xdotool "$wdw_id")"
        ;;
    window_moved*)
        id=$(echo "$wdw_id" | awk '{print $1}')
        if [ -z "$id" ]; then
            continue
        fi
        position=$(echo "$wdw_id" | awk '{print $3,$4,$5,$6}')
        on_window_moved "$(wmctrl_to_xdotool $id)" "$position"
        ;;
    *)
        echo "Unknown message: $message"
        ;;
    esac
done
echo "all done, exiting"
