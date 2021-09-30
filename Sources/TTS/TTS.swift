import Combine
import Foundation
import SwiftUI

public typealias TTSWordBoundaryPublisher = AnyPublisher<TTSWordBoundary, Never>
public typealias TTSStatusPublisher = AnyPublisher<TTSUtterance, Never>
public typealias TTSMiscPublisher = AnyPublisher<Void, Never>
public typealias TTSFailedPublisher = AnyPublisher<TTSFailure, Never>

public typealias TTSWordBoundarySubject = PassthroughSubject<TTSWordBoundary, Never>
public typealias TTSStatusSubject = PassthroughSubject<TTSUtterance, Never>
public typealias TTSMiscSubject = PassthroughSubject<Void, Never>
public typealias TTSFailedSubject = PassthroughSubject<TTSFailure, Never>

public enum TTSGender: String, Codable, CaseIterable, Identifiable {
    public var id: String {
        return rawValue
    }
    case female
    case male
    case other
}
public enum TTSError: Error {
    case utteranceNotFound
    case missingTTSService
}
public struct TTSVoice {
    public var id: String = "default"
    public var name: String = "default"
    public var gender: TTSGender = .other
    public var pitch: Double? = nil
    public var rate: Double? = nil
    public var locale: Locale
    public init(gender: TTSGender, locale: Locale) {
        self.gender = gender
        self.locale = locale
    }
    public init(id: String = "default", name: String = "default", gender: TTSGender = .other, rate:Double? = nil, pitch:Double? = nil, locale: Locale) {
        self.id = id
        self.name = name
        self.gender = gender
        self.locale = locale
        self.rate = rate
        self.pitch = pitch
    }
}
public struct TTSFailure {
    public var utterance: TTSUtterance
    public var error: Error
    public init(utterance: TTSUtterance, error: Error) {
        self.utterance = utterance
        self.error = error
    }
}
public struct TTSWordBoundary {
    public let utterance: TTSUtterance
    public let wordBoundary: TTSUtteranceWordBoundary
    public init(utterance: TTSUtterance, wordBoundary: TTSUtteranceWordBoundary) {
        self.utterance = utterance
        self.wordBoundary = wordBoundary
    }
}
public struct TTSUtteranceWordBoundary {
    public let string: String
    public let range: Range<String.Index>
    public init(string: String, range: Range<String.Index>) {
        self.string = string
        self.range = range
    }
}
public enum TTSUtteranceStatus: String, Equatable {
    case none
    case queued
    case preparing
    case paused
    case finished
    case speaking
    case cancelled
}
public typealias TTSServiceIdentifier = String
public protocol TTSService : AnyObject {
    var id:TTSServiceIdentifier { get }
    var available:Bool { get }
    var cancelledPublisher: TTSStatusPublisher { get }
    var finishedPublisher: TTSStatusPublisher { get }
    var startedPublisher: TTSStatusPublisher { get }
    var speakingWordPublisher: TTSWordBoundaryPublisher { get }
    var failurePublisher: TTSFailedPublisher { get }
    func pause()
    func `continue`()
    func stop()
    func start(utterance: TTSUtterance)
}
public struct TTSUtterance: Identifiable, Equatable {
    public static func == (lhs: TTSUtterance, rhs: TTSUtterance) -> Bool {
        lhs.id == rhs.id
    }
    internal var statusSubject = CurrentValueSubject<TTSUtteranceStatus,Never>(.none)
    internal var wordBoundarySubject = PassthroughSubject<TTSUtteranceWordBoundary,Never>()
    internal var failureSubject = PassthroughSubject<Error,Never>()
    public let id = UUID().uuidString
    public let tag:String?
    public let speechString: String
    public let voice: TTSVoice
    public var statusPublisher:AnyPublisher<TTSUtteranceStatus,Never>
    public var wordBoundaryPublisher:AnyPublisher<TTSUtteranceWordBoundary,Never>
    public var failurePublisher:AnyPublisher<Error,Never>
    public init(_ speechString: String, voice: TTSVoice,tag:String? = nil) {
        self.speechString = speechString
        self.voice = voice
        self.tag = tag
        self.statusPublisher = statusSubject.eraseToAnyPublisher()
        self.wordBoundaryPublisher = wordBoundarySubject.eraseToAnyPublisher()
        self.failurePublisher = failureSubject.eraseToAnyPublisher()
    }
    func updateStatus(_ status:TTSUtteranceStatus) {
        if statusSubject.value != status {
            statusSubject.send(status)
        }
    }
    public init(_ speechString: String, gender: TTSGender = .female, locale: Locale = .current, rate:Double? = nil, pitch:Double? = nil, tag:String? = nil) {
        self.speechString = speechString
        self.tag = tag
        self.voice = TTSVoice(gender: gender, rate: rate, pitch: pitch, locale: locale)
        self.statusPublisher = statusSubject.eraseToAnyPublisher()
        self.wordBoundaryPublisher = wordBoundarySubject.eraseToAnyPublisher()
        self.failurePublisher = failureSubject.eraseToAnyPublisher()
    }
    
}

public class TTS: ObservableObject {
    private var queue: [TTSUtterance] = []
    @Published public private(set) var isSpeaking: Bool = false
    @Published public private(set) var currentlySpeaking: TTSUtterance?
    @Published public var disabled: Bool = false {
        didSet {
            if disabled {
                cancelAll()
            }
        }
    }
    
    
    private var publishers = Set<AnyCancellable>()
    
    private let queuedSubject: TTSStatusSubject = .init()
    private let preparingSubject: TTSStatusSubject = .init()
    private let speakingSubject: TTSStatusSubject = .init()
    private let pausedSubject: TTSStatusSubject = .init()
    private let cancelledSubject: TTSStatusSubject = .init()
    private let finishedSubject: TTSStatusSubject = .init()
    private let finishedQueueSubject: TTSMiscSubject = .init()
    private let failedSubject: TTSFailedSubject = .init()
    private let speakingWordSubject: TTSWordBoundarySubject = .init()
    
    public var queued: TTSStatusPublisher  { return queuedSubject.eraseToAnyPublisher()}
    public var preparing: TTSStatusPublisher  { return preparingSubject.eraseToAnyPublisher()}
    public var speaking: TTSStatusPublisher  { return speakingSubject.eraseToAnyPublisher()}
    public var paused: TTSStatusPublisher  { return pausedSubject.eraseToAnyPublisher()}
    public var cancelled: TTSStatusPublisher  { return cancelledSubject.eraseToAnyPublisher()}
    public var finished: TTSStatusPublisher  { return finishedSubject.eraseToAnyPublisher()}
    public var finishedQueue: TTSMiscPublisher  { return finishedQueueSubject.eraseToAnyPublisher()}
    public var failed: TTSFailedPublisher  { return failedSubject.eraseToAnyPublisher()}
    public var speakingWord: TTSWordBoundaryPublisher  { return speakingWordSubject.eraseToAnyPublisher()}
    
    private var currentService:TTSService? = nil
    private var selectedService:TTSService?
    private var services = [TTSService]()
    
    private var bestAvailableService:TTSService? {
        guard let service = selectedService, service.available == true else {
            return services.first(where: { $0.available })
        }
        return selectedService
    }
    
    private func dequeue(_ utterance: TTSUtterance) {
        queue.removeAll { $0.id == utterance.id }
    }
    private func runQueue() {
        if isSpeaking {
            return
        }
        guard let utterance = queue.first else {
            notSpeaking()
            finishedQueueSubject.send()
            return
        }
        guard let service = bestAvailableService else {
            notSpeaking()
            failed(TTSFailure.init(utterance: utterance, error: TTSError.missingTTSService))
            return
        }
        currentService = service
        currentlySpeaking = utterance
        isSpeaking = true
        preparingSubject.send(utterance)
        utterance.updateStatus(.preparing)
        service.start(utterance: utterance)
    }
    private func notSpeaking() {
        currentService = nil
        currentlySpeaking = nil
        isSpeaking = false
    }
    
    private func cancelled(_ utterance:TTSUtterance) {
        cancelledSubject.send(utterance)
        utterance.updateStatus(.cancelled)
        dequeue(utterance)
        if currentlySpeaking == utterance {
            notSpeaking()
            runQueue()
        }
    }
    private func failed(_ failure:TTSFailure) {
        failedSubject.send(failure)
        failure.utterance.failureSubject.send(failure.error)
        dequeue(failure.utterance)
        notSpeaking()
        runQueue()
    }
    private func finished(_ utterance:TTSUtterance) {
        finishedSubject.send(utterance)
        utterance.updateStatus(.finished)
        dequeue(utterance)
        notSpeaking()
        runQueue()
    }
    private func started(_ utterance:TTSUtterance) {
        speakingSubject.send(utterance)
        utterance.updateStatus(.speaking)
    }
    private func speakingWord(_ wordBoundary:TTSWordBoundary) {
        speakingWordSubject.send(wordBoundary)
        wordBoundary.utterance.wordBoundarySubject.send(wordBoundary.wordBoundary)
    }
    
    public init(_ services:TTSService...) {
        services.forEach { s in
            self.add(service: s)
        }
        self.selectedService = services.first(where: { $0.available })
    }
    public init(_ services:[TTSService]) {
        services.forEach { s in
            self.add(service: s)
        }
        self.selectedService = services.first(where: { $0.available })
    }

    public func add(service:TTSService, select:Bool = false) {
        self.services.append(service)
        service.cancelledPublisher.receive(on: DispatchQueue.main).sink { [weak self] u in
            self?.cancelled(u)
        }.store(in: &publishers)
        service.finishedPublisher.receive(on: DispatchQueue.main).sink { [weak self] u in
            self?.finished(u)
        }.store(in: &publishers)
        service.startedPublisher.receive(on: DispatchQueue.main).sink { [weak self] u in
            self?.started(u)
        }.store(in: &publishers)
        service.speakingWordPublisher.receive(on: DispatchQueue.main).sink { [weak self] w in
            self?.speakingWord(w)
        }.store(in: &publishers)
        service.failurePublisher.receive(on: DispatchQueue.main).sink { [weak self] f in
            self?.failed(f)
        }.store(in: &publishers)
        if select {
            self.select(service: service)
        }
    }
    public func remove(service:TTSService) {
        if let index = services.firstIndex(where: { $0.id == service.id }) {
            self.services.remove(at: index)
            if selectedService?.id == service.id {
                self.selectedService = services.first
            }
        }
    }
    public func remove(service identifier:TTSServiceIdentifier) {
        if let index = services.firstIndex(where: { $0.id == identifier }) {
            self.services.remove(at: index)
            if selectedService?.id == identifier {
                self.selectedService = services.first
            }
        }
    }
    public func select(service:TTSService) {
        if let s = services.first(where: { $0.id == service.id }) {
            self.selectedService = s
        } else {
            self.add(service: service)
            if service.available {
                self.selectedService = service
            } else {
                debugPrint("trying to add an unavailable TTS as selected")
            }
        }
    }
    public func select(service identifier:TTSServiceIdentifier) {
        if let s = services.first(where: { $0.id == identifier }) {
            if s.available {
                self.selectedService = s
            } else {
                debugPrint("trying to add an unavailable TTS as selected")
            }
        } else {
            debugPrint("no such service")
        }
    }
    public final func queue(_ utterances: [TTSUtterance]) {
        if disabled {
            return
        }
        for utterance in utterances {
            queue(utterance)
        }
    }
    public final func queue(_ utterance: TTSUtterance) {
        if disabled {
            return
        }
        queue.append(utterance)
        queuedSubject.send(utterance)
        utterance.updateStatus(.queued)
        runQueue()
    }
    public final func play(_ utterances: [TTSUtterance]) {
        cancelAll()
        queue(utterances)
    }
    public final func play(_ utterance: TTSUtterance) {
        cancelAll()
        queue(utterance)
    }
    public final func cancelAll() {
        queue.forEach { u in
            cancelledSubject.send(u)
            u.updateStatus(.cancelled)
        }
        queue.removeAll()
        currentService?.stop()
        notSpeaking()
    }
    public final func cancel(_ utterance: TTSUtterance) {
        if utterance.id == currentlySpeaking?.id {
            currentService?.stop()
        } else {
            dequeue(utterance)
        }
    }
    public final func pause() {
        guard let u = currentlySpeaking else {
            return
        }
        currentService?.pause()
        pausedSubject.send(u)
        u.updateStatus(.paused)
    }
    public final func `continue`() {
        guard let u = currentlySpeaking else {
            return
        }
        currentService?.continue()
        speakingSubject.send(u)
        u.updateStatus(.speaking)
    }
}
extension Collection {

    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Bool {
        return (indices.contains(index) ? self[index] : nil) != nil
    }
}
