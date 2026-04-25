import { useEffect, useMemo, useState } from "react";
import { formatMonthYear, getMonthDays, todayKey } from "../lib/date";
import { loadEntryDates } from "../lib/entries";
import type { StorageAdapter } from "../storage/StorageAdapter";

interface CalendarViewProps {
	adapter: StorageAdapter;
	onSelectDate: (dateKey: string) => void;
}

const DAY_LABELS = [
	{ key: "sun", label: "S" },
	{ key: "mon", label: "M" },
	{ key: "tue", label: "T" },
	{ key: "wed", label: "W" },
	{ key: "thu", label: "T" },
	{ key: "fri", label: "F" },
	{ key: "sat", label: "S" },
];

/**
 * Month-grid calendar. Shows a dot under any day with an entry. Today is
 * rendered as an inverted circle. Only today + days with existing entries
 * are clickable.
 */
export function CalendarView({ adapter, onSelectDate }: CalendarViewProps) {
	const today = todayKey();
	const now = new Date();
	const [year, setYear] = useState(now.getFullYear());
	const [month, setMonth] = useState(now.getMonth());
	const [entryDates, setEntryDates] = useState<Set<string> | null>(null);

	useEffect(() => {
		let cancelled = false;
		loadEntryDates(adapter)
			.then((dates) => {
				if (!cancelled) setEntryDates(dates);
			})
			.catch(console.error);
		return () => {
			cancelled = true;
		};
	}, [adapter]);

	const days = useMemo(() => getMonthDays(year, month), [year, month]);

	function prevMonth() {
		if (month === 0) {
			setYear(year - 1);
			setMonth(11);
		} else {
			setMonth(month - 1);
		}
	}

	function nextMonth() {
		if (month === 11) {
			setYear(year + 1);
			setMonth(0);
		} else {
			setMonth(month + 1);
		}
	}

	if (!entryDates) return null;

	return (
		<div className="max-w-3xl mx-auto px-4 py-6 font-serif">
			<div className="flex items-center justify-center gap-6 mb-6 text-[var(--color-fg)]">
				<button
					type="button"
					onClick={prevMonth}
					aria-label="Previous month"
					className="bg-transparent border-none cursor-pointer text-[var(--color-fg-subtle)] hover:text-[var(--color-fg)] text-lg"
				>
					‹
				</button>
				<h2 className="text-base">{formatMonthYear(year, month)}</h2>
				<button
					type="button"
					onClick={nextMonth}
					aria-label="Next month"
					className="bg-transparent border-none cursor-pointer text-[var(--color-fg-subtle)] hover:text-[var(--color-fg)] text-lg"
				>
					›
				</button>
			</div>

			<div className="grid grid-cols-7 gap-1 mb-2 text-xs text-[var(--color-fg-subtle)]">
				{DAY_LABELS.map((d) => (
					<div key={d.key} className="text-center py-2">
						{d.label}
					</div>
				))}
			</div>

			<div className="grid grid-cols-7 gap-1">
				{days.map((day) => {
					const isToday = day.dateKey === today;
					const hasEntry = entryDates.has(day.dateKey);
					const clickable = isToday || hasEntry;

					return (
						<button
							key={day.dateKey}
							type="button"
							disabled={!clickable}
							onClick={() => clickable && onSelectDate(day.dateKey)}
							className={`aspect-square flex flex-col items-center justify-center rounded-full bg-transparent border-none text-sm transition-colors ${
								clickable ? "cursor-pointer" : "cursor-default"
							} ${
								isToday
									? "bg-[var(--color-fg)] text-[var(--color-bg)]"
									: day.isCurrentMonth
										? clickable
											? "text-[var(--color-fg)] hover:bg-[color-mix(in_oklab,var(--color-fg)_8%,transparent)]"
											: "text-[var(--color-fg-subtle)]"
										: "text-[color-mix(in_oklab,var(--color-fg-subtle)_50%,transparent)]"
							}`}
						>
							<span>{day.date.getDate()}</span>
							{hasEntry && !isToday && (
								<span className="block w-1 h-1 rounded-full bg-[var(--color-fg-subtle)] mt-0.5" />
							)}
						</button>
					);
				})}
			</div>
		</div>
	);
}
