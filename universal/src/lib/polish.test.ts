import { afterEach, describe, expect, it, vi } from "vitest";
import { defaultSettings } from "./settings";
import { localCleanup, parseChatCompletion, parseGeminiInteraction, parseResponsesPayload, polishText } from "./polish";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
  vi.restoreAllMocks();
});

describe("localCleanup", () => {
  it("removes common dictation fillers and repetition", () => {
    expect(localCleanup("um this this is ready to ship")).toBe("This is ready to ship.");
  });

  it("preserves terminal punctuation", () => {
    expect(localCleanup("is this ready?" )).toBe("Is this ready?");
  });
});

describe("parseGeminiInteraction", () => {
  it("joins text from model output steps", () => {
    expect(parseGeminiInteraction({
      steps: [
        { type: "thought", content: [{ type: "text", text: "hidden" }] },
        { type: "model_output", content: [{ type: "text", text: "Clean text." }] }
      ]
    })).toBe("Clean text.");
  });
});

describe("parseResponsesPayload", () => {
  it("uses output_text when present", () => {
    expect(parseResponsesPayload({ output_text: "Clean text." })).toBe("Clean text.");
  });

  it("joins text from response output items", () => {
    expect(parseResponsesPayload({
      output: [
        { type: "message", content: [{ type: "output_text", text: "Clean " }, { type: "output_text", text: "text." }] }
      ]
    })).toBe("Clean text.");
  });
});

describe("parseChatCompletion", () => {
  it("reads string chat completion content", () => {
    expect(parseChatCompletion({ choices: [{ message: { content: "Clean text." } }] })).toBe("Clean text.");
  });

  it("joins text chat completion parts", () => {
    expect(parseChatCompletion({
      choices: [{ message: { content: [{ type: "text", text: "Clean " }, { type: "text", text: "text." }] } }]
    })).toBe("Clean text.");
  });
});

describe("polishText", () => {
  it("uses the NVIDIA demo endpoint when no NVIDIA key is set", async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ text: "Clean text." }), { status: 200 }));
    globalThis.fetch = fetchMock as typeof fetch;

    await expect(polishText("um clean text", {
      ...defaultSettings,
      provider: "nvidia",
      nvidiaApiKey: "",
      nvidiaDemoApiBaseUrl: "https://demo.example"
    })).resolves.toBe("Clean text.");

    expect(fetchMock).toHaveBeenCalledWith("https://demo.example/api/demo/nvidia-polish", expect.objectContaining({
      method: "POST"
    }));
  });
});
