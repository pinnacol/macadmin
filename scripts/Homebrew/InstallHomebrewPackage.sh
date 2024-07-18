#!/bin/bash
# InstallHomebrewPackage.sh
# Checks for missing Command Line Developer Tools, downloads and installs Homebrew package,
# and updates logged-in user's shells. Intented to run in Jamf Self Service
#
# Fraser Hess
# © Pinnacol Assurance 2024
#
# Arguments:
# $4 - a custom event trigger for a policy that installs Command Line Developer Tools

# Uncomment line below for debugging
#set -x

# Homebrew package signing changed in v4.3.9 from Mike McQuaid to Patrick Linnane
# https://infosec.exchange/@shuu/112803268733080002
#expected_team_ID="6248TWFRH6"
expected_team_ID="927JGANW46"
xcode_tools_event="${4}"

err() {
  echo "ERROR: $*" >&2
}


# Check for Command Line Developer Tools by performing the same check as the Homebrew package
if [[ ! -f "/Library/Developer/CommandLineTools/usr/bin/git" ]]; then
  if [[ -z "${xcode_tools_event}" ]]; then
    err "Command Line Developer Tools are missing and no policy trigger was provided"
    exit 1
  fi
  echo "Command Line Developer Tools are missing. Attempting to install..."
  /usr/local/jamf/bin/jamf policy -event "${xcode_tools_event}" -forceNoRecon
  if [[ ! -f "/Library/Developer/CommandLineTools/usr/bin/git" ]]; then
    # Still no CLI git
    err "Command Line Developer Tools failed to install"
    exit 1
  fi
fi

# Search for a package download in the last 10 Homebrew releases
# Not at releases have a pkg asset and packages are added some time after release
download_URL=$(/usr/bin/curl -fs "https://api.github.com/repos/Homebrew/brew/releases?per_page=10" | awk -F '"' '/browser_download_url/ && /pkg/ { print $4; exit }')

if [[ -z "${download_URL}" ]]; then
  err "Failed to find a Homebrew package download URL"
  exit 1
fi

# Download package to a temporary directory
pkg_download_dest=$(mktemp -d)
pkg_filename=$(basename "${download_URL}")
pkg_filepath="${pkg_download_dest}/${pkg_filename}"
echo "Downloading ${pkg_filename} to ${pkg_download_dest}..."
/usr/bin/curl -fsLvo "${pkg_filepath}" "${download_URL}"

# Verify the package code signature with spctl/Gatekeeper
echo "Verifying package..."
spctl_out=$(/usr/sbin/spctl -a -vv -t install "${pkg_filepath}" 2>&1 )
spctl_status=$(echo $?)
teamID=$(echo "${spctl_out}" | awk -F '(' '/origin=/ {print $2 }' | tr -d '()' )
if [[ ${spctl_status} -ne 0 ]]; then
  err "Unable to verify package"
  exit 1
fi

if [[ "${teamID}" != "${expected_team_ID}" ]]; then
  err "Developer Team ID ${teamID} does not match expected ID ${expected_team_ID}"
  exit 1
fi
echo "Package verified."

# Install package
echo "Starting install..."
/usr/sbin/installer -verbose -pkg "${pkg_filepath}" -target /

# Verify package installation
echo "Verifying installation..."
if /usr/sbin/pkgutil --pkg-info sh.brew.homebrew; then
  echo "Package receipt found"
else
  err "Installation failed. No package receipt found"
  exit 1
fi

if [[ "$(arch)" == "i386" ]]; then
  homebrew_dir="/usr/local/Homebrew"
else
  homebrew_dir="/opt/homebrew"
fi
if [[ ! -f "${homebrew_dir}/bin/brew" ]]; then
  err "Installation failed. brew executable not found"
  exit 1
fi
echo "brew executable found"

# Update bash and zsh
echo "Updating shells..."
current_user=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')
printf '\n# Homebrew added by Self Service %s\neval $(%s/bin/brew shellenv)\n'  "$(date)" "${homebrew_dir}" | tee -a "/Users/${current_user}/.zshrc" "/Users/${current_user}/.bash_profile"
/usr/sbin/chown "${current_user}" "/Users/${current_user}/.zshrc" "/Users/${current_user}/.bash_profile"

echo "Homebrew installation complete"

exit 0
