import { useEffect, useState } from "react";
import { getStoredTheme, type Theme, toggleTheme } from "../lib/theme";

/**
 * Discreet corner button to toggle light/dark theme.
 * Shows a sun (in dark mode) or moon (in light mode).
 */
export function ThemeToggle() {
	const [theme, setTheme] = useState<Theme>(() => {
		const stored = getStoredTheme();
		if (stored) return stored;
		return document.documentElement.classList.contains("dark")
			? "dark"
			: "light";
	});

	// Stay in sync when Cmd+Shift+L toggles the theme externally.
	useEffect(() => {
		const observer = new MutationObserver(() => {
			const isDark = document.documentElement.classList.contains("dark");
			setTheme(isDark ? "dark" : "light");
		});
		observer.observe(document.documentElement, {
			attributes: true,
			attributeFilter: ["class"],
		});
		return () => observer.disconnect();
	}, []);

	function handleClick() {
		const next = toggleTheme();
		setTheme(next);
	}

	return (
		<button
			type="button"
			onClick={handleClick}
			aria-label={
				theme === "dark" ? "Switch to light mode" : "Switch to dark mode"
			}
			className="fixed bottom-4 right-4 p-2 rounded-full text-[var(--color-fg-subtle)] hover:text-[var(--color-fg)] transition-colors cursor-pointer bg-transparent border-none text-lg"
		>
			{theme === "dark" ? "\u2600" : "\u263E"}
		</button>
	);
}
