import { useRef, useState } from "react";

interface LocationFieldProps {
	value: string | null;
	recentLocations: string[];
	onChange: (location: string) => void;
}

/**
 * Inline-editable location span. By default it looks like the surrounding
 * header text. Clicking reveals an <input> with a datalist of recent
 * locations. The change is committed on Enter or blur.
 */
export function LocationField({
	value,
	recentLocations,
	onChange,
}: LocationFieldProps) {
	const [editing, setEditing] = useState(false);
	const [draft, setDraft] = useState(value ?? "");
	const inputRef = useRef<HTMLInputElement>(null);

	function startEditing() {
		setDraft(value ?? "");
		setEditing(true);
		// Focus on next tick after the input is mounted.
		requestAnimationFrame(() => inputRef.current?.focus());
	}

	function commit() {
		const trimmed = draft.trim();
		if (trimmed && trimmed !== value) {
			onChange(trimmed);
		}
		setEditing(false);
	}

	if (editing) {
		return (
			<>
				<input
					ref={inputRef}
					list="noot-recent-locations"
					type="text"
					value={draft}
					onChange={(e) => setDraft(e.target.value)}
					onBlur={commit}
					onKeyDown={(e) => {
						if (e.key === "Enter") commit();
						if (e.key === "Escape") setEditing(false);
					}}
					className="bg-transparent border-b border-current outline-none text-center font-serif text-inherit w-36"
				/>
				<datalist id="noot-recent-locations">
					{recentLocations.map((loc) => (
						<option key={loc} value={loc} />
					))}
				</datalist>
			</>
		);
	}

	return (
		<button
			type="button"
			onClick={startEditing}
			className="bg-transparent border-none text-inherit font-inherit cursor-pointer p-0 hover:border-b hover:border-current"
		>
			{value ?? "Set location"}
		</button>
	);
}
