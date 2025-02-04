#!/bin/bash
# StartupScreenPowerPreference.sh
# 
# Fraser Hess
# © Pinnacol Assurance 2025
#
# Arguments:
#   NONE

# Uncomment line below for debugging
#set -x

err() {
  echo "ERROR: $*" >&2
}

if [[ $(id -u) -ne 0 ]]; then
  err "Run this script as root or using sudo"
  exit 1
fi

# Must run on macOS Sequoia 15
major_os=$(/usr/bin/sw_vers --productVersion | /usr/bin/cut -d . -f 1)
if [[ ${major_os} -lt 15 ]]; then
  err "This script requires macOS 15 or later"
  exit 1
fi

if [[ $(arch) != "arm64" ]]; then
  err "This script requires Apple silicon"
  exit 1
fi

battery_present=$(/usr/sbin/ioreg -c AppleSmartBattery -r | awk '/BatteryInstalled/ {print $NF}')
if [[ "${battery_present}" != "Yes" ]]; then
  err "This script should only be run on an Apple laptop"
  exit 1
fi

if [[ ! -f /usr/local/bin/dialog ]]; then
  err "This script requires swiftDialog"
  exit 1
fi

boot_preference=$(/usr/sbin/nvram BootPreference 2> /dev/null | awk '{print $NF}')

option0="Do not start up when the screen is opened or power is connected"
option1="Start up only when power is connected"
option2="Start up only when the screen is opened"
option3="Start up when either the screen is opened or power is connected"

case ${boot_preference} in
  "%00" | "%01" | "%02" )
    varname="option${boot_preference: -1}"
    selected_option="${!varname}"
    ;;
  *)
    selected_option="${option3}"
    ;;
esac

if json_output=$(/usr/local/bin/dialog --height 200 --title "Power and screen startup preference" --message "Choose your preference for starting up your Mac" --icon SF=power.circle.fill --overlayicon SF=macbook,bgcolor=none --button2text "Cancel" --selecttitle "Startup preference" --selectvalues "${option0},${option1},${option2},${option3}" --selectdefault "${selected_option}" --moveable --json); then
  selected_index=$(/usr/bin/jq '."Startup preference".selectedIndex' <<< "${json_output}")
  case ${selected_index} in
    0 | 1 | 2 )
      /usr/sbin/nvram BootPreference=%0"${selected_index}"
      ;;
    *)
      /usr/sbin/nvram -d BootPreference
      ;;
    esac
fi