import { VoiceRecorder } from 'capacitor-voice-recorder';

// Example of using the voice recorder plugin with streaming for WhisperKit integration

class AudioStreamer {
  constructor() {
    this.isStreaming = false;
    this.audioChunks = [];
    this.listeners = {};
  }

  async checkPermissions() {
    try {
      const hasPermission = await VoiceRecorder.hasAudioRecordingPermission();
      
      if (!hasPermission.value) {
        const permissionStatus = await VoiceRecorder.requestAudioRecordingPermission();
        return permissionStatus.value;
      }
      
      return true;
    } catch (error) {
      console.error('Permission check failed:', error);
      return false;
    }
  }

  async startStreaming(options = {}) {
    if (this.isStreaming) {
      console.warn('Already streaming');
      return;
    }

    const hasPermission = await this.checkPermissions();
    if (!hasPermission) {
      throw new Error('Audio recording permission denied');
    }

    // Configure streaming options for WhisperKit
    const streamingOptions = {
      sampleRate: options.sampleRate || 16000, // WhisperKit expects 16kHz
      channelCount: options.channelCount || 1, // Mono audio
      encoding: options.encoding || 'pcm16', // 16-bit PCM
      chunkDurationMs: options.chunkDurationMs || 100 // 100ms chunks
    };

    // Set up audio chunk listener
    this.audioChunkListener = await VoiceRecorder.addListener('audioChunk', (chunk) => {
      this.handleAudioChunk(chunk);
    });

    // Set up error listener
    this.errorListener = await VoiceRecorder.addListener('streamError', (error) => {
      this.handleStreamError(error);
    });

    try {
      const result = await VoiceRecorder.startStreaming(streamingOptions);
      if (result.value) {
        this.isStreaming = true;
        this.audioChunks = [];
        console.log('Audio streaming started');
      } else {
        throw new Error('Failed to start streaming');
      }
    } catch (error) {
      await this.cleanup();
      throw error;
    }
  }

  async stopStreaming() {
    if (!this.isStreaming) {
      console.warn('Not currently streaming');
      return;
    }

    try {
      await VoiceRecorder.stopStreaming();
      this.isStreaming = false;
      console.log('Audio streaming stopped');
      
      // Clean up listeners
      await this.cleanup();
      
      return this.audioChunks;
    } catch (error) {
      console.error('Failed to stop streaming:', error);
      throw error;
    }
  }

  async cleanup() {
    if (this.audioChunkListener) {
      await this.audioChunkListener.remove();
      this.audioChunkListener = null;
    }
    
    if (this.errorListener) {
      await this.errorListener.remove();
      this.errorListener = null;
    }
  }

  handleAudioChunk(chunk) {
    // Store the chunk
    this.audioChunks.push(chunk);
    
    // Notify any registered handlers
    if (this.listeners.onAudioChunk) {
      this.listeners.onAudioChunk(chunk);
    }
    
    // Log chunk info
    console.log(`Received audio chunk: ${chunk.duration}ms at ${chunk.timestamp}ms`);
  }

  handleStreamError(error) {
    console.error('Stream error:', error);
    
    if (this.listeners.onError) {
      this.listeners.onError(error);
    }
    
    // Stop streaming on error
    this.stopStreaming().catch(console.error);
  }

  // Register event handlers
  on(event, handler) {
    this.listeners[event] = handler;
  }

  // Convert base64 audio data to ArrayBuffer
  base64ToArrayBuffer(base64) {
    const binaryString = atob(base64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }
    return bytes.buffer;
  }

  // Convert PCM16 data to Float32 for WhisperKit
  pcm16ToFloat32(pcm16Buffer) {
    const pcm16 = new Int16Array(pcm16Buffer);
    const float32 = new Float32Array(pcm16.length);
    
    for (let i = 0; i < pcm16.length; i++) {
      float32[i] = pcm16[i] / 32768.0;
    }
    
    return float32;
  }

  // Process audio chunks for WhisperKit
  processChunksForWhisperKit(chunks) {
    const processedChunks = [];
    
    for (const chunk of chunks) {
      const arrayBuffer = this.base64ToArrayBuffer(chunk.data);
      
      let audioData;
      if (chunk.format.encoding === 'pcm16') {
        audioData = this.pcm16ToFloat32(arrayBuffer);
      } else if (chunk.format.encoding === 'float32') {
        audioData = new Float32Array(arrayBuffer);
      } else {
        console.warn(`Unsupported encoding: ${chunk.format.encoding}`);
        continue;
      }
      
      processedChunks.push({
        data: audioData,
        timestamp: chunk.timestamp,
        duration: chunk.duration,
        format: chunk.format
      });
    }
    
    return processedChunks;
  }
}

// Example usage
async function runStreamingExample() {
  const streamer = new AudioStreamer();
  
  // Register chunk handler for real-time processing
  streamer.on('onAudioChunk', (chunk) => {
    // Process chunk in real-time
    // You can send this to WhisperKit for real-time transcription
    console.log('Real-time chunk received:', chunk.timestamp);
  });
  
  // Register error handler
  streamer.on('onError', (error) => {
    console.error('Streaming error:', error);
  });
  
  try {
    // Start streaming with WhisperKit-compatible settings
    await streamer.startStreaming({
      sampleRate: 16000,
      channelCount: 1,
      encoding: 'pcm16',
      chunkDurationMs: 100
    });
    
    // Stream for 5 seconds
    setTimeout(async () => {
      try {
        const chunks = await streamer.stopStreaming();
        console.log(`Recorded ${chunks.length} chunks`);
        
        // Process chunks for WhisperKit
        const processedChunks = streamer.processChunksForWhisperKit(chunks);
        console.log('Processed chunks ready for WhisperKit:', processedChunks.length);
        
        // Here you would send the processed chunks to WhisperKit
        // for transcription
        
      } catch (error) {
        console.error('Failed to stop streaming:', error);
      }
    }, 5000);
    
  } catch (error) {
    console.error('Failed to start streaming:', error);
  }
}

// Export for use in other modules
export { AudioStreamer, runStreamingExample };