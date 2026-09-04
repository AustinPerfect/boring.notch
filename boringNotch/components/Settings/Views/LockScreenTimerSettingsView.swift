//
//  LockScreenTimerSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct LockScreenTimerSettings: View {
    @Default(.enableLockScreenTimerWidget) private var isEnabled
    @ObservedObject private var timer = LockScreenTimerWidgetManager.shared
    @State private var durationMinutes = 10.0

    var body: some View {
        Section {
            Defaults.Toggle(key: .enableLockScreenTimerWidget) {
                Text("Show timer widget on lock screen")
            }
            .disabled(!Defaults[.showOnLockScreen])

            Stepper(value: $durationMinutes, in: 1...180, step: 1) {
                HStack {
                    Text("Duration")
                    Spacer()
                    Text("\(Int(durationMinutes)) min")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!isEnabled)

            HStack {
                if timer.isTimerActive {
                    Text(timer.formattedRemainingTime)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if timer.isTimerActive {
                    Button("Cancel", role: .destructive) {
                        timer.cancel()
                    }
                }

                Button(timer.isTimerActive ? "Restart" : "Start") {
                    timer.start(minutes: durationMinutes)
                }
                .disabled(!isEnabled)
            }
        } header: {
            Text("Lock Screen Timer")
        } footer: {
            Text("Start a timer here, then lock the Mac to see and control it on the lock screen.")
        }
    }
}
