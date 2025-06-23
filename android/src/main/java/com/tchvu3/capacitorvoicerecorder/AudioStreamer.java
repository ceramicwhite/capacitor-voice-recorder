package com.tchvu3.capacitorvoicerecorder;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Base64;
import android.util.Log;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public class AudioStreamer {
    private static final String TAG = "AudioStreamer";
    
    public interface AudioStreamerListener {
        void onAudioData(byte[] data, long timestamp, int duration, AudioStreamFormat format);
        void onError(String message, String code);
    }
    
    public static class AudioStreamFormat {
        public final int sampleRate;
        public final int channelCount;
        public final String encoding;
        
        public AudioStreamFormat(int sampleRate, int channelCount, String encoding) {
            this.sampleRate = sampleRate;
            this.channelCount = channelCount;
            this.encoding = encoding;
        }
    }
    
    public static class StreamingOptions {
        public final int sampleRate;
        public final int channelCount;
        public final String encoding;
        public final int chunkDurationMs;
        
        public StreamingOptions(int sampleRate, int channelCount, String encoding, int chunkDurationMs) {
            this.sampleRate = sampleRate;
            this.channelCount = channelCount;
            this.encoding = encoding;
            this.chunkDurationMs = chunkDurationMs;
        }
        
        public static StreamingOptions getDefault() {
            return new StreamingOptions(16000, 1, "pcm16", 100);
        }
    }
    
    private AudioStreamerListener listener;
    private AudioRecord audioRecord;
    private StreamingOptions options;
    private HandlerThread recordingThread;
    private Handler recordingHandler;
    private boolean isStreaming = false;
    private long startTime;
    
    public AudioStreamer(StreamingOptions options) {
        this.options = options;
    }
    
    public void setListener(AudioStreamerListener listener) {
        this.listener = listener;
    }
    
    public void startStreaming() throws Exception {
        if (isStreaming) {
            throw new Exception("Already streaming");
        }
        
        int channelConfig = options.channelCount == 1 ? 
            AudioFormat.CHANNEL_IN_MONO : AudioFormat.CHANNEL_IN_STEREO;
        
        int audioFormat = getAudioFormat();
        
        int minBufferSize = AudioRecord.getMinBufferSize(
            options.sampleRate,
            channelConfig,
            audioFormat
        );
        
        if (minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
            throw new Exception("Invalid audio configuration");
        }
        
        // Calculate buffer size for chunk duration
        int bytesPerSample = getBytesPerSample();
        int samplesPerChunk = (options.sampleRate * options.chunkDurationMs) / 1000;
        int bufferSize = Math.max(minBufferSize, samplesPerChunk * bytesPerSample * options.channelCount);
        
        audioRecord = new AudioRecord(
            MediaRecorder.AudioSource.MIC,
            options.sampleRate,
            channelConfig,
            audioFormat,
            bufferSize
        );
        
        if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
            audioRecord.release();
            throw new Exception("Failed to initialize AudioRecord");
        }
        
        startTime = System.currentTimeMillis();
        
        recordingThread = new HandlerThread("AudioStreamerThread");
        recordingThread.start();
        recordingHandler = new Handler(recordingThread.getLooper());
        
        audioRecord.startRecording();
        isStreaming = true;
        
        recordingHandler.post(recordingRunnable);
    }
    
    public void stopStreaming() {
        if (!isStreaming) {
            return;
        }
        
        isStreaming = false;
        
        if (recordingHandler != null) {
            recordingHandler.removeCallbacks(recordingRunnable);
        }
        
        if (audioRecord != null) {
            try {
                audioRecord.stop();
            } catch (IllegalStateException e) {
                Log.e(TAG, "Error stopping audio record", e);
            }
            audioRecord.release();
            audioRecord = null;
        }
        
        if (recordingThread != null) {
            recordingThread.quitSafely();
            recordingThread = null;
        }
    }
    
    private final Runnable recordingRunnable = new Runnable() {
        @Override
        public void run() {
            if (!isStreaming || audioRecord == null) {
                return;
            }
            
            int bytesPerSample = getBytesPerSample();
            int samplesPerChunk = (options.sampleRate * options.chunkDurationMs) / 1000;
            int bufferSize = samplesPerChunk * bytesPerSample * options.channelCount;
            
            byte[] buffer = new byte[bufferSize];
            
            int bytesRead = audioRecord.read(buffer, 0, bufferSize);
            
            if (bytesRead > 0) {
                byte[] processedData = processAudioData(buffer, bytesRead);
                long timestamp = System.currentTimeMillis() - startTime;
                
                AudioStreamFormat format = new AudioStreamFormat(
                    options.sampleRate,
                    options.channelCount,
                    options.encoding
                );
                
                if (listener != null) {
                    listener.onAudioData(processedData, timestamp, options.chunkDurationMs, format);
                }
            } else if (bytesRead < 0) {
                if (listener != null) {
                    listener.onError("Error reading audio data", String.valueOf(bytesRead));
                }
            }
            
            if (isStreaming) {
                recordingHandler.post(this);
            }
        }
    };
    
    private int getAudioFormat() {
        switch (options.encoding) {
            case "pcm8":
                return AudioFormat.ENCODING_PCM_8BIT;
            case "float32":
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    return AudioFormat.ENCODING_PCM_FLOAT;
                }
                // Fall through to pcm16 if float32 not supported
            case "pcm16":
            default:
                return AudioFormat.ENCODING_PCM_16BIT;
        }
    }
    
    private int getBytesPerSample() {
        switch (options.encoding) {
            case "pcm8":
                return 1;
            case "float32":
                return 4;
            case "pcm16":
            default:
                return 2;
        }
    }
    
    private byte[] processAudioData(byte[] buffer, int bytesRead) {
        // If encoding matches native format, return as-is
        if (options.encoding.equals("pcm16") && getAudioFormat() == AudioFormat.ENCODING_PCM_16BIT) {
            byte[] result = new byte[bytesRead];
            System.arraycopy(buffer, 0, result, 0, bytesRead);
            return result;
        }
        
        // Convert between formats if needed
        if (options.encoding.equals("float32") && Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            // Convert PCM16 to Float32
            return convertPCM16ToFloat32(buffer, bytesRead);
        }
        
        // Return original data for other cases
        byte[] result = new byte[bytesRead];
        System.arraycopy(buffer, 0, result, 0, bytesRead);
        return result;
    }
    
    private byte[] convertPCM16ToFloat32(byte[] pcm16Data, int length) {
        ByteBuffer pcm16Buffer = ByteBuffer.wrap(pcm16Data, 0, length);
        pcm16Buffer.order(ByteOrder.LITTLE_ENDIAN);
        
        ByteBuffer floatBuffer = ByteBuffer.allocate(length * 2);
        floatBuffer.order(ByteOrder.LITTLE_ENDIAN);
        
        while (pcm16Buffer.hasRemaining()) {
            short sample = pcm16Buffer.getShort();
            float floatSample = sample / 32768.0f;
            floatBuffer.putFloat(floatSample);
        }
        
        return floatBuffer.array();
    }
    
    public boolean isStreaming() {
        return isStreaming;
    }
}