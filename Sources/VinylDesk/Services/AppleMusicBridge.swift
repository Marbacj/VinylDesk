import AppKit
import Foundation
import Observation

private struct MusicSnapshot: Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let status: PlaybackStatus
}

/// Dedicated serial background executor for `NSAppleScript` so UI never blocks and AppleScript stays thread-safe.
private final class AppleScriptExecutor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vinyldesk.applescript", qos: .userInitiated)

    func runString(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                let result = script?.executeAndReturnError(&error)
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: result?.stringValue)
                }
            }
        }
    }

    func runData(_ source: String) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                let result = script?.executeAndReturnError(&error)
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    let data = result?.data
                    continuation.resume(returning: (data?.isEmpty == false) ? data : nil)
                }
            }
        }
    }

    func runVoid(_ source: String) async {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                _ = script?.executeAndReturnError(&error)
                continuation.resume()
            }
        }
    }
}

@MainActor
@Observable
public final class AppleMusicBridge {
    private nonisolated static let musicBundleID = "com.apple.Music"
    private nonisolated static let playerInfoNotification = Notification.Name("com.apple.Music.playerInfo")

    public private(set) var isMusicRunning: Bool = false
    public private(set) var currentTrack: TrackInfo?
    public private(set) var playbackStatus: PlaybackStatus = .stopped
    public private(set) var currentPosition: TimeInterval = 0
    public private(set) var artwork: NSImage?
    public private(set) var ambientColor: NSColor?
    public private(set) var lyrics: [LyricLine] = []
    public private(set) var currentLyricLine: LyricLine?

    public var shouldShowWidget: Bool {
        guard isMusicRunning, let track = currentTrack, !track.isEmpty else { return false }
        return playbackStatus == .playing || playbackStatus == .paused
    }

    public var progress: Double {
        guard let duration = currentTrack?.duration, duration > 0 else { return 0 }
        return min(max(currentPosition / duration, 0), 1)
    }

    private let settings: AppSettings
    private let executor = AppleScriptExecutor()
    private let artworkService = ArtworkService()
    private let lyricsService = LyricsService()

    private var anchorPosition: TimeInterval = 0
    private var anchorDate: Date = Date()
    private var lastResyncDate: Date = .distantPast
    private var isScrubbing: Bool = false

    private var progressTimer: Timer?
    private var distributedObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    private var artworkTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var resyncTask: Task<Void, Never>?

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func start() {
        isMusicRunning = Self.checkMusicRunning()
        setupObservers()
        startProgressTimer()

        if isMusicRunning {
            Task { await fullSyncFromMusicApp() }
        }
    }

    public func stop() {
        progressTimer?.invalidate()
        progressTimer = nil

        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
            self.distributedObserver = nil
        }
        if let launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
            self.launchObserver = nil
        }
        if let terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }
        artworkTask?.cancel()
        lyricsTask?.cancel()
        resyncTask?.cancel()
    }

    // MARK: - Controls

    public func togglePlayPause() {
        guard isMusicRunning else { return }
        if playbackStatus == .playing {
            playbackStatus = .paused
            anchorPosition = currentPosition
            anchorDate = Date()
        } else if playbackStatus == .paused {
            playbackStatus = .playing
            anchorPosition = currentPosition
            anchorDate = Date()
        }
        Task {
            await executor.runVoid(#"tell application "Music" to playpause"#)
            try? await Task.sleep(for: .milliseconds(250))
            await syncPositionOnly()
        }
    }

    public func nextTrack() {
        guard isMusicRunning else { return }
        Task {
            await executor.runVoid(#"tell application "Music" to next track"#)
        }
    }

    public func previousTrack() {
        guard isMusicRunning else { return }
        Task {
            await executor.runVoid(#"tell application "Music" to previous track"#)
        }
    }

    public func beginScrubbing() {
        isScrubbing = true
    }

    public func updateScrubbing(progress: Double) {
        guard let duration = currentTrack?.duration, duration > 0 else { return }
        let clamped = min(max(progress, 0), 1)
        let target = clamped * duration
        currentPosition = target
        anchorPosition = target
        anchorDate = Date()
        updateActiveLyric()
    }

    public func commitScrubbing(progress: Double) {
        isScrubbing = false
        guard isMusicRunning, let duration = currentTrack?.duration, duration > 0 else { return }
        let clamped = min(max(progress, 0), 1)
        let target = clamped * duration
        currentPosition = target
        anchorPosition = target
        anchorDate = Date()
        updateActiveLyric()

        let formatted = String(format: "%.2f", target)
        Task {
            await executor.runVoid(#"tell application "Music" to set player position to \#(formatted)"#)
        }
    }

    public func openAppleMusic() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.musicBundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }

    public func refreshLyricsForCurrentTrack() {
        guard let track = currentTrack, !track.isEmpty else { return }
        if !settings.showLyrics {
            currentLyricLine = nil
            return
        }
        loadLyrics(for: track, forceRefresh: true)
    }

    // MARK: - Observers

    private func setupObservers() {
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.playerInfoNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo
            let name = userInfo?["Name"] as? String
            let artist = userInfo?["Artist"] as? String
            let album = userInfo?["Album"] as? String
            let totalTimeMs = (userInfo?["Total Time"] as? NSNumber)?.doubleValue
            let stateStr = userInfo?["Player State"] as? String

            Task { @MainActor [weak self] in
                self?.handlePlayerInfoNotification(
                    name: name,
                    artist: artist,
                    album: album,
                    totalTimeMs: totalTimeMs,
                    stateString: stateStr
                )
            }
        }

        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.musicBundleID else { return }
            Task { @MainActor [weak self] in
                self?.isMusicRunning = true
                try? await Task.sleep(for: .milliseconds(800))
                await self?.fullSyncFromMusicApp()
            }
        }

        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.musicBundleID else { return }
            Task { @MainActor [weak self] in
                self?.handleMusicTerminated()
            }
        }
    }

    private func handleMusicTerminated() {
        isMusicRunning = false
        playbackStatus = .stopped
        currentTrack = nil
        currentPosition = 0
        artwork = nil
        ambientColor = nil
        lyrics = []
        currentLyricLine = nil
        artworkTask?.cancel()
        lyricsTask?.cancel()
    }

    private func handlePlayerInfoNotification(
        name: String?,
        artist: String?,
        album: String?,
        totalTimeMs: Double?,
        stateString: String?
    ) {
        isMusicRunning = Self.checkMusicRunning()
        guard isMusicRunning else {
            handleMusicTerminated()
            return
        }

        let newStatus = parseStatus(stateString)
        if newStatus == .stopped {
            playbackStatus = .stopped
            currentTrack = nil
            currentPosition = 0
            currentLyricLine = nil
            return
        }

        let duration = (totalTimeMs ?? 0) / 1000.0
        let incomingTrack = TrackInfo(
            title: name ?? "",
            artist: artist ?? "",
            album: album ?? "",
            duration: duration
        )

        if incomingTrack.isEmpty {
            Task { await fullSyncFromMusicApp() }
            return
        }

        let isNewTrack = currentTrack?.cacheKey != incomingTrack.cacheKey
        currentTrack = incomingTrack
        playbackStatus = newStatus

        if isNewTrack {
            currentPosition = 0
            anchorPosition = 0
            anchorDate = Date()
            lyrics = []
            currentLyricLine = nil
            loadArtwork(for: incomingTrack)
            if settings.showLyrics {
                loadLyrics(for: incomingTrack, forceRefresh: false)
            }
        } else {
            anchorPosition = currentPosition
            anchorDate = Date()
        }

        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await syncPositionOnly()
        }
    }

    // MARK: - AppleScript Sync

    private func fullSyncFromMusicApp() async {
        guard Self.checkMusicRunning() else {
            handleMusicTerminated()
            return
        }

        let script = """
        tell application "Music"
            if player state is stopped then
                return "STOPPED"
            end if
            set pState to (player state as string)
            set pPos to player position
            try
                set tName to name of current track
                set tArtist to artist of current track
                set tAlbum to album of current track
                set tDur to duration of current track
            on error
                return "STOPPED"
            end try
            return pState & "\u{001F}" & tName & "\u{001F}" & tArtist & "\u{001F}" & tAlbum & "\u{001F}" & (tDur as string) & "\u{001F}" & (pPos as string)
        end tell
        """

        guard let output = await executor.runString(script) else { return }
        if output == "STOPPED" {
            playbackStatus = .stopped
            currentTrack = nil
            currentPosition = 0
            currentLyricLine = nil
            return
        }

        let parts = output.components(separatedBy: "\u{001F}")
        guard parts.count >= 6 else { return }

        let status = parseStatus(parts[0])
        let track = TrackInfo(
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            duration: Self.parseLocalizedDouble(parts[4]) ?? 0
        )
        let position = Self.parseLocalizedDouble(parts[5]) ?? 0

        guard !track.isEmpty else { return }

        let isNewTrack = currentTrack?.cacheKey != track.cacheKey
        isMusicRunning = true
        currentTrack = track
        playbackStatus = status
        currentPosition = position
        anchorPosition = position
        anchorDate = Date()
        lastResyncDate = Date()

        if isNewTrack {
            lyrics = []
            currentLyricLine = nil
            loadArtwork(for: track)
            if settings.showLyrics {
                loadLyrics(for: track, forceRefresh: false)
            }
        } else {
            updateActiveLyric()
        }
    }

    private func syncPositionOnly() async {
        guard Self.checkMusicRunning(), !isScrubbing else { return }

        let script = """
        tell application "Music"
            if player state is stopped then
                return "STOPPED"
            end if
            return (player state as string) & "\u{001F}" & (player position as string)
        end tell
        """

        guard let output = await executor.runString(script) else { return }
        if output == "STOPPED" {
            playbackStatus = .stopped
            currentTrack = nil
            currentPosition = 0
            currentLyricLine = nil
            return
        }

        let parts = output.components(separatedBy: "\u{001F}")
        guard parts.count >= 2 else { return }

        let status = parseStatus(parts[0])
        if let pos = Self.parseLocalizedDouble(parts[1]) {
            playbackStatus = status
            currentPosition = pos
            anchorPosition = pos
            anchorDate = Date()
            lastResyncDate = Date()
            updateActiveLyric()
        }
    }

    // MARK: - Artwork & Lyrics Loading

    private func loadArtwork(for track: TrackInfo) {
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let self else { return }
            let localBytes = await self.fetchLocalArtworkData()
            if Task.isCancelled { return }

            let resolvedData = await self.artworkService.resolveArtworkData(
                for: track,
                localArtworkData: localBytes
            )
            if Task.isCancelled { return }

            guard self.currentTrack?.cacheKey == track.cacheKey else { return }

            if let resolvedData, let image = NSImage(data: resolvedData) {
                let extractedColor = ColorExtractor.extractAmbientColor(from: image)
                self.artwork = image
                self.ambientColor = extractedColor
            } else {
                self.artwork = nil
                self.ambientColor = nil
            }
        }
    }

    private func fetchLocalArtworkData() async -> Data? {
        guard Self.checkMusicRunning() else { return nil }
        let script = """
        tell application "Music"
            try
                if (count of artworks of current track) > 0 then
                    return raw data of artwork 1 of current track
                end if
            end try
        end tell
        """
        return await executor.runData(script)
    }

    private func loadLyrics(for track: TrackInfo, forceRefresh: Bool) {
        lyricsTask?.cancel()
        let preferBilingual = settings.showBilingualLyrics

        lyricsTask = Task { [weak self] in
            guard let self else { return }
            let fetched = await self.lyricsService.fetchLyrics(for: track, preferBilingual: preferBilingual)
            if Task.isCancelled { return }
            guard self.currentTrack?.cacheKey == track.cacheKey else { return }

            self.lyrics = fetched
            self.updateActiveLyric()
        }
    }

    // MARK: - Timer & Interpolation

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickProgress()
            }
        }
        progressTimer?.tolerance = 0.05
    }

    private func tickProgress() {
        guard isMusicRunning, playbackStatus == .playing, !isScrubbing, let track = currentTrack else {
            return
        }

        let elapsed = Date().timeIntervalSince(anchorDate)
        let computed = anchorPosition + elapsed
        currentPosition = track.duration > 0 ? min(computed, track.duration) : max(0, computed)
        updateActiveLyric()

        // Periodically resync with Music.app while playing to stay accurate if scrubbed inside Music.app.
        if Date().timeIntervalSince(lastResyncDate) >= 5.0 {
            lastResyncDate = Date()
            resyncTask?.cancel()
            resyncTask = Task { [weak self] in
                await self?.syncPositionOnly()
            }
        }
    }

    private func updateActiveLyric() {
        guard settings.showLyrics, !lyrics.isEmpty else {
            if currentLyricLine != nil {
                currentLyricLine = nil
            }
            return
        }

        let nextLine = LRCParser.activeLine(in: lyrics, at: currentPosition)
        if nextLine != currentLyricLine {
            currentLyricLine = nextLine
        }
    }

    // MARK: - Helpers

    private func parseStatus(_ raw: String?) -> PlaybackStatus {
        switch (raw ?? "").lowercased() {
        case "playing": return .playing
        case "paused": return .paused
        default: return .stopped
        }
    }

    private static func checkMusicRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == musicBundleID }
    }

    private static func parseLocalizedDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Double(trimmed) {
            return direct
        }
        let commaNormalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(commaNormalized)
    }
}
