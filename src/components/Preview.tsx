import { renderMarkdown } from "../lib/markdown";

interface PreviewProps {
	content: string;
}

export function Preview({ content }: PreviewProps) {
	const html = renderMarkdown(content);
	return (
		<article className="prose prose-lg font-serif max-w-[65ch] mx-auto prose-headings:font-serif dark:prose-invert">
			{/* biome-ignore lint/security/noDangerouslySetInnerHtml: sanitized by DOMPurify */}
			<div dangerouslySetInnerHTML={{ __html: html }} />
		</article>
	);
}
