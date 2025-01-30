#!/bin/bash
launch_agent_name="com.pinnacol.disableDialpadAutoupdate"
launch_agent_path="/Library/LaunchAgents/${launch_agent_name}.plist"
cat > "${launch_agent_path}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/launchctl</string>
		<string>setenv</string>
		<string>DIALPAD_DISABLE_UPDATES</string>
		<string>1</string>
	</array>
	<key>Label</key>
	<string>$launch_agent_name</string>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF

currentUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')
uid=$(id -u "${currentUser}")

/bin/launchctl bootstrap gui/${uid} "${launch_agent_path}"

exit 0
