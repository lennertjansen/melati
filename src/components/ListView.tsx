import { useEffect, useMemo, useState } from "react";
import { formatRelativeDate, parseDateKey } from "../lib/date";
import { type EntrySummary, loadEntrySummaries } from "../lib/entries";
import { getIntlLocale, t } from "../lib/i18n";
import type { StorageAdapter } from "../storage/StorageAdapter";

interface ListViewProps {
	adapter: StorageAdapter;
	onSelectDate: (dateKey: string) => void;
}

type Grouping = "flat" | "grouped";
const GROUPING_KEY = "noot.listGrouping";

function getStoredGrouping(): Grouping {
	const stored = localStorage.getItem(GROUPING_KEY);
	return stored === "grouped" ? "grouped" : "flat";
}

function monthKey(dateKey: string): string {
	return dateKey.slice(0, 7);
}

function formatMonthLabel(monthKey: string): string {
	const [y, m] = monthKey.split("-").map(Number);
	return new Date(y, m - 1, 1).toLocaleDateString(getIntlLocale(), {
		month: "long",
		year: "numeric",
	});
}

/**
 * Chronological list of all entries, most recent first. Supports a
 * flat/grouped toggle (preference persists in localStorage).
 */
export function ListView({ adapter, onSelectDate }: ListViewProps) {
	const [summaries, setSummaries] = useState<EntrySummary[] | null>(null);
	const [grouping, setGrouping] = useState<Grouping>(() => getStoredGrouping());

	useEffect(() => {
		let cancelled = false;
		loadEntrySummaries(adapter)
			.then((s) => {
				if (!cancelled) setSummaries(s);
			})
			.catch(console.error);
		return () => {
			cancelled = true;
		};
	}, [adapter]);

	function setGroupingPersisted(next: Grouping) {
		setGrouping(next);
		localStorage.setItem(GROUPING_KEY, next);
	}

	const grouped = useMemo(() => {
		if (!summaries) return null;
		const groups: { month: string; items: EntrySummary[] }[] = [];
		for (const s of summaries) {
			const m = monthKey(s.dateKey);
			const last = groups[groups.length - 1];
			if (last && last.month === m) {
				last.items.push(s);
			} else {
				groups.push({ month: m, items: [s] });
			}
		}
		return groups;
	}, [summaries]);

	if (!summaries) return null;

	if (summaries.length === 0) {
		return (
			<div className="max-w-3xl mx-auto px-4 py-24 text-center font-serif text-[var(--color-fg-subtle)]">
				{t("list.empty")}
			</div>
		);
	}

	return (
		<div className="max-w-3xl mx-auto px-4 py-6">
			<div className="flex justify-end mb-4 font-serif text-xs">
				<div className="flex items-center gap-3 text-[var(--color-fg-subtle)]">
					<button
						type="button"
						onClick={() => setGroupingPersisted("flat")}
						className={`bg-transparent border-none cursor-pointer transition-colors ${
							grouping === "flat"
								? "font-semibold text-[var(--color-fg)]"
								: "hover:text-[var(--color-fg)]"
						}`}
					>
						{t("list.flat")}
					</button>
					<span aria-hidden="true">·</span>
					<button
						type="button"
						onClick={() => setGroupingPersisted("grouped")}
						className={`bg-transparent border-none cursor-pointer transition-colors ${
							grouping === "grouped"
								? "font-semibold text-[var(--color-fg)]"
								: "hover:text-[var(--color-fg)]"
						}`}
					>
						{t("list.grouped")}
					</button>
				</div>
			</div>

			{grouping === "flat"
				? summaries.map((s) => (
						<EntryRow key={s.dateKey} summary={s} onSelect={onSelectDate} />
					))
				: grouped?.map((g) => (
						<section key={g.month} className="mb-6">
							<h2 className="font-serif text-xs uppercase tracking-wide text-[var(--color-fg-subtle)] py-2">
								{formatMonthLabel(g.month)}
							</h2>
							{g.items.map((s) => (
								<EntryRow key={s.dateKey} summary={s} onSelect={onSelectDate} />
							))}
						</section>
					))}
		</div>
	);
}

function EntryRow({
	summary,
	onSelect,
}: {
	summary: EntrySummary;
	onSelect: (dateKey: string) => void;
}) {
	const dateLabel = formatRelativeDate(summary.dateKey);
	const shortDate = parseDateKey(summary.dateKey).toLocaleDateString(
		getIntlLocale(),
		{
			month: "short",
			day: "numeric",
		},
	);
	const showShort =
		dateLabel === t("relative.today") || dateLabel === t("relative.yesterday");

	return (
		<button
			type="button"
			onClick={() => onSelect(summary.dateKey)}
			className="w-full text-left bg-transparent border-none border-b border-solid border-[color-mix(in_oklab,var(--color-fg)_10%,transparent)] cursor-pointer py-4 px-0 font-serif"
		>
			<div className="flex items-baseline gap-2 text-[var(--color-fg)]">
				<span className="font-semibold">{dateLabel}</span>
				{showShort && (
					<span className="text-xs text-[var(--color-fg-subtle)]">
						{shortDate}
					</span>
				)}
				{summary.location && (
					<>
						<span aria-hidden="true" className="text-[var(--color-fg-subtle)]">
							·
						</span>
						<span className="text-sm text-[var(--color-fg-subtle)]">
							{summary.location}
						</span>
					</>
				)}
			</div>
			{summary.preview && (
				<div className="mt-1 text-sm text-[var(--color-fg-subtle)] truncate">
					{summary.preview}
				</div>
			)}
		</button>
	);
}
