import { useMemo } from "react";
import { formatHeaderParts } from "../lib/date";
import { LocationField } from "./LocationField";

interface HeaderProps {
	dateKey: string;
	createdAt: string | null;
	location: string | null;
	recentLocations: string[];
	onLocationChange: (location: string) => void;
}

/**
 * Subtle centered header anchoring the entry in time and place.
 *
 *   Saturday · April 11, 2026 · 1:05 PM · Amsterdam
 *
 * The location is inline-editable via <LocationField>.
 */
export function Header({
	dateKey,
	createdAt,
	location,
	recentLocations,
	onLocationChange,
}: HeaderProps) {
	const { dayName, dateText, timeText } = useMemo(
		() => formatHeaderParts(dateKey, createdAt),
		[dateKey, createdAt],
	);

	return (
		<header className="flex flex-wrap items-center justify-center gap-2 py-6 text-[var(--color-fg-subtle)] font-serif text-sm select-none">
			<span>{dayName}</span>
			<span aria-hidden="true">·</span>
			<span>{dateText}</span>
			<span aria-hidden="true">·</span>
			<span>{timeText}</span>
			<span aria-hidden="true">·</span>
			<LocationField
				value={location}
				recentLocations={recentLocations}
				onChange={onLocationChange}
			/>
		</header>
	);
}
