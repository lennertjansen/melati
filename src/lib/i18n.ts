/**
 * Lightweight i18n. Auto-detects from `navigator.language`. No visible toggle
 * yet — that lands when there's a settings surface (see plan).
 *
 * Two locales for now: `en` (default) and `nl`. Adding more is a matter of
 * extending the `Strings` dict and `LOCALES` map.
 */

export type Locale = "en" | "nl";

const STRINGS = {
	en: {
		"tab.today": "Today",
		"tab.entries": "Entries",
		"tab.calendar": "Calendar",
		back: "‹ Back",
		placeholder: "Start writing…",
		"location.set": "Set location",
		"list.flat": "Flat",
		"list.grouped": "Grouped",
		"list.empty": "No entries yet",
		"cal.prev": "Previous month",
		"cal.next": "Next month",
		"relative.today": "Today",
		"relative.yesterday": "Yesterday",
	},
	nl: {
		"tab.today": "Vandaag",
		"tab.entries": "Notities",
		"tab.calendar": "Kalender",
		back: "‹ Terug",
		placeholder: "Begin met schrijven…",
		"location.set": "Locatie instellen",
		"list.flat": "Plat",
		"list.grouped": "Gegroepeerd",
		"list.empty": "Nog geen notities",
		"cal.prev": "Vorige maand",
		"cal.next": "Volgende maand",
		"relative.today": "Vandaag",
		"relative.yesterday": "Gisteren",
	},
} as const satisfies Record<Locale, Record<string, string>>;

export type StringKey = keyof (typeof STRINGS)["en"];

const INTL_LOCALES: Record<Locale, string> = {
	en: "en-US",
	nl: "nl-NL",
};

const LOCALE_STORAGE_KEY = "noot.locale";

let cachedLocale: Locale | null = null;

function isLocale(value: string | null): value is Locale {
	return value === "en" || value === "nl";
}

export function getLocale(): Locale {
	if (cachedLocale) return cachedLocale;
	if (typeof localStorage !== "undefined") {
		const stored = localStorage.getItem(LOCALE_STORAGE_KEY);
		if (isLocale(stored)) {
			cachedLocale = stored;
			return cachedLocale;
		}
	}
	const lang =
		typeof navigator !== "undefined" ? (navigator.language ?? "en") : "en";
	cachedLocale = lang.toLowerCase().startsWith("nl") ? "nl" : "en";
	return cachedLocale;
}

export function getIntlLocale(): string {
	return INTL_LOCALES[getLocale()];
}

export function t(key: StringKey): string {
	return STRINGS[getLocale()][key];
}

/**
 * 0 = Sunday, 1 = Monday. Tries `Intl.Locale.weekInfo` first (Chrome/Safari);
 * falls back to a fixed table per locale.
 */
export function getFirstDayOfWeek(): 0 | 1 {
	const locale = getLocale();
	try {
		const weekInfo = new Intl.Locale(getIntlLocale()) as Intl.Locale & {
			weekInfo?: { firstDay: number };
			getWeekInfo?: () => { firstDay: number };
		};
		const firstDay =
			weekInfo.weekInfo?.firstDay ?? weekInfo.getWeekInfo?.().firstDay;
		if (firstDay === 7 || firstDay === 0) return 0;
		if (firstDay === 1) return 1;
	} catch {
		// fall through
	}
	return locale === "nl" ? 1 : 0;
}
