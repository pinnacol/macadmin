#!/bin/bash
# Inventory On Zoom Rooms Automatic Update
# Creates a Launch Daemon that runs an inventory when Zoom Rooms is autoupdated
# It should when the Zoom Rooms executable changes
# It exits if the autoupdate flag file at /Library/Logs/us.zoom.ZoomRoomUpdateRecord doesn't exist
# It waits for the Zoom Rooms process (ZoomPresence) to launch before kicking off inventory_command
# Change inventory_command to support another management system
# 
# Fraser Hess
# © Pinnacol Assurance 2024
#
# Arguments:
#   NONE
# Configuration
# Label of the launch daemon
launch_daemon_name="com.pinnacol.inventoryOnZRUpdate"
# Inventory command that runs after an automatic update
inventory_command="/usr/local/jamf/bin/jamf recon -randomDelaySeconds 300"

# Uncomment line below for debugging
#set -x

# Set launch daemon path
launch_daemon_path="/Library/LaunchDaemons/${launch_daemon_name}.plist"

# Create launch daemon
cat > "${launch_daemon_path}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$launch_daemon_name</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>-c</string>
		<string>[ -f /Library/Logs/us.zoom.ZoomRoomUpdateRecord ] || exit; until pgrep -qx ZoomPresence; do sleep 2; done; $inventory_command</string>
	</array>
	<key>WatchPaths</key>
	<array>
		<string>/Applications/ZoomPresence.app/Contents/MacOS/ZoomPresence</string>
	</array>
</dict>
</plist>
EOF

# Set permissions
/usr/sbin/chown root:wheel "${launch_daemon_path}"
/bin/chmod 644 "${launch_daemon_path}"

# Bootstrap the launch daemon
/bin/launchctl bootstrap system "${launch_daemon_path}"

