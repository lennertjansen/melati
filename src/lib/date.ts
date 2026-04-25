/**
 * Date + header formatting helpers.
 *
 * Noot uses ISO date strings (YYYY-MM-DD) as the canonical "entry key" — it's
 * the filename, it's sortable, and it's trivially parsed. Everything else is
 * derivable: day-of-week, pretty date, pretty time.
 */

/** Returns today's date in the user's LOCAL timezone as YYYY-MM-DD. */
export function todayKey(): string {
	return toDateKey(new Date());
}

/** Converts a Date to a YYYY-MM-DD string in the user's local timezone. */
export function toDateKey(date: Date): string {
	const year = date.getFullYear();
	const month = String(date.getMonth() + 1).padStart(2, "0");
	const day = String(date.getDate()).padStart(2, "0");
	return `${year}-${month}-${day}`;
}

/** Returns the current wall-clock time as an ISO string with local offset. */
export function nowIsoWithOffset(): string {
	const now = new Date();
	const tzOffsetMin = -now.getTimezoneOffset();
	const sign = tzOffsetMin >= 0 ? "+" : "-";
	const absMin = Math.abs(tzOffsetMin);
	const offH = String(Math.floor(absMin / 60)).padStart(2, "0");
	const offM = String(absMin % 60).padStart(2, "0");
	const pad = (n: number) => String(n).padStart(2, "0");
	return (
		`${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}` +
		`T${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}` +
		`${sign}${offH}:${offM}`
	);
}

export interface HeaderParts {
	/** e.g. "Saturday" */
	dayName: string;
	/** e.g. "April 11, 2026" */
	dateText: string;
	/** e.g. "1:05 PM" */
	timeText: string;
}

/**
 * Build the header fragments for a given entry.
 *
 * - `dateKey` is the filename date (YYYY-MM-DD). It determines the day name
 *   and the pretty date.
 * - `createdAtIso` is the wall-clock time of first write, pulled from the
 *   entry's frontmatter. It determines the time shown in the header.
 */
export function formatHeaderParts(
	dateKey: string,
	createdAtIso: string | null,
): HeaderParts {
	const dayDate = parseDateKey(dateKey);
	const dayName = dayDate.toLocaleDateString(undefined, { weekday: "long" });
	const dateText = dayDate.toLocaleDateString(undefined, {
		month: "long",
		day: "numeric",
		year: "numeric",
	});

	const timeSource = createdAtIso ? new Date(createdAtIso) : new Date();
	const timeText = timeSource.toLocaleTimeString(undefined, {
		hour: "numeric",
		minute: "2-digit",
	});

	return { dayName, dateText, timeText };
}

/** Parse a YYYY-MM-DD string into a Date at local midnight. */
export function parseDateKey(key: string): Date {
	const [y, m, d] = key.split("-").map(Number);
	return new Date(y, m - 1, d);
}

/**
 * Format a date key relative to today: "Today", "Yesterday", or a long-form
 * date like "April 11, 2026".
 */
export function formatRelativeDate(dateKey: string): string {
	if (dateKey === todayKey()) return "Today";
	const today = new Date();
	const yesterday = new Date(
		today.getFullYear(),
		today.getMonth(),
		today.getDate() - 1,
	);
	if (dateKey === toDateKey(yesterday)) return "Yesterday";
	return parseDateKey(dateKey).toLocaleDateString(undefined, {
		weekday: "long",
		month: "long",
		day: "numeric",
		year: "numeric",
	});
}

export interface MonthDay {
	date: Date;
	dateKey: string;
	isCurrentMonth: boolean;
}

/**
 * 6-week (42-cell) calendar grid for a given month, starting on Sunday.
 * Includes trailing days from the previous month and leading days of the
 * next month so the grid is always 7×6.
 */
export function getMonthDays(year: number, month: number): MonthDay[] {
	const firstOfMonth = new Date(year, month, 1);
	const startOffset = firstOfMonth.getDay();
	const gridStart = new Date(year, month, 1 - startOffset);
	const days: MonthDay[] = [];
	for (let i = 0; i < 42; i++) {
		const d = new Date(
			gridStart.getFullYear(),
			gridStart.getMonth(),
			gridStart.getDate() + i,
		);
		days.push({
			date: d,
			dateKey: toDateKey(d),
			isCurrentMonth: d.getMonth() === month,
		});
	}
	return days;
}

/** "April 2026" — month and year in the user's locale. */
export function formatMonthYear(year: number, month: number): string {
	return new Date(year, month, 1).toLocaleDateString(undefined, {
		month: "long",
		year: "numeric",
	});
}
