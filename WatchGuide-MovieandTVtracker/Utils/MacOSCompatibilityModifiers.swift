import SwiftUI

#if os(macOS)
/// macOS compatibility shims for iOS-only SwiftUI modifiers used across the app.
/// These keep feature code shared while making unsupported modifiers no-ops on macOS.
enum PlatformNavigationBarTitleDisplayMode {
    case automatic
    case inline
    case large
}

enum PlatformKeyboardType {
    case `default`
    case asciiCapable
    case numbersAndPunctuation
    case URL
    case numberPad
    case phonePad
    case namePhonePad
    case emailAddress
    case decimalPad
    case twitter
    case webSearch
    case asciiCapableNumberPad
}

enum PlatformAutocapitalizationType {
    case never
    case words
    case sentences
    case characters
    case none
}

extension View {
    func navigationBarTitleDisplayMode(_ mode: PlatformNavigationBarTitleDisplayMode) -> some View {
        self
    }

    func keyboardType(_ type: PlatformKeyboardType) -> some View {
        self
    }

    func autocapitalization(_ style: PlatformAutocapitalizationType) -> some View {
        self
    }

}
#endif
