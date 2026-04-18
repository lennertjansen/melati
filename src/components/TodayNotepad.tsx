import { useCallback, useEffect, useRef, useState } from "react";
import { nowIsoWithOffset, todayKey } from "../lib/date";
import type { JournalEntry, StorageAdapter } from "../storage/StorageAdapter";
import { Editor } from "./Editor";
import { Header } from "./Header";

interface TodayNotepadProps {
	adapter: StorageAdapter;
}

/**
 * The main screen: today's entry. Loads (or creates) the entry on mount,
 * renders the header + editor, and auto-saves on every content change
 * (debounced 500ms).
 */
export function TodayNotepad({ adapter }: TodayNotepadProps) {
	const [entry, setEntry] = useState<JournalEntry | null>(null);
	const [recentLocations, setRecentLocations] = useState<string[]>([]);
	const dateKey = todayKey();

	// -- Load or create today's entry ----------------------------------------

	useEffect(() => {
		let cancelled = false;
		async function load() {
			const existing = await adapter.get(dateKey);
			if (cancelled) return;
			if (existing) {
				setEntry(existing);
			} else {
				setEntry({
					date: dateKey,
					content: "",
					createdAt: nowIsoWithOffset(),
					location: null,
				});
			}
		}
		load().catch(console.error);
		return () => {
			cancelled = true;
		};
	}, [adapter, dateKey]);

	// -- Collect recent locations from past entries --------------------------

	useEffect(() => {
		async function scan() {
			const keys = await adapter.list();
			const locations = new Set<string>();
			for (const key of keys) {
				const e = await adapter.get(key);
				if (e?.location) locations.add(e.location);
			}
			setRecentLocations([...locations].sort());
		}
		scan().catch(console.error);
	}, [adapter]);

	// -- Debounced auto-save (500ms) -----------------------------------------

	const entryRef = useRef(entry);
	entryRef.current = entry;

	useEffect(() => {
		if (!entry) return;
		const timer = setTimeout(() => {
			adapter.put(entry).catch(console.error);
		}, 500);
		return () => clearTimeout(timer);
	}, [entry, adapter]);

	// -- Save on beforeunload -------------------------------------------------

	useEffect(() => {
		function flush() {
			if (entryRef.current) {
				adapter.put(entryRef.current).catch(console.error);
			}
		}
		window.addEventListener("beforeunload", flush);
		return () => window.removeEventListener("beforeunload", flush);
	}, [adapter]);

	// -- Handlers -------------------------------------------------------------

	const handleContentChange = useCallback((value: string) => {
		setEntry((prev) => (prev ? { ...prev, content: value } : prev));
	}, []);

	const handleLocationChange = useCallback((location: string) => {
		setEntry((prev) => (prev ? { ...prev, location } : prev));
	}, []);

	const handleBlur = useCallback(() => {
		if (entryRef.current) {
			adapter.put(entryRef.current).catch(console.error);
		}
	}, [adapter]);

	// -- Render ----------------------------------------------------------------

	if (!entry) {
		return null; // loading
	}

	return (
		<div className="max-w-3xl mx-auto px-4">
			<Header
				dateKey={entry.date}
				createdAt={entry.createdAt}
				location={entry.location}
				recentLocations={recentLocations}
				onLocationChange={handleLocationChange}
			/>
			<Editor
				content={entry.content}
				onChange={handleContentChange}
				onBlur={handleBlur}
			/>
		</div>
	);
}
