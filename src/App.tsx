import { useEffect, useMemo, useState } from "react";
import { BottomNav, type BottomNavTab } from "./components/BottomNav";
import { CalendarView } from "./components/CalendarView";
import { EntryEditor } from "./components/EntryEditor";
import { ListView } from "./components/ListView";
import { ThemeToggle } from "./components/ThemeToggle";
import { todayKey } from "./lib/date";
import { initTheme, subscribeSystemTheme, toggleTheme } from "./lib/theme";
import { IdbAdapter } from "./storage/IdbAdapter";

type AppState = "loading" | "ready";

type View =
	| { name: "today" }
	| { name: "list" }
	| { name: "calendar" }
	| { name: "entry"; dateKey: string; from: "list" | "calendar" };

export default function App() {
	const adapter = useMemo(() => new IdbAdapter(), []);
	const [state, setState] = useState<AppState>("loading");
	const [view, setView] = useState<View>({ name: "today" });

	useEffect(() => {
		initTheme();
		return subscribeSystemTheme(() => {});
	}, []);

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

	useEffect(() => {
		adapter
			.init()
			.then(() => setState("ready"))
			.catch((err) => {
				console.error("Storage init error:", err);
			});
	}, [adapter]);

	if (state === "loading") {
		return null;
	}

	function navigate(tab: BottomNavTab) {
		if (tab === "today") setView({ name: "today" });
		else if (tab === "list") setView({ name: "list" });
		else setView({ name: "calendar" });
	}

	function openEntry(dateKey: string, from: "list" | "calendar") {
		if (dateKey === todayKey()) {
			setView({ name: "today" });
		} else {
			setView({ name: "entry", dateKey, from });
		}
	}

	const activeTab: BottomNavTab = view.name === "entry" ? view.from : view.name;

	return (
		<>
			<div className="pb-20">
				{view.name === "today" && (
					<EntryEditor adapter={adapter} dateKey={todayKey()} />
				)}
				{view.name === "entry" && (
					<EntryEditor
						adapter={adapter}
						dateKey={view.dateKey}
						onBack={() =>
							setView(
								view.from === "list" ? { name: "list" } : { name: "calendar" },
							)
						}
					/>
				)}
				{view.name === "list" && (
					<ListView
						adapter={adapter}
						onSelectDate={(dk) => openEntry(dk, "list")}
					/>
				)}
				{view.name === "calendar" && (
					<CalendarView
						adapter={adapter}
						onSelectDate={(dk) => openEntry(dk, "calendar")}
					/>
				)}
			</div>
			<BottomNav active={activeTab} onNavigate={navigate} />
			<ThemeToggle />
		</>
	);
}
