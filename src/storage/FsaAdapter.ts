import { del, get as idbGet, set as idbSet } from "idb-keyval";
import { nowIsoWithOffset } from "../lib/date";
import { parseDoc, stringifyDoc } from "./frontmatter";
import {
	type JournalEntry,
	NeedsFolderError,
	type StorageAdapter,
} from "./StorageAdapter";

/**
 * File System Access API implementation of StorageAdapter.
 *
 * Strategy:
 *   - User picks a parent directory on first run. We call
 *     `getDirectoryHandle("Noot", { create: true })` to auto-create a
 *     `Noot/` subdirectory inside it — the user never touches Finder.
 *   - The resulting FileSystemDirectoryHandle is persisted in IndexedDB
 *     (idb-keyval). On subsequent app loads we restore it and silently
 *     re-verify permission.
 *   - Each journal entry is a `YYYY-MM-DD.md` file directly inside the
 *     `Noot/` subdir. No nesting, no index.
 *
 * Chromium-only. Safari + Firefox don't ship the File System Access API
 * yet, which is an accepted Phase 1 limitation.
 */

const HANDLE_KEY = "noot:dirHandle";

export class FsaAdapter implements StorageAdapter {
	private dirHandle: FileSystemDirectoryHandle | null = null;

	isReady(): boolean {
		return this.dirHandle !== null;
	}

	async init(): Promise<void> {
		const stored = await idbGet<FileSystemDirectoryHandle>(HANDLE_KEY);
		if (!stored) {
			throw new NeedsFolderError();
		}

		// Silent permission check: `queryPermission` never prompts.
		const state = await stored.queryPermission({ mode: "readwrite" });
		if (state === "granted") {
			this.dirHandle = stored;
			return;
		}

		// We can't call `requestPermission` here — it needs a user gesture.
		// Surface it to the app so it can render the FolderPicker and let
		// the user click.
		throw new NeedsFolderError();
	}

	async pickFolder(): Promise<void> {
		// Try resurrecting a previous handle first — if the user kept the
		// same folder and we just need a gesture-backed permission prompt,
		// avoid making them re-navigate Finder.
		const stored = await idbGet<FileSystemDirectoryHandle>(HANDLE_KEY);
		if (stored) {
			const state = await stored.requestPermission({ mode: "readwrite" });
			if (state === "granted") {
				this.dirHandle = stored;
				return;
			}
			// They declined or browser revoked — fall through to fresh picker.
			await del(HANDLE_KEY);
		}

		const parent = await window.showDirectoryPicker({ mode: "readwrite" });
		const noot = await parent.getDirectoryHandle("Noot", { create: true });
		await idbSet(HANDLE_KEY, noot);
		this.dirHandle = noot;
	}

	async get(date: string): Promise<JournalEntry | null> {
		const dir = this.requireDir();
		let fileHandle: FileSystemFileHandle;
		try {
			fileHandle = await dir.getFileHandle(fileName(date), { create: false });
		} catch (err) {
			if (err instanceof DOMException && err.name === "NotFoundError") {
				return null;
			}
			throw err;
		}

		const file = await fileHandle.getFile();
		const text = await file.text();
		const { data, content } = parseDoc(text);

		return {
			date,
			content,
			createdAt: data.created_at,
			location: data.location,
		};
	}

	async put(entry: JournalEntry): Promise<void> {
		const dir = this.requireDir();

		// Ensure createdAt is stamped on first save and preserved thereafter.
		const createdAt = entry.createdAt ?? nowIsoWithOffset();

		const serialized = stringifyDoc({
			data: {
				created_at: createdAt,
				location: entry.location,
			},
			content: entry.content,
		});

		const fileHandle = await dir.getFileHandle(fileName(entry.date), {
			create: true,
		});
		const writable = await fileHandle.createWritable();
		await writable.write(serialized);
		await writable.close();
	}

	async list(): Promise<string[]> {
		const dir = this.requireDir();
		const keys: string[] = [];
		for await (const [name, handle] of dir.entries()) {
			if (handle.kind !== "file") continue;
			if (!name.endsWith(".md")) continue;
			keys.push(name.replace(/\.md$/, ""));
		}
		return keys;
	}

	private requireDir(): FileSystemDirectoryHandle {
		if (!this.dirHandle) {
			throw new Error(
				"FsaAdapter not initialized — call init() or pickFolder() first",
			);
		}
		return this.dirHandle;
	}
}

function fileName(date: string): string {
	return `${date}.md`;
}
