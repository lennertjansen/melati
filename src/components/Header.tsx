import { useMemo } from "react";
import { formatHeaderParts } from "../lib/date";
import { t } from "../lib/i18n";
import { LocationField } from "./LocationField";

interface HeaderProps {
	dateKey: string;
	createdAt: string | null;
	location: string | null;
	recentLocations: string[];
	onLocationChange: (location: string) => void;
	onBack?: () => void;
	readOnly?: boolean;
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
	onBack,
	readOnly,
}: HeaderProps) {
	const { dayName, dateText, timeText } = useMemo(
		() => formatHeaderParts(dateKey, createdAt),
		[dateKey, createdAt],
	);

	const showLocationDot = !readOnly || !!location;

	return (
		<div className="relative">
			{onBack && (
				<button
					type="button"
					onClick={onBack}
					className="absolute left-0 top-6 bg-transparent border-none cursor-pointer text-[var(--color-fg-subtle)] hover:text-[var(--color-fg)] font-serif text-sm transition-colors"
				>
					{t("back")}
				</button>
			)}
			<header className="flex flex-wrap items-center justify-center gap-2 py-6 text-[var(--color-fg-subtle)] font-serif text-sm select-none">
				<span>{dayName}</span>
				<span aria-hidden="true">·</span>
				<span>{dateText}</span>
				<span aria-hidden="true">·</span>
				<span>{timeText}</span>
				{showLocationDot && <span aria-hidden="true">·</span>}
				<LocationField
					value={location}
					recentLocations={recentLocations}
					onChange={onLocationChange}
					readOnly={readOnly}
				/>
			</header>
		</div>
	);
}
