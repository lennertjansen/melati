import { useEffect, useRef, useState } from "react";
import { t } from "../lib/i18n";

interface LocationFieldProps {
	value: string | null;
	recentLocations: string[];
	onChange: (location: string) => void;
	readOnly?: boolean;
}

/**
 * Inline-editable location span styled to match the surrounding header text.
 * Clicking opens an input with a custom serif suggestions popover (filtered
 * `recentLocations`). Up/Down navigates suggestions; Enter commits the
 * highlighted suggestion (or the current draft); Esc cancels; click-outside
 * commits and closes.
 *
 * In read-only mode (past entries), renders a static span and hides itself
 * entirely when there's no value.
 */
export function LocationField({
	value,
	recentLocations,
	onChange,
	readOnly,
}: LocationFieldProps) {
	const [editing, setEditing] = useState(false);
	const [draft, setDraft] = useState(value ?? "");
	const [activeIdx, setActiveIdx] = useState(-1);
	const wrapperRef = useRef<HTMLSpanElement>(null);
	const inputRef = useRef<HTMLInputElement>(null);

	const filtered = editing
		? recentLocations.filter((loc) =>
				loc.toLowerCase().includes(draft.trim().toLowerCase()),
			)
		: [];

	function startEditing() {
		setDraft(value ?? "");
		setActiveIdx(-1);
		setEditing(true);
		requestAnimationFrame(() => inputRef.current?.focus());
	}

	function commit(override?: string) {
		const next = (override ?? draft).trim();
		if (next && next !== value) onChange(next);
		setEditing(false);
	}

	const draftRef = useRef(draft);
	draftRef.current = draft;

	useEffect(() => {
		if (!editing) return;
		function handleMouseDown(e: MouseEvent) {
			if (
				wrapperRef.current &&
				!wrapperRef.current.contains(e.target as Node)
			) {
				const next = draftRef.current.trim();
				if (next && next !== value) onChange(next);
				setEditing(false);
			}
		}
		document.addEventListener("mousedown", handleMouseDown);
		return () => document.removeEventListener("mousedown", handleMouseDown);
	}, [editing, value, onChange]);

	if (readOnly) {
		if (!value) return null;
		return <span>{value}</span>;
	}

	if (!editing) {
		return (
			<button
				type="button"
				onClick={startEditing}
				className="bg-transparent border-none text-inherit font-inherit cursor-pointer p-0 hover:border-b hover:border-current"
			>
				{value ?? t("location.set")}
			</button>
		);
	}

	function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
		if (e.key === "ArrowDown") {
			e.preventDefault();
			setActiveIdx((i) =>
				filtered.length === 0 ? -1 : (i + 1) % filtered.length,
			);
		} else if (e.key === "ArrowUp") {
			e.preventDefault();
			setActiveIdx((i) =>
				filtered.length === 0 ? -1 : i <= 0 ? filtered.length - 1 : i - 1,
			);
		} else if (e.key === "Enter") {
			e.preventDefault();
			const choice = activeIdx >= 0 ? filtered[activeIdx] : undefined;
			commit(choice);
		} else if (e.key === "Escape") {
			e.preventDefault();
			setEditing(false);
		}
	}

	return (
		<span ref={wrapperRef} className="relative inline-block">
			<input
				ref={inputRef}
				type="text"
				value={draft}
				onChange={(e) => {
					setDraft(e.target.value);
					setActiveIdx(-1);
				}}
				onKeyDown={handleKeyDown}
				className="bg-transparent border-b border-current outline-none text-center font-serif text-inherit w-36"
			/>
			{filtered.length > 0 && (
				<ul className="absolute top-full left-1/2 -translate-x-1/2 mt-1 min-w-full whitespace-nowrap z-20 bg-[var(--color-bg)] border border-[color-mix(in_oklab,var(--color-fg)_15%,transparent)] shadow-sm font-serif text-sm py-1">
					{filtered.map((loc, i) => (
						<li key={loc}>
							<button
								type="button"
								onMouseDown={(e) => {
									e.preventDefault();
									commit(loc);
								}}
								onMouseEnter={() => setActiveIdx(i)}
								className={`w-full text-left px-3 py-1 bg-transparent border-none cursor-pointer ${
									i === activeIdx
										? "text-[var(--color-fg)] bg-[color-mix(in_oklab,var(--color-fg)_8%,transparent)]"
										: "text-[var(--color-fg-subtle)]"
								}`}
							>
								{loc}
							</button>
						</li>
					))}
				</ul>
			)}
		</span>
	);
}
