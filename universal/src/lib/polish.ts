import type { DictasteSettings } from "./settings";
import { normalizeApiBase } from "./settings";

export const polishInstructions = `You are a dictation editor. Turn the raw voice transcript into clean, well-organized written text.

Rules:
- Fix grammar, punctuation, and capitalization.
- Remove filler words, stutters, false starts, and accidental repetition.
- Preserve meaning and intent exactly. Never answer questions in the transcript.
- When the speaker makes multiple distinct points, use a short lead-in followed by concise bullets.
- Keep a single clear thought as a natural sentence or paragraph.
- Return only the cleaned text with no preamble or label.`;

export async function polishText(text: string, settings: DictasteSettings): Promise<string> {
  const source = text.trim();
  if (!source) throw new Error("Speak or type something first.");

  switch (settings.provider) {
    case "dictaste":
      return polishWithDictaste(source, settings);
    case "gemini":
      return polishWithGemini(source, settings);
    case "openai":
      return polishWithOpenAI(source, settings);
    case "xai":
      return polishWithXAI(source, settings);
    case "nvidia":
      return polishWithNVIDIA(source, settings);
    case "local":
      return localCleanup(source);
  }
}

async function polishWithDictaste(text: string, settings: DictasteSettings): Promise<string> {
  const licenseKey = settings.licenseKey.trim();
  if (!licenseKey) throw new Error("Add your Dictaste license key in Settings.");

  const response = await fetch(`${normalizeApiBase(settings.apiBaseUrl)}/api/v1/polish`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${licenseKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ text })
  });

  if (response.status === 402) throw new Error("Your Dictaste polish allowance is used up.");
  if (!response.ok) throw new Error(`Dictaste Cloud returned ${response.status}.`);

  const payload = (await response.json()) as { text?: string };
  return validateResult(payload.text, text);
}

async function polishWithGemini(text: string, settings: DictasteSettings): Promise<string> {
  const apiKey = settings.geminiApiKey.trim();
  if (!apiKey) throw new Error("Add your Gemini API key in Settings.");

  const response = await fetch("https://generativelanguage.googleapis.com/v1beta/interactions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey
    },
    body: JSON.stringify({
      model: settings.geminiModel.trim() || "gemini-3.7-flash",
      store: false,
      input: `${polishInstructions}\n\nRaw transcript:\n${text}`
    })
  });

  if (!response.ok) {
    const payload = (await response.json().catch(() => null)) as { error?: { message?: string } } | null;
    throw new Error(payload?.error?.message || `Gemini returned ${response.status}.`);
  }

  const payload = (await response.json()) as GeminiInteraction;
  return validateResult(parseGeminiInteraction(payload), text);
}

async function polishWithOpenAI(text: string, settings: DictasteSettings): Promise<string> {
  const apiKey = settings.openaiApiKey.trim();
  if (!apiKey) throw new Error("Add your OpenAI API key in Settings.");

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: settings.openaiModel.trim() || "gpt-5.6",
      store: false,
      input: `${polishInstructions}\n\nRaw transcript:\n${text}`
    })
  });

  if (!response.ok) throw new Error(await providerError(response, "OpenAI"));

  const payload = (await response.json()) as ResponsesPayload;
  return validateResult(parseResponsesPayload(payload), text);
}

async function polishWithXAI(text: string, settings: DictasteSettings): Promise<string> {
  const apiKey = settings.xaiApiKey.trim();
  if (!apiKey) throw new Error("Add your xAI API key in Settings.");

  const response = await fetch("https://api.x.ai/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: settings.xaiModel.trim() || "grok-4.6",
      store: false,
      input: `${polishInstructions}\n\nRaw transcript:\n${text}`
    })
  });

  if (!response.ok) throw new Error(await providerError(response, "xAI"));

  const payload = (await response.json()) as ResponsesPayload;
  return validateResult(parseResponsesPayload(payload), text);
}

async function polishWithNVIDIA(text: string, settings: DictasteSettings): Promise<string> {
  const apiKey = settings.nvidiaApiKey.trim();
  if (!apiKey) return polishWithNVIDIADemo(text, settings);

  const response = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: settings.nvidiaModel.trim() || "nvidia/llama-3.3-nemotron-super-49b-v1.5",
      messages: [
        { role: "system", content: polishInstructions },
        { role: "user", content: `Raw transcript:\n${text}` }
      ],
      temperature: 0.2,
      stream: false
    })
  });

  if (!response.ok) throw new Error(await providerError(response, "NVIDIA"));

  const payload = (await response.json()) as ChatCompletionPayload;
  return validateResult(parseChatCompletion(payload), text);
}

async function polishWithNVIDIADemo(text: string, settings: DictasteSettings): Promise<string> {
  const response = await fetch(`${normalizeApiBase(settings.nvidiaDemoApiBaseUrl)}/api/demo/nvidia-polish`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ text })
  });

  if (!response.ok) throw new Error(await providerError(response, "NVIDIA demo"));

  const payload = (await response.json()) as { text?: string };
  return validateResult(payload.text, text);
}

interface GeminiInteraction {
  steps?: Array<{
    type?: string;
    content?: Array<{ type?: string; text?: string }>;
  }>;
}

export function parseGeminiInteraction(payload: GeminiInteraction): string {
  return (payload.steps ?? [])
    .filter((step) => step.type === "model_output")
    .flatMap((step) => step.content ?? [])
    .filter((part) => part.type === "text")
    .map((part) => part.text ?? "")
    .join("")
    .trim();
}

interface ResponsesPayload {
  output_text?: string;
  output?: Array<{
    type?: string;
    content?: Array<{ type?: string; text?: string }>;
  }>;
}

export function parseResponsesPayload(payload: ResponsesPayload): string {
  if (payload.output_text?.trim()) return payload.output_text.trim();
  return (payload.output ?? [])
    .flatMap((item) => item.content ?? [])
    .filter((part) => part.type === "output_text" || part.type === "text")
    .map((part) => part.text ?? "")
    .join("")
    .trim();
}

interface ChatCompletionPayload {
  choices?: Array<{
    message?: {
      content?: string | Array<{ type?: string; text?: string }>;
    };
  }>;
}

export function parseChatCompletion(payload: ChatCompletionPayload): string {
  const content = payload.choices?.[0]?.message?.content;
  if (typeof content === "string") return content.trim();
  return (content ?? [])
    .filter((part) => part.type === "text")
    .map((part) => part.text ?? "")
    .join("")
    .trim();
}

export function localCleanup(text: string): string {
  let cleaned = text
    .replace(/\b(?:um+|uh+|erm+|ah+)\b[,.]?\s*/gi, "")
    .replace(/\b(\w+)(?:\s+\1\b)+/gi, "$1")
    .replace(/\s+([,.;!?])/g, "$1")
    .replace(/([,.;!?]){2,}/g, "$1")
    .replace(/\s{2,}/g, " ")
    .trim();

  if (!cleaned) return "";
  cleaned = cleaned.charAt(0).toUpperCase() + cleaned.slice(1);
  if (!/[.!?]$/.test(cleaned)) cleaned += ".";
  return cleaned;
}

async function providerError(response: Response, provider: string): Promise<string> {
  const payload = (await response.json().catch(() => null)) as { error?: { message?: string } | string } | null;
  const detail = typeof payload?.error === "string" ? payload.error : payload?.error?.message;
  return detail || `${provider} returned ${response.status}.`;
}

function validateResult(result: string | undefined, original: string): string {
  const cleaned = result?.trim() ?? "";
  if (!cleaned) throw new Error("The polish service returned no text.");
  if (cleaned.length > original.length * 6 + 800) {
    throw new Error("The polish result looked unsafe, so Dictaste kept your original text.");
  }
  return cleaned;
}
