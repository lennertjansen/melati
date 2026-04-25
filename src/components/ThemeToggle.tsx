import { useEffect, useState } from "react";
import { getStoredTheme, type Theme, toggleTheme } from "../lib/theme";

interface ThemeToggleProps {
	visible?: boolean;
}

/**
 * Discreet corner button to toggle light/dark theme.
 * Shows a sun (in dark mode) or moon (in light mode).
 */
export function ThemeToggle({ visible = true }: ThemeToggleProps) {
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
			className={`fixed top-4 right-4 p-2 rounded-full text-[var(--color-fg-subtle)] hover:text-[var(--color-fg)] cursor-pointer bg-transparent border-none text-lg z-10 transition-opacity duration-300 ${
				visible ? "opacity-100" : "opacity-0 pointer-events-none"
			}`}
		>
			{theme === "dark" ? "\u2600" : "\u263E"}
		</button>
	);
}
