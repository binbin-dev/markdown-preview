//
//  SettingsSupport.swift
//  md-preview
//
//  Shared helpers for the Settings pane files.
//

import AppKit
import SwiftUI

func L(_ key: String, default value: String? = nil) -> String {
    let localized = NSLocalizedString(key, comment: "")
    if let value, localized == key {
        return value
    }
    return localized
}

var appDelegate: AppDelegate? {
    NSApp.delegate as? AppDelegate
}

// MARK: - Column layout

/// Width of every Settings pane, so switching tabs only changes the height.
let settingsPaneWidth: CGFloat = 640

/// A trailing-colon label for the leading column, as in Safari's Settings.
func columnLabel(_ key: String) -> String {
    String(format: L("%@:"), L(key))
}

/// Gray explanation under a control in the trailing column.
struct SettingsCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 360, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// The blank space Safari leaves between groups of settings.
    func settingsGroupGap() -> some View {
        padding(.bottom, 12)
    }
}

/// One option in a custom choice control: the text-size samples, the
/// appearance thumbnails, the theme cards, or a font row.
///
/// The system draws a focus ring around whichever button holds keyboard
/// focus, and macOS does not give a plain button focus when it is clicked.
/// The ring therefore stayed on the first option while the selection moved.
/// This button takes focus when it is chosen, and again whenever its
/// selection changes from elsewhere (⌘+ / ⌘−, the toolbar's A buttons), so
/// the ring marks the selected option once the keyboard is in use.
struct SettingsChoiceButton<Label: View>: View {
    let isSelected: Bool
    /// Whether a selected option takes focus when the view first appears, so
    /// a pane opens with its ring on the selection instead of on whichever
    /// button macOS focused first. Off inside a sheet or gallery that already
    /// opens with another primary action focused.
    var claimsFocusOnAppear = true
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @FocusState private var isFocused: Bool
    @State private var focusRing = FocusRingVisibility.shared

    var body: some View {
        Button {
            action()
            isFocused = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .focusEffectDisabled(!focusRing.isKeyboardActive)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onAppear {
            if claimsFocusOnAppear, isSelected {
                isFocused = true
            }
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                isFocused = true
            }
        }
    }
}

/// An ⓘ button that shows the full explanation in a popover, for settings
/// whose caption would otherwise run to several lines.
struct SettingsInfoButton: View {
    let text: String
    @State private var isShown = false

    init(_ text: String) { self.text = text }

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Details"))
        .popover(isPresented: $isShown, arrowEdge: .trailing) {
            Text(text)
                .frame(width: 300, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
        }
    }
}
