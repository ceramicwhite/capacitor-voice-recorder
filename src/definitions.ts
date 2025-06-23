import type { Directory } from '@capacitor/filesystem';
import type { PluginListenerHandle } from '@capacitor/core';

export type Base64String = string;

export interface RecordingData {
  value: {
    recordDataBase64?: Base64String;
    msDuration: number;
    mimeType: string;
    path?: string;
  };
}

export type RecordingOptions =
  | never
  | {
      directory: Directory;
      subDirectory?: string;
    };

export interface StreamingOptions {
  sampleRate?: number; // Default: 16000 for WhisperKit compatibility
  channelCount?: number; // Default: 1 (mono)
  encoding?: 'pcm16' | 'pcm8' | 'float32'; // Default: 'pcm16'
  chunkDurationMs?: number; // Default: 100ms chunks
}

export interface AudioChunk {
  data: Base64String; // Base64 encoded audio data
  timestamp: number; // Timestamp in milliseconds
  duration: number; // Duration of chunk in milliseconds
  format: {
    sampleRate: number;
    channelCount: number;
    encoding: string;
  };
}

export interface GenericResponse {
  value: boolean;
}

export const RecordingStatus = {
  RECORDING: 'RECORDING',
  PAUSED: 'PAUSED',
  NONE: 'NONE',
  STREAMING: 'STREAMING',
} as const;

export interface CurrentRecordingStatus {
  status: (typeof RecordingStatus)[keyof typeof RecordingStatus];
}

export interface VoiceRecorderPlugin {
  canDeviceVoiceRecord(): Promise<GenericResponse>;

  requestAudioRecordingPermission(): Promise<GenericResponse>;

  hasAudioRecordingPermission(): Promise<GenericResponse>;

  startRecording(options?: RecordingOptions): Promise<GenericResponse>;

  stopRecording(): Promise<RecordingData>;

  pauseRecording(): Promise<GenericResponse>;

  resumeRecording(): Promise<GenericResponse>;

  getCurrentStatus(): Promise<CurrentRecordingStatus>;

  // New streaming methods
  startStreaming(options?: StreamingOptions): Promise<GenericResponse>;

  stopStreaming(): Promise<GenericResponse>;

  addListener(
    eventName: 'audioChunk',
    listenerFunc: (chunk: AudioChunk) => void
  ): Promise<PluginListenerHandle>;

  addListener(
    eventName: 'streamError',
    listenerFunc: (error: { message: string; code: string }) => void
  ): Promise<PluginListenerHandle>;

  removeAllListeners(): Promise<void>;
}
