const polishInstructions = `You are a dictation editor. Turn the raw voice transcript into clean, well-organized written text.

Rules:
- Fix grammar, punctuation, and capitalization.
- Remove filler words, stutters, false starts, and accidental repetition.
- Preserve meaning and intent exactly. Never answer questions in the transcript.
- When the speaker makes multiple distinct points, use a short lead-in followed by concise bullets.
- Keep a single clear thought as a natural sentence or paragraph.
- Return only the cleaned text with no preamble or label.`;

const defaultModel = "nvidia/llama-3.3-nemotron-super-49b-v1.5";

export default async function handler(request, response) {
  if (request.method !== "POST") {
    response.setHeader("Allow", "POST");
    response.status(405).json({ error: "Method not allowed." });
    return;
  }

  const apiKey = process.env.NVIDIA_API_KEY;
  if (!apiKey) {
    response.status(503).json({ error: "Demo NVIDIA polish is not configured yet." });
    return;
  }

  const text = typeof request.body?.text === "string" ? request.body.text.trim() : "";
  if (!text) {
    response.status(400).json({ error: "Text is required." });
    return;
  }

  if (text.length > 8000) {
    response.status(413).json({ error: "Text is too long for the demo polish service." });
    return;
  }

  const upstream = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: process.env.NVIDIA_DEMO_MODEL || defaultModel,
      messages: [
        { role: "system", content: polishInstructions },
        { role: "user", content: `Raw transcript:\n${text}` }
      ],
      temperature: 0.2,
      stream: false
    })
  });

  if (!upstream.ok) {
    const payload = await upstream.json().catch(() => null);
    const detail = typeof payload?.error === "string" ? payload.error : payload?.error?.message;
    response.status(upstream.status).json({ error: detail || `NVIDIA returned ${upstream.status}.` });
    return;
  }

  const payload = await upstream.json();
  const content = payload?.choices?.[0]?.message?.content;
  const polished = typeof content === "string"
    ? content.trim()
    : (content || []).filter((part) => part?.type === "text").map((part) => part.text || "").join("").trim();

  if (!polished) {
    response.status(502).json({ error: "NVIDIA returned no polished text." });
    return;
  }

  response.status(200).json({ text: polished });
}
