# FujiCam

Use a Fujifilm X-T4 (or another gphoto2-supported Fujifilm body) as a macOS webcam.

- `FujiCam.app` is a menu-bar app that reads the camera's USB live view through libgphoto2.
- `CameraExtension` is a CoreMediaIO camera extension that shows up as **FujiCam X-T4** in FaceTime, Zoom, Teams, browsers, etc.

The app pushes frames into the extension's sink stream; while no frames arrive the camera shows a "Waiting for Fujifilm camera…" placeholder.

The menu also offers a floating **preview window** (⌘P) with exposure settings (mode, shutter, aperture, ISO, EV), focus mode, AF status, film simulation, battery, and the current **AF point** drawn over the image.

## Camera setup (X-T4)

1. `MENU › SET UP › CONNECTION SETTING › PC CONNECTION MODE` → **USB TETHER SHOOTING AUTO**
2. Set auto power-off to OFF and preferably power the camera via USB-C PD or a dummy battery.
3. Connect via USB-C.

## Build & install

Requires Xcode signed in with your Apple Developer account (Xcode › Settings › Accounts) and Homebrew.

`install.sh` first builds a patched libgphoto2 into `vendor/` (`scripts/build-libgphoto2.sh`). The patch makes libgphoto2's raw `opcode` config return the camera's response, which is needed to read the Fuji focus point (property `0xD347`).

```sh
./scripts/install.sh
```

On first launch, approve the extension in **System Settings › General › Login Items & Extensions › Camera Extensions**.
Then pick **FujiCam X-T4** as camera in your video app. FujiCam.app must be running for live video.

## Notes

- macOS's `ptpcamerad` grabs PTP cameras; FujiCam kills it before connecting.
- Live view is ~1024 px wide at up to ~30 fps (the camera's USB limit), scaled/cropped to 1280×720.
- libgphoto2 (LGPL-2.1) and its dependencies are bundled into the app at build time (`scripts/bundle-gphoto2.sh`); Homebrew is only needed to build.
- Quit FujiCam via its menu (or a normal `kill`): it closes the camera's live-view session on exit. A hard kill (`kill -9`) can leave the camera busy until it is power-cycled.
