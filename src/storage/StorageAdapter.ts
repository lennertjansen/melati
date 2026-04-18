/**
 * Storage abstraction.
 *
 * All file I/O goes through this interface. The single most important
 * architectural decision in Phase 1 — it decouples the app from the File
 * System Access API so that we can:
 *
 *   - swap in a different backend later (IndexedDB fallback, iCloud Drive,
 *     R2 blob store) without touching the UI layer
 *   - export every entry to a native app in a 10-line script that only
 *     touches the adapter
 *   - stub out the storage layer for tests (Phase 1.5+)
 *
 * The single source of truth is the JournalEntry record; all app state
 * flows around values of this shape.
 */

export interface JournalEntry {
	/** ISO date key, YYYY-MM-DD. Doubles as the filename stem. */
	date: string;
	/** Markdown body WITHOUT frontmatter. */
	content: string;
	/** Wall-clock time of first write, ISO with local offset. Null until first save. */
	createdAt: string | null;
	/** User-set location (e.g. "Amsterdam"). Null until set. */
	location: string | null;
}

/**
 * Thrown by `init()` when restoring silently is not possible and the app
 * must show its FolderPicker gate. The caller catches this and renders a
 * button that will ultimately call `pickFolder()` inside a user gesture.
 */
export class NeedsFolderError extends Error {
	constructor(message = "Noot needs the user to pick a folder") {
		super(message);
		this.name = "NeedsFolderError";
	}
}

export interface StorageAdapter {
	/**
	 * Attempt to restore persisted state (handle, permission) silently,
	 * without any user interaction. Call on app boot. If restoration
	 * requires the user to pick a folder or re-grant access, this throws
	 * `NeedsFolderError` and the app should render its FolderPicker.
	 */
	init(): Promise<void>;

	/**
	 * Open the native directory picker and grant Noot access. Must be
	 * called from inside a user gesture (click handler). On success the
	 * adapter becomes ready.
	 */
	pickFolder(): Promise<void>;

	/** Whether the adapter is ready to serve reads/writes. */
	isReady(): boolean;

	/** Load an entry by date key, or null if no file exists yet. */
	get(date: string): Promise<JournalEntry | null>;

	/** Create or overwrite an entry. */
	put(entry: JournalEntry): Promise<void>;

	/** List every stored date key (YYYY-MM-DD), unordered. */
	list(): Promise<string[]>;
}
