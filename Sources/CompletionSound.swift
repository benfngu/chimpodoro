import AVFoundation

/// One bounded player, retained through playback. Uses the regular audio output
/// rather than the independently configured macOS system-alert sound channel.
final class CompletionSound {
    private var player: AVAudioPlayer?

    @discardableResult
    func play(url: URL? = Bundle.main.url(forResource: "Completion", withExtension: "wav")) -> Bool {
        if player == nil {
            guard let url else { return false }
            do { player = try AVAudioPlayer(contentsOf: url) }
            catch { return false }
        }
        guard let player else { return false }
        // Repeated previews restart the same short sound; they cannot accumulate.
        player.stop()
        player.currentTime = 0
        player.numberOfLoops = 0
        player.volume = 1
        return player.play()
    }
}
