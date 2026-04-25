import { EditorContent, useEditor } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import { useEffect, useRef } from "react";
import { Markdown } from "tiptap-markdown";

interface EditorProps {
	content: string;
	onChange: (value: string) => void;
	onBlur?: () => void;
	readOnly?: boolean;
}

interface MarkdownStorage {
	markdown: { getMarkdown(): string };
}

/**
 * TipTap WYSIWYG editor — renders markdown inline (headings, bold, italic,
 * lists, code, blockquotes). No toolbar, just a clean writing surface.
 *
 * The editor is intentionally uncontrolled after mount: TipTap owns its
 * internal state, and we only push content in when it changes externally
 * (e.g. loading a different day's entry). User keystrokes flow out via
 * onChange but never loop back in via setContent.
 */
export function Editor({ content, onChange, onBlur, readOnly }: EditorProps) {
	const lastEmitted = useRef(content);

	const editor = useEditor({
		editable: !readOnly,
		extensions: [
			StarterKit,
			Markdown.configure({
				html: false,
				transformPastedText: true,
				transformCopiedText: true,
			}),
		],
		content,
		editorProps: {
			attributes: {
				class:
					"font-serif text-lg leading-relaxed max-w-[65ch] mx-auto text-[var(--color-fg)]",
			},
		},
		onUpdate: ({ editor }) => {
			if (readOnly) return;
			const md = (
				editor.storage as unknown as MarkdownStorage
			).markdown.getMarkdown();
			lastEmitted.current = md;
			onChange(md);
		},
		onBlur: () => {
			if (readOnly) return;
			onBlur?.();
		},
	});

	// Only sync content from parent when it differs from what the editor
	// last emitted — i.e. an external change, not an echo of our own update.
	useEffect(() => {
		if (!editor) return;
		if (content !== lastEmitted.current) {
			lastEmitted.current = content;
			editor.commands.setContent(content);
		}
	}, [editor, content]);

	return <EditorContent editor={editor} />;
}
