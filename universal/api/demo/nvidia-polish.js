const polishInstructions = `You are a dictation editor. Turn the raw voice transcript into clean, well-organized written text.

Rules:
- Fix grammar, punctuation, and capitalization.
- Remove filler words, stutters, false starts, and accidental repetition.
- Preserve meaning and intent exactly. Never answer questions in the transcript.
- When the speaker makes multiple distinct points, use a short lead-in followed by concise bullets.
- Keep a single clear thought as a natural sentence or paragraph.
- Return only the cleaned text with no preamble or label.`;

const defaultModel = "nvidia/llama-3.3-nemotron-super-49b-v1.5";
const maxBodyBytes = 12_000;
const maxTextLength = 8000;
const upstreamTimeoutMs = 20_000;
const allowedOrigins = new Set([
  "https://dictaste.com",
  "https://www.dictaste.com",
  "http://127.0.0.1:4173",
  "http://localhost:4173",
  "capacitor://localhost",
  "ionic://localhost",
  "https://localhost"
]);

export default async function handler(request, response) {
  applySafeHeaders(request, response);

  if (request.method === "OPTIONS") {
    response.status(204).end();
    return;
  }

  if (request.method !== "POST") {
    response.setHeader("Allow", "POST");
    response.status(405).json({ error: "Method not allowed." });
    return;
  }

  if (isOversized(request)) {
    response.status(413).json({ error: "Request is too large." });
    return;
  }

  const contentType = headerValue(request, "content-type");
  if (contentType && !contentType.toLowerCase().includes("application/json")) {
    response.status(415).json({ error: "Content-Type must be application/json." });
    return;
  }

  const apiKey = process.env.NVIDIA_API_KEY;
  if (!apiKey) {
    response.status(503).json({ error: "Demo NVIDIA polish is not configured yet." });
    return;
  }

  const text = readTranscript(request.body);
  if (text.error) {
    response.status(text.status).json({ error: text.error });
    return;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), upstreamTimeoutMs);
  try {
    const upstream = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json"
      },
      signal: controller.signal,
      body: JSON.stringify({
        model: process.env.NVIDIA_DEMO_MODEL || defaultModel,
        messages: [
          { role: "system", content: polishInstructions },
          { role: "user", content: `Raw transcript:\n${text.value}` }
        ],
        temperature: 0.2,
        stream: false
      })
    });

    if (!upstream.ok) {
      await upstream.body?.cancel?.().catch(() => undefined);
      response.status(502).json({ error: "Demo polish is temporarily unavailable." });
      return;
    }

    let payload;
    try {
      payload = await upstream.json();
    } catch {
      response.status(502).json({ error: "Demo polish returned an unreadable response." });
      return;
    }

    const polished = polishFromPayload(payload);
    if (!polished) {
      response.status(502).json({ error: "NVIDIA returned no polished text." });
      return;
    }

    response.status(200).json({ text: polished });
  } catch (error) {
    const timedOut = error instanceof Error && error.name === "AbortError";
    response.status(timedOut ? 504 : 502).json({
      error: timedOut ? "Demo polish timed out. Try again." : "Demo polish is temporarily unavailable."
    });
  } finally {
    clearTimeout(timer);
  }
}

function readTranscript(body) {
  let parsed = body;
  if (typeof parsed === "string") {
    try {
      parsed = JSON.parse(parsed);
    } catch {
      return { status: 400, error: "Request body must be JSON." };
    }
  }
  if (parsed == null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { status: 400, error: "Request body must be a JSON object." };
  }
  const text = typeof parsed.text === "string" ? parsed.text.trim() : "";
  if (!text) return { status: 400, error: "Text is required." };
  if (text.length > maxTextLength) {
    return { status: 413, error: "Text is too long for the demo polish service." };
  }
  return { value: text };
}

function polishFromPayload(payload) {
  const content = payload?.choices?.[0]?.message?.content;
  if (typeof content === "string") return content.trim();
  return (Array.isArray(content) ? content : [])
    .filter((part) => part?.type === "text")
    .map((part) => part.text || "")
    .join("")
    .trim();
}

function applySafeHeaders(request, response) {
  const origin = headerValue(request, "origin");
  if (origin && allowedOrigins.has(origin)) {
    response.setHeader("Access-Control-Allow-Origin", origin);
    response.setHeader("Vary", "Origin");
  }
  response.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  response.setHeader("Access-Control-Allow-Headers", "Content-Type");
  response.setHeader("Access-Control-Max-Age", "600");
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("Referrer-Policy", "no-referrer");
  response.setHeader("Cache-Control", "no-store");
  response.setHeader("X-Frame-Options", "DENY");
}

function isOversized(request) {
  const declared = Number(headerValue(request, "content-length"));
  if (Number.isFinite(declared) && declared > maxBodyBytes) return true;
  return typeof request.body === "string" && request.body.length > maxBodyBytes;
}

function headerValue(request, name) {
  const headers = request.headers ?? {};
  const value = headers[name] ?? headers[name.toLowerCase()];
  if (Array.isArray(value)) return value[0] ?? "";
  return typeof value === "string" ? value : "";
}
