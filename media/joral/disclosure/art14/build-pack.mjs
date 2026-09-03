import { marked } from 'marked';
import fs from 'node:fs';
const dir = 'disclosure/art14/';
const docs = [
  ['README.md',            'How the pack is used'],
  ['early-warning.md',     'Report to ENISA + CSIRT — §A 24 h · §B 72 h · §C final'],
  ['customer-notice.md',   'Notice to affected users — Art. 14(8)'],
  ['distribution-list.md', 'Customer distribution list — what “confirmed” means'],
];
marked.use({ gfm: true });
const esc = s => s.replace(/&/g,'&amp;').replace(/</g,'&lt;');
let body = '';
for (const [f, sub] of docs) {
  let md = fs.readFileSync(dir + f, 'utf8');
  // fill-in fields → highlighted blanks
  let html = marked.parse(md);
  html = html.replace(/\[\[([^\]]*)\]\]/g, (_, t) => `<span class="fill">${t.trim() || '&nbsp;'}</span>`);
  html = html.replace(/\[ \]/g, '<span class="box"></span>');
  body += `<section class="doc"><div class="crumb">disclosure/art14/${f} · ${sub}</div>${html}</section>`;
}
const css = fs.readFileSync(new URL('./pack.css', import.meta.url), 'utf8');
const logo = 'data:image/png;base64,' + fs.readFileSync('joral logo.png').toString('base64');
const page = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Article 14 Notice Pack</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Open+Sans:ital,wght@0,400;0,600;0,700;0,800;1,400;1,600&family=Saira+Semi+Condensed:wght@700&display=swap">
<style>${css}</style></head><body>
<header class="cover">
  <div class="brand">
    <img src="${logo}" alt="Joral — Capture Creativity">
    <div class="meta"><b>Joral LLC</b> · Industrial Edge Platform / 10BASE-T1S Media Gateway<br>Product security · EU Cyber Resilience Act<br>Prepared 28 Aug 2026 · for Carl, CTO</div>
  </div>
  <div class="kicker">Regulation (EU) 2024/2847 · Article 14 · in force from 11 September 2026</div>
  <h1>Article 14 notice pack</h1>
  <p class="lede">The two notices Joral must write under a 24-hour clock once a unit is on the EU market, drafted now so that on the day only the facts are missing — and the checklist that says whether the customer notice has anywhere to go.</p>
  <div class="status"><span class="k">Position on 28 August 2026</span><b>No unit has been placed on the EU market, and no incident has occurred.</b> The Article 14 duty attaches at first shipment, not on 11 September — and from 11 September it attaches with no run-up. Everything in this pack therefore has to exist <b>before unit one</b>.</div>
  <dl class="facts">
    <div><dt>Bound by</dt><dd>First shipment (law in force 11 Sep 2026)</dd></div>
    <div><dt>Status</dt><dd>Drafts. Not published, not filed. No case open.</dd></div>
    <div><dt>Left blank for counsel</dt><dd>Coordinating CSIRT · EU authorised representative</dd></div>
    <div><dt>Engineering owed</dt><dd>None — build-ID → SBOM lookup and signed update path are in place</dd></div>
  </dl>
  <p class="note">Highlighted fields <span class="fill">like this</span> are filled on the day. Everything else is already decided. The working copies are the Markdown files named at the top of each section; this PDF is the reading copy.</p>
</header>
${body}
<div class="foot"><b>Joral LLC</b> · 262-378-5500 · joralllc.com · security@joralllc.com — Article 14 notice pack, 28 Aug 2026. Internal working document; not for distribution outside Joral and counsel.</div>
</body></html>`;
fs.writeFileSync('cra-article-14-notice-pack.html', page);
console.log('wrote cra-article-14-notice-pack.html', page.length);
