#!/bin/bash
########################################################################################################
#                                                                                                      #
#   This script is free software, published under the terms of the GNU Public License Version3.        #
#   It can be modified and redistributed under the same ore aquivalent terms.                          #
#                                                                                                      #
#   Bash-Script to send broadcasts to all users to the desktop-notification-daemon (via notify-send).  #
#   root permissions are required to call notify-send from another users account (sudo -u $user).      #
#                                                                                                      #
#   Written in bash using getopts for options processing.                                              #
#   Type "notify-send-wall -h" to get usage Information.                                               #
#                                                                                                      #
########################################################################################################

sessionarray="gnome-session"       # i.e. "gnome-session openbox startkde"

[ "x$DISPLAY" = "x" ] && export DISPLAY=:0.0 

# Defaults
title="ACHTUNG!"
timeout="0"              # message-timeout in milliseconds (only with notification-daemon or modified notify-osd)
icon="/usr/share/icons/gnome/scalable/devices/drive-harddisk.svg"

# Process options with getopts
while getopts ":t:m:i:T:vh" opt; do
  case $opt in
    t) title=$OPTARG;;      # setting title, else fall back to "no title"
    m) message=$OPTARG;;    # message text (optional)
    T) timeout=$OPTARG;;    # display-time in milliseconds (optional)
    i) icon=$OPTARG;;       # notification icon (optional), could be i.e. "battery", "sonata", "network" or an icon path.
    v) echo -e "notify-send-wall: Written in bash, using getopts. Made by Henning Hollermann 2011/10, GPL v3 License."; exit 0;;
    h) echo -e "Usage: $0 -t <title> [options]\nOptions:\n  -t <title>\tSet Title\n  -m <msg>\tSet Message to Display\n  -T <time>\tSet Display-Time in milliseconds (default: 2000ms)\n  -i\t\tNotification icon. Could be something like battery-charging, sonata, network or an icon file path. \n  -h\t\tDisplay this help message\n  -v\t\tDisplay version information"; exit 0;;
    \?) echo -e "Invalid option: -$OPTARG\n$help" >&2; exit 1;;
    :) echo "Option -$OPTARG requires an argument." >&2; exit 1;;
  esac
done

# Send notification to all sessions
for session in $sessionarray; do
    pids=$(pgrep $session)
    for pid in $pids; do
        # Determine session owner
        user=$(stat -c '%U' /proc/$pid)
        # send notification to session (must be executed by $user: root-permissions sequired)
        sudo -u $user DBUS_SESSION_BUS_ADDRESS=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$pid/environ | sed -e 's/DBUS_SESSION_BUS_ADDRESS=//') /usr/bin/notify-send -i "$icon" -u normal -t "$timeout" "$title" "$message"
    done;
done

# Logging
#logger "sudo -u $user DBUS_SESSION_BUS_ADDRESS=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$pid/environ | sed -e 's/DBUS_SESSION_BUS_ADDRESS=//') /usr/bin/notify-send -i "$icon" -u normal -t "$timeout" "$title" "$message""

exit 0;
