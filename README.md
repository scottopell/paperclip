# SPaperClip

## Build Releasable Thing
### Create .app
`xcodebuild -scheme spaperclip -configuration Release -derivedDataPath build`

Your .app will be in `build/Build/Products/Release/spaperclip.app`



### Create DMG
`hdiutil create -volname "spaperclip" -srcfolder build/Build/Products/Release/spaperclip.app -ov -format UDZO spaperclip.dmg`

Your .dmg will be in `./spaperclip.dmg`

# sPaperclip

sPaperclip is a powerful clipboard manager for macOS that helps you keep track of your clipboard history.

## Features

- Clipboard history tracking with metadata (source app, timestamp)
- Detailed clipboard content view with support for various formats
- **Quick Search**: Global keyboard shortcut to access clipboard history from anywhere
- Menu bar item for quick access to statistics
- Core Data persistence for reliable clipboard history storage

## Quick Search

The new Quick Search feature allows you to access your clipboard history from anywhere with a global keyboard shortcut, similar to Spotlight:

1. Press **Cmd+Shift+Space** (default) to open the Quick Search window
2. Type to search through your clipboard history
3. Use arrow keys to navigate through the results
4. Press Enter to select and copy an item
5. Press Esc to dismiss the window

You can customize the keyboard shortcut in Preferences → Keyboard Shortcuts.

## Requirements

- macOS 15.0 or later

## Building from Source

1. Clone the repository
2. Open the project in Xcode
3. Build and run the project
