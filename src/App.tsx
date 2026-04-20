import { useEffect, useMemo, useState } from "react";
import { ThemeToggle } from "./components/ThemeToggle";
import { TodayNotepad } from "./components/TodayNotepad";
import { initTheme, subscribeSystemTheme, toggleTheme } from "./lib/theme";
import { IdbAdapter } from "./storage/IdbAdapter";

type AppState = "loading" | "ready";

export default function App() {
	const adapter = useMemo(() => new IdbAdapter(), []);
	const [state, setState] = useState<AppState>("loading");

	// -- Theme bootstrap -------------------------------------------------------

	useEffect(() => {
		initTheme();
		return subscribeSystemTheme(() => {});
	}, []);

	// Cmd+Shift+L to toggle theme.
	useEffect(() => {
		function handleKey(e: KeyboardEvent) {
			if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key === "L") {
				e.preventDefault();
				toggleTheme();
			}
		}
		window.addEventListener("keydown", handleKey);
		return () => window.removeEventListener("keydown", handleKey);
	}, []);

	// -- Storage bootstrap -----------------------------------------------------

	useEffect(() => {
		adapter
			.init()
			.then(() => setState("ready"))
			.catch((err) => {
				console.error("Storage init error:", err);
			});
	}, [adapter]);

	// -- Render ----------------------------------------------------------------

	if (state === "loading") {
		return null;
	}

	return (
		<>
			<TodayNotepad adapter={adapter} />
			<ThemeToggle />
		</>
	);
}
