export type BottomNavTab = "today" | "list" | "calendar";

interface BottomNavProps {
	active: BottomNavTab;
	onNavigate: (tab: BottomNavTab) => void;
}

const TABS: { id: BottomNavTab; label: string }[] = [
	{ id: "today", label: "Today" },
	{ id: "list", label: "Entries" },
	{ id: "calendar", label: "Calendar" },
];

/**
 * Three-tab bottom navigation. Always visible. The `active` prop tracks the
 * source tab even when viewing a past entry full-screen.
 */
export function BottomNav({ active, onNavigate }: BottomNavProps) {
	return (
		<nav className="fixed bottom-0 left-0 right-0 border-t border-[color-mix(in_oklab,var(--color-fg)_10%,transparent)] bg-[var(--color-bg)]">
			<ul className="max-w-3xl mx-auto px-4 py-3 flex items-center justify-center gap-8 font-serif text-sm">
				{TABS.map((tab) => {
					const isActive = active === tab.id;
					return (
						<li key={tab.id}>
							<button
								type="button"
								onClick={() => onNavigate(tab.id)}
								className={`bg-transparent border-none cursor-pointer transition-colors ${
									isActive
										? "font-semibold text-[var(--color-fg)]"
										: "text-[var(--color-fg-subtle)] hover:text-[var(--color-fg)]"
								}`}
							>
								{tab.label}
							</button>
						</li>
					);
				})}
			</ul>
		</nav>
	);
}
