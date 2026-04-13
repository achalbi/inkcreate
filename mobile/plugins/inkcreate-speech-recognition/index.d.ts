export type SpeechRecognitionPreferredMode = "basic" | "advanced";

export interface SpeechRecognitionTranscriptionOptions {
  audioUrl: string;
  locale?: string;
  preferredMode?: SpeechRecognitionPreferredMode;
}

export interface SpeechRecognitionTranscriptionResult {
  text: string;
  locale: string;
  preferredMode: SpeechRecognitionPreferredMode;
}

export interface InkcreateSpeechRecognitionPlugin {
  transcribeAudio(options: SpeechRecognitionTranscriptionOptions): Promise<SpeechRecognitionTranscriptionResult>;
  startTranscription(options: SpeechRecognitionTranscriptionOptions): Promise<SpeechRecognitionTranscriptionResult>;
  extractSpeech(options: SpeechRecognitionTranscriptionOptions): Promise<SpeechRecognitionTranscriptionResult>;
}

export const InkcreateSpeechRecognition: InkcreateSpeechRecognitionPlugin;

export default InkcreateSpeechRecognition;
