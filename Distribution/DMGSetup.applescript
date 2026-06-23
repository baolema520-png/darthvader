on run
    set appBundlePOSIX to POSIX path of (path to me)
    if appBundlePOSIX does not contain "/Volumes/" then
        display alert "Open this installer from the 520CAM disk image." buttons {"OK"} default button 1
        return
    end if

    set volRoot to do shell script "dirname " & quoted form of appBundlePOSIX
    set volName to do shell script "basename " & quoted form of volRoot

    my applyInstallerLayout(volName)
    my openGuide(appBundlePOSIX)
end run

on applyInstallerLayout(volName)
    tell application "Finder"
        if not (exists disk volName) then return
        tell disk volName
            open
            set containerWindow to container window
            set current view of containerWindow to icon view
            set toolbar visible of containerWindow to false
            set statusbar visible of containerWindow to false
            set the bounds of containerWindow to {200, 120, 800, 520}
            set viewOptions to the icon view options of containerWindow
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 88
            set text size of viewOptions to 12
            set background picture of viewOptions to file ".background:dmg-background.tiff"
            try
                set position of item "520CAM Setup.app" of containerWindow to {68, 248}
            end try
            try
                set position of item "520CAM.app" of containerWindow to {248, 248}
            end try
            try
                set position of item "Applications" of containerWindow to {428, 248}
            end try
            update without registering applications
        end tell
    end tell
end applyInstallerLayout

on openGuide(appBundlePOSIX)
    set guidePOSIX to appBundlePOSIX & "Contents/Resources/guides/guide.html"
    do shell script "open " & quoted form of guidePOSIX
end openGuide
