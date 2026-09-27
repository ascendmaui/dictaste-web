import { SpeechRecognition } from "@capacitor-community/speech-recognition";
import { Capacitor, type PluginListenerHandle } from "@capacitor/core";

export interface SpeechCallbacks {
  language: string;
  onPartial: (text: string) => void;
  onFinal: (text: string) => void;
  onState: (listening: boolean) => void;
  onError: (message: string) => void;
}

let browserRecognition: BrowserSpeechRecognition | null = null;
let partialHandle: PluginListenerHandle | null = null;
let stateHandle: PluginListenerHandle | null = null;
let lastNativeMatch = "";

export async function startSpeech(callbacks: SpeechCallbacks): Promise<void> {
  if (Capacitor.isNativePlatform()) {
    await startNativeSpeech(callbacks);
    return;
  }
  startBrowserSpeech(callbacks);
}

export async function stopSpeech(): Promise<void> {
  if (Capacitor.isNativePlatform()) {
    await SpeechRecognition.stop().catch(() => undefined);
    await removeNativeListeners();
    return;
  }
  browserRecognition?.stop();
  browserRecognition = null;
}

async function startNativeSpeech(callbacks: SpeechCallbacks): Promise<void> {
  const availability = await SpeechRecognition.available();
  if (!availability.available) throw new Error("Speech recognition is not available on this device.");

  let permission = await SpeechRecognition.checkPermissions();
  if (permission.speechRecognition !== "granted") {
    permission = await SpeechRecognition.requestPermissions();
  }
  if (permission.speechRecognition !== "granted") {
    throw new Error("Microphone and speech-recognition permission are required.");
  }

  await removeNativeListeners();
  lastNativeMatch = "";
  partialHandle = await SpeechRecognition.addListener("partialResults", ({ matches }) => {
    lastNativeMatch = matches?.[0]?.trim() ?? lastNativeMatch;
    if (lastNativeMatch) callbacks.onPartial(lastNativeMatch);
  });
  stateHandle = await SpeechRecognition.addListener("listeningState", ({ status }) => {
    const listening = status === "started";
    callbacks.onState(listening);
    if (!listening && lastNativeMatch) callbacks.onFinal(lastNativeMatch);
  });

  callbacks.onState(true);
  const result = await SpeechRecognition.start({
    language: callbacks.language,
    maxResults: 5,
    prompt: "Speak to Dictaste",
    partialResults: true,
    popup: false
  }).catch(async (caught) => {
    callbacks.onState(false);
    await removeNativeListeners();
    throw new Error(normalizeSpeechError(caught));
  });
  const finalMatch = result.matches?.[0]?.trim();
  if (finalMatch) callbacks.onFinal(finalMatch);
}

function startBrowserSpeech(callbacks: SpeechCallbacks): void {
  const Recognition = window.SpeechRecognition ?? window.webkitSpeechRecognition;
  if (!Recognition) throw new Error("Speech recognition is unavailable here. You can still type or paste text.");

  browserRecognition?.abort();
  const recognition = new Recognition();
  browserRecognition = recognition;
  recognition.lang = callbacks.language;
  recognition.continuous = true;
  recognition.interimResults = true;
  let finalText = "";

  recognition.onstart = () => callbacks.onState(true);
  recognition.onerror = (event) => {
    callbacks.onState(false);
    callbacks.onError(event.error === "not-allowed" ? "Allow microphone access to dictate." : `Speech recognition: ${event.error}`);
  };
  recognition.onend = () => {
    callbacks.onState(false);
    if (finalText.trim()) callbacks.onFinal(finalText.trim());
    browserRecognition = null;
  };
  recognition.onresult = (event) => {
    let interim = "";
    for (let index = event.resultIndex; index < event.results.length; index += 1) {
      const phrase = event.results[index][0]?.transcript ?? "";
      if (event.results[index].isFinal) finalText += `${phrase} `;
      else interim += phrase;
    }
    callbacks.onPartial(`${finalText}${interim}`.trim());
  };
  recognition.start();
}

async function removeNativeListeners(): Promise<void> {
  await partialHandle?.remove();
  await stateHandle?.remove();
  partialHandle = null;
  stateHandle = null;
}

function normalizeSpeechError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error ?? "");
  if (/asset|recognition|unavailable|notawareofasset|6301/i.test(message)) {
    return "Speech recognition is unavailable in this simulator. Type or paste text here, or test dictation on a real iPhone.";
  }
  return message || "Speech recognition could not start. Type or paste text here instead.";
}
