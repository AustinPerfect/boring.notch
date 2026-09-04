//
//  LockScreenFocusWidgetManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class LockScreenFocusWidgetManager: ObservableObject {
    static let shared = LockScreenFocusWidgetManager()

    @Published private(set) var isActive: Bool
    @Published private(set) var focusName: String

    private let container = LockScreenWidgetContainer()
    private var notificationObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        isActive = Defaults[.lockScreenFocusActive]
        focusName = Defaults[.lockScreenFocusName]

        container.configure(cornerRadius: 22, frame: { context in
            let size = CGSize(width: 300, height: 48)
            return NSRect(
                x: context.frame.midX - size.width / 2,
                y: context.frame.midY + 70,
                width: size.width,
                height: size.height
            )
        }) {
            LockScreenFocusWidgetView()
        }

        observeFocusChanges()
        observeSettings()
        updateContainer()
    }

    private func observeFocusChanges() {
        let center = DistributedNotificationCenter.default()
        notificationObservers.append(center.addObserver(
            forName: Notification.Name("_NSDoNotDisturbEnabledNotification"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let name = notification.userInfo?["FocusModeName"] as? String
            Task { @MainActor in
                self?.setFocus(active: true, name: name)
            }
        })

        notificationObservers.append(center.addObserver(
            forName: Notification.Name("_NSDoNotDisturbDisabledNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setFocus(active: false, name: nil)
            }
        })
    }

    private func observeSettings() {
        Defaults.publisher(.enableLockScreenFocusWidget)
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateContainer() }
            }
            .store(in: &cancellables)

        Defaults.publisher(.lockScreenFocusActive)
            .sink { [weak self] change in
                Task { @MainActor in
                    self?.isActive = change.newValue
                    self?.updateContainer()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.lockScreenFocusName)
            .sink { [weak self] change in
                Task { @MainActor in
                    self?.focusName = change.newValue
                }
            }
            .store(in: &cancellables)
    }

    private func setFocus(active: Bool, name: String?) {
        isActive = active
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            focusName = name
        }
        updateContainer()
    }

    private func updateContainer() {
        container.setEnabled(Defaults[.enableLockScreenFocusWidget] && isActive)
    }
}

private struct LockScreenFocusWidgetView: View {
    @ObservedObject private var focus = LockScreenFocusWidgetManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.indigo)

            Text(focus.focusName.isEmpty ? "Focus" : focus.focusName)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Spacer()

            Text("On")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 15)
        .frame(width: 300, height: 48)
        .foregroundStyle(.white)
        .background(widgetBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.clear)
                .glassEffect(.clear.tint(.white.opacity(0.16)), in: .rect(cornerRadius: 22))
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.28))
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
        }
    }
}

struct LockScreenFocusSettings: View {
    @Default(.enableLockScreenFocusWidget) private var isEnabled
    @Default(.lockScreenFocusActive) private var manualFocusActive
    @Default(.lockScreenFocusName) private var manualFocusName

    var body: some View {
        Section {
            Defaults.Toggle(key: .enableLockScreenFocusWidget) {
                Text("Show Focus status on lock screen")
            }
            .disabled(!Defaults[.showOnLockScreen])

            Toggle("Focus is active", isOn: $manualFocusActive)
                .disabled(!isEnabled)

            TextField("Focus name", text: $manualFocusName)
                .disabled(!isEnabled || !manualFocusActive)
        } header: {
            Text("Lock Screen Focus")
        } footer: {
            Text("The manual controls are a fallback when macOS does not expose the active Focus name.")
        }
    }
}
