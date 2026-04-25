import { useEffect, useMemo, useState } from "react";
import {
	formatMonthYear,
	getMonthDays,
	getWeekdayLabels,
	todayKey,
} from "../lib/date";
import { type EntrySummary, loadEntrySummaries } from "../lib/entries";
import { getFirstDayOfWeek, t } from "../lib/i18n";
import type { StorageAdapter } from "../storage/StorageAdapter";

interface CalendarViewProps {
	adapter: StorageAdapter;
	onSelectDate: (dateKey: string) => void;
}

const CELL_BORDER =
	"border-[color-mix(in_oklab,var(--color-fg)_10%,transparent)]";

/**
 * Notion-style month grid. Each cell is filled — day number top-right and a
 * single-line preview below for any day with an entry. Today's day number
 * gets the inverted-circle treatment. Only today + days with existing
 * entries are clickable.
 */
export function CalendarView({ adapter, onSelectDate }: CalendarViewProps) {
	const today = todayKey();
	const now = new Date();
	const [year, setYear] = useState(now.getFullYear());
	const [month, setMonth] = useState(now.getMonth());
	const [summaries, setSummaries] = useState<Map<string, EntrySummary> | null>(
		null,
	);

	useEffect(() => {
		let cancelled = false;
		loadEntrySummaries(adapter)
			.then((list) => {
				if (cancelled) return;
				const byKey = new Map<string, EntrySummary>();
				for (const s of list) byKey.set(s.dateKey, s);
				setSummaries(byKey);
			})
			.catch(console.error);
		return () => {
			cancelled = true;
		};
	}, [adapter]);

	const firstDayOfWeek = getFirstDayOfWeek();
	const weekdayLabels = useMemo(() => getWeekdayLabels(), []);
	const days = useMemo(
		() => getMonthDays(year, month, firstDayOfWeek),
		[year, month, firstDayOfWeek],
	);

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

	if (!summaries) return null;

	return (
		<div className="max-w-5xl mx-auto px-4 py-6 font-serif">
			<div className="flex items-center justify-center gap-6 mb-6 text-[var(--color-fg)]">
				<button
					type="button"
					onClick={prevMonth}
					aria-label={t("cal.prev")}
					className="bg-transparent border-none cursor-pointer text-[var(--color-fg-subtle)] hover:text-[var(--color-fg)] text-lg"
				>
					‹
				</button>
				<h2 className="text-base">{formatMonthYear(year, month)}</h2>
				<button
					type="button"
					onClick={nextMonth}
					aria-label={t("cal.next")}
					className="bg-transparent border-none cursor-pointer text-[var(--color-fg-subtle)] hover:text-[var(--color-fg)] text-lg"
				>
					›
				</button>
			</div>

			<div className="grid grid-cols-7 mb-1 text-xs text-[var(--color-fg-subtle)] uppercase tracking-wide">
				{weekdayLabels.map((d) => (
					<div key={d.dayOfWeek} className="text-center py-2">
						{d.label}
					</div>
				))}
			</div>

			<div className={`grid grid-cols-7 border-l border-t ${CELL_BORDER}`}>
				{days.map((day) => {
					const isToday = day.dateKey === today;
					const summary = summaries.get(day.dateKey);
					const hasEntry = !!summary;
					const clickable = day.isCurrentMonth && (isToday || hasEntry);

					return (
						<button
							key={day.dateKey}
							type="button"
							disabled={!clickable}
							onClick={() => clickable && onSelectDate(day.dateKey)}
							className={`min-h-24 p-2 border-r border-b ${CELL_BORDER} flex flex-col items-stretch text-left bg-transparent transition-colors ${
								clickable
									? "cursor-pointer hover:bg-[color-mix(in_oklab,var(--color-fg)_4%,transparent)]"
									: "cursor-default"
							}`}
						>
							<div className="flex justify-end">
								{isToday ? (
									<span className="inline-flex items-center justify-center w-6 h-6 rounded-full bg-[var(--color-fg)] text-[var(--color-bg)] text-xs">
										{day.date.getDate()}
									</span>
								) : (
									<span
										className={`text-xs ${
											day.isCurrentMonth
												? hasEntry
													? "text-[var(--color-fg)]"
													: "text-[var(--color-fg-subtle)]"
												: "text-[color-mix(in_oklab,var(--color-fg-subtle)_50%,transparent)]"
										}`}
									>
										{day.date.getDate()}
									</span>
								)}
							</div>
							{hasEntry && day.isCurrentMonth && summary.preview && (
								<div className="mt-1 text-xs text-[var(--color-fg-subtle)] truncate">
									{summary.preview}
								</div>
							)}
						</button>
					);
				})}
			</div>
		</div>
	);
}
