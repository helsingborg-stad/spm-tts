import Foundation
import AVKit
import Combine
import FFTPublisher
import AudioSwitchboard

enum AudioPlayerStatus {
    case started
    case paused
    case stopped
    case cancelled
    case failed
}
struct AudioPlayerItem {
    var id: String
    var status: AudioPlayerStatus
    var error: Error?
}
// https://stackoverflow.com/questions/56999334/boost-increase-volume-of-text-to-speech-avspeechutterance-to-make-it-louder
class AudioBufferPlayer: ObservableObject {
    enum AudioBufferPlayerError: Error {
        case unableToInitlializeInputFormat
        case unableToInitlializeOutputFormat
        case unableToInitlializeAudioConverter
        case unableToInitlializeBufferFormat
        case unknownBufferType
    }
    weak var fft: FFTPublisher?
    let statusSubject: PassthroughSubject<AudioPlayerItem, Never> = .init()
    let status: AnyPublisher<AudioPlayerItem, Never>
    let playbackTime: PassthroughSubject<Float, Never> = .init()
    private let outputFormat = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatFloat32, sampleRate: 22050, channels: 1, interleaved: false)
    private var cancellable:AnyCancellable?
    private(set) var isPlaying: Bool = false
    private var converter: AVAudioConverter!
    private let audioSwitchboard:AudioSwitchboard
    private let player: AVAudioPlayerNode = AVAudioPlayerNode()
    private let bufferSize: UInt32 = 512
    private var bufferCounter: Int = 0
    private var currentlyPlaying: String? = nil {
        didSet {
            isPlaying = currentlyPlaying != nil
        }
    }
    init(_ audioSwitchboard:AudioSwitchboard) {
        self.audioSwitchboard = audioSwitchboard
        self.status = statusSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }
    private func play(buffer: AVAudioPCMBuffer, id: String) {
        self.bufferCounter += 1
        self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { (_) -> Void in
            DispatchQueue.main.async { [ weak self] in
                guard let this = self else {
                    return
                }
                this.bufferCounter -= 1
                if this.bufferCounter == 0, this.currentlyPlaying == id {
                    this.statusSubject.send(AudioPlayerItem(id: id, status: .stopped))
                    this.currentlyPlaying = nil
                    this.stop()
                }
            }
        }
    }
    private func prepare(buffer: AVAudioBuffer, id: String) {
        guard player.isPlaying else {
            return
        }
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer, pcmBuffer.frameLength > 0 else {
            //self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: AudioBufferPlayerError.unknownBufferType))
            return
        }
        if buffer.format.commonFormat == .otherFormat {
            play(buffer: pcmBuffer, id: id)
        } else {
            initializeConverter(id: id, buffer: buffer)
            guard let outputFormat = outputFormat else {
                self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: AudioBufferPlayerError.unableToInitlializeOutputFormat))
                return
            }
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: pcmBuffer.frameCapacity) else {
                self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: AudioBufferPlayerError.unableToInitlializeBufferFormat))
                return
            }
            do {
                try self.converter.convert(to: convertedBuffer, from: pcmBuffer)
                play(buffer: convertedBuffer, id: id)
            } catch {
                self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: error))
            }
        }
    }
    private func postCurrentPosition(for rate: Float) {
        guard self.player.isPlaying else {
            return
        }
        if let nodeTime = self.player.lastRenderTime, let playerTime = self.player.playerTime(forNodeTime: nodeTime) {
            let elapsedSeconds = (Float(playerTime.sampleTime) / rate)
            self.playbackTime.send(elapsedSeconds)
        }
    }
    private func initializeConverter(id: String,buffer: AVAudioBuffer) {
        guard converter == nil else {
            return
        }
        guard let outputAudioFormat = outputFormat else {
            self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: AudioBufferPlayerError.unableToInitlializeOutputFormat))
            return
        }
        guard let c = AVAudioConverter(from: buffer.format, to: outputAudioFormat) else {
            self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: AudioBufferPlayerError.unableToInitlializeAudioConverter))
            return
        }
        converter = c
    }
    func `continue`() {
        guard currentlyPlaying != nil else {
            return
        }
        if !player.isPlaying {
            player.play()
        }
    }
    func pause() {
        guard currentlyPlaying != nil else {
            return
        }
        if player.isPlaying {
            player.pause()
        }
    }
    func stop() {
        if let currentlyPlaying = currentlyPlaying {
            statusSubject.send(AudioPlayerItem(id: currentlyPlaying, status: .cancelled))
        }
        converter = nil
        audioSwitchboard.stop(owner: "AppleTTS")
        player.stop()
        bufferCounter = 0
        currentlyPlaying = nil
        self.fft?.end()
    }
    func play(id: String, buffer: AVAudioBuffer) {
        guard let outputFormat = outputFormat else {
            stop()
            self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: AudioBufferPlayerError.unableToInitlializeInputFormat))
            return
        }
        if id == self.currentlyPlaying {
            prepare(buffer: buffer, id: id)
            return
        }
        cancellable?.cancel()
        cancellable = audioSwitchboard.claim(owner: "AppleTTS").sink { [weak self] in
            self?.stop()
        }
        let audioEngine = audioSwitchboard.audioEngine
        currentlyPlaying = id
        bufferCounter = 0
        audioEngine.attach(player)
        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: outputFormat)
        let rate = Float(audioEngine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        audioEngine.mainMixerNode.installTap(onBus: 0, bufferSize: self.bufferSize, format: audioEngine.mainMixerNode.outputFormat(forBus: 0)) { [weak self] (buffer, _) in
            guard let this = self else {
                return
            }
            buffer.frameLength = this.bufferSize
            DispatchQueue.main.async {
                guard this.player.isPlaying else {
                    return
                }
                this.fft?.consume(buffer: buffer.audioBufferList, frames: buffer.frameLength, rate: rate)
                this.postCurrentPosition(for: rate)
            }
        }
        try? audioSwitchboard.start(owner: "AppleTTS")
        self.player.play()
        self.statusSubject.send(AudioPlayerItem(id: id, status: .started))
        prepare(buffer: buffer, id: id)
    }
}
