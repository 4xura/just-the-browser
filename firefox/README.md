---
layout: layout.njk
title: Mozilla Firefox configuration
permalink: "firefox/index.html"
---

Firefox features can be configured using Group Policy templates on Windows, Intune on Windows, configuration profiles on macOS, or with a custom `policies.json` file. This project uses the JSON file method on Linux, Windows Registry settings on Windows, and a Profile Manager file on macOS. Firefox stable and Firefox Developer Edition use the same Just the Browser policy settings.

You can check which policies are applied in Firefox by navigating to the `about:policies` page.

### Windows installation

The Windows registry policy applies to both Firefox stable and Firefox Developer Edition, including when both are installed. The setup script detects Mozilla's installation registry entries, Windows uninstall registry entries, and the common `C:\Program Files\Firefox Developer Edition` and `C:\Program Files (x86)\Firefox Developer Edition` directories.

1. Open the [registry file for installation](https://raw.githubusercontent.com/4xura/just-the-browser/main/firefox/install.reg) and save it (`Ctrl+S`) anywhere on your computer.
2. In the File Explorer, right-click the file and select Open with > Registry Editor.
3. Follow the prompts to install the registry keys to the Windows Registry.
4. Restart every installed Firefox edition.

Open `about:policies` in Firefox stable and/or Firefox Developer Edition. The Active tab should list the Just the Browser policies described below. The Errors tab should be empty.

To remove the custom configuration from both editions, follow the same steps with the [registry file for uninstallation](https://raw.githubusercontent.com/4xura/just-the-browser/main/firefox/uninstall.reg), then restart each edition. This removes the Just the Browser registry key from your system.

The Windows setup script and registry files never overwrite or delete an existing per-installation `distribution\policies.json`. If one exists, its unrelated policies can remain active alongside the registry policies. After uninstalling, policies from that file can also remain active. Review the file yourself before merging or deleting it; common locations include `C:\Program Files\Mozilla Firefox\distribution\policies.json` and `C:\Program Files\Firefox Developer Edition\distribution\policies.json`.

### macOS installation

The macOS configuration file applies to all versions of Firefox. This includes Firefox stable, Firefox ESR, Firefox Beta, Firefox Developer Edition, and Firefox Nightly.

1. Open the [configuration file](https://raw.githubusercontent.com/4xura/just-the-browser/main/firefox/firefox.mobileconfig) and save it (`Command+S`) anywhere on your computer.
2. In the Finder, open the configuration file you downloaded. You should see a prompt that the profile is ready for review.
3. Open the System Settings application (Apple menu > System Settings) and navigate to General > Device Management. If you are on macOS 12 Monterey or an older version, the application is called System Preferences, and you need to open the Profiles section.
4. Double-click on the 'Mozilla Firefox settings' configuration, then click the Install button and follow the prompts.

To remove the custom configuration, open the Device Management settings (or Profiles pane) again, select the 'Mozilla Firefox settings' configuration, and then click the remove (-) button.

If there is no Firefox item in the Device Management settings, you may have the older JSON file created by older versions of Just the Browser. You can delete the JSON file by opening your Terminal app (`Command+Spacebar` and type "terminal") and pasting this command:

```shell
sudo rm "/Applications/Firefox.app/Contents/Resources/distribution/policies.json"
```

If you install Just the Browser again in the future, it will use the newer mobileconfig method.

### Linux installation for Firefox Flatpak

Follow these instructions if you are using the [Firefox Flatpak package](https://flathub.org/en/apps/org.mozilla.firefox).

1. Open the [configuration file](https://raw.githubusercontent.com/4xura/just-the-browser/main/firefox/policies.json) and save it (`Ctrl+S`) anywhere on your computer. Make sure the file is called "policies.json" (without the quotes).
2. Open a new Terminal window in the directory where the file is located. For example, if it's in your Downloads folder, open a Terminal and run `cd ~/Downloads` to switch to the Downloads directory.
3. Find your Flatpak architecture and save it as a variable:
```shell
FLATPAK_ARCH=$(flatpak --default-arch)
```
4. Create the managed policies directory:
```shell
mkdir -p "$HOME/.local/share/flatpak/extension/org.mozilla.firefox.systemconfig/$FLATPAK_ARCH/stable/policies"
```
5. Copy the configuration file to the directory:
```shell
cp ./policies.json "$HOME/.local/share/flatpak/extension/org.mozilla.firefox.systemconfig/$FLATPAK_ARCH/stable/policies/"
```
6. Restart the browser.

To remove the custom configuration, delete the `policies.json` file from the managed policies directory and restart the browser. You can do that with these commands:

```shell
FLATPAK_ARCH=$(flatpak --default-arch)
rm "$HOME/.local/share/flatpak/extension/org.mozilla.firefox.systemconfig/$FLATPAK_ARCH/stable/policies/policies.json"
```

### Linux installation for system package

1. Open the [configuration file](https://raw.githubusercontent.com/4xura/just-the-browser/main/firefox/policies.json) and save it (`Ctrl+S`) anywhere on your computer. Make sure the file is called "policies.json" (without the quotes).
2. Open a new Terminal window in the directory where the file is located. For example, if it's in your Downloads folder, open a Terminal and run `cd ~/Downloads` to switch to the Downloads directory.
3. Create the Firefox policies directory with this command:
```shell
sudo mkdir -p /etc/firefox/policies/
```
4. Copy the file to the new folder:
```shell
sudo cp ./policies.json /etc/firefox/policies/
```
5. Restart Firefox.

To remove the custom configuration, delete the `policies.json` file from the distribution folder and restart Firefox. You can do that with this command:
```shell
sudo rm /etc/firefox/policies/policies.json
```

### Linux installation for Firefox Developer Edition

The setup script detects Developer Edition from common installation directories and command names, then installs the policy in the detected installation's `distribution/policies.json`. If an archive was extracted elsewhere, set `FIREFOX_DEVELOPER_PATH` to the directory containing its `firefox` executable before starting the script:

```shell
FIREFOX_DEVELOPER_PATH="/path/to/firefox" ./main.sh
```

The script records an ownership copy next to the policy. Repeated installation is idempotent, and uninstall removes the policy only when it is still identical to that owned copy. An unrelated or subsequently modified policy file is left unchanged.

The system-wide `/etc/firefox/policies/policies.json` location may also be supported by a distribution-packaged Developer Edition build. For a manual installation without the setup script, use the per-installation method:

1. Download the [configuration file](https://raw.githubusercontent.com/4xura/just-the-browser/main/firefox/policies.json) and save it as `policies.json`.
2. Find the directory containing the Developer Edition `firefox` executable.
3. Check whether its `distribution/policies.json` already exists. If it does, do not overwrite it; either merge the Just the Browser entries into its top-level `policies` object or leave the existing file unchanged.
4. If no policy file exists, create the `distribution` directory and copy the downloaded file to `distribution/policies.json`.
5. Restart Firefox Developer Edition and verify the Active and Errors tabs in `about:policies`.

To uninstall this per-installation configuration, remove only the `distribution/policies.json` file that you added, then restart Firefox Developer Edition. Do not delete a file that was merged with or is managed by another tool.

On Windows, the shared registry method above is preferred because it configures stable and Developer Edition together without writing into either installation. On macOS, the configuration profile already contains separate payloads for stable, Developer Edition, and Nightly. On Linux, policy locations depend on how each build was packaged, so archive installations may need the per-installation method.

### Browser settings

These are the policy settings in the Just the Browser configuration files for Firefox.

Firefox 149+ uses the `AIControls` setting to configure generative AI features, replacing the `GenerativeAI` setting introduced in Firefox 144 and Firefox ESR 140.4. Both settings are included in Just the Browser's configuration to maintain backwards compatibility.

| Feature | Information |
| ------- | ----------- |
| DisableFirefoxStudies | Prevents Firefox from enrolling in [Studies](https://support.mozilla.org/en-US/kb/shield), which may involve additional analytics reporting. |
| DisableTelemetry | Prevents the upload of telemetry data. As of Firefox 83 and Firefox ESR 78.5, local storage of telemetry data is disabled as well. |
| DontCheckDefaultBrowser | Prevents popup warnings about Firefox not being the default browser. |
| FirefoxHome | Turns off stores, sponsored stories, and sponsored top sites on the Firefox Home page. |
| AIControls | Turns off most AI controls, including SmartTabGroups, LinkPreviewKeyPoints, SidebarChatbot, and the SmartWindow. PDFAltText and Translations are left enabled, but they can be turned off from `about:preferences#ai` if desired. |
| GenerativeAI | The previous version of the AIControls setting for Firefox versions 144-148. |
| SearchEngines | Removes Perplexity AI as a default search engine. |
| IPProtectionAvailable | The built-in Firefox VPN is [normally blocked](https://support.mozilla.org/en-US/kb/built-in-vpn?as=u&utm_source=inproduct#:~:text=Enterprise%20note) when enterprise policies are active. This setting allows it to function again. |

### Documentation

- [Firefox administrator reference](https://firefox-admin-docs.mozilla.org/reference/policies/)
- [Block generative AI features with Firefox AI controls](https://support.mozilla.org/en-US/kb/firefox-ai-controls)
- [Customize Firefox using policies.json](https://support.mozilla.org/en-US/kb/customizing-firefox-using-policiesjson)
- [Firefox policies list (deprecated)](https://mozilla.github.io/policy-templates/)
