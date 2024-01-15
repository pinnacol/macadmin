#!/bin/zsh
# DefineKeyboards.sh
# Predefines keyboards so that Keyboard Setup Assistant does not launch
# 
# Fraser Hess
# © Pinnacol Assurance 2023
#
# Arguments:
#   NONE

# Uncomment line below for debugging
#set -x

declare -A keyboards

keyboards[1031-4176-0]=40 # YubiKey
keyboards[1957-1118-0]=40 # Microsoft Sculpt Ergonomic
keyboards[219-1118-0]=40  # Microsoft Natural Ergonomic Keyboard 4000

for id type in "${(@kv)keyboards}"; do
  /usr/bin/defaults write /Library/Preferences/com.apple.keyboardtype.plist keyboardtype -dict-add "$id" -integer $type
done
