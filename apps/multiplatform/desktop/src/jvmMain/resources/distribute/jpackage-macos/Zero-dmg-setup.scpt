tell application "Finder"
  tell disk "Zero"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 540}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:Zero-background.png"
    set position of item "Zero.app" of container window to {180, 225}
    set position of item "Applications" of container window to {480, 225}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
