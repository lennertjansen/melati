import { EditorContent, useEditor } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import { useEffect } from "react";
import { Markdown } from "tiptap-markdown";

interface EditorProps {
	content: string;
	onChange: (value: string) => void;
	onBlur?: () => void;
}

interface MarkdownStorage {
	markdown: { getMarkdown(): string };
}

/**
 * TipTap WYSIWYG editor — renders markdown inline (headings, bold, italic,
 * lists, code, blockquotes). No toolbar, just a clean writing surface.
 */
export function Editor({ content, onChange, onBlur }: EditorProps) {
	const editor = useEditor({
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
			onChange(
				(editor.storage as unknown as MarkdownStorage).markdown.getMarkdown(),
			);
		},
		onBlur: () => {
			onBlur?.();
		},
	});

	// Sync content from parent when it changes externally (e.g. initial load).
	useEffect(() => {
		if (!editor) return;
		const current = (
			editor.storage as unknown as MarkdownStorage
		).markdown.getMarkdown();
		if (current !== content) {
			editor.commands.setContent(content);
		}
	}, [editor, content]);

	return <EditorContent editor={editor} />;
}
