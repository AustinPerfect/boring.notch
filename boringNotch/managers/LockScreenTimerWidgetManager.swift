//
//  LockScreenTimerWidgetManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class LockScreenTimerWidgetManager: ObservableObject {
    static let shared = LockScreenTimerWidgetManager()

    @Published private(set) var remainingTime: TimeInterval = 0
    @Published private(set) var isTimerActive = false
    @Published private(set) var isPaused = false

    private let container = LockScreenWidgetContainer(allowsInteraction: true)
    private var deadline: Date?
    private var pausedRemainingTime: TimeInterval = 0
    private var ticker: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        container.configure(
            cornerRadius: 24,
            frame: { context in
                let size = CGSize(width: 350, height: 72)
                return NSRect(
                    x: context.frame.midX - size.width / 2,
                    y: context.frame.midY - size.height - 20,
                    width: size.width,
                    height: size.height
                )
            }
        ) {
            LockScreenTimerWidgetView()
        }

        Defaults.publisher(.enableLockScreenTimerWidget)
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateContainer() }
            }
            .store(in: &cancellables)

        updateContainer()
    }

    func start(minutes: Double) {
        let duration = max(1, minutes * 60)
        remainingTime = duration
        pausedRemainingTime = duration
        deadline = Date().addingTimeInterval(duration)
        isPaused = false
        isTimerActive = true
        startTicker()
        updateContainer()
    }

    func togglePause() {
        guard isTimerActive else { return }

        if isPaused {
            deadline = Date().addingTimeInterval(pausedRemainingTime)
            isPaused = false
            startTicker()
        } else {
            pausedRemainingTime = remainingTime
            deadline = nil
            isPaused = true
            stopTicker()
        }
    }

    func cancel() {
        stopTicker()
        deadline = nil
        pausedRemainingTime = 0
        remainingTime = 0
        isPaused = false
        isTimerActive = false
        updateContainer()
    }

    var formattedRemainingTime: String {
        let seconds = max(0, Int(remainingTime.rounded(.up)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let ticker {
            RunLoop.main.add(ticker, forMode: .common)
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let deadline else { return }

        remainingTime = max(0, deadline.timeIntervalSinceNow)
        if remainingTime == 0 {
            cancel()
        }
    }

    private func updateContainer() {
        container.setEnabled(isTimerActive && Defaults[.enableLockScreenTimerWidget])
    }
}

private struct LockScreenTimerWidgetView: View {
    @ObservedObject private var timer = LockScreenTimerWidgetManager.shared

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "timer")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 30)

            Text(timer.formattedRemainingTime)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: timer.togglePause) {
                Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(timer.isPaused ? "Resume timer" : "Pause timer")

            Button(action: timer.cancel) {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel timer")
        }
        .padding(.horizontal, 16)
        .frame(width: 350, height: 72)
        .foregroundStyle(.white)
        .background(widgetBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.clear)
                .glassEffect(.clear.tint(.white.opacity(0.16)), in: .rect(cornerRadius: 24))
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black.opacity(0.28))
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
        }
    }
}
