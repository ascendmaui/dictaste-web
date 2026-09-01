import { useEffect, useMemo, useState } from "react";
import { addHistory, clearHistory, loadHistory, type HistoryItem } from "./lib/history";
import { polishText } from "./lib/polish";
import {
  defaultSettings,
  loadSettings,
  normalizeApiBase,
  saveSettings,
  type DictasteSettings,
  type PolishProvider
} from "./lib/settings";
import { startSpeech, stopSpeech } from "./lib/speech";

const providerLabels: Record<PolishProvider, string> = {
  local: "Private local cleanup",
  dictaste: "Dictaste Cloud",
  gemini: "Google Gemini",
  openai: "ChatGPT API",
  xai: "xAI Grok",
  nvidia: "NVIDIA LLM"
};

export default function App() {
  const [settings, setSettings] = useState<DictasteSettings>(defaultSettings);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [transcript, setTranscript] = useState("");
  const [polished, setPolished] = useState("");
  const [history, setHistory] = useState<HistoryItem[]>([]);
  const [isListening, setIsListening] = useState(false);
  const [isPolishing, setIsPolishing] = useState(false);
  const [notice, setNotice] = useState("Ready when you are.");
  const [error, setError] = useState("");
  const [isOnline, setIsOnline] = useState(navigator.onLine);
  const [installEvent, setInstallEvent] = useState<BeforeInstallPromptEvent | null>(null);

  useEffect(() => {
    void Promise.all([loadSettings(), loadHistory()]).then(([savedSettings, savedHistory]) => {
      setSettings(savedSettings);
      setHistory(savedHistory);
    });

    const online = () => setIsOnline(true);
    const offline = () => setIsOnline(false);
    const install = (event: Event) => {
      event.preventDefault();
      setInstallEvent(event as BeforeInstallPromptEvent);
    };
    window.addEventListener("online", online);
    window.addEventListener("offline", offline);
    window.addEventListener("beforeinstallprompt", install);
    return () => {
      window.removeEventListener("online", online);
      window.removeEventListener("offline", offline);
      window.removeEventListener("beforeinstallprompt", install);
    };
  }, []);

  const wordCount = useMemo(() => transcript.trim().split(/\s+/).filter(Boolean).length, [transcript]);

  async function toggleRecording() {
    setError("");
    if (isListening) {
      await stopSpeech();
      setIsListening(false);
      setNotice("Dictation stopped.");
      return;
    }

    const prefix = transcript.trim();
    try {
      await startSpeech({
        language: settings.language,
        onPartial: (value) => setTranscript([prefix, value].filter(Boolean).join(prefix ? " " : "")),
        onFinal: (value) => {
          const next = [prefix, value].filter(Boolean).join(prefix ? " " : "");
          setTranscript(next);
          setNotice("Captured. Polish it when ready.");
          if (settings.autoPolish) void runPolish(next);
        },
        onState: (listening) => {
          setIsListening(listening);
          setNotice(listening ? "Listening… speak naturally." : "Dictation stopped.");
        },
        onError: (message) => setError(message)
      });
    } catch (caught) {
      setIsListening(false);
      setError(messageFrom(caught));
    }
  }

  async function runPolish(source = transcript) {
    setError("");
    setIsPolishing(true);
    setNotice(settings.provider === "local" ? "Cleaning locally…" : `Polishing with ${providerLabels[settings.provider]}…`);
    try {
      const result = await polishText(source, settings);
      setPolished(result);
      const item: HistoryItem = {
        id: crypto.randomUUID(),
        transcript: source.trim(),
        polished: result,
        createdAt: new Date().toISOString()
      };
      setHistory(await addHistory(item));
      setNotice("Polished and saved to recent history.");
    } catch (caught) {
      setError(messageFrom(caught));
      setNotice("Your original words are still here.");
    } finally {
      setIsPolishing(false);
    }
  }

  async function copyText(value: string) {
    await navigator.clipboard.writeText(value);
    setNotice("Copied.");
  }

  async function shareText(value: string) {
    if (navigator.share) {
      await navigator.share({ title: "Dictaste", text: value });
      return;
    }
    await copyText(value);
  }

  function speakText(value: string) {
    speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(value);
    utterance.lang = settings.language;
    speechSynthesis.speak(utterance);
    setNotice("Reading aloud.");
  }

  async function persistSettings(next: DictasteSettings) {
    const normalized = { ...next, apiBaseUrl: normalizeApiBase(next.apiBaseUrl) };
    setSettings(normalized);
    await saveSettings(normalized);
    setSettingsOpen(false);
    setNotice(`${providerLabels[normalized.provider]} selected.`);
  }

  async function installApp() {
    if (!installEvent) return;
    await installEvent.prompt();
    await installEvent.userChoice;
    setInstallEvent(null);
  }

  return (
    <div className="app-shell">
      <div className="ambient ambient-one" />
      <div className="ambient ambient-two" />
      <header className="topbar">
        <div className="brand">
          <img src="/icon-192.png" alt="" />
          <div>
            <strong>Dictaste</strong>
            <span>Speak it. Ship it.</span>
          </div>
        </div>
        <div className="top-actions">
          {installEvent && <button className="quiet-button" onClick={installApp}>Install</button>}
          <button className="icon-button" onClick={() => setSettingsOpen(true)} aria-label="Open settings">⚙</button>
        </div>
      </header>

      <main>
        <section className="hero-card glass-card">
          <div className="eyebrow-row">
            <span className={`status-dot ${isListening ? "live" : ""}`} />
            <span>{isListening ? "Listening" : providerLabels[settings.provider]}</span>
            <span className={`network-pill ${isOnline ? "" : "offline"}`}>{isOnline ? "Online" : "Offline"}</span>
          </div>
          <h1>Turn the thought in your head into text you can send.</h1>
          <p>Tap once, speak naturally, then let Dictaste clean the result without changing your meaning.</p>
          <button className={`record-button ${isListening ? "recording" : ""}`} onClick={toggleRecording} aria-label={isListening ? "Stop recording" : "Start recording"}>
            <span className="record-core">{isListening ? "■" : "●"}</span>
            <span>{isListening ? "Stop" : "Speak"}</span>
          </button>
          <div className="notice" role="status">{notice}</div>
          {error && <div className="error-banner" role="alert">{error}</div>}
        </section>

        <section className="workspace-grid">
          <article className="editor-card glass-card">
            <div className="card-heading">
              <div>
                <span className="step-number">01</span>
                <h2>Your words</h2>
              </div>
              <span>{wordCount} words</span>
            </div>
            <textarea
              value={transcript}
              onChange={(event) => setTranscript(event.target.value)}
              placeholder="Speak, type, or paste here…"
              aria-label="Raw transcript"
            />
            <div className="button-row">
              <button className="primary-button" onClick={() => runPolish()} disabled={isPolishing || !transcript.trim()}>
                {isPolishing ? "Polishing…" : "Polish text"}
              </button>
              <button className="secondary-button" onClick={() => { setTranscript(""); setPolished(""); setError(""); }}>Clear</button>
            </div>
          </article>

          <article className="editor-card glass-card output-card">
            <div className="card-heading">
              <div>
                <span className="step-number">02</span>
                <h2>Ready to ship</h2>
              </div>
              {polished && <span className="ready-label">Ready</span>}
            </div>
            <div className={`output-area ${polished ? "has-output" : ""}`}>
              {polished || "Your polished text will appear here."}
            </div>
            <div className="button-row">
              <button className="primary-button" disabled={!polished} onClick={() => copyText(polished)}>Copy</button>
              <button className="secondary-button" disabled={!polished} onClick={() => shareText(polished)}>Share</button>
              <button className="secondary-button" disabled={!polished} onClick={() => speakText(polished)}>Read</button>
            </div>
          </article>
        </section>

        <section className="history-section glass-card">
          <div className="card-heading">
            <div>
              <span className="step-number">Recent</span>
              <h2>Your latest drafts</h2>
            </div>
            {history.length > 0 && <button className="text-button" onClick={async () => { await clearHistory(); setHistory([]); }}>Clear history</button>}
          </div>
          {history.length === 0 ? (
            <p className="empty-history">Nothing saved yet. Your last 20 polished drafts stay on this device.</p>
          ) : (
            <div className="history-list">
              {history.slice(0, 6).map((item) => (
                <button key={item.id} className="history-item" onClick={() => { setTranscript(item.transcript); setPolished(item.polished); window.scrollTo({ top: 0, behavior: "smooth" }); }}>
                  <span>{item.polished}</span>
                  <time>{new Date(item.createdAt).toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}</time>
                </button>
              ))}
            </div>
          )}
        </section>
      </main>

      <footer>Private by default · Keys are never included in source control</footer>

      {settingsOpen && (
        <SettingsDialog
          initial={settings}
          onClose={() => setSettingsOpen(false)}
          onSave={persistSettings}
        />
      )}
    </div>
  );
}

function SettingsDialog({ initial, onClose, onSave }: { initial: DictasteSettings; onClose: () => void; onSave: (settings: DictasteSettings) => Promise<void> }) {
  const [draft, setDraft] = useState(initial);
  return (
    <div className="modal-backdrop" role="presentation" onMouseDown={onClose}>
      <div className="settings-dialog" role="dialog" aria-modal="true" aria-labelledby="settings-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-heading">
          <div>
            <span className="eyebrow">Settings</span>
            <h2 id="settings-title">Choose how Dictaste polishes</h2>
          </div>
          <button className="icon-button" onClick={onClose} aria-label="Close settings">×</button>
        </div>

        <label>
          Polish provider
          <select value={draft.provider} onChange={(event) => setDraft({ ...draft, provider: event.target.value as PolishProvider })}>
            <option value="local">Private local cleanup — no key</option>
            <option value="dictaste">Dictaste Cloud — license key</option>
            <option value="gemini">Google Gemini — your API key</option>
            <option value="openai">ChatGPT API — your OpenAI key</option>
            <option value="xai">xAI Grok — your API key</option>
            <option value="nvidia">NVIDIA LLM — your API key</option>
          </select>
        </label>

        {draft.provider === "dictaste" && (
          <>
            <label>
              Dictaste license key
              <input type="password" autoComplete="off" value={draft.licenseKey} onChange={(event) => setDraft({ ...draft, licenseKey: event.target.value })} placeholder="Paste license key" />
            </label>
            <label>
              API address
              <input value={draft.apiBaseUrl} onChange={(event) => setDraft({ ...draft, apiBaseUrl: event.target.value })} />
            </label>
          </>
        )}

        {draft.provider === "gemini" && (
          <>
            <label>
              Gemini API key
              <input type="password" autoComplete="off" value={draft.geminiApiKey} onChange={(event) => setDraft({ ...draft, geminiApiKey: event.target.value })} placeholder="Paste Gemini auth key" />
            </label>
            <label>
              Gemini model
              <input value={draft.geminiModel} onChange={(event) => setDraft({ ...draft, geminiModel: event.target.value })} />
            </label>
            <p className="field-help">Uses Google’s current Gemini Interactions API. Restrict the key to Gemini before using it.</p>
          </>
        )}

        {draft.provider === "openai" && (
          <>
            <label>
              OpenAI API key
              <input type="password" autoComplete="off" value={draft.openaiApiKey} onChange={(event) => setDraft({ ...draft, openaiApiKey: event.target.value })} placeholder="Paste OpenAI API key" />
            </label>
            <label>
              OpenAI model
              <input value={draft.openaiModel} onChange={(event) => setDraft({ ...draft, openaiModel: event.target.value })} />
            </label>
            <p className="field-help">Uses the OpenAI Responses API. Restrict the key to this app before using it.</p>
          </>
        )}

        {draft.provider === "xai" && (
          <>
            <label>
              xAI API key
              <input type="password" autoComplete="off" value={draft.xaiApiKey} onChange={(event) => setDraft({ ...draft, xaiApiKey: event.target.value })} placeholder="Paste xAI API key" />
            </label>
            <label>
              xAI model
              <input value={draft.xaiModel} onChange={(event) => setDraft({ ...draft, xaiModel: event.target.value })} />
            </label>
            <p className="field-help">Uses xAI’s Responses API. Restrict the key to Grok text generation before using it.</p>
          </>
        )}

        {draft.provider === "nvidia" && (
          <>
            <label>
              NVIDIA API key
              <input type="password" autoComplete="off" value={draft.nvidiaApiKey} onChange={(event) => setDraft({ ...draft, nvidiaApiKey: event.target.value })} placeholder="Paste NVIDIA API key" />
            </label>
            <label>
              NVIDIA model
              <input value={draft.nvidiaModel} onChange={(event) => setDraft({ ...draft, nvidiaModel: event.target.value })} />
            </label>
            <p className="field-help">Uses NVIDIA’s hosted NIM chat endpoint. Pick any supported text model from NVIDIA Build.</p>
          </>
        )}

        <label>
          Dictation language
          <select value={draft.language} onChange={(event) => setDraft({ ...draft, language: event.target.value })}>
            <option value="en-US">English (US)</option>
            <option value="en-GB">English (UK)</option>
            <option value="es-US">Spanish</option>
            <option value="fr-FR">French</option>
            <option value="de-DE">German</option>
            <option value="it-IT">Italian</option>
            <option value="pt-BR">Portuguese</option>
          </select>
        </label>

        <label className="checkbox-row">
          <input type="checkbox" checked={draft.autoPolish} onChange={(event) => setDraft({ ...draft, autoPolish: event.target.checked })} />
          Polish automatically after dictation
        </label>
        <label className="checkbox-row">
          <input type="checkbox" checked={draft.rememberKeys} onChange={(event) => setDraft({ ...draft, rememberKeys: event.target.checked })} />
          Remember keys on this device
        </label>
        <p className="field-help">Leave “Remember keys” off on shared devices. No key is bundled into the app or committed to Git.</p>

        <div className="dialog-actions">
          <button className="secondary-button" onClick={onClose}>Cancel</button>
          <button className="primary-button" onClick={() => onSave(draft)}>Save settings</button>
        </div>
      </div>
    </div>
  );
}

function messageFrom(error: unknown): string {
  return error instanceof Error ? error.message : "Something went wrong. Your original text is safe.";
}
