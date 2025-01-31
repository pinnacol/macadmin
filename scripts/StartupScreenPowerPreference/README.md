# Startup Screen Open/Power Plug Preference script

### StartupScreenPowerPreference.sh

This script reads and writes the `BootPreference` nvram variable in macOS 15 as documented [here](https://support.apple.com/en-us/120622). It uses swiftDialog for the user interface.

It should be scoped to Apple laptops running macOS 15 or later and must run as root to save the change.

Rewrite the `option0-option3` variables to suit your explanation of the settings.