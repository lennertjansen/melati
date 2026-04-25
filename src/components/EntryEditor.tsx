import { useCallback, useEffect, useRef, useState } from "react";
import { nowIsoWithOffset, todayKey } from "../lib/date";
import { t } from "../lib/i18n";
import type { JournalEntry, StorageAdapter } from "../storage/StorageAdapter";
import { Editor } from "./Editor";
import { Header } from "./Header";

interface EntryEditorProps {
	adapter: StorageAdapter;
	dateKey: string;
	onBack?: () => void;
}

/**
 * Render and edit a single entry by date key. Today's entry is editable
 * (auto-save 500ms debounce, blur save, beforeunload flush). Past entries
 * are read-only — the paper-permanent feel.
 */
export function EntryEditor({ adapter, dateKey, onBack }: EntryEditorProps) {
	const [entry, setEntry] = useState<JournalEntry | null>(null);
	const [recentLocations, setRecentLocations] = useState<string[]>([]);
	const readOnly = dateKey !== todayKey();

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
		if (readOnly) return;
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
	}, [adapter, readOnly]);

	const entryRef = useRef(entry);
	entryRef.current = entry;

	useEffect(() => {
		if (readOnly || !entry) return;
		const timer = setTimeout(() => {
			adapter.put(entry).catch(console.error);
		}, 500);
		return () => clearTimeout(timer);
	}, [entry, adapter, readOnly]);

	useEffect(() => {
		if (readOnly) return;
		return () => {
			if (entryRef.current) {
				adapter.put(entryRef.current).catch(console.error);
			}
		};
	}, [adapter, readOnly]);

	useEffect(() => {
		if (readOnly) return;
		function flush() {
			if (entryRef.current) {
				adapter.put(entryRef.current).catch(console.error);
			}
		}
		window.addEventListener("beforeunload", flush);
		return () => window.removeEventListener("beforeunload", flush);
	}, [adapter, readOnly]);

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
	const showPlaceholder = !readOnly && isEmpty;

	return (
		<div className="max-w-3xl mx-auto px-4">
			<Header
				dateKey={entry.date}
				createdAt={entry.createdAt}
				location={entry.location}
				recentLocations={recentLocations}
				onLocationChange={handleLocationChange}
				onBack={onBack}
				readOnly={readOnly}
			/>
			<div className="relative">
				{showPlaceholder && (
					<div
						className="absolute inset-0 pointer-events-none font-serif text-lg leading-relaxed max-w-[65ch] mx-auto text-[var(--color-fg-subtle)] pt-[0.4rem]"
						aria-hidden="true"
					>
						{t("placeholder")}
					</div>
				)}
				<Editor
					key={dateKey}
					content={entry.content}
					onChange={handleContentChange}
					onBlur={handleBlur}
					readOnly={readOnly}
				/>
			</div>
		</div>
	);
}
