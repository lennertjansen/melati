import { useCallback, useEffect, useRef, useState } from "react";
import { nowIsoWithOffset } from "../lib/date";
import type { JournalEntry, StorageAdapter } from "../storage/StorageAdapter";
import { Editor } from "./Editor";
import { Header } from "./Header";

interface EntryEditorProps {
	adapter: StorageAdapter;
	dateKey: string;
	onBack?: () => void;
}

/**
 * Render and edit a single entry by date key. Loads (or creates) the entry
 * on mount, auto-saves on change (500ms debounce), and flushes pending
 * writes before navigating away.
 */
export function EntryEditor({ adapter, dateKey, onBack }: EntryEditorProps) {
	const [entry, setEntry] = useState<JournalEntry | null>(null);
	const [recentLocations, setRecentLocations] = useState<string[]>([]);

	useEffect(() => {
		let cancelled = false;
		setEntry(null);
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

	const entryRef = useRef(entry);
	entryRef.current = entry;

	useEffect(() => {
		if (!entry) return;
		const timer = setTimeout(() => {
			adapter.put(entry).catch(console.error);
		}, 500);
		return () => clearTimeout(timer);
	}, [entry, adapter]);

	// Flush pending writes before unmount or when the entry changes.
	useEffect(() => {
		return () => {
			if (entryRef.current) {
				adapter.put(entryRef.current).catch(console.error);
			}
		};
	}, [adapter]);

	useEffect(() => {
		function flush() {
			if (entryRef.current) {
				adapter.put(entryRef.current).catch(console.error);
			}
		}
		window.addEventListener("beforeunload", flush);
		return () => window.removeEventListener("beforeunload", flush);
	}, [adapter]);

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

	if (!entry) {
		return null;
	}

	const isEmpty = entry.content.trim() === "";

	return (
		<div className="max-w-3xl mx-auto px-4">
			<Header
				dateKey={entry.date}
				createdAt={entry.createdAt}
				location={entry.location}
				recentLocations={recentLocations}
				onLocationChange={handleLocationChange}
				onBack={onBack}
			/>
			<div className="relative">
				{isEmpty && (
					<div
						className="absolute inset-0 pointer-events-none font-serif text-lg leading-relaxed max-w-[65ch] mx-auto text-[var(--color-fg-subtle)] pt-[0.4rem]"
						aria-hidden="true"
					>
						Start writing…
					</div>
				)}
				<Editor
					key={dateKey}
					content={entry.content}
					onChange={handleContentChange}
					onBlur={handleBlur}
				/>
			</div>
		</div>
	);
}
