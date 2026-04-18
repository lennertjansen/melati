import { useEffect, useMemo, useState } from "react";
import { FolderPicker } from "./components/FolderPicker";
import { TodayNotepad } from "./components/TodayNotepad";
import { initTheme, subscribeSystemTheme, toggleTheme } from "./lib/theme";
import { FsaAdapter } from "./storage/FsaAdapter";
import { NeedsFolderError } from "./storage/StorageAdapter";

type AppState = "loading" | "needsFolder" | "ready";

export default function App() {
	const adapter = useMemo(() => new FsaAdapter(), []);
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
				if (err instanceof NeedsFolderError) {
					setState("needsFolder");
				} else {
					console.error("Storage init error:", err);
					setState("needsFolder");
				}
			});
	}, [adapter]);

	// -- Render ----------------------------------------------------------------

	if (state === "loading") {
		return null;
	}

	if (state === "needsFolder") {
		return (
			<FolderPicker adapter={adapter} onGranted={() => setState("ready")} />
		);
	}

	return <TodayNotepad adapter={adapter} />;
}
