/**
 * Tiny hand-rolled YAML-frontmatter parser.
 *
 * Noot's frontmatter schema is only two fields:
 *
 *     ---
 *     created_at: 2026-04-11T13:05:00+02:00
 *     location: Amsterdam
 *     ---
 *     (body...)
 *
 * That's far less than what gray-matter / js-yaml cover, and both of those
 * pull in Node's Buffer which is a pain in the browser. So we hand-roll:
 * one parser, one serializer, both forgiving.
 *
 * If the schema ever grows beyond flat string-keyed scalars, swap this for a
 * real YAML parser — keep the signatures of parseDoc / stringifyDoc stable
 * and the rest of the app won't need to change.
 */

export interface Frontmatter {
	created_at: string | null;
	location: string | null;
}

export interface MarkdownDoc {
	data: Frontmatter;
	content: string;
}

const FRONTMATTER_RE = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/;

/** Parse a markdown string with optional frontmatter. Missing fields default to null. */
export function parseDoc(raw: string): MarkdownDoc {
	const match = raw.match(FRONTMATTER_RE);
	if (!match) {
		return {
			data: { created_at: null, location: null },
			content: raw,
		};
	}

	const [, yaml, body] = match;
	const data: Frontmatter = { created_at: null, location: null };

	for (const line of yaml.split(/\r?\n/)) {
		const trimmed = line.trim();
		if (!trimmed || trimmed.startsWith("#")) continue;
		const colonIdx = trimmed.indexOf(":");
		if (colonIdx === -1) continue;

		const key = trimmed.slice(0, colonIdx).trim();
		const value = unquote(trimmed.slice(colonIdx + 1).trim());

		if (key === "created_at") data.created_at = value || null;
		else if (key === "location") data.location = value || null;
		// unknown keys are tolerated and ignored.
	}

	return { data, content: body };
}

/** Serialize a frontmatter + body pair back into a markdown string. */
export function stringifyDoc(doc: MarkdownDoc): string {
	const lines: string[] = ["---"];
	if (doc.data.created_at !== null) {
		lines.push(`created_at: ${doc.data.created_at}`);
	}
	if (doc.data.location !== null) {
		lines.push(`location: ${quoteIfNeeded(doc.data.location)}`);
	}
	lines.push("---", "", doc.content);
	return lines.join("\n");
}

/** Strip surrounding single or double quotes, if present. */
function unquote(value: string): string {
	if (value.length >= 2) {
		const first = value[0];
		const last = value[value.length - 1];
		if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
			return value.slice(1, -1);
		}
	}
	return value;
}

/** Quote a string if it contains a character YAML would otherwise misparse. */
function quoteIfNeeded(value: string): string {
	if (/[:#\n"']/.test(value)) {
		return `"${value.replace(/"/g, '\\"')}"`;
	}
	return value;
}
