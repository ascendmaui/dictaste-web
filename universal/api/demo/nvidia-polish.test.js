import { afterEach, describe, expect, it, vi } from "vitest";
import handler from "./nvidia-polish.js";

const originalFetch = globalThis.fetch;
const originalKey = process.env.NVIDIA_API_KEY;

afterEach(() => {
  globalThis.fetch = originalFetch;
  if (originalKey === undefined) delete process.env.NVIDIA_API_KEY;
  else process.env.NVIDIA_API_KEY = originalKey;
  vi.restoreAllMocks();
});

describe("nvidia polish demo handler", () => {
  it("rejects a missing transcript before calling upstream", async () => {
    process.env.NVIDIA_API_KEY = "test-nvidia-key";
    const fetchMock = vi.fn();
    globalThis.fetch = fetchMock;
    const response = mockResponse();

    await handler({ method: "POST", body: {} }, response);

    expect(response.statusCode).toBe(400);
    expect(response.body).toEqual({ error: "Text is required." });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects text over the demo limit", async () => {
    process.env.NVIDIA_API_KEY = "test-nvidia-key";
    const response = mockResponse();

    await handler({ method: "POST", body: { text: "a".repeat(8001) } }, response);

    expect(response.statusCode).toBe(413);
    expect(response.body.error).toBe("Text is too long for the demo polish service.");
  });

  it("rejects a non-JSON string body", async () => {
    process.env.NVIDIA_API_KEY = "test-nvidia-key";
    const response = mockResponse();

    await handler({ method: "POST", body: "not-json" }, response);

    expect(response.statusCode).toBe(400);
    expect(response.body).toEqual({ error: "Request body must be JSON." });
  });

  it("hides upstream failures and does not echo the response body", async () => {
    process.env.NVIDIA_API_KEY = "test-nvidia-key";
    globalThis.fetch = vi.fn(async () => new Response(JSON.stringify({
      error: { message: "env NVIDIA_API_KEY leaked in upstream body" }
    }), { status: 401 }));
    const response = mockResponse();

    await handler({ method: "POST", body: { text: "um hello" } }, response);

    expect(response.statusCode).toBe(502);
    expect(response.body).toEqual({ error: "Demo polish is temporarily unavailable." });
    expect(JSON.stringify(response.body)).not.toContain("NVIDIA_API_KEY");
    expect(JSON.stringify(response.body)).not.toContain("leaked");
  });

  it("returns a timeout when the upstream request is aborted", async () => {
    process.env.NVIDIA_API_KEY = "test-nvidia-key";
    globalThis.fetch = vi.fn(async () => {
      const error = new Error("stack: secret at handler.js:1");
      error.name = "AbortError";
      throw error;
    });
    const response = mockResponse();

    await handler({ method: "POST", body: { text: "um hello" } }, response);

    expect(response.statusCode).toBe(504);
    expect(response.body).toEqual({ error: "Demo polish timed out. Try again." });
    expect(JSON.stringify(response.body)).not.toContain("stack");
  });

  it("returns polished text from a successful upstream response", async () => {
    process.env.NVIDIA_API_KEY = "test-nvidia-key";
    globalThis.fetch = vi.fn(async () => new Response(JSON.stringify({
      choices: [{ message: { content: "Hello." } }]
    }), { status: 200 }));
    const response = mockResponse();

    await handler({ method: "POST", body: { text: "um hello" } }, response);

    expect(response.statusCode).toBe(200);
    expect(response.body).toEqual({ text: "Hello." });
  });

  it("says the demo is unconfigured without naming an environment value", async () => {
    delete process.env.NVIDIA_API_KEY;
    const response = mockResponse();

    await handler({ method: "POST", body: { text: "um hello" } }, response);

    expect(response.statusCode).toBe(503);
    expect(response.body.error).toBe("Demo NVIDIA polish is not configured yet.");
    expect(JSON.stringify(response.body)).not.toContain("NVIDIA_API_KEY");
  });
});

function mockResponse() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    }
  };
}
