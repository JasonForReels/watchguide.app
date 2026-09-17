import SwiftUI

#if os(tvOS)
/// tvOS compatibility shims — mirrors the macOS stubs for modifiers unavailable on tvOS.
enum PlatformNavigationBarTitleDisplayMode {
    case automatic
    case inline
    case large
}

extension View {
    func navigationBarTitleDisplayMode(_ mode: PlatformNavigationBarTitleDisplayMode) -> some View {
        self
    }
}
#endif

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

// iOS bar placements, mapped onto their macOS window-toolbar equivalents.
// The SDK's versions are marked unavailable on macOS, so the compiler prefers these.
extension ToolbarPlacement {
    static var navigationBar: ToolbarPlacement { .windowToolbar }
}

extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
    static var navigationBarLeading: ToolbarItemPlacement { .navigation }
    static var navigationBarTrailing: ToolbarItemPlacement { .primaryAction }
}

extension ListStyle where Self == InsetListStyle {
    static var insetGrouped: InsetListStyle { .inset }
}

extension View {
    func navigationBarTitleDisplayMode(_ mode: PlatformNavigationBarTitleDisplayMode) -> some View {
        self
    }

    func statusBarHidden(_ hidden: Bool = true) -> some View {
        self
    }

    func keyboardType(_ type: PlatformKeyboardType) -> some View {
        self
    }

    func autocapitalization(_ style: PlatformAutocapitalizationType) -> some View {
        self
    }

    func textInputAutocapitalization(_ style: PlatformAutocapitalizationType?) -> some View {
        self
    }

    /// macOS has no full-screen covers; present as a large sheet instead.
    func fullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            content(item).frame(minWidth: 900, minHeight: 650)
        }
    }

    func fullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().frame(minWidth: 900, minHeight: 650)
        }
    }
}
#endif
