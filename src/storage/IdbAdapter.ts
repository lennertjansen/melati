import { get as idbGet, keys as idbKeys, set as idbSet } from "idb-keyval";
import type { JournalEntry, StorageAdapter } from "./StorageAdapter";

const KEY_PREFIX = "entry:";

/**
 * IndexedDB-backed storage adapter using idb-keyval.
 *
 * No folder picker needed — the app opens straight to the notepad.
 * Each entry is stored as JSON under key `entry:YYYY-MM-DD`.
 */
export class IdbAdapter implements StorageAdapter {
	private ready = false;

	async init(): Promise<void> {
		// Request persistent storage so the browser won't evict our data.
		await navigator.storage?.persist?.();
		this.ready = true;
	}

	isReady(): boolean {
		return this.ready;
	}

	async get(date: string): Promise<JournalEntry | null> {
		const value = await idbGet<string>(KEY_PREFIX + date);
		if (value == null) return null;
		return JSON.parse(value) as JournalEntry;
	}

	async put(entry: JournalEntry): Promise<void> {
		await idbSet(KEY_PREFIX + entry.date, JSON.stringify(entry));
	}

	async list(): Promise<string[]> {
		const allKeys = await idbKeys<string>();
		return allKeys
			.filter((k) => typeof k === "string" && k.startsWith(KEY_PREFIX))
			.map((k) => k.slice(KEY_PREFIX.length));
	}
}
