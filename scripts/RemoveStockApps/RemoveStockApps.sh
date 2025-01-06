#!/bin/bash
# RemoveStockApps.sh
# Removes apps that Apple includes from the factory
# 
# Fraser Hess
# © Pinnacol Assurance 2025
#
# Arguments:
# $1 (or $4 if using Jamf Pro) - The app being removed - Keynote Numbers Pages iMovie GarageBand
# Special values:
# Leave empty for all factory apps
# "iWork" removes Keynote, Numbers, and Pages
# "iLife" removes iMovie and GarageBand

# Uncomment line below for debugging
#set -x

# Shift parameters for Jamf Pro
if [[ $1 == "/" ]]; then
  shift 3
fi

apps="${1}"

if [[ -z "${apps}" ]]; then
  apps="Keynote Numbers Pages iMovie GarageBand"
elif [[ "${apps}" == "iWork" ]]; then
  apps="Keynote Numbers Pages"
elif [[ "${apps}" == "iLife" ]]; then
  apps="iMovie GarageBand"
fi


for app in ${apps}; do
  rm -rf /Applications/"${app}".app
  receipts=$(pkgutil --pkgs | grep -i "${app}" | grep -v MAContent)
  for receipt in ${receipts}; do
    pkgutil --forget "${receipt}"
  done
  if [[ "${app}" == "GarageBand" ]]; then
    # Special section for GarageBand content
    # Remove sounds and loop content
    rm -rf "/Library/Audio/Apple Loops/Apple"
    rm -rf "/Library/Application Support/Logic"
    rm -rf "/Library/Application Support/GarageBand"
    rm -rf "/Library/Audio/Impulse Responses"
    # Remove MAContent receipts. Will error on a factory Mac,
    # so the output is redirected to /dev/null
    ma_receipts=$(pkgutil --pkgs | grep MAContent)
    for receipt in ${ma_receipts}; do
      pkgutil --forget "${receipt}" &> /dev/null
    done
  fi
done
