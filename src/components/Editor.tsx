import { useEffect, useRef, useState } from "react";
import { Preview } from "./Preview";

interface EditorProps {
	content: string;
	onChange: (value: string) => void;
}

/**
 * Fullscreen editor with Cmd+E toggle between textarea and rendered preview.
 *
 * The textarea is purposefully unstyled — no borders, no background — so it
 * feels like writing on a blank page. Same font, size, and max-width as the
 * Preview for visual continuity when toggling.
 */
export function Editor({ content, onChange }: EditorProps) {
	const [mode, setMode] = useState<"edit" | "preview">("edit");
	const textareaRef = useRef<HTMLTextAreaElement>(null);

	// Auto-focus when entering edit mode.
	useEffect(() => {
		if (mode === "edit") {
			textareaRef.current?.focus();
		}
	}, [mode]);

	// Cmd+E toggles edit/preview.
	useEffect(() => {
		function handleKey(e: KeyboardEvent) {
			if ((e.metaKey || e.ctrlKey) && e.key === "e") {
				e.preventDefault();
				setMode((m) => (m === "edit" ? "preview" : "edit"));
			}
		}
		window.addEventListener("keydown", handleKey);
		return () => window.removeEventListener("keydown", handleKey);
	}, []);

	if (mode === "preview") {
		return <Preview content={content} />;
	}

	return (
		<textarea
			ref={textareaRef}
			value={content}
			onChange={(e) => onChange(e.target.value)}
			placeholder="Start writing..."
			className="w-full max-w-[65ch] mx-auto block min-h-[70vh] bg-transparent outline-none resize-none text-lg leading-relaxed font-serif text-[var(--color-fg)] placeholder:text-[var(--color-fg-subtle)]"
		/>
	);
}
