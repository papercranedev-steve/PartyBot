// Draws the dialog page's gold ornaments as SVG, rasterises them and writes TGA files for the addon.
// Usage (needs `npm install @resvg/resvg-js` in a scratch folder with this file copied there):
//   node ornaments.mjs "<addons>/partybot-addons/PartyBot/Textures"
// Previews (PNG, x3 and a page mock) go to %TEMP%\ornament.
//
// The page's weight is on the left (portrait, text start), so the scrollwork is heavier on the right:
//   DialogCornerRight  256x128, the top-right corner (border point 236,20): a long vine along the
//                      top edge, a short one down the right edge; mirrored for the bottom right
//   DialogCornerLeft   64x64, the top-left corner (border point 14,14): a small stud; mirrored
// Aged brass rather than shiny gold: muted gradient, an emboss light, grime noise in the recesses.
import { Resvg } from '@resvg/resvg-js';
import fs from 'node:fs';
import path from 'node:path';

const OUT = process.argv[2] || '.';
const PREVIEW = path.join(process.env.TEMP || '.', 'ornament');
fs.mkdirSync(PREVIEW, { recursive: true });

const defs = (seed) => `
<defs>
  <linearGradient id="brass" x1="0" y1="0" x2="0.3" y2="1">
    <stop offset="0" stop-color="#d8c27c"/>
    <stop offset="0.4" stop-color="#a9822f"/>
    <stop offset="0.75" stop-color="#6c4f1b"/>
    <stop offset="1" stop-color="#3b2a0d"/>
  </linearGradient>
  <radialGradient id="gem" cx="0.38" cy="0.35" r="0.75">
    <stop offset="0" stop-color="#b8584a"/>
    <stop offset="0.45" stop-color="#6e1712"/>
    <stop offset="1" stop-color="#1e0403"/>
  </radialGradient>
  <filter id="age" x="-10%" y="-10%" width="120%" height="120%" color-interpolation-filters="sRGB">
    <feGaussianBlur in="SourceAlpha" stdDeviation="1.1" result="blur"/>
    <feSpecularLighting in="blur" surfaceScale="2.6" specularConstant="0.75" specularExponent="16"
        lighting-color="#f4e2a8" result="spec">
      <feDistantLight azimuth="235" elevation="42"/>
    </feSpecularLighting>
    <feComposite in="spec" in2="SourceAlpha" operator="in" result="specIn"/>
    <feComposite in="SourceGraphic" in2="specIn" operator="arithmetic" k2="1" k3="0.55" result="lit"/>
    <feTurbulence type="fractalNoise" baseFrequency="0.6" numOctaves="3" seed="${seed}" result="noise"/>
    <feColorMatrix in="noise" type="matrix"
        values="0 0 0 0 0.10  0 0 0 0 0.07  0 0 0 0 0.02  -3.2 0 0 0 1.45" result="grime"/>
    <feComposite in="grime" in2="SourceAlpha" operator="in" result="grimeIn"/>
    <feMerge result="aged"><feMergeNode in="lit"/><feMergeNode in="grimeIn"/></feMerge>
    <feComposite in="aged" in2="SourceAlpha" operator="in" result="clipped"/>
    <feGaussianBlur in="SourceAlpha" stdDeviation="1.4"/>
    <feOffset dx="1" dy="1.4"/>
    <feComponentTransfer result="shadow"><feFuncA type="linear" slope="0.7"/></feComponentTransfer>
    <feMerge><feMergeNode in="shadow"/><feMergeNode in="clipped"/></feMerge>
  </filter>
</defs>`;

// a brass line with a dark edge (no light rim: the emboss light does that)
function vine(d, w = 2.8) {
    return `
  <path d="${d}" fill="none" stroke="#140c03" stroke-opacity="0.9" stroke-width="${w + 1.6}" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="${d}" fill="none" stroke="url(#brass)" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
}
// a round-tipped leaf from (x, y), pointing at 'angle' degrees, with a faint vein
function leaf(x, y, angle, len, wid) {
    const d = `M 0 0 C ${len * 0.2} ${-wid}, ${len * 0.8} ${-wid * 1.05}, ${len} 0 C ${len * 0.8} ${wid * 1.05}, ${len * 0.2} ${wid}, 0 0 Z`;
    return `<g transform="translate(${x},${y}) rotate(${angle})">
    <path d="${d}" fill="url(#brass)" stroke="#140c03" stroke-opacity="0.85" stroke-width="1" stroke-linejoin="round"/>
    <path d="M 1.5 0 Q ${len * 0.5} ${-wid * 0.15} ${len * 0.82} 0" fill="none" stroke="#2a1804" stroke-opacity="0.45" stroke-width="0.7" stroke-linecap="round"/>
  </g>`;
}
// a round berry
function berry(x, y, r) {
    return `<circle cx="${x}" cy="${y}" r="${r}" fill="url(#brass)" stroke="#140c03" stroke-opacity="0.85" stroke-width="0.9"/>`;
}
// a small dark garnet in a round brass mount
function gem(cx, cy, r) {
    return `
  <circle cx="${cx}" cy="${cy}" r="${r + 2.6}" fill="url(#brass)" stroke="#140c03" stroke-width="1"/>
  <circle cx="${cx}" cy="${cy}" r="${r}" fill="url(#gem)" stroke="#140c03" stroke-width="0.9"/>
  <circle cx="${cx - r * 0.35}" cy="${cy - r * 0.4}" r="${r * 0.22}" fill="#f3d6b0" fill-opacity="0.5"/>`;
}

// top right: corner at (236,20); the top border line is y = 20, the right one x = 236
const cornerRight = `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="128" viewBox="0 0 256 128">${defs(7)}
<g filter="url(#age)">
  ${vine('M 228 20 C 216 20, 212 11, 200 11 C 186 11, 184 27, 168 27 C 152 27, 150 13, 136 13 C 122 13, 120 24, 108 23 C 98 22, 94 12, 86 13 C 78 14, 78 24, 86 24 C 91 24, 92 18, 88 18')}
  ${vine('M 200 11 C 196 5, 188 3, 184 6 C 181 8.5, 184 12, 187 10', 2.0)}
  ${vine('M 168 27 C 162 33, 152 35, 146 32 C 141 29.5, 143 25, 147 26.5', 2.0)}
  ${leaf(136, 13, -165, 15, 4.6)}
  ${leaf(108, 23, 165, 12, 4.0)}
  ${leaf(214, 15.5, -140, 11, 3.8)}
  ${berry(178, 20.5, 2.1)}
  ${berry(182.5, 23.5, 1.8)}
  ${berry(120, 8.5, 1.8)}
  ${vine('M 236 28 C 236 35, 229 38, 229 45 C 229 52, 236 54, 236 59 C 236 64, 231 66, 229 63 C 227.5 60.5, 230 58.5, 232 60', 2.4)}
  ${leaf(229.5, 45, 115, 11, 4.0)}
  ${gem(236, 20, 3.3)}
</g></svg>`;

// top left: corner at (14,14), a small stud with two short curled arms
const LEFT_ARM = `
  ${vine('M 21 14 C 27 14, 29 9.5, 35 9.5 C 40 9.5, 41 14, 37.5 14.5', 2.0)}
  ${leaf(30, 11, -20, 9, 3.0)}`;
const cornerLeft = `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">${defs(11)}
<g filter="url(#age)">
  <g>${LEFT_ARM}</g>
  <g transform="matrix(0,1,1,0,0,0)">${LEFT_ARM}</g>
  ${gem(14, 14, 2.6)}
</g></svg>`;

function rasterise(svg, w) {
    return new Resvg(svg, { fitTo: { mode: 'width', value: w }, background: 'rgba(0,0,0,0)' }).render();
}

// uncompressed 32-bit TGA, top-left origin
function tga(rendered) {
    const { width, height } = rendered;
    const rgba = rendered.pixels;
    const head = Buffer.alloc(18);
    head[2] = 2;
    head.writeUInt16LE(width, 12);
    head.writeUInt16LE(height, 14);
    head[16] = 32;
    head[17] = 0x28;
    const body = Buffer.alloc(width * height * 4);
    for (let i = 0; i < width * height; i++) {
        body[i * 4] = rgba[i * 4 + 2];
        body[i * 4 + 1] = rgba[i * 4 + 1];
        body[i * 4 + 2] = rgba[i * 4];
        body[i * 4 + 3] = rgba[i * 4 + 3];
    }
    return Buffer.concat([head, body]);
}

// the line under the speaker's name: printed ink on the parchment, drawn 1:1 at the text column's
// width (DialogPage.lua COLUMN_W = 428) in the left of a 512x32 canvas, the art in rows 6..26
const RULE_W = 428, MID = RULE_W / 2;
const INK = '#4a3216';
const inkFilter = `
<defs>
  <filter id="ink" x="-5%" y="-50%" width="110%" height="200%" color-interpolation-filters="sRGB">
    <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="5" result="noise"/>
    <feColorMatrix in="noise" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -0.9 1.5" result="worn"/>
    <feComposite in="SourceGraphic" in2="worn" operator="in"/>
  </filter>
</defs>`;
// a soft spiral beside the centre knot, s = 1 left, -1 right (mirrored)
const curl = (s) => `<path d="M ${MID - 7 * s} 16 C ${MID - 13 * s} 16, ${MID - 15 * s} 11, ${MID - 20 * s} 11.2 C ${MID - 24.5 * s} 11.4, ${MID - 25 * s} 17, ${MID - 21 * s} 17.2 C ${MID - 18.5 * s} 17.3, ${MID - 18 * s} 14.6, ${MID - 19.8 * s} 14.4"
    fill="none" stroke="${INK}" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="${MID - 31 * s}" cy="16" r="1.3" fill="${INK}"/>`;
const rule = `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="32" viewBox="0 0 512 32">${inkFilter}
<defs>
  <linearGradient id="fadeL" gradientUnits="userSpaceOnUse" x1="2" y1="0" x2="${MID - 37}" y2="0">
    <stop offset="0" stop-color="${INK}" stop-opacity="0"/><stop offset="0.45" stop-color="${INK}"/><stop offset="1" stop-color="${INK}"/>
  </linearGradient>
  <linearGradient id="fadeR" gradientUnits="userSpaceOnUse" x1="${RULE_W - 2}" y1="0" x2="${MID + 37}" y2="0">
    <stop offset="0" stop-color="${INK}" stop-opacity="0"/><stop offset="0.45" stop-color="${INK}"/><stop offset="1" stop-color="${INK}"/>
  </linearGradient>
</defs>
<g filter="url(#ink)" opacity="0.8">
  <path d="M 4 16 L ${MID - 37} 16" stroke="url(#fadeL)" stroke-width="1.3" stroke-linecap="round"/>
  <path d="M ${RULE_W - 4} 16 L ${MID + 37} 16" stroke="url(#fadeR)" stroke-width="1.3" stroke-linecap="round"/>
  ${curl(1)}
  ${curl(-1)}
  <circle cx="${MID}" cy="16" r="4.6" fill="none" stroke="${INK}" stroke-width="1.2"/>
  <circle cx="${MID}" cy="16" r="1.8" fill="${INK}"/>
</g></svg>`;

const pieces = [['DialogCornerRight', cornerRight, 256], ['DialogCornerLeft', cornerLeft, 64], ['DialogRule', rule, 512]];
const png = {};
for (const [name, svg, w] of pieces) {
    const r = rasterise(svg, w);
    fs.writeFileSync(path.join(OUT, name + '.tga'), tga(r));
    png[name] = r.asPng().toString('base64');
    fs.writeFileSync(path.join(PREVIEW, name + '-x3.png'), rasterise(svg, w * 3).asPng());
}

// a mock of the page as the addon places the pieces (same sizes and offsets as DialogPage.lua)
const W = 600, H = 180, B = 9;
const img = (name, w, h, t) => `<image href="data:image/png;base64,${png[name]}" width="${w}" height="${h}" transform="${t}"/>`;
const R = 236, RT = 20, L = 14;
const mock = `<svg xmlns="http://www.w3.org/2000/svg" width="${W + 40}" height="${H + 40}" viewBox="-20 -20 ${W + 40} ${H + 40}">
<rect x="-20" y="-20" width="${W + 40}" height="${H + 40}" fill="#5b5426"/>
<rect x="6" y="6" width="${W - 12}" height="${H - 12}" fill="#d8bf8c"/>
<rect x="${B}" y="${B}" width="${W - 2 * B}" height="${H - 2 * B}" fill="none" stroke="#2a1804" stroke-width="5"/>
<rect x="${B}" y="${B}" width="${W - 2 * B}" height="${H - 2 * B}" fill="none" stroke="#b8923e" stroke-width="3"/>
<rect x="22" y="26" width="112" height="112" fill="#111" stroke="#b8923e" stroke-width="2"/>
<text x="154" y="44" font-family="serif" font-size="18" fill="#33200a">Tyorn</text>
<text x="154" y="80" font-family="sans-serif" font-size="14" fill="#33200a">Ah! Need something? Just say the word!</text>
${img('DialogRule', 512, 32, 'translate(146,40)')}
${img('DialogCornerRight', 256, 128, `translate(${W - B - R},${B - RT})`)}
${img('DialogCornerRight', 256, 128, `translate(${W - B - R},${H - B + RT}) scale(1,-1)`)}
${img('DialogCornerLeft', 64, 64, `translate(${B - L},${B - L})`)}
${img('DialogCornerLeft', 64, 64, `translate(${B - L},${H - B + L}) scale(1,-1)`)}
</svg>`;
fs.writeFileSync(path.join(PREVIEW, 'mock.png'), rasterise(mock, (W + 40) * 1.5).asPng());
console.log('done');