import AVFoundation
import Foundation

// List all available voices and their identifiers
let voices = AVSpeechSynthesisVoice.speechVoices()

struct VoiceRecord: Codable {
    let identifier: String
    let name: String
    let language: String
    let quality: Int
    let gender: String
}

if CommandLine.arguments.contains("--json") {
    let records = voices.map { voice in
        let gender: String
        switch voice.gender {
        case .male: gender = "male"
        case .female: gender = "female"
        default: gender = "neutral"
        }
        return VoiceRecord(
            identifier: voice.identifier,
            name: voice.name,
            language: voice.language,
            quality: voice.quality.rawValue,
            gender: gender)
    }
    let data = try JSONEncoder().encode(records)
    print(String(data: data, encoding: .utf8)!)
    exit(EXIT_SUCCESS)
}

print("Available Voices and Their Identifiers:")

for voice in voices {
    print("Language: \(voice.language), Identifier: \(voice.identifier), Name: \(voice.name), Quality: \(voice.quality.rawValue)")
}

// Optionally, you can speak a sample text using each voice
let synthesizer = AVSpeechSynthesizer()
for voice in voices {
    let utterance = AVSpeechUtterance(string: "Hello, this is a sample text in \(voice.language).")
    utterance.voice = voice
    synthesizer.speak(utterance)
}
