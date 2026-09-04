//
//  LockScreenReminderWidgetManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class LockScreenReminderWidgetManager {
    static let shared = LockScreenReminderWidgetManager()

    private let calendarService = CalendarService()
    private let container = LockScreenWidgetContainer()
    private var nextReminder: EventModel?
    private var refreshTimer: Timer?
    private var isLockScreenVisible = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        container.configure(
            cornerRadius: 22,
            frame: { context in
                let size = CGSize(width: 360, height: 48)
                return NSRect(
                    x: context.frame.midX - size.width / 2,
                    y: context.frame.midY + 8,
                    width: size.width,
                    height: size.height
                )
            },
            onLockScreenVisibilityChange: { [weak self] visible in
                self?.visibilityChanged(visible)
            }
        ) { [weak self] in
            if let reminder = self?.nextReminder {
                LockScreenReminderWidgetView(reminder: reminder)
            }
        }

        Defaults.publisher(.enableLockScreenReminderWidget)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)

        container.setEnabled(false)
    }

    private func visibilityChanged(_ visible: Bool) {
        isLockScreenVisible = visible
        if visible {
            startRefreshTimer()
            refresh()
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func refresh() {
        guard isLockScreenVisible, Defaults[.enableLockScreenReminderWidget] else {
            container.setEnabled(false)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let now = Date()
            let end = now.addingTimeInterval(24 * 60 * 60)
            let events = await calendarService.events(from: now, to: end, calendars: [])
            guard !Task.isCancelled else { return }
            nextReminder = events.first { event in
                if case .reminder(let completed) = event.type {
                    return !completed
                }
                return false
            }
            container.setEnabled(nextReminder != nil)
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }
}

private struct LockScreenReminderWidgetView: View {
    let reminder: EventModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(nsColor: reminder.calendar.color))

            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: reminder.calendar.color))
                .frame(width: 5, height: 19)

            Text(reminder.title.isEmpty ? "Reminder" : reminder.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(reminder.start, style: .time)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(width: 360, height: 48)
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
