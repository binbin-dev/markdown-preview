//
//  FocusRingVisibility.swift
//  md-preview
//
//  Focus rings follow the last input method: hidden after a mouse click and
//  shown again once the keyboard moves focus.
//

import AppKit
import ObjectiveC
import SwiftUI

/// Whether the keyboard is being used to move focus.
///
/// macOS draws a focus ring around whatever holds keyboard focus, including
/// when a view focuses a control as it appears or after a mouse click. The
/// app should look calm until the reader actually navigates with the
/// keyboard, so every SwiftUI surface turns the system focus effect off while
/// the last input was a click, and back on once Tab moves focus.
///
/// Typing and command shortcuts take the keyboard without navigating; they
/// must not bring the rings back, or a single keystroke in the editor would
/// light them up across every window until the next click.
@Observable
@MainActor
final class FocusRingVisibility {
    static let shared = FocusRingVisibility()

    private(set) var isKeyboardActive = false

    private var monitor: Any?
    private var keyWindowObserver: Any?

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            // The monitor runs on the main thread; NSEvent is not Sendable,
            // so the isolation has to be asserted across the closure.
            MainActor.assumeIsolated {
                self?.note(event)
            }
            return event
        }
        // A popover or sheet arrives with fresh AppKit controls, which start
        // with the system ring until the policy runs.
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AppKitFocusRingPolicy.apply()
            }
        }
    }

    private func note(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // Only the keys that walk the focus ring count as navigation.
            guard Self.movesFocus(event), !isKeyboardActive else { return }
            isKeyboardActive = true
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let wasKeyboardActive = isKeyboardActive
            isKeyboardActive = false
            if wasKeyboardActive {
                // Before the event is dispatched, so the click's own focus
                // change does not draw a ring.
                AppKitFocusRingPolicy.apply()
            }
            // After dispatch, to catch controls the event created — a
            // popover opened by this click, for instance.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    AppKitFocusRingPolicy.apply()
                }
            }
            return
        default:
            return
        }
        // Before the event is dispatched, so a Tab restores the ring style in
        // time for the newly focused control to draw it.
        AppKitFocusRingPolicy.apply()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                AppKitFocusRingPolicy.apply()
            }
        }
    }

    /// Tab and Shift-Tab, including the Control variants that walk the
    /// window's focus ring; AppKit keeps 48 as the key code for all of them.
    private static func movesFocus(_ event: NSEvent) -> Bool {
        event.keyCode == 48
    }

    /// A fresh window starts without a ring even when a keyboard shortcut
    /// opened it.
    func reset() {
        isKeyboardActive = false
        AppKitFocusRingPolicy.apply()
    }
}

private struct FocusRingPolicyModifier: ViewModifier {
    @State private var visibility = FocusRingVisibility.shared

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled(!visibility.isKeyboardActive)
    }
}

extension View {
    /// Hides focus rings until the keyboard is used, for a whole SwiftUI
    /// hosting root. Apply it once at the top of each root view.
    func hidesFocusRingUntilKeyboard() -> some View {
        modifier(FocusRingPolicyModifier())
    }
}

/// AppKit controls draw their own rings, outside SwiftUI's focus effect.
/// Walk the windows and switch the ring style on buttons and segmented
/// controls, restoring each control's own style when the keyboard is used.
@MainActor
private enum AppKitFocusRingPolicy {
    private static var originalKey: UInt8 = 0

    static func apply() {
        let keyboard = FocusRingVisibility.shared.isKeyboardActive
        for window in NSApp.windows {
            guard let content = window.contentView else { continue }
            apply(to: content, keyboard: keyboard)
        }
    }

    private static func apply(to view: NSView, keyboard: Bool) {
        if view is NSButton || view is NSSegmentedControl || view is NSTextField
            || view is NSTableView || view is NSCollectionView {
            applyRingPolicy(to: view, keyboard: keyboard)
            // While a text field is being edited the field editor draws the
            // ring, not the field itself.
            if let field = view as? NSTextField,
               let editor = field.currentEditor() {
                applyRingPolicy(to: editor, keyboard: keyboard)
            }
        }
        for subview in view.subviews {
            apply(to: subview, keyboard: keyboard)
        }
    }

    private static func applyRingPolicy(to view: NSView, keyboard: Bool) {
        let original: NSFocusRingType
        if let stored = objc_getAssociatedObject(view, &originalKey) as? NSNumber,
           let storedType = NSFocusRingType(rawValue: stored.uintValue) {
            original = storedType
        } else {
            original = view.focusRingType
            objc_setAssociatedObject(view, &originalKey,
                                     NSNumber(value: original.rawValue),
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let wanted: NSFocusRingType = keyboard ? original : .none
        if view.focusRingType != wanted {
            view.focusRingType = wanted
            view.setKeyboardFocusRingNeedsDisplay(view.bounds)
        }
    }
}
