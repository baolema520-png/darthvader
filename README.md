# 520CAM

macOS app for real-time face blur, pixelation, and virtual backgrounds. Includes a virtual camera for Zoom, Google Meet, and OBS.

## Download

**[Download 520CAM.dmg](APP%20FINAL/520CAM.dmg)** (macOS 13+)

## Install

1. Open `520CAM.dmg`
2. Drag **520CAM** to **Applications**
3. Open **520CAM** from Applications
4. Click **Start** and allow **Camera** access when macOS asks
5. Click **Virtual Cam** to enable the virtual camera
6. In your video app, select **520CAM** as the camera

Optional: double-click **Start Here** in the DMG for the step-by-step setup guide.

## Build from source

```bash
xcodegen generate
./Scripts/build_release_app.sh
./Scripts/package_dmg.sh build-artifacts/520CAM.app "APP FINAL/520CAM.dmg"
```

## License

All rights reserved.
