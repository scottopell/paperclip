# SPaperClip

## Build Releasable Thing
### Create .app
`xcodebuild -scheme spaperclip -configuration Release -derivedDataPath build`

Your .app will be in `build/Build/Products/Release/spaperclip.app`



### Create DMG
`hdiutil create -volname "spaperclip" -srcfolder build/Build/Products/Release/spaperclip.app -ov -format UDZO spaperclip.dmg`

Your .dmg will be in `./spaperclip.dmg`
