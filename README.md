# VoiceToTextPackage

`VoiceToTextPackage` is a Swift package designed to simplify real-time speech transcription from the microphone within your SwiftUI applications. It leverages Apple's `Speech` and `AVFoundation` frameworks to provide a streamlined API for microphone access, speech recognition, and authorization handling.

## Features

-   Real-time speech transcription from microphone input.
-   Start and stop transcription with a simple API.
-   Observable state for `transcribedText`, `isRecording`, `authorizationStatus`, and `error`.
-   Supports selecting a specific language for transcription.
-   Handles microphone and speech recognition authorization requests.
-   Provides a list of supported locales for language selection.

## Requirements

-   iOS 15.0+
-   Xcode 13.0+
-   Swift 5.5+

## Usage

### 1. Configure `Info.plist`

**This is a crucial step!** Your application needs to declare its intent to use the microphone and speech recognition. In your **main app target's** `Info.plist` file, add the following entries:

-   **Privacy - Microphone Usage Description** (`NSMicrophoneUsageDescription`)
    -   Type: String
    -   Value: `This app needs microphone access to transcribe your speech.`
-   **Privacy - Speech Recognition Usage Description** (`NSSpeechRecognitionUsageDescription`)
    -   Type: String
    -   Value: `This app uses speech recognition to convert your voice to text.`

    _Example `Info.plist` snippet (viewed as Source Code):_

    ```xml
    <key>NSMicrophoneUsageDescription</key>
    <string>This app needs microphone access to transcribe your speech.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>This app uses speech recognition to convert your voice to text.</string>
    ```

### 2. Implement in Your SwiftUI View

Import the package and use `SpeechTranscriber` as an `@StateObject`.

```swift
import SwiftUI
import VoiceToTextPackage // Import your package

struct ContentView: View {
    // Initialize with a default locale, e.g., US English (en-US)
    // You can change this to any supported locale.
    @StateObject private var speechTranscriber = SpeechTranscriber(locale: Locale(identifier: "en-US"))

    @State private var showingLocalePicker = false
    @State private var selectedLocaleIdentifier: String = "en-US" // Stores the currently chosen language

    var body: some View {
        VStack(spacing: 20) {
            // Display for transcribed text
            Text(speechTranscriber.transcribedText)
                .font(.title2)
                .padding()
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(speechTranscriber.isRecording ? .red : .clear, lineWidth: 2)
                )
                .animation(.easeOut(duration: 0.2), value: speechTranscriber.isRecording)

            // Start/Stop Transcription Button
            Button(action: {
                if speechTranscriber.isRecording {
                    speechTranscriber.stopRecording()
                } else {
                    Task {
                        // Request authorization before attempting to start
                        await speechTranscriber.requestAuthorization()
                        if speechTranscriber.authorizationStatus == .authorized {
                            do {
                                try speechTranscriber.startRecording()
                            } catch {
                                // Error will be automatically set on speechTranscriber.error
                                print("Error starting recording: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }) {
                Label(speechTranscriber.isRecording ? "Stop Transcribing" : "Start Transcribing",
                      systemImage: speechTranscriber.isRecording ? "mic.slash.fill" : "mic.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(speechTranscriber.isRecording ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(15)
            }
            .disabled(speechTranscriber.authorizationStatus != .authorized && !speechTranscriber.isRecording)
            .padding(.horizontal)

            // Button to open language selection
            Button("Select Language") {
                showingLocalePicker = true
            }
            .padding(.horizontal)
            .buttonStyle(.bordered)

            // Display any errors
            if let error = speechTranscriber.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .onAppear {
            // Request authorization when the view appears
            Task {
                await speechTranscriber.requestAuthorization()
            }
        }
        // Present the language picker sheet
        .sheet(isPresented: $showingLocalePicker) {
            LocalePickerView(selectedLocaleIdentifier: $selectedLocaleIdentifier) { newLocaleIdentifier in
                if let newLocale = Locale(identifier: newLocaleIdentifier) {
                    speechTranscriber.setLocale(newLocale)
                }
                showingLocalePicker = false
            }
        }
        // Update the transcriber's locale when a new one is selected from the picker
        .onChange(of: selectedLocaleIdentifier) { newIdentifier in
            if let newLocale = Locale(identifier: newIdentifier) {
                speechTranscriber.setLocale(newLocale)
            }
        }
    }
}

// Helper View for Language Selection (can be a separate file in your app)
struct LocalePickerView: View {
    @Binding var selectedLocaleIdentifier: String
    var onSelect: (String) -> Void

    private var sortedSupportedLocales: [Locale] {
        SpeechTranscriber.supportedLocales()
            .filter { $0.languageCode != nil && !$0.identifier.contains("@") }
            .sorted { (lhs: Locale, rhs: Locale) -> Bool in
                lhs.localizedString(forIdentifier: lhs.identifier) ?? "" < rhs.localizedString(forIdentifier: rhs.identifier) ?? ""
            }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(sortedSupportedLocales, id: \.identifier) { locale in
                    Button(action: {
                        selectedLocaleIdentifier = locale.identifier
                        onSelect(locale.identifier)
                    }) {
                        HStack {
                            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            Spacer()
                            if locale.identifier == selectedLocaleIdentifier {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Language")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
