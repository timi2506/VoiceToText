import Foundation
import Speech
import AVFoundation
import Combine

public class SpeechTranscriber: NSObject, ObservableObject {

    @Published public var transcribedText: String = ""
    @Published public var isRecording: Bool = false
    @Published public var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published public var error: Error?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var currentLocale: Locale

    // New property for inactivity timeout
    public var silenceTimeoutDuration: TimeInterval = 2.0 // Default to 2 seconds of inactivity

    public init(locale: Locale = Locale.current) {
        self.currentLocale = locale
        super.init()

        speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
        speechRecognizer?.delegate = self
    }

    public func requestAuthorization() async {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                self.authorizationStatus = authStatus
                if authStatus == .denied || authStatus == .restricted {
                    self.error = SpeechTranscriberError.speechRecognitionDenied
                }
            }
        }

        await AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.error = SpeechTranscriberError.microphoneAccessDenied
                    self.authorizationStatus = .denied
                }
            }
        }
    }

    public func startRecording() throws {
        error = nil
        transcribedText = ""

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechTranscriberError.recognizerNotAvailable
        }
        guard authorizationStatus == .authorized else {
            throw SpeechTranscriberError.notAuthorized
        }

        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = SpeechTranscriberError.audioSessionSetupFailed(error)
            throw SpeechTranscriberError.audioSessionSetupFailed(error)
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechTranscriberError.recognitionRequestCreationFailed
        }
        recognitionRequest.shouldReportPartialResults = true

        // --- NEW LINE: Set the endOfSpeechTimeout ---
        recognitionRequest.endOfSpeechTimeout = silenceTimeoutDuration


        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = SpeechTranscriberError.audioEngineStartFailed(error)
            throw SpeechTranscriberError.audioEngineStartFailed(error)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, taskError in
            guard let self = self else { return }

            var isFinal = false
            if let result = result {
                self.transcribedText = result.bestTranscription.formattedString
                isFinal = result.isFinal
            }

            // The 'taskError' will be non-nil if the endOfSpeechTimeout is reached
            // or if other errors occur. If isFinal is true, it means speech completed.
            if taskError != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                self.isRecording = false

                if let taskError = taskError {
                    // Check if the error is due to silence timeout
                    if let sferror = taskError as? SFSpeechRecognizerError, sferror.code == .endOfSpeechDetected {
                        // This is expected behavior for silence timeout, so we don't necessarily set `self.error`
                        // unless you want to explicitly inform the user that it stopped due to silence.
                        print("Transcription stopped due to inactivity.")
                    } else {
                        self.error = SpeechTranscriberError.recognitionFailed(taskError)
                    }
                }
            }
        }
        isRecording = true
    }

    public func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Error deactivating audio session: \(error.localizedDescription)")
        }
    }

    public func setLocale(_ newLocale: Locale) {
        if currentLocale != newLocale {
            stopRecording()
            currentLocale = newLocale
            speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
            speechRecognizer?.delegate = self
        }
    }

    public static func supportedLocales() -> Set<Locale> {
        return SFSpeechRecognizer.supportedLocales()
    }

    deinit {
        stopRecording()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
}

extension SpeechTranscriber: SFSpeechRecognizerDelegate {
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            DispatchQueue.main.async {
                self.error = SpeechTranscriberError.recognizerNotAvailable
                if self.isRecording {
                    self.stopRecording()
                }
            }
        } else {
            if let currentError = self.error as? SpeechTranscriberError, case .recognizerNotAvailable = currentError {
                self.error = nil
            }
        }
    }
}

public enum SpeechTranscriberError: Error, LocalizedError {
    case notAuthorized
    case speechRecognitionDenied
    case microphoneAccessDenied
    case recognizerNotAvailable
    case audioSessionSetupFailed(Error)
    case audioEngineStartFailed(Error)
    case recognitionRequestCreationFailed
    case recognitionFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition and/or microphone access not authorized. Please enable in device Settings > Privacy & Security."
        case .speechRecognitionDenied:
            return "Speech recognition access denied. Please enable in device Settings > Privacy & Security > Speech Recognition."
        case .microphoneAccessDenied:
            return "Microphone access denied. Please enable in device Settings > Privacy & Security > Microphone."
        case .recognizerNotAvailable:
            return "Speech recognizer is not currently available (e.g., no internet, or language not supported offline)."
        case .audioSessionSetupFailed(let underlyingError):
            return "Failed to set up audio session: \(underlyingError.localizedDescription)"
        case .audioEngineStartFailed(let underlyingError):
            return "Failed to start audio engine: \(underlyingError.localizedDescription)"
        case .recognitionRequestCreationFailed:
            return "Failed to create speech recognition request."
        case .recognitionFailed(let underlyingError):
            return "Speech recognition failed: \(underlyingError.localizedDescription)"
        }
    }
}
