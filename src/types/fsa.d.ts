/**
 * File System Access API ambient types.
 *
 * TypeScript's DOM lib doesn't ship full typings for the File System Access
 * API yet (it's a Chromium-only spec). We declare just the subset Noot uses.
 */

interface FileSystemHandlePermissionDescriptor {
	mode?: "read" | "readwrite";
}

interface FileSystemDirectoryHandle {
	queryPermission(
		descriptor?: FileSystemHandlePermissionDescriptor,
	): Promise<PermissionState>;
	requestPermission(
		descriptor?: FileSystemHandlePermissionDescriptor,
	): Promise<PermissionState>;
}

interface Window {
	showDirectoryPicker(options?: {
		mode?: "read" | "readwrite";
	}): Promise<FileSystemDirectoryHandle>;
}
