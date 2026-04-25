import type { StorageAdapter } from "../storage/StorageAdapter";

export interface EntrySummary {
	dateKey: string;
	location: string | null;
	preview: string;
}

/**
 * Strip common markdown syntax from a single line so previews look like plain
 * text. Not a full parser — just enough to clean up headings, emphasis,
 * inline code, and link syntax for at-a-glance reading.
 */
function stripMarkdown(line: string): string {
	return line
		.replace(/^#{1,6}\s+/, "")
		.replace(/^[-*+]\s+/, "")
		.replace(/^>\s+/, "")
		.replace(/`([^`]+)`/g, "$1")
		.replace(/\*\*([^*]+)\*\*/g, "$1")
		.replace(/__([^_]+)__/g, "$1")
		.replace(/\*([^*]+)\*/g, "$1")
		.replace(/_([^_]+)_/g, "$1")
		.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
		.trim();
}

/** First non-empty line of `content`, with markdown stripped, truncated. */
export function extractPreview(content: string, maxLength = 100): string {
	const lines = content.split("\n");
	for (const line of lines) {
		const cleaned = stripMarkdown(line);
		if (cleaned) {
			return cleaned.length > maxLength
				? `${cleaned.slice(0, maxLength).trimEnd()}…`
				: cleaned;
		}
	}
	return "";
}

/**
 * Load every entry as a summary, sorted by date descending (most recent
 * first). Used by ListView.
 */
export async function loadEntrySummaries(
	adapter: StorageAdapter,
): Promise<EntrySummary[]> {
	const keys = await adapter.list();
	const summaries: EntrySummary[] = [];
	for (const key of keys) {
		const entry = await adapter.get(key);
		if (!entry) continue;
		summaries.push({
			dateKey: entry.date,
			location: entry.location,
			preview: extractPreview(entry.content),
		});
	}
	summaries.sort((a, b) => (a.dateKey < b.dateKey ? 1 : -1));
	return summaries;
}

/** Set of every date key that has an entry. Used by CalendarView for dots. */
export async function loadEntryDates(
	adapter: StorageAdapter,
): Promise<Set<string>> {
	const keys = await adapter.list();
	return new Set(keys);
}
