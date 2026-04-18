import DOMPurify from "dompurify";
import { marked } from "marked";

/**
 * Render raw markdown to sanitized HTML.
 *
 * `marked` produces HTML from the markdown AST; `DOMPurify` then strips any
 * script tags, event handlers, or other XSS vectors before we hand the
 * string to `dangerouslySetInnerHTML`. This is the sole reason we can safely
 * use `dangerouslySetInnerHTML` at all.
 */
export function renderMarkdown(markdown: string): string {
	const rawHtml = marked.parse(markdown, { async: false }) as string;
	return DOMPurify.sanitize(rawHtml);
}
