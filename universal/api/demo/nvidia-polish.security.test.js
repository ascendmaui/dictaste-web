import { describe, expect, it, vi } from "vitest";
import handler from "./nvidia-polish.js";

describe("nvidia polish demo security headers", () => {
  it("answers preflight for the product origin without calling upstream", async () => {
    const fetchMock = vi.fn();
    globalThis.fetch = fetchMock;
    const response = mockResponse();

    await handler({
      method: "OPTIONS",
      headers: { origin: "https://dictaste.com" }
    }, response);

    expect(response.statusCode).toBe(204);
    expect(response.headers["access-control-allow-origin"]).toBe("https://dictaste.com");
    expect(response.headers["access-control-allow-methods"]).toBe("POST, OPTIONS");
    expect(response.headers["access-control-allow-headers"]).toBe("Content-Type");
    expect(response.headers["access-control-allow-credentials"]).toBeUndefined();
    expect(response.headers["x-content-type-options"]).toBe("nosniff");
    expect(response.headers["referrer-policy"]).toBe("no-referrer");
    expect(response.headers["cache-control"]).toBe("no-store");
    expect(response.headers["x-frame-options"]).toBe("DENY");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("does not reflect an unlisted origin", async () => {
    const response = mockResponse();

    await handler({
      method: "OPTIONS",
      headers: { origin: "https://evil.example" }
    }, response);

    expect(response.headers["access-control-allow-origin"]).toBeUndefined();
    expect(response.headers["vary"]).toBeUndefined();
  });

  it("rejects an oversized body before reading a provider key", async () => {
    delete process.env.NVIDIA_API_KEY;
    const fetchMock = vi.fn();
    globalThis.fetch = fetchMock;
    const response = mockResponse();

    await handler({
      method: "POST",
      headers: {
        origin: "https://dictaste.com",
        "content-type": "application/json",
        "content-length": "20000"
      },
      body: { text: "short" }
    }, response);

    expect(response.statusCode).toBe(413);
    expect(response.body).toEqual({ error: "Request is too large." });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects a non-JSON content type", async () => {
    const response = mockResponse();

    await handler({
      method: "POST",
      headers: { "content-type": "text/plain" },
      body: { text: "hello" }
    }, response);

    expect(response.statusCode).toBe(415);
    expect(response.body).toEqual({ error: "Content-Type must be application/json." });
  });
});

function mockResponse() {
  return {
    statusCode: 200,
    ended: false,
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
    },
    end() {
      this.ended = true;
      return this;
    }
  };
}
