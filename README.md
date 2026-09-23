# ROCKNIX Controller Plus

Controller, touchscreen, mouse, and trackball enhancements for **ROCKNIX on the Retroid Pocket 5**.

[日本語の説明はこちら / Japanese documentation](README-ja.txt)

> [!WARNING]
> This package is currently intended only for the Retroid Pocket 5. The installer checks the device model and stops without making changes on unsupported hardware.

## Features

- Per-game button mapping on every platform supported by EmulationStation
- Independent settings for A, B, X, Y, L1, L2, R1, and R2
- `NORMAL`, `TURBO`, `REPEAT`, and `TOGGLE` modes for each button
- Mapping one physical button to another button or to all supported buttons
- Configurable TURBO and REPEAT rates
- Per-game 4-way D-pad mode for games that must not receive diagonal input
- Native analog-stick input by default, with optional left-stick-to-D-pad conversion
- In-game settings OSD opened with HOME + Back
- Arcade touchscreen, relative mouse, and inertial trackball modes
- Configurable mouse movement and trackball inertia
- Automatic pointer-direction adjustment for rotated arcade games
- Prevents automatic sleep while charging so network and SSH access remain available
- Native InputPlumber integration without replacing the controller with a userspace virtual gamepad
- Installer and uninstaller that run directly from the ROCKNIX Ports menu

## Requirements

- Retroid Pocket 5
- A recent ROCKNIX installation with the standard EmulationStation and InputPlumber services
- Access to the ROCKNIX `STORAGE` partition, either by inserting the storage card into a computer or by copying files over the network

## Installation

### Method 1: Copy the repository folder

1. Download this repository with **Code → Download ZIP**, then extract it.
2. Copy the included `roms` folder to the root of the ROCKNIX `STORAGE` partition.
3. Merge it with the existing `roms` folder when prompted. Do not remove your existing ROMs.
4. Return the storage card to the Retroid Pocket 5 and start ROCKNIX.
5. Refresh the game list, or restart EmulationStation, if the new entries do not appear immediately.
6. Open **Ports** and run **Install Retroid Controls**.
7. Wait for `INSTALLATION COMPLETE`. The device automatically reboots after approximately eight seconds to activate the native input driver.

After copying, the important paths should look like this:

```text
STORAGE/
└── roms/
    └── ports/
        ├── Install Retroid Controls.sh
        ├── Uninstall Retroid Controls.sh
        └── rocknix-retroid-controls/
```

### Method 2: Use the packaged archive

1. Download [`retroid-controls-final.tgz`](retroid-controls-final.tgz).
2. Extract its contents directly into `STORAGE/roms/ports/`.
3. Follow steps 4–7 above.

Do not interrupt the automatic reboot. If it is interrupted, perform one normal full reboot before testing the controller.

## Using per-game settings

In EmulationStation:

1. Highlight a game.
2. Open the game's advanced or per-game options.
3. Change only the controller options you need.
4. Launch the game normally.

Settings are stored per game. Leaving a setting unchanged keeps the standard behavior. Button mappings, TURBO, REPEAT, TOGGLE, 4-way mode, and left-stick mode are available across platforms. Touch, mouse, and trackball options are added to supported arcade cores.

### Button modes

| Mode | Behavior |
|---|---|
| `NORMAL` | Sends the selected target button while the physical button is held. Use this for ordinary remapping. |
| `TURBO` | Repeatedly presses the target button for as long as the physical button is held. |
| `REPEAT` | Sends an initial press, waits for the configured delay, then repeats like a keyboard key. |
| `TOGGLE` | Alternates the target button between held and released each time the physical button is pressed. |
| `Disabled` | Prevents the physical button from sending a game input. |

Each physical button can target A, B, X, Y, L1, L2, R1, R2, or all supported buttons.

### Directional and analog options

- **8-way:** normal D-pad behavior, including diagonals.
- **4-way:** allows only one D-pad axis at a time, for games designed for four-direction controls.
- **Native analog:** passes the left analog stick through as analog input. This is the default and is recommended for games such as Space Harrier.
- **Left stick as D-pad:** converts the left analog stick to digital directions for games that require it.

### Arcade touch modes

- **Touchscreen:** direct touch input.
- **Mouse:** relative pointer movement, similar to a laptop trackpad.
- **Trackball:** relative movement with configurable inertia.

Mouse speed can be adjusted from 10% to 200% in 10% increments. Pointer direction follows the arcade game's screen rotation.

## In-game OSD

While a game is running:

1. Hold **HOME**.
2. Press **Back**.
3. Release both buttons.

The game temporarily leaves fullscreen mode and the `RETROID CONTROLS` menu appears.

- D-pad: move through the menu
- A: select
- B: go back or close

The OSD uses a dedicated non-TURBO input profile, so existing game TURBO or REPEAT mappings do not affect menu navigation. Fullscreen mode and the game's input profile are restored when the menu closes. Changes are saved for the current game. Controller changes take effect when the OSD closes; touch, mouse, and trackball mode changes take effect the next time the game is launched.

## Charging and sleep

While external power is connected, automatic sleep is inhibited so the device remains reachable over the network. Deliberately pressing the power button still allows normal sleep behavior.

## Updating or reinstalling

Replace the files in `STORAGE/roms/ports/` with the newer package, then run **Install Retroid Controls** again. The configuration patching is designed to be repeatable and avoids duplicating menu entries.

Before changing configuration files, the installer creates a timestamped backup under:

```text
/storage/.config/retroid-controls/backups/
```

## Uninstallation

1. Open **Ports**.
2. Run **Uninstall Retroid Controls**.
3. Wait for `UNINSTALLATION COMPLETE` and the automatic reboot.

The uninstaller removes the managed controller, touchscreen, Sway, power, and EmulationStation changes. It leaves the installer files in Ports so the package can be installed again later.

The configuration present immediately before uninstallation is backed up under:

```text
/storage/.config/retroid-controls/uninstall-backups/
```

## Troubleshooting

### The installer is not visible in Ports

Confirm that `Install Retroid Controls.sh` is directly inside `STORAGE/roms/ports/`, then refresh the EmulationStation game list or reboot ROCKNIX.

### The controller does not respond after installation

The native InputPlumber binary and capability map are activated during a full reboot. Allow the scheduled reboot to finish. If it was interrupted, reboot the device normally once; do not repeatedly restart InputPlumber while a game is running.

### HOME + Back does not open the OSD

Launch the game from EmulationStation after completing the installation and reboot. Press HOME and Back together, then release both buttons. The OSD intentionally waits for both releases to prevent a stuck HOME hotkey state.

### Installation or uninstallation fails

Review the logs:

```text
/storage/retroid-controls-install.log
/storage/retroid-controls-uninstall.log
```

The scripts stop on validation errors and keep timestamped configuration backups for recovery.

## Package layout

```text
roms/ports/
├── Install Retroid Controls.sh
├── Uninstall Retroid Controls.sh
└── rocknix-retroid-controls/
    ├── install.sh
    ├── uninstall.sh
    └── payload/
```

The `payload` directory contains the native RP5 InputPlumber build, controller profiles, OSD, touchscreen helpers, service definitions, and idempotent configuration patching tools.
