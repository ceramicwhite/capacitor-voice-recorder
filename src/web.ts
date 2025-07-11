import { WebPlugin } from '@capacitor/core';

import { VoiceRecorderImpl } from './VoiceRecorderImpl';
import type {
  CurrentRecordingStatus,
  GenericResponse,
  RecordingData,
  RecordingOptions,
  VoiceRecorderPlugin,
  StreamingOptions,
} from './definitions';

export class VoiceRecorderWeb extends WebPlugin implements VoiceRecorderPlugin {
  private voiceRecorderInstance = new VoiceRecorderImpl();

  public canDeviceVoiceRecord(): Promise<GenericResponse> {
    return VoiceRecorderImpl.canDeviceVoiceRecord();
  }

  public hasAudioRecordingPermission(): Promise<GenericResponse> {
    return VoiceRecorderImpl.hasAudioRecordingPermission();
  }

  public requestAudioRecordingPermission(): Promise<GenericResponse> {
    return VoiceRecorderImpl.requestAudioRecordingPermission();
  }

  public startRecording(options?: RecordingOptions): Promise<GenericResponse> {
    return this.voiceRecorderInstance.startRecording(options);
  }

  public stopRecording(): Promise<RecordingData> {
    return this.voiceRecorderInstance.stopRecording();
  }

  public pauseRecording(): Promise<GenericResponse> {
    return this.voiceRecorderInstance.pauseRecording();
  }

  public resumeRecording(): Promise<GenericResponse> {
    return this.voiceRecorderInstance.resumeRecording();
  }

  public getCurrentStatus(): Promise<CurrentRecordingStatus> {
    return this.voiceRecorderInstance.getCurrentStatus();
  }

  public async startStreaming(_options?: StreamingOptions): Promise<GenericResponse> {
    console.warn('Audio streaming is not implemented for web.');
    return { value: false };
  }

  public async stopStreaming(): Promise<GenericResponse> {
    console.warn('Audio streaming is not implemented for web.');
    return { value: false };
  }

  public async removeAllListeners(): Promise<void> {
    await super.removeAllListeners();
  }
}
