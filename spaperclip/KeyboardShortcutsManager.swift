import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

@MainActor
final class LayoutAwareShortcutManager {
    static let shared = LayoutAwareShortcutManager()

    private let characterDefaultsKey = "QuickSearchShortcutCharacter"
    private var observers: [NSObjectProtocol] = []
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let inputSourceNotification = Notification.Name(
            kTISNotifySelectedKeyboardInputSourceChanged as String
        )
        observers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: inputSourceNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.applyCurrentLayout() }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.applyCurrentLayout() }
            }
        )

        applyCurrentLayout()
    }

    func shortcutDidChange(_ shortcut: KeyboardShortcuts.Shortcut?) {
        guard let shortcut else {
            UserDefaults.standard.removeObject(forKey: characterDefaultsKey)
            return
        }

        if let character = Self.character(forKeyCode: shortcut.carbonKeyCode) {
            UserDefaults.standard.set(
                String(character).lowercased(),
                forKey: characterDefaultsKey
            )
        } else {
            UserDefaults.standard.removeObject(forKey: characterDefaultsKey)
        }
    }

    private func applyCurrentLayout() {
        guard let intendedCharacter = UserDefaults.standard.string(forKey: characterDefaultsKey),
            intendedCharacter.count == 1,
            let currentShortcut = KeyboardShortcuts.getShortcut(for: .toggleQuickSearch),
            let mappedKeyCode = Self.keyCode(for: Character(intendedCharacter)),
            mappedKeyCode != currentShortcut.carbonKeyCode
        else {
            return
        }

        KeyboardShortcuts.setShortcut(
            .init(
                carbonKeyCode: mappedKeyCode,
                carbonModifiers: currentShortcut.carbonModifiers
            ),
            for: .toggleQuickSearch
        )
    }

    static func keyCode(for character: Character) -> Int? {
        let target = String(character).lowercased()
        return (0..<128).first { keyCode in
            self.character(forKeyCode: keyCode).map { String($0).lowercased() } == target
        }
    }

    static func character(forKeyCode keyCode: Int) -> Character? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(
                source,
                kTISPropertyUnicodeKeyLayoutData
            )
        else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        let keyboardLayout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).first
    }
}

struct ShortcutSettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Quick Search") {
                KeyboardShortcuts.Recorder(
                    for: .toggleQuickSearch,
                    onChange: LayoutAwareShortcutManager.shared.shortcutDidChange
                )
                .accessibilityIdentifier("settings.quick-search-shortcut")
            }

            Text("This shortcut follows the selected character when you switch keyboard layouts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460, height: 180)
        .navigationTitle("Shortcuts")
        .accessibilityIdentifier("settings.shortcuts")
    }
}
