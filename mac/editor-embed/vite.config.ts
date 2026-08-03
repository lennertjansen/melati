import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
	plugins: [viteSingleFile()],
	build: {
		outDir: "../Resources/editor",
		emptyOutDir: true,
		target: "es2020",
		cssCodeSplit: false,
		assetsInlineLimit: 100_000_000,
	},
});
