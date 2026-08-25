#!/bin/bash

# Allow alternate base URL as first command-line argument, for testing and development
if [ -z "$1" ]; then
    BASEURL="https://raw.githubusercontent.com/4xura/just-the-browser/main"
else
    BASEURL="$1"
fi

OS=$(uname)
MICROSOFT_EDGE_MAC_CONFIG="$BASEURL/edge/edge.mobileconfig"
GOOGLE_CHROME_MAC_CONFIG="$BASEURL/chrome/chrome.mobileconfig"
FIREFOX_MAC_CONFIG="$BASEURL/firefox/firefox.mobileconfig"
FIREFOX_SETTINGS="$BASEURL/firefox/policies.json"
CHROME_SETTINGS="$BASEURL/chrome/managed_policies.json"
BRAVE_SETTINGS="$BASEURL/brave/managed_policies.json"
BRAVE_MAC_CONFIG="$BASEURL/brave/brave.mobileconfig"

# Generate a temporary directory on macOS instead of broken default $TMPDIR
if [ "$OS" = "Darwin" ]; then
    TMPDIR=`mktemp -d`
fi

# Get command to run as root
SUDO=$(which sudo)
DOAS=$(which doas)
if [[ -f "${SUDO}" && -x "${SUDO}" ]]; then
    AS_ROOT="${SUDO}"
elif [[ -f "${DOAS}" && -x "${DOAS}" ]]; then
    AS_ROOT="${DOAS}"
else
    echo "No option to run as root, your system does not have sudo or doas installed."
    exit 1
fi

# Confirm that root access is available
_confirm_root() {
    if [ "$EUID" != 0 ]; then
        echo "Root access is required for this step."
        "${AS_ROOT}" echo "Root access granted." || { echo "Exiting."; exit 1; }
    fi
}

# Report a legacy Firefox JSON file on macOS without deleting a file the script cannot identify as its own
_legacy_cleanup() {
    if [ "$OS" = "Darwin" ] && [ -e "/Applications/Firefox.app/Contents/Resources/distribution/policies.json" ]; then
        echo "Existing Firefox policies.json file found and left unchanged:"
        echo "  /Applications/Firefox.app/Contents/Resources/distribution/policies.json"
        echo "Policies from this file may remain active."
    fi
}

# Run a policy file operation either as the current user or with elevated access
_run_policy_command() {
    local policy_access="$1"
    shift
    if [ "$policy_access" = "root" ]; then
        "${AS_ROOT}" "$@"
    else
        "$@"
    fi
}

# Safely install a Firefox policies.json and record the exact file owned by this script
_install_firefox_policy_file() {
    local policy_directory="$1"
    local policy_label="$2"
    local policy_access="$3"
    local policy_file="$policy_directory/policies.json"
    local policy_marker="$policy_directory/.just-the-browser-policies.json"
    local policy_temp
    policy_temp=$(mktemp "${TMPDIR:-/tmp}/just-the-browser-firefox.XXXXXX") || return 1

    curl -Lfs -o "$policy_temp" "$FIREFOX_SETTINGS" || { rm -f "$policy_temp"; echo "Download failed for $policy_label."; return 1; }

    if [ -e "$policy_file" ]; then
        if [ -e "$policy_marker" ] && cmp -s "$policy_file" "$policy_marker"; then
            # This script owns the unchanged file, so it is safe to update it.
            :
        elif cmp -s "$policy_file" "$policy_temp"; then
            echo "$policy_label already has the current settings. The existing file was left unchanged."
            rm -f "$policy_temp"
            return 0
        else
            echo "Existing policy file found at $policy_file."
            echo "It was not changed because it is not an unmodified file owned by Just the Browser."
            rm -f "$policy_temp"
            return 1
        fi
    fi

    if [ "$policy_access" = "root" ]; then
        _confirm_root
    fi
    _run_policy_command "$policy_access" mkdir -p "$policy_directory" || { rm -f "$policy_temp"; return 1; }
    _run_policy_command "$policy_access" cp "$policy_temp" "$policy_file" || { rm -f "$policy_temp"; return 1; }
    _run_policy_command "$policy_access" cp "$policy_temp" "$policy_marker" || { rm -f "$policy_temp"; return 1; }
    _run_policy_command "$policy_access" chmod 644 "$policy_file" "$policy_marker" || { rm -f "$policy_temp"; return 1; }
    rm -f "$policy_temp"
    echo "Updated $policy_label settings."
}

# Remove only an unchanged policy file created by this script, or an exact current legacy copy
_uninstall_firefox_policy_file() {
    local policy_directory="$1"
    local policy_label="$2"
    local policy_access="$3"
    local policy_file="$policy_directory/policies.json"
    local policy_marker="$policy_directory/.just-the-browser-policies.json"
    local policy_temp

    if [ ! -e "$policy_file" ]; then
        echo "No $policy_label policy file was found."
        return 0
    fi

    if [ -e "$policy_marker" ]; then
        if ! cmp -s "$policy_file" "$policy_marker"; then
            echo "$policy_file has changed since Just the Browser installed it."
            echo "The policy and ownership files were left unchanged."
            return 1
        fi
    else
        policy_temp=$(mktemp "${TMPDIR:-/tmp}/just-the-browser-firefox.XXXXXX") || return 1
        curl -Lfs -o "$policy_temp" "$FIREFOX_SETTINGS" || { rm -f "$policy_temp"; echo "Could not verify $policy_file; it was left unchanged."; return 1; }
        if ! cmp -s "$policy_file" "$policy_temp"; then
            echo "$policy_file is not the current Just the Browser policy file."
            echo "It was left unchanged."
            rm -f "$policy_temp"
            return 1
        fi
        rm -f "$policy_temp"
    fi

    if [ "$policy_access" = "root" ]; then
        _confirm_root
    fi
    _run_policy_command "$policy_access" rm -f "$policy_file" "$policy_marker" || return 1
    echo "Removed $policy_label settings."
}

# Add a directory only when it contains Firefox Developer Edition
_add_firefox_developer_path() {
    local firefox_path="$1"
    local existing_firefox_path
    [ -x "$firefox_path/firefox" ] || return
    if [ -f "$firefox_path/application.ini" ]; then
        grep -qi '^CodeName=Firefox Developer Edition' "$firefox_path/application.ini" || return
    else
        case "$firefox_path" in
            *irefox*eveloper*) ;;
            *) return ;;
        esac
    fi
    for existing_firefox_path in "${FIREFOX_DEVELOPER_PATHS[@]}"; do
        [ "$existing_firefox_path" = "$firefox_path" ] && return
    done
    FIREFOX_DEVELOPER_PATHS+=("$firefox_path")
}

# Detect Developer Edition from PATH, an override, and common archive installation directories
_find_firefox_developer_paths() {
    local firefox_command
    local firefox_executable
    local firefox_resolved
    local firefox_path
    FIREFOX_DEVELOPER_PATHS=()
    if [ -n "$FIREFOX_DEVELOPER_PATH" ]; then
        _add_firefox_developer_path "$FIREFOX_DEVELOPER_PATH"
    fi
    for firefox_command in firefox-developer-edition firefox-developer firefox-aurora firefox; do
        firefox_executable=$(command -v "$firefox_command" 2>/dev/null)
        if [ -n "$firefox_executable" ]; then
            firefox_resolved=$(readlink -f "$firefox_executable" 2>/dev/null)
            [ -n "$firefox_resolved" ] || firefox_resolved="$firefox_executable"
            _add_firefox_developer_path "$(dirname "$firefox_resolved")"
        fi
    done
    for firefox_path in \
        "/opt/firefox-developer-edition" \
        "/opt/firefox" \
        "/usr/lib/firefox-developer-edition" \
        "/usr/lib64/firefox-developer-edition" \
        "/usr/local/lib/firefox-developer-edition" \
        "$HOME/firefox-developer-edition" \
        "$HOME/.local/firefox-developer-edition" \
        "$HOME/.local/opt/firefox-developer-edition"; do
        _add_firefox_developer_path "$firefox_path"
    done
    return 0
}

# Render initial interface for all pages
_show_header() {
    clear
    echo -e "\nJust the Browser ($OS)\n========\n"
}

# Install Google Chrome settings
_install_chrome() {
    _show_header
    echo "Downloading configuration, please wait..."
    if [ "$OS" = "Darwin" ]; then
        # Download and open configuration file
        curl -Lfs -o "$TMPDIR/chrome.mobileconfig" "$GOOGLE_CHROME_MAC_CONFIG" || { read -p "Download failed! Press Enter/Return to continue."; return; }
        open "$TMPDIR/chrome.mobileconfig"
        open -b "com.apple.systempreferences"
        # Prompt user to accept file
        echo -e "\nIn the System Settings application, navigate to General > Device Management, then open Google Chrome settings and click the Install button.\n\nIn older macOS versions with System Preferences, this is in the Profiles section.\n"
        read -p "Press Enter/Return to continue."
    else
        _confirm_root
        "${AS_ROOT}" mkdir -p "/etc/opt/chrome/policies/managed"
        "${AS_ROOT}" curl -Lfs -o "/etc/opt/chrome/policies/managed/managed_policies.json" "$CHROME_SETTINGS" || { read -p "Download failed! Press Enter/Return to continue."; return; }
        read -p "Installed Chrome settings. Press Enter/Return to continue."
    fi
}

# Remove Google Chrome settings
_uninstall_chrome() {
    _show_header
    if [ "$OS" = "Darwin" ]; then
        open -b "com.apple.systempreferences"
        echo -e "\nIn the System Settings application, navigate to General > Device Management, then select 'Google Chrome settings' and click the remove (-) button.\n\nIn older macOS versions with System Preferences, this is in the Profiles section.\n"
        read -p "Press Enter/Return to continue."
    else
        _confirm_root
        "${AS_ROOT}" rm "/etc/opt/chrome/policies/managed/managed_policies.json" || { read -p "Remove failed! Press Enter/Return to continue."; return; }
        read -p "Removed Chrome settings. Press Enter/Return to continue."
    fi
}

# Install Chromium settings
_install_chromium() {
    _show_header
    echo "Downloading configuration, please wait..."
    _confirm_root
    # Install to /etc/chromium-browser/policies/managed for Ubuntu and related distributions
    "${AS_ROOT}" mkdir -p "/etc/chromium-browser/policies/managed"
    "${AS_ROOT}" curl -Lfs -o "/etc/chromium-browser/policies/managed/managed_policies.json" "$CHROME_SETTINGS" || { read -p "Download failed! Press Enter/Return to continue."; return; }
    # Install to /etc/chromium/policies/managed for other distributions
    "${AS_ROOT}" mkdir -p "/etc/chromium/policies/managed"
    "${AS_ROOT}" curl -Lfs -o "/etc/chromium/policies/managed/managed_policies.json" "$CHROME_SETTINGS" || { read -p "Download failed! Press Enter/Return to continue."; return; }
    # Completed
    read -p "Installed Chromium settings. Press Enter/Return to continue."
}

# Remove Google Chrome settings
_uninstall_chromium() {
    _show_header
    _confirm_root
    # Uninstall from /etc/chromium-browser/policies/managed for Ubuntu and related distributions
    if [ -e "/etc/chromium-browser/policies/managed/managed_policies.json" ]; then
        "${AS_ROOT}" rm "/etc/chromium-browser/policies/managed/managed_policies.json" || { read -p "Remove failed! Press Enter/Return to continue."; return; }
    fi
    # Uninstall from /etc/chromium/policies/managed for other distributions
    if [ -e "/etc/chromium/policies/managed/managed_policies.json" ]; then
        "${AS_ROOT}" rm "/etc/chromium/policies/managed/managed_policies.json" || { read -p "Remove failed! Press Enter/Return to continue."; return; }
    fi
    read -p "Removed Chromium settings. Press Enter/Return to continue."
}

# Install Chromium settings for Flatpak
_install_chromium_flatpak() {
    _show_header
    FLATPAK_ARCH=$(flatpak --default-arch)
    FLATPAK_PATH="$HOME/.local/share/flatpak/extension/org.chromium.Chromium.Extension.just-the-browser/$FLATPAK_ARCH/1/policies/managed"
    mkdir -p "$FLATPAK_PATH"
    curl -Lfs -o "$FLATPAK_PATH/managed_policies.json" "$CHROME_SETTINGS" || { read -p "Download failed! Press Enter/Return to continue."; return; }
    read -p "Installed Chromium settings. Press Enter/Return to continue."
}

# Remove Chromium settings for Flatpak
_uninstall_chromium_flatpak() {
    _show_header
    FLATPAK_ARCH=$(flatpak --default-arch)
    FLATPAK_PATH="$HOME/.local/share/flatpak/extension/org.chromium.Chromium.Extension.just-the-browser/$FLATPAK_ARCH/1/policies/managed"
    rm "$FLATPAK_PATH/managed_policies.json" || { read -p "Remove failed! Press Enter/Return to continue."; return; }
    read -p "Removed Chromium settings. Press Enter/Return to continue."
}

# Install Microsoft Edge settings
_install_edge() {
    _show_header
    echo "Downloading configuration, please wait..."
    # Download and open configuration file
    curl -Lfs -o "$TMPDIR/edge.mobileconfig" "$MICROSOFT_EDGE_MAC_CONFIG" || { read -p "Download failed! Press Enter/Return to continue."; return; }
    open "$TMPDIR/edge.mobileconfig"
    open -b "com.apple.systempreferences"
    # Prompt user to accept file
    echo -e "\nIn the System Settings application, navigate to General > Device Management, then open Microsoft Edge settings and click the Install button.\n\nIn older macOS versions with System Preferences, this is in the Profiles section.\n"
    read -p "Press Enter/Return to continue."
}

# Remove Microsoft Edge settings
_uninstall_edge() {
    _show_header
    open -b "com.apple.systempreferences"
    echo -e "\nIn the System Settings application, navigate to General > Device Management, then select 'Microsoft Edge settings' and click the remove (-) button.\n\nIn older macOS versions with System Preferences, this is in the Profiles section.\n"
    read -p "Press Enter/Return to continue."
}

# Install Firefox settings
_install_firefox() {
    _show_header
    _legacy_cleanup
    echo "Downloading configuration, please wait..."
    if [ "$OS" = "Darwin" ]; then
        # Download and open configuration file
        curl -Lfs -o "$TMPDIR/firefox.mobileconfig" "$FIREFOX_MAC_CONFIG" || { read -p "Download failed! Press Enter/Return to continue."; return; }
        open "$TMPDIR/firefox.mobileconfig"
        open -b "com.apple.systempreferences"
        # Prompt user to accept file
        echo -e "\nIn the System Settings application, navigate to General > Device Management, then open 'Mozilla Firefox settings' and click the Install button.\n\nIn older macOS versions with System Preferences, this is in the Profiles section.\n"
        read -p "Press Enter/Return to continue."
    else
        _install_firefox_policy_file "/etc/firefox/policies" "Firefox" "root"
        read -p "Press Enter/Return to continue."
    fi
}

# Remove Firefox settings
_uninstall_firefox() {
    _show_header
    _legacy_cleanup
    if [ "$OS" = "Darwin" ]; then
        open -b "com.apple.systempreferences"
        echo -e "\nIn the System Settings application, navigate to General > Device Management, then select 'Mozilla Firefox settings' and click the remove (-) button.\n\nIn older macOS versions with System Preferences, this is in the Profiles section.\n"
        read -p "Press Enter/Return to continue."
    else
        _uninstall_firefox_policy_file "/etc/firefox/policies" "Firefox" "root"
        read -p "Press Enter/Return to continue.";
    fi
}

# Install Firefox Developer Edition settings into each detected archive installation
_install_firefox_developer() {
    local firefox_path
    _show_header
    _find_firefox_developer_paths
    if [ ${#FIREFOX_DEVELOPER_PATHS[@]} -eq 0 ]; then
        read -p "Firefox Developer Edition was not found. Set FIREFOX_DEVELOPER_PATH to its installation directory and try again. Press Enter/Return to continue."
        return
    fi
    for firefox_path in "${FIREFOX_DEVELOPER_PATHS[@]}"; do
        _install_firefox_policy_file "$firefox_path/distribution" "Firefox Developer Edition ($firefox_path)" "root"
    done
    read -p "Press Enter/Return to continue."
}

# Remove script-owned settings from each detected Firefox Developer Edition installation
_uninstall_firefox_developer() {
    local firefox_path
    _show_header
    _find_firefox_developer_paths
    if [ ${#FIREFOX_DEVELOPER_PATHS[@]} -eq 0 ]; then
        read -p "Firefox Developer Edition was not found. Set FIREFOX_DEVELOPER_PATH to its installation directory and try again. Press Enter/Return to continue."
        return
    fi
    for firefox_path in "${FIREFOX_DEVELOPER_PATHS[@]}"; do
        _uninstall_firefox_policy_file "$firefox_path/distribution" "Firefox Developer Edition ($firefox_path)" "root"
    done
    read -p "Press Enter/Return to continue."
}

# Install Firefox settings for Flatpak
_install_firefox_flatpak() {
    _show_header
    FLATPAK_ARCH=$(flatpak --default-arch)
    FLATPAK_PATH="$HOME/.local/share/flatpak/extension/org.mozilla.firefox.systemconfig/$FLATPAK_ARCH/stable/policies"
    _install_firefox_policy_file "$FLATPAK_PATH" "Firefox Flatpak" "user"
    read -p "Press Enter/Return to continue."
}

# Remove Firefox settings for Flatpak
_uninstall_firefox_flatpak() {
    _show_header
    FLATPAK_ARCH=$(flatpak --default-arch)
    FLATPAK_PATH="$HOME/.local/share/flatpak/extension/org.mozilla.firefox.systemconfig/$FLATPAK_ARCH/stable/policies"
    _uninstall_firefox_policy_file "$FLATPAK_PATH" "Firefox Flatpak" "user"
    read -p "Press Enter/Return to continue."
}

# Install Brave settings
_install_brave() {
    _show_header
    echo "Downloading configuration, please wait..."
    if [ "$OS" = "Darwin" ]; then
        # Download and open configuration file
        curl -Lfs -o "$TMPDIR/brave.mobileconfig" "$BRAVE_MAC_CONFIG" || { read -p "Download failed! Press Enter/Return to continue."; return; }
        open "$TMPDIR/brave.mobileconfig"
        open -b "com.apple.systempreferences"
        # Prompt user to accept file
        echo -e "\nIn the System Settings application, navigate to General > Device Management, then open Brave settings and click the Install button.\n\nIn older macOS versions with System Preferences, this is in the Profiles section.\n"
        read -p "Press Enter/Return to continue."
    else
        _confirm_root
        "${AS_ROOT}" mkdir -p "/etc/brave/policies/managed"
        "${AS_ROOT}" curl -Lfs -o "/etc/brave/policies/managed/managed_policies.json" "$BRAVE_SETTINGS" || { read -p "Download failed! Press Enter/Return to continue."; return; }
        read -p "Installed Brave settings. Press Enter/Return to continue."
    fi
}

# Remove Brave settings
_uninstall_brave() {
    _show_header
    if [ "$OS" = "Darwin" ]; then
        open -b "com.apple.systempreferences"
        echo -e "\nIn the System Settings application, navigate to General > Device Management, then select 'Brave settings' and click the remove (-) button.\n\nIn older macOS versions with System Preferences, this is in the Profiles section.\n"
        read -p "Press Enter/Return to continue."
    else
        _confirm_root
        "${AS_ROOT}" rm "/etc/brave/policies/managed/managed_policies.json" || { read -p "Remove failed! Press Enter/Return to continue."; return; }
        read -p "Removed Brave settings. Press Enter/Return to continue."
    fi
}

# Main menu selection
_main() {
    # Create list for menu options
    declare -a options=()
    # Google Chrome without settings applied
    if [ "$OS" = "Darwin" ]; then
        options+=("Google Chrome: Update settings")
    elif [ "$OS" = "Linux" ] && { [ -x "$(command -v google-chrome)" ] || [ -x "$(command -v google-chrome-stable)" ]; }; then
        options+=("Google Chrome: Update settings")
    fi
    # Google Chrome with settings already applied
    if [ "$OS" = "Darwin" ]; then
        options+=("Google Chrome: Remove settings")
    elif [ "$OS" = "Linux" ] && [ -e "/etc/opt/chrome/policies/managed/managed_policies.json" ]; then
        options+=("Google Chrome: Remove settings")
    fi
    # Chromium without settings applied
    if [ "$OS" = "Linux" ] && { [ -x "$(command -v chromium-browser)" ] || [ -x "$(command -v chromium)" ]; }; then
        options+=("Chromium: Update settings")
    fi
    # Chromium with settings already applied
    if [ "$OS" = "Linux" ] && [ -e "/etc/chromium-browser/policies/managed/managed_policies.json" ]; then
        options+=("Chromium: Remove settings")
    elif [ "$OS" = "Linux" ] && [ -e "/etc/chromium/policies/managed/managed_policies.json" ]; then
        options+=("Chromium: Remove settings")
    fi
    # Chromium Flatpak
    if [ "$OS" = "Linux" ] && [ -x "$(command -v flatpak)" ] && flatpak list | grep -q "org.chromium.Chromium"; then
        options+=("Chromium Flatpak: Update settings")
        options+=("Chromium Flatpak: Remove settings")
    fi
    # Microsoft Edge
    if [ "$OS" = "Darwin" ]; then
        options+=("Microsoft Edge: Update settings")
        options+=("Microsoft Edge: Remove settings")
    fi
    # Firefox without settings applied
    if [ "$OS" = "Darwin" ]; then
        options+=("Mozilla Firefox: Update settings")
    elif [ "$OS" = "Linux" ] && [ -x "$(command -v firefox)" ]; then
        options+=("Mozilla Firefox: Update settings")
    fi
    # Firefox with settings already applied
    if [ "$OS" = "Darwin" ]; then
        options+=("Mozilla Firefox: Remove settings")
    elif [ "$OS" = "Linux" ] && [ -e "/etc/firefox/policies/policies.json" ]; then
        options+=("Mozilla Firefox: Remove settings")
    fi
    # Firefox Developer Edition archive installation
    if [ "$OS" = "Linux" ]; then
        _find_firefox_developer_paths
        if [ ${#FIREFOX_DEVELOPER_PATHS[@]} -gt 0 ]; then
            options+=("Firefox Developer Edition: Update settings")
            options+=("Firefox Developer Edition: Remove settings")
        fi
    fi
    # Firefox Flatpak
    if [ "$OS" = "Linux" ] && [ -x "$(command -v flatpak)" ] && flatpak list | grep -q "org.mozilla.firefox"; then
        options+=("Firefox Flatpak: Update settings")
        options+=("Firefox Flatpak: Remove settings")
    fi
    # Brave without settings applied
    if [ "$OS" = "Darwin" ]; then
        options+=("Brave: Update settings")
    elif [ "$OS" = "Linux" ] && [ -x "$(command -v brave-browser)" ]; then
        options+=("Brave: Update settings")
    fi
    # Brave with settings already applied
    if [ "$OS" = "Darwin" ]; then
        options+=("Brave: Remove settings")
    elif [ "$OS" = "Linux" ] && [ -e "/etc/brave/policies/managed/managed_policies.json" ]; then
        options+=("Brave: Remove settings")
    fi
    # Add exit option
    options+=("Exit")
    # Show main menu
    _show_header
    echo -e "Select an option by typing the number, then pressing Return/Enter on your keyboard to confirm.\n\nYou will need to restart your browser for changes to take effect.\n"
    select choice in "${options[@]}"; do
        if [ "$choice" = "Google Chrome: Update settings" ]; then
            _install_chrome
        elif [ "$choice" = "Google Chrome: Remove settings" ]; then
            _uninstall_chrome
        elif [ "$choice" = "Chromium: Update settings" ]; then
            _install_chromium
        elif [ "$choice" = "Chromium: Remove settings" ]; then
            _uninstall_chromium
        elif [ "$choice" = "Chromium Flatpak: Update settings" ]; then
            _install_chromium_flatpak
        elif [ "$choice" = "Chromium Flatpak: Remove settings" ]; then
            _uninstall_chromium_flatpak
        elif [ "$choice" = "Microsoft Edge: Update settings" ]; then
            _install_edge
        elif [ "$choice" = "Microsoft Edge: Remove settings" ]; then
            _uninstall_edge
        elif [ "$choice" = "Mozilla Firefox: Update settings" ]; then
            _install_firefox
        elif [ "$choice" = "Mozilla Firefox: Remove settings" ]; then
            _uninstall_firefox
        elif [ "$choice" = "Firefox Developer Edition: Update settings" ]; then
            _install_firefox_developer
        elif [ "$choice" = "Firefox Developer Edition: Remove settings" ]; then
            _uninstall_firefox_developer
        elif [ "$choice" = "Firefox Flatpak: Update settings" ]; then
            _install_firefox_flatpak
        elif [ "$choice" = "Firefox Flatpak: Remove settings" ]; then
            _uninstall_firefox_flatpak
        elif [ "$choice" = "Brave: Update settings" ]; then
            _install_brave
        elif [ "$choice" = "Brave: Remove settings" ]; then
            _uninstall_brave
        elif [ "$choice" = "Exit" ]; then
            exit 0
        else
            read -p "Invalid option. Press Enter/Return to continue.";
        fi
    done
}

_main
