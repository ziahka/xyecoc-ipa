import AVFoundation
import Foundation

/// Тихий аудиотрек удерживает приложение живым в фоне (приём SideStore):
/// генерируем WAV из нулевых сэмплов и крутим его бесконечно в сессии
/// категории .playback с .mixWithOthers — iOS не суспендит приложение,
/// пользователь ничего не слышит и его музыка не глушится.
/// Работает только при UIBackgroundModes: audio (задан в project.yml).
@MainActor
final class SilentKeepAlive: ObservableObject {
    static let shared = SilentKeepAlive()
    private init() {}

    @Published private(set) var isRunning = false

    private var player: AVAudioPlayer?
    private var interruptionObserver: NSObjectProtocol?

    /// WAV: RIFF-заголовок + PCM 16-bit mono 44.1 kHz, секунда нулей.
    private static func silentWavData(seconds: Double = 1.0) -> Data {
        let sampleRate = 44_100
        let dataSize = Int(Double(sampleRate) * seconds) * 2 // 16-bit mono

        var bytes: [UInt8] = []
        func appendString(_ s: String) { bytes.append(contentsOf: Array(s.utf8)) }
        func appendU32(_ v: UInt32) {
            bytes.append(UInt8(v & 0xff))
            bytes.append(UInt8((v >> 8) & 0xff))
            bytes.append(UInt8((v >> 16) & 0xff))
            bytes.append(UInt8((v >> 24) & 0xff))
        }
        func appendU16(_ v: UInt16) {
            bytes.append(UInt8(v & 0xff))
            bytes.append(UInt8((v >> 8) & 0xff))
        }

        appendString("RIFF")
        appendU32(UInt32(36 + dataSize))
        appendString("WAVE")
        appendString("fmt ")
        appendU32(16)                 // размер fmt-чанка
        appendU16(1)                  // PCM
        appendU16(1)                  // mono
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * 2)) // byte rate
        appendU16(2)                  // block align
        appendU16(16)                 // bits per sample
        appendString("data")
        appendU32(UInt32(dataSize))

        var wav = Data(bytes)
        wav.append(Data(count: dataSize)) // нулевые сэмплы
        return wav
    }

    func start() {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.silentWavData())
            player.numberOfLoops = -1
            player.volume = 0.0001 // двойная страховка неслышности
            player.prepareToPlay()
            guard player.play() else {
                try? session.setActive(false, options: [.notifyOthersOnDeactivation])
                return
            }
            self.player = player
            isRunning = true
            observeInterruptions()
        } catch {
            // Аудиосессия могла быть перехвачена системой; молча сдаёмся —
            // приложение просто будет работать как обычно без keep-alive.
            isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isRunning = false
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    /// Телефонный звонок или чужая музыка перебивают сессию —
    /// после окончания прерывания возобновляем тишину.
    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                  type == .ended else { return }
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    if options.contains(.shouldResume) {
                        self.player?.play()
                    }
                } catch {
                    // не смогли вернуться в сессию — keep-alive тихо гаснет
                }
            }
        }
    }
}
