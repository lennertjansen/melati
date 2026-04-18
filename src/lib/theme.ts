/**
 * Theme system: light / dark, following the OS by default, overridable
 * manually, persisted to localStorage.
 *
 * The plan keeps this simple: a `.dark` class on <html> swaps the CSS
 * variables defined in global.css. No React context, no state libraries —
 * just DOM classList + localStorage + a tiny subscriber for system changes.
 */

const STORAGE_KEY = "noot:theme";

export type Theme = "light" | "dark";

function getSystemTheme(): Theme {
	return window.matchMedia("(prefers-color-scheme: dark)").matches
		? "dark"
		: "light";
}

export function getStoredTheme(): Theme | null {
	const stored = localStorage.getItem(STORAGE_KEY);
	return stored === "light" || stored === "dark" ? stored : null;
}

export function applyTheme(theme: Theme): void {
	document.documentElement.classList.toggle("dark", theme === "dark");
}

/**
 * Read the stored preference (or fall back to OS) and apply it immediately.
 * Call this once on app boot.
 */
export function initTheme(): Theme {
	const current = getStoredTheme() ?? getSystemTheme();
	applyTheme(current);
	return current;
}

/** Flip the theme, apply it, and persist the choice. */
export function toggleTheme(): Theme {
	const isDark = document.documentElement.classList.contains("dark");
	const next: Theme = isDark ? "light" : "dark";
	applyTheme(next);
	localStorage.setItem(STORAGE_KEY, next);
	return next;
}

/**
 * Subscribe to OS-level theme changes. Only follows the OS if the user has
 * NOT manually overridden the theme (no entry in localStorage). Returns an
 * unsubscribe function.
 */
export function subscribeSystemTheme(
	onChange: (theme: Theme) => void,
): () => void {
	const mql = window.matchMedia("(prefers-color-scheme: dark)");
	const handler = (e: MediaQueryListEvent) => {
		if (getStoredTheme() !== null) return; // user has explicit preference
		const next: Theme = e.matches ? "dark" : "light";
		applyTheme(next);
		onChange(next);
	};
	mql.addEventListener("change", handler);
	return () => mql.removeEventListener("change", handler);
}
