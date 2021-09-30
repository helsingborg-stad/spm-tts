import Foundation
import AVFoundation
import Combine
import FFTPublisher
import AudioSwitchboard

public enum AppleTTSError : Error {
    case unavailable
}

public class AppleTTS: NSObject, TTSService, AVSpeechSynthesizerDelegate, ObservableObject {
    struct Current {
        let native:AVSpeechUtterance
        let custom:TTSUtterance
    }
    public let id: TTSServiceIdentifier = "AppleTTS"
    private let cancelledSubject: TTSStatusSubject = .init()
    private let finishedSubject: TTSStatusSubject = .init()
    private let startedSubject: TTSStatusSubject = .init()
    private let speakingWordSubject: TTSWordBoundarySubject = .init()
    private let failureSubject: TTSFailedSubject = .init()
    
    private var synthesizer = AVSpeechSynthesizer()
    private var playerPublisher: AnyCancellable?
    private var db = [AVSpeechUtterance: TTSUtterance]()
    private var audioPlayer:AudioBufferPlayer
    private var cancellables = Set<AnyCancellable>()
    public var cancelledPublisher: TTSStatusPublisher  { cancelledSubject.eraseToAnyPublisher() }
    public var finishedPublisher: TTSStatusPublisher { finishedSubject.eraseToAnyPublisher() }
    public var startedPublisher: TTSStatusPublisher { startedSubject.eraseToAnyPublisher() }
    public var speakingWordPublisher: TTSWordBoundaryPublisher { speakingWordSubject.eraseToAnyPublisher() }
    public var failurePublisher: TTSFailedPublisher { failureSubject.eraseToAnyPublisher() }
    public private(set) var available:Bool = true
    public weak var fft: FFTPublisher? {
        didSet {
            audioPlayer.fft = fft
        }
    }
    public init(audioSwitchBoard:AudioSwitchboard, fft: FFTPublisher? = nil) {
        audioPlayer = AudioBufferPlayer(audioSwitchBoard)
        synthesizer = AVSpeechSynthesizer()
        
        if #available(iOS 14.0, *) {
            synthesizer.usesApplicationAudioSession = true
        }
        super.init()
        synthesizer.delegate = self
        self.fft = fft
        audioPlayer.fft = fft
        
        self.available = audioSwitchBoard.availableServices.contains(.play)
        audioSwitchBoard.$availableServices.sink { [weak self] services in
            if services.contains(.play) == false {
                self?.stop()
                self?.available = false
            } else {
                self?.available = true
            }
        }.store(in: &cancellables)
        
        playerPublisher = audioPlayer.status.sink { [weak self] (item) in
            guard let this = self else {
                return
            }
            guard let record = this.db.first(where: { $0.value.id == item.id }) else {
                return
            }
            if item.status == .cancelled {
                this.db[record.key] = nil
                this.cancelledSubject.send(record.value)
            } else if item.status == .started {
                this.startedSubject.send(record.value)
            } else if item.status == .stopped {
                this.db[record.key] = nil
                this.finishedSubject.send(record.value)
                this.stop()
            } else if item.status == .failed, let error = item.error {
                this.db.forEach { (key, value) in
                    if value.id == item.id {
                        this.failureSubject.send(TTSFailure(utterance: value, error: error))
                    }
                }
                this.db[record.key] = nil
                this.stop()
            }
        }
    }
    public func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
        audioPlayer.pause()
    }
    public func `continue`() {
        synthesizer.continueSpeaking()
        audioPlayer.continue()
    }
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer.stop()
    }
    public func start(utterance: TTSUtterance) {
        if !available {
            failureSubject.send(.init(utterance: utterance, error: AppleTTSError.unavailable))
            return
        }
        if synthesizer.isSpeaking {
            stop()
        }
        let u = AVSpeechUtterance(string: utterance.speechString)
        u.voice = bestVoice(for: utterance.voice)
        u.volume = 1
        if let r = utterance.voice.rate {
            
            print(r,Float(r),u.rate)
            u.rate = Float(r)
        }
        if let p = utterance.voice.pitch {
            u.pitchMultiplier = Float(p)
        }
        db[u] = utterance
        synthesizer.write(u) { (buff) in
            if self.db[u] == utterance {
                self.audioPlayer.play(id: utterance.id, buffer: buff)
            }
        }
    }
    private func bestVoice(for voice: TTSVoice) -> AVSpeechSynthesisVoice? {
        let lang = voice.locale.identifier.replacingOccurrences(of: "_", with: "-")
        var voices = AVSpeechSynthesisVoice.speechVoices().filter { v in v.language == lang }
        voices.sort { (v1, _) in v1.quality == .enhanced }
        for v in voices {
            if voice.gender == .other {
                return v
            } else if voice.gender == .female && v.gender == .female {
                return v
            } else if voice.gender == .male && v.gender == .male {
                return v
            }
        }
        return firstVoice(for: voice)
    }
    private func firstVoice(for voice: TTSVoice) -> AVSpeechSynthesisVoice? {
        let lang = voice.locale.languageCode ?? voice.locale.identifier.replacingOccurrences(of: "_", with: "-")
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { v in v.language.prefix(2) == lang }
        for v in voices {
            if voice.gender == .other {
                return v
            } else if voice.gender == .female && v.gender == .female {
                return v
            } else if voice.gender == .male && v.gender == .male {
                return v
            }
        }
        if !voices.isEmpty {
            return voices.first
        }
        return AVSpeechSynthesisVoice(identifier: lang)
    }
    public final func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        guard let u = db[utterance] else {
            return
        }
        guard let range = Range(characterRange, in: u.speechString) else {
            return
        }
        let word = String(u.speechString[range])
        speakingWordSubject.send(TTSWordBoundary(utterance: u, wordBoundary: TTSUtteranceWordBoundary(string: word, range: range)))
    }
}
