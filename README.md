# TapoControl

Control TP-Link Tapo smart bulbs from your Mac's menu bar. It talks to the bulbs directly over your
home network, with no cloud or hub.

<img width="348" height="446" alt="Screenshot 2026-11-23 at 10 45 17 PM" src="https://github.com/user-attachments/assets/23a28c4b-6841-438f-ac3f-c4c33c367901" />


## Features

- Turn bulbs on or off, one at a time or all at once
- Adjust brightness, white temperature and colour
- One-click scenes: Bright, Warm, Dim, Off
- Stores only a key derived from your password, never the password itself

## Requirements

- macOS 26 or later, and Xcode to build it
- Tapo bulbs on the same network as your Mac
- **Third-Party Compatibility** turned on in the Tapo app: Me → Third-Party Services

## Getting started

1. Clone this repo and open `TapoControl.xcodeproj` in Xcode.
2. In the target's Signing & Capabilities, choose your own team and change the bundle identifier.
3. Press **⌘R**. A lightbulb appears in the menu bar.
4. Click it, enter your Tapo email and password, and allow Local Network access when macOS asks.
5. Open Settings in the panel to name your bulbs and set their IP addresses.

To keep it installed without Xcode: Product → Archive → Distribute App → Custom → Copy App. Then move
the app to Applications and turn on **Launch at login** in its Settings.

## How it works

The bulbs speak TP-Link's local KLAP protocol, the same one [python-kasa](https://github.com/python-kasa/python-kasa)
uses. The code is in three folders:

- `TapoKit/` has the protocol: handshake, encryption and bulb commands.
- `Shared/` has state, saved credentials and scenes.
- `TapoControl/` has the menu bar interface.

Run the tests with **⌘U**. To test a bulb from Terminal without the app, run `python3 tools/klap_probe.py`.
