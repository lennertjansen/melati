import { Editor } from "@tiptap/core";
import Placeholder from "@tiptap/extension-placeholder";
import StarterKit from "@tiptap/starter-kit";
import { Markdown } from "tiptap-markdown";
import "./fonts.css";

declare global {
	interface Window {
		webkit?: {
			messageHandlers: {
				melati?: { postMessage: (m: unknown) => void };
			};
		};
		melatiSetContent?: (md: string) => void;
		melatiSetReadOnly?: (ro: boolean) => void;
		melatiSetTheme?: (theme: "light" | "dark") => void;
		melatiFocus?: () => void;
		melatiExec?: (cmd: string) => void;
		melatiBlur?: () => void;
	}
}

// Touch platforms get OS text services and their own CSS scope; on mac the
// hardware keyboard + menu handle everything and autocorrect stays off.
const isTouch = /iPhone|iPad|iPod/.test(navigator.userAgent);
if (isTouch) {
	document.documentElement.classList.add("platform-ios");
}

function post(msg: Record<string, unknown>) {
	window.webkit?.messageHandlers.melati?.postMessage(msg);
}

window.onerror = (message, source, lineno, colno, error) => {
	post({
		type: "error",
		message: String(message),
		source: String(source ?? ""),
		line: lineno,
		col: colno,
		stack: error?.stack ?? "",
	});
};

const origLog = console.log;
const origErr = console.error;
console.log = (...args) => {
	origLog(...args);
	post({ type: "log", level: "log", args: args.map(String) });
};
console.error = (...args) => {
	origErr(...args);
	post({ type: "log", level: "error", args: args.map(String) });
};

type MarkdownStorage = { getMarkdown: () => string };

function getMarkdown(e: Editor): string {
	return (e.storage as { markdown: MarkdownStorage }).markdown.getMarkdown();
}

const root = document.getElementById("root");
if (!root) {
	throw new Error("editor embed: missing #root element");
}

const editor = new Editor({
	element: root,
	extensions: [
		StarterKit.configure({}),
		Placeholder.configure({
			placeholder: "Start writing...",
		}),
		Markdown.configure({
			html: false,
			transformPastedText: true,
			transformCopiedText: true,
		}),
	],
	content: "",
	editorProps: {
		attributes: {
			spellcheck: "false",
			autocorrect: isTouch ? "on" : "off",
			autocapitalize: isTouch ? "sentences" : "off",
			autocomplete: "off",
		},
	},
	onUpdate: ({ editor }) => {
		const md = getMarkdown(editor);
		post({ type: "change", md });
		editor.commands.scrollIntoView();
	},
	onFocus: () => {
		post({ type: "focus" });
	},
	onBlur: () => {
		post({ type: "blur" });
	},
});

let lastReceived = "";

window.melatiSetContent = (md: string) => {
	if (md === lastReceived) return;
	lastReceived = md;
	const current = getMarkdown(editor);
	if (md !== current) {
		const wasFocused = editor.isFocused;
		editor.commands.setContent(md, { emitUpdate: false });
		// A mid-typing content swap only happens on a sync merge, which
		// places the live text last - keep the caret at the end so typing
		// continues where it left off.
		if (wasFocused) {
			editor.commands.focus("end");
		}
	}
};

window.melatiSetReadOnly = (ro: boolean) => {
	editor.setEditable(!ro);
};

window.melatiSetTheme = (theme: "light" | "dark") => {
	if (theme === "dark") {
		document.documentElement.classList.add("dark");
	} else {
		document.documentElement.classList.remove("dark");
	}
};

window.melatiFocus = () => {
	editor.commands.focus();
};

window.melatiBlur = () => {
	editor.commands.blur();
};

// Formatting commands for the native accessory toolbar (iOS has no menu bar).
window.melatiExec = (cmd: string) => {
	const chain = editor.chain().focus();
	switch (cmd) {
		case "bold":
			chain.toggleBold().run();
			break;
		case "italic":
			chain.toggleItalic().run();
			break;
		case "h1":
			chain.toggleHeading({ level: 1 }).run();
			break;
		case "h2":
			chain.toggleHeading({ level: 2 }).run();
			break;
		case "bulletList":
			chain.toggleBulletList().run();
			break;
		case "orderedList":
			chain.toggleOrderedList().run();
			break;
		case "blockquote":
			chain.toggleBlockquote().run();
			break;
		default:
			break;
	}
};

post({ type: "ready" });
