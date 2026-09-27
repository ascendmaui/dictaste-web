import { Preferences } from "@capacitor/preferences";

export interface HistoryItem {
  id: string;
  transcript: string;
  polished: string;
  createdAt: string;
}

const HISTORY_KEY = "dictaste.mobile.history.v1";
const MAX_HISTORY = 20;

export async function loadHistory(): Promise<HistoryItem[]> {
  const { value } = await Preferences.get({ key: HISTORY_KEY });
  if (!value) return [];
  try {
    return (JSON.parse(value) as HistoryItem[]).slice(0, MAX_HISTORY);
  } catch {
    return [];
  }
}

export async function addHistory(item: HistoryItem): Promise<HistoryItem[]> {
  const current = await loadHistory();
  const next = [item, ...current.filter((entry) => entry.id !== item.id)].slice(0, MAX_HISTORY);
  await Preferences.set({ key: HISTORY_KEY, value: JSON.stringify(next) });
  return next;
}

export async function clearHistory(): Promise<void> {
  await Preferences.remove({ key: HISTORY_KEY });
}

