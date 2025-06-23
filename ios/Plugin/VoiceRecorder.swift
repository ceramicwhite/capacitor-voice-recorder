import Foundation
import AVFoundation
import Capacitor

@objc(VoiceRecorder)
public class VoiceRecorder: CAPPlugin {

    private var customMediaRecorder: CustomMediaRecorder?
    private var audioStreamer: AudioStreamer?
    private var isStreaming = false

    @objc func canDeviceVoiceRecord(_ call: CAPPluginCall) {
        call.resolve(ResponseGenerator.successResponse())
    }

    @objc func requestAudioRecordingPermission(_ call: CAPPluginCall) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                call.resolve(ResponseGenerator.successResponse())
            } else {
                call.resolve(ResponseGenerator.failResponse())
            }
        }
    }

    @objc func hasAudioRecordingPermission(_ call: CAPPluginCall) {
        call.resolve(ResponseGenerator.fromBoolean(doesUserGaveAudioRecordingPermission()))
    }

    @objc func startRecording(_ call: CAPPluginCall) {
        if !doesUserGaveAudioRecordingPermission() {
            call.reject(Messages.MISSING_PERMISSION)
            return
        }

        if customMediaRecorder != nil || isStreaming {
            call.reject(Messages.ALREADY_RECORDING)
            return
        }

        customMediaRecorder = CustomMediaRecorder()
        if customMediaRecorder == nil {
            call.reject(Messages.CANNOT_RECORD_ON_THIS_PHONE)
            return
        }

        let directory: String? = call.getString("directory")
        let subDirectory: String? = call.getString("subDirectory")
        let recordOptions = RecordOptions(directory: directory, subDirectory: subDirectory)
        let successfullyStartedRecording = customMediaRecorder!.startRecording(recordOptions: recordOptions)
        if successfullyStartedRecording == false {
            customMediaRecorder = nil
            call.reject(Messages.CANNOT_RECORD_ON_THIS_PHONE)
        } else {
            call.resolve(ResponseGenerator.successResponse())
        }
    }

    @objc func stopRecording(_ call: CAPPluginCall) {
        if customMediaRecorder == nil {
            call.reject(Messages.RECORDING_HAS_NOT_STARTED)
            return
        }

        customMediaRecorder?.stopRecording()

        let audioFileUrl = customMediaRecorder?.getOutputFile()
        if audioFileUrl == nil {
            customMediaRecorder = nil
            call.reject(Messages.FAILED_TO_FETCH_RECORDING)
            return
        }

        var path = audioFileUrl!.lastPathComponent
        if let subDirectory = customMediaRecorder?.options?.subDirectory {
            path = subDirectory + "/" + path
        }

        let sendDataAsBase64 = customMediaRecorder?.options?.directory == nil
        let recordData = RecordData(
            recordDataBase64: sendDataAsBase64 ? readFileAsBase64(audioFileUrl) : nil,
            mimeType: "audio/aac",
            msDuration: getMsDurationOfAudioFile(audioFileUrl),
            path: sendDataAsBase64 ? nil : path
        )
        customMediaRecorder = nil
        if (sendDataAsBase64 && recordData.recordDataBase64 == nil) || recordData.msDuration < 0 {
            call.reject(Messages.EMPTY_RECORDING)
        } else {
            call.resolve(ResponseGenerator.dataResponse(recordData.toDictionary()))
        }
    }

    @objc func pauseRecording(_ call: CAPPluginCall) {
        if customMediaRecorder == nil {
            call.reject(Messages.RECORDING_HAS_NOT_STARTED)
        } else {
            call.resolve(ResponseGenerator.fromBoolean(customMediaRecorder?.pauseRecording() ?? false))
        }
    }

    @objc func resumeRecording(_ call: CAPPluginCall) {
        if customMediaRecorder == nil {
            call.reject(Messages.RECORDING_HAS_NOT_STARTED)
        } else {
            call.resolve(ResponseGenerator.fromBoolean(customMediaRecorder?.resumeRecording() ?? false))
        }
    }

    @objc func getCurrentStatus(_ call: CAPPluginCall) {
        if isStreaming {
            call.resolve(ResponseGenerator.statusResponse(CurrentRecordingStatus.STREAMING))
        } else if customMediaRecorder == nil {
            call.resolve(ResponseGenerator.statusResponse(CurrentRecordingStatus.NONE))
        } else {
            call.resolve(ResponseGenerator.statusResponse(customMediaRecorder?.getCurrentStatus() ?? CurrentRecordingStatus.NONE))
        }
    }

    @objc func startStreaming(_ call: CAPPluginCall) {
        if !doesUserGaveAudioRecordingPermission() {
            call.reject(Messages.MISSING_PERMISSION)
            return
        }

        if customMediaRecorder != nil || isStreaming {
            call.reject(Messages.ALREADY_RECORDING)
            return
        }

        // Parse streaming options
        let sampleRate = call.getDouble("sampleRate") ?? 16000
        let channelCount = call.getInt("channelCount") ?? 1
        let encoding = call.getString("encoding") ?? "pcm16"
        let chunkDurationMs = call.getInt("chunkDurationMs") ?? 100

        let options = AudioStreamer.StreamingOptions(
            sampleRate: sampleRate,
            channelCount: channelCount,
            encoding: encoding,
            chunkDurationMs: chunkDurationMs
        )

        audioStreamer = AudioStreamer(options: options)
        audioStreamer?.delegate = self

        do {
            try audioStreamer?.startStreaming()
            isStreaming = true
            call.resolve(ResponseGenerator.successResponse())
        } catch {
            audioStreamer = nil
            call.reject("STREAMING_FAILED", error.localizedDescription, error)
        }
    }

    @objc func stopStreaming(_ call: CAPPluginCall) {
        if !isStreaming {
            call.reject("STREAMING_NOT_STARTED", "Audio streaming has not been started")
            return
        }

        audioStreamer?.stopStreaming()
        audioStreamer = nil
        isStreaming = false
        call.resolve(ResponseGenerator.successResponse())
    }

    func doesUserGaveAudioRecordingPermission() -> Bool {
        return AVAudioSession.sharedInstance().recordPermission == AVAudioSession.RecordPermission.granted
    }

    func readFileAsBase64(_ filePath: URL?) -> String? {
        if filePath == nil {
            return nil
        }

        do {
            let fileData = try Data.init(contentsOf: filePath!)
            let fileStream = fileData.base64EncodedString(options: NSData.Base64EncodingOptions.init(rawValue: 0))
            return fileStream
        } catch {}

        return nil
    }

    func getMsDurationOfAudioFile(_ filePath: URL?) -> Int {
        if filePath == nil {
            return -1
        }
        return Int(CMTimeGetSeconds(AVURLAsset(url: filePath!).duration) * 1000)
    }

}

// MARK: - AudioStreamerDelegate
extension VoiceRecorder: AudioStreamerDelegate {
    func audioStreamer(_ streamer: AudioStreamer, didReceiveAudioData data: Data, timestamp: TimeInterval, format: AudioStreamFormat) {
        let base64Data = data.base64EncodedString()
        let chunkData: [String: Any] = [
            "data": base64Data,
            "timestamp": Int(timestamp * 1000), // Convert to milliseconds
            "duration": streamer.streamingOptions.chunkDurationMs,
            "format": [
                "sampleRate": format.sampleRate,
                "channelCount": format.channelCount,
                "encoding": format.encoding
            ]
        ]
        
        notifyListeners("audioChunk", data: chunkData)
    }
    
    func audioStreamer(_ streamer: AudioStreamer, didEncounterError error: Error) {
        let errorData: [String: Any] = [
            "message": error.localizedDescription,
            "code": (error as NSError).code.description
        ]
        
        notifyListeners("streamError", data: errorData)
    }
}
