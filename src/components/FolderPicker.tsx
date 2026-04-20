/**
 * First-run welcome screen.
 *
 * Shown when the app has no persisted directory handle (first ever launch)
 * or the user revoked permission. A single button triggers the native
 * directory picker, then calls back into the adapter's pickFolder().
 */

import type { StorageAdapter } from "../storage/StorageAdapter";

interface FolderPickerProps {
	adapter: StorageAdapter;
	onGranted: () => void;
}

export function FolderPicker({ adapter, onGranted }: FolderPickerProps) {
	async function handleClick() {
		try {
			await adapter.pickFolder?.();
			onGranted();
		} catch (err) {
			// User cancelled the native picker — do nothing, let them retry.
			console.warn("Folder picker cancelled or denied:", err);
		}
	}

	return (
		<div className="flex flex-col items-center justify-center min-h-screen gap-8 px-4 text-center">
			<h1 className="text-4xl font-bold font-serif tracking-tight">Noot</h1>
			<p className="text-lg text-[var(--color-fg-subtle)] max-w-md">
				Pick a location for your journal. Noot will create a{" "}
				<span className="font-semibold">Noot/</span> folder inside it.
			</p>
			<button
				type="button"
				onClick={handleClick}
				className="px-6 py-3 rounded-lg bg-[var(--color-fg)] text-[var(--color-bg)] font-serif text-lg cursor-pointer hover:opacity-90 transition-opacity"
			>
				Choose folder
			</button>
		</div>
	);
}
