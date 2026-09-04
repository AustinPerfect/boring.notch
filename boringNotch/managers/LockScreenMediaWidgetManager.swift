//
//  LockScreenMediaWidgetManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults

@MainActor
final class LockScreenMediaWidgetManager {
    static let shared = LockScreenMediaWidgetManager()

    private let musicManager = MusicManager.shared
    private let container = LockScreenWidgetContainer(allowsInteraction: true)
    private var cancellables = Set<AnyCancellable>()

    private init() {
        container.configure(cornerRadius: 26, frame: { context in
            let size = CGSize(width: 360, height: 108)
            return NSRect(
                x: context.frame.midX - size.width / 2,
                y: context.frame.midY - size.height - 100,
                width: size.width,
                height: size.height
            )
        }) {
            LockScreenMediaWidgetView()
        }

        observeChanges()
        refresh()
    }

    private func observeChanges() {
        musicManager.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableLockScreenMediaWidget)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)
    }

    private func refresh() {
        container.setEnabled(Defaults[.enableLockScreenMediaWidget] && hasMediaMetadata)
    }

    private var hasMediaMetadata: Bool {
        if musicManager.isPlaying {
            return true
        }

        let title = musicManager.songTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let artist = musicManager.artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let placeholderTitles = ["i'm handsome", "unknown", "not playing"]
        let placeholderArtists = ["me", "unknown"]
        return (!title.isEmpty && !placeholderTitles.contains(title))
            || (!artist.isEmpty && !placeholderArtists.contains(artist))
    }
}
