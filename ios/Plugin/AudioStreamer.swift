import Foundation
import AVFoundation

protocol AudioStreamerDelegate: AnyObject {
    func audioStreamer(_ streamer: AudioStreamer, didReceiveAudioData data: Data, timestamp: TimeInterval, format: AudioStreamFormat)
    func audioStreamer(_ streamer: AudioStreamer, didEncounterError error: Error)
}

struct AudioStreamFormat {
    let sampleRate: Double
    let channelCount: Int
    let encoding: String
}

class AudioStreamer {
    
    weak var delegate: AudioStreamerDelegate?
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFormat: AVAudioFormat?
    private(set) var streamingOptions: StreamingOptions
    private var isStreaming = false
    private var startTime: TimeInterval = 0
    
    struct StreamingOptions {
        let sampleRate: Double
        let channelCount: Int
        let encoding: String
        let chunkDurationMs: Int
        
        init(sampleRate: Double = 16000, channelCount: Int = 1, encoding: String = "pcm16", chunkDurationMs: Int = 100) {
            self.sampleRate = sampleRate
            self.channelCount = channelCount
            self.encoding = encoding
            self.chunkDurationMs = chunkDurationMs
        }
    }
    
    init(options: StreamingOptions = StreamingOptions()) {
        self.streamingOptions = options
    }
    
    func startStreaming() throws {
        guard !isStreaming else {
            throw StreamingError.alreadyStreaming
        }
        
        // Set up audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true)
        
        // Initialize audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw StreamingError.failedToInitializeEngine
        }
        
        inputNode = audioEngine.inputNode
        
        // Configure audio format for WhisperKit compatibility
        let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: streamingOptions.sampleRate,
            channels: AVAudioChannelCount(streamingOptions.channelCount),
            interleaved: false
        )
        
        guard let format = desiredFormat else {
            throw StreamingError.invalidFormat
        }
        
        audioFormat = format
        
        // Calculate buffer size based on chunk duration
        let sampleRate = format.sampleRate
        let chunkDuration = Double(streamingOptions.chunkDurationMs) / 1000.0
        let bufferSize = AVAudioFrameCount(sampleRate * chunkDuration)
        
        startTime = Date().timeIntervalSince1970
        
        // Install tap on input node
        inputNode?.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: inputNode?.outputFormat(forBus: 0),
            block: { [weak self] buffer, time in
                self?.processAudioBuffer(buffer, time: time)
            }
        )
        
        // Start the engine
        try audioEngine.start()
        isStreaming = true
    }
    
    func stopStreaming() {
        guard isStreaming else { return }
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false)
        
        audioEngine = nil
        inputNode = nil
        audioFormat = nil
        isStreaming = false
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let audioFormat = audioFormat else { return }
        
        // Convert to desired format if needed
        let converter = AVAudioConverter(from: buffer.format, to: audioFormat)
        let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: AVAudioFrameCount(audioFormat.sampleRate * Double(streamingOptions.chunkDurationMs) / 1000.0)
        )
        
        guard let converter = converter, let convertedBuffer = convertedBuffer else {
            delegate?.audioStreamer(self, didEncounterError: StreamingError.conversionFailed)
            return
        }
        
        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if let error = error {
            delegate?.audioStreamer(self, didEncounterError: error)
            return
        }
        
        // Convert buffer to data based on encoding type
        let data: Data
        switch streamingOptions.encoding {
        case "pcm16":
            data = convertFloatBufferToPCM16(convertedBuffer)
        case "pcm8":
            data = convertFloatBufferToPCM8(convertedBuffer)
        case "float32":
            data = convertFloatBufferToData(convertedBuffer)
        default:
            data = convertFloatBufferToPCM16(convertedBuffer)
        }
        
        let timestamp = Date().timeIntervalSince1970 - startTime
        let format = AudioStreamFormat(
            sampleRate: audioFormat.sampleRate,
            channelCount: Int(audioFormat.channelCount),
            encoding: streamingOptions.encoding
        )
        
        delegate?.audioStreamer(self, didReceiveAudioData: data, timestamp: timestamp, format: format)
    }
    
    private func convertFloatBufferToPCM16(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let floatChannelData = buffer.floatChannelData else {
            return Data()
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var data = Data()
        
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                let sample = floatChannelData[channel][frame]
                let int16Sample = Int16(max(-32768, min(32767, sample * 32767)))
                withUnsafeBytes(of: int16Sample) { bytes in
                    data.append(contentsOf: bytes)
                }
            }
        }
        
        return data
    }
    
    private func convertFloatBufferToPCM8(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let floatChannelData = buffer.floatChannelData else {
            return Data()
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var data = Data()
        
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                let sample = floatChannelData[channel][frame]
                let uint8Sample = UInt8(max(0, min(255, (sample + 1.0) * 127.5)))
                data.append(uint8Sample)
            }
        }
        
        return data
    }
    
    private func convertFloatBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let floatChannelData = buffer.floatChannelData else {
            return Data()
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var data = Data()
        
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                let sample = floatChannelData[channel][frame]
                withUnsafeBytes(of: sample) { bytes in
                    data.append(contentsOf: bytes)
                }
            }
        }
        
        return data
    }
}

enum StreamingError: LocalizedError {
    case alreadyStreaming
    case failedToInitializeEngine
    case invalidFormat
    case conversionFailed
    
    var errorDescription: String? {
        switch self {
        case .alreadyStreaming:
            return "Audio streaming is already active"
        case .failedToInitializeEngine:
            return "Failed to initialize audio engine"
        case .invalidFormat:
            return "Invalid audio format specified"
        case .conversionFailed:
            return "Failed to convert audio buffer"
        }
    }
}