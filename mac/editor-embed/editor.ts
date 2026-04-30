import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
import { Markdown } from "tiptap-markdown";

declare global {
  interface Window {
    webkit?: {
      messageHandlers: {
        noot?: { postMessage: (m: unknown) => void };
      };
    };
    nootSetContent?: (md: string) => void;
    nootSetReadOnly?: (ro: boolean) => void;
    nootSetTheme?: (theme: "light" | "dark") => void;
    nootFocus?: () => void;
  }
}

function post(msg: Record<string, unknown>) {
  window.webkit?.messageHandlers.noot?.postMessage(msg);
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

const root = document.getElementById("root")!;

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
      autocorrect: "off",
      autocapitalize: "off",
      autocomplete: "off",
    },
  },
  onUpdate: ({ editor }) => {
    const md = (editor.storage as any).markdown.getMarkdown();
    post({ type: "change", md });
    editor.commands.scrollIntoView();
  },
  onBlur: () => {
    post({ type: "blur" });
  },
});

let lastReceived = "";

window.nootSetContent = (md: string) => {
  if (md === lastReceived) return;
  lastReceived = md;
  const current = (editor.storage as any).markdown.getMarkdown();
  if (md !== current) {
    editor.commands.setContent(md, { emitUpdate: false });
  }
};

window.nootSetReadOnly = (ro: boolean) => {
  editor.setEditable(!ro);
};

window.nootSetTheme = (theme: "light" | "dark") => {
  if (theme === "dark") {
    document.documentElement.classList.add("dark");
  } else {
    document.documentElement.classList.remove("dark");
  }
};

window.nootFocus = () => {
  editor.commands.focus();
};

post({ type: "ready" });
