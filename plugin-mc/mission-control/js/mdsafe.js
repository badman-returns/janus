// mdsafe.js — the one rule for a reply's markdown: it carries words, never markup. Three renderer
// overrides on marked, so no caller has to remember to strip anything afterwards: raw HTML comes
// out as the text it is, a link that is not http(s) keeps its words and loses its href, and an
// image becomes its alt text — a reply must not make the page fetch anything, or run anything.
// test_front_talk.sh imports this file and asserts exactly that against the vendored marked.
export const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
export const SAFE = {
  html: t => esc(t.text),
  image: t => esc(t.text || t.title || ""),
  link(t) {
    const words = this.parser.parseInline(t.tokens);
    return /^https?:\/\//i.test(t.href || "") ? `<a href="${esc(t.href)}" target="_blank" rel="noopener noreferrer">${words}</a>` : words;
  },
};
