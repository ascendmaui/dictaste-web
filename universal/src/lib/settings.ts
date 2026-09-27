import { Preferences } from "@capacitor/preferences";

export type PolishProvider = "local" | "dictaste" | "gemini" | "openai" | "xai" | "nvidia";

export interface DictasteSettings {
  provider: PolishProvider;
  language: string;
  apiBaseUrl: string;
  licenseKey: string;
  geminiApiKey: string;
  geminiModel: string;
  openaiApiKey: string;
  openaiModel: string;
  xaiApiKey: string;
  xaiModel: string;
  nvidiaApiKey: string;
  nvidiaModel: string;
  nvidiaDemoApiBaseUrl: string;
  rememberKeys: boolean;
  autoPolish: boolean;
}

const SETTINGS_KEY = "dictaste.mobile.settings.v1";

export const defaultSettings: DictasteSettings = {
  provider: "local",
  language: "en-US",
  apiBaseUrl: "https://dictaste.com",
  licenseKey: "",
  geminiApiKey: "",
  geminiModel: "gemini-3.7-flash",
  openaiApiKey: "",
  openaiModel: "gpt-5.6",
  xaiApiKey: "",
  xaiModel: "grok-4.6",
  nvidiaApiKey: "",
  nvidiaModel: "nvidia/llama-3.3-nemotron-super-49b-v1.5",
  nvidiaDemoApiBaseUrl: "https://dictaste.com",
  rememberKeys: false,
  autoPolish: false
};

export async function loadSettings(): Promise<DictasteSettings> {
  const { value } = await Preferences.get({ key: SETTINGS_KEY });
  if (!value) return defaultSettings;

  try {
    const parsed = JSON.parse(value) as Partial<DictasteSettings>;
    return { ...defaultSettings, ...parsed };
  } catch {
    return defaultSettings;
  }
}

export async function saveSettings(settings: DictasteSettings): Promise<void> {
  const persisted = settings.rememberKeys
    ? settings
    : {
        ...settings,
        licenseKey: "",
        geminiApiKey: "",
        openaiApiKey: "",
        xaiApiKey: "",
        nvidiaApiKey: ""
      };
  await Preferences.set({ key: SETTINGS_KEY, value: JSON.stringify(persisted) });
}

export function normalizeApiBase(value: string): string {
  const trimmed = value.trim().replace(/\/+$/, "");
  return trimmed || defaultSettings.apiBaseUrl;
}
