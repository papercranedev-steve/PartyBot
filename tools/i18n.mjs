#!/usr/bin/env node
// The PartyBot addons' text: i18n/<addon>/<lang>.json (zh.json is the base, every key is there) is
// the only source; each addon reads <addon>/Locales/<lang>.lua, which this tool writes. Addons:
// every folder in i18n/ (PartyBot, PartyBot_Assist). PartyBot_Dev is Chinese only and has none.
//
//   node tools/i18n.mjs build         write <addon>/Locales/<lang>.lua from i18n/<addon>/<lang>.json
//   node tools/i18n.mjs check [--all] check, write nothing (--all lists the untranslated keys)
//
// The JSON files: one flat object, key -> string. Keys are "<file>.<what>" (the Lua file that
// uses them, lower case). Variables are written {name}; the code fills them by name:
// L("quest.accepted", { name = n, quest = q }). |cff..|r colour codes and \n are part of the text.
// A key starting with "//" is a note for translators ("//quest.accepted": "name: a companion").
// All addons share one table at run time (PartyBot's ns.LOCALES), so a key may live in only one
// of them; an add-on package's code may also use PartyBot's keys.
//
// check (exit code 1 on errors):
//   errors: a file that is not a flat object of strings; a translation key zh.json lacks; a key
//           whose {variables} differ from zh.json; a key the code uses that zh.json lacks;
//           L("key", { ... }) missing a variable of the text; L["key"] on a text with variables;
//           Locales/*.lua not built from the current JSON; a key in two addons
//   warns:  a variable the code passes that the text does not have; keys nothing uses
//   and how much of each translation is done.
// A new language also needs its entry in PartyBot/Locales/Locale.lua and in every addon's toc.

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const I18N = path.join(root, 'i18n');
const CORE = 'PartyBot';
const BASE = 'zh';

const command = process.argv[2];
const listAll = process.argv.includes('--all');
if (command !== 'build' && command !== 'check') {
    console.log('usage: node tools/i18n.mjs build | check [--all]');
    process.exit(2);
}

let errors = 0;
const error = msg => { errors++; console.log('ERROR ' + msg); };
const warn = msg => console.log('warn  ' + msg);

const varsOf = text => [...new Set([...text.matchAll(/\{(\w+)\}/g)].map(m => m[1]))].sort();

function load(addon, lang) {
    const file = path.join(I18N, addon, lang + '.json');
    let data;
    try { data = JSON.parse(fs.readFileSync(file, 'utf8')); }
    catch (e) { error(`${addon}/${lang}.json: ${e.message}`); return {}; }
    if (!data || typeof data !== 'object' || Array.isArray(data)) { error(`${addon}/${lang}.json: not an object`); return {}; }
    const out = {};
    for (const [key, value] of Object.entries(data)) {
        if (key.startsWith('//')) continue;
        if (typeof value !== 'string') { error(`${addon}/${lang}.json "${key}": not a string`); continue; }
        out[key] = value;
    }
    return out;
}

const addons = fs.readdirSync(I18N, { withFileTypes: true }).filter(e => e.isDirectory()).map(e => e.name)
    .sort((a, b) => (a === CORE ? -1 : b === CORE ? 1 : a.localeCompare(b)));
const data = {};        // addon -> { langs, tables, base }
for (const addon of addons) {
    const langs = fs.readdirSync(path.join(I18N, addon)).filter(f => f.endsWith('.json')).map(f => f.slice(0, -5)).sort();
    const tables = Object.fromEntries(langs.map(l => [l, load(addon, l)]));
    data[addon] = { langs, tables, base: tables[BASE] || {} };
}

// one key, one addon
const owner = {};
for (const addon of addons) {
    for (const key of Object.keys(data[addon].base)) {
        if (owner[key]) error(`${addon}/${BASE}.json "${key}": also in ${owner[key]}/${BASE}.json`);
        else owner[key] = addon;
    }
}
function luaString(s) {
    let out = '"';
    for (const ch of s) {
        const c = ch.codePointAt(0);
        if (ch === '\\') out += '\\\\';
        else if (ch === '"') out += '\\"';
        else if (ch === '\n') out += '\\n';
        else if (ch === '\r') out += '\\r';
        else if (ch === '\t') out += '\\t';
        else if (c < 32 || c === 127) out += '\\' + String(c).padStart(3, '0');
        else out += ch;
    }
    return out + '"';
}


function luaFile(addon, lang) {
    const lines = [
        `-- Generated from i18n/${addon}/${lang}.json by tools/i18n.mjs build. Do not edit: change the JSON and build.`,
        'local _, ns = ...',
        `local L = ns.LOCALES.${lang}`,
    ];
    for (const [key, text] of Object.entries(data[addon].tables[lang])) lines.push(`L[${luaString(key)}] = ${luaString(text)}`);
    return lines.join('\n') + '\n';
}

for (const addon of addons) {
    const { langs, tables, base } = data[addon];
    for (const lang of langs.filter(l => l !== BASE)) {
        for (const [key, text] of Object.entries(tables[lang])) {
            if (!(key in base)) { error(`${addon}/${lang}.json "${key}": not in ${BASE}.json`); continue; }
            const a = varsOf(base[key]).join(','), b = varsOf(text).join(',');
            if (a !== b) error(`${addon}/${lang}.json "${key}": variables {${b}} but ${BASE}.json has {${a}}`);
        }
    }
}

if (command === 'build') {
    if (errors) { console.log(`${errors} error(s), nothing written`); process.exit(1); }
    for (const addon of addons) {
        const dir = path.join(root, addon, 'Locales');
        fs.mkdirSync(dir, { recursive: true });
        for (const lang of data[addon].langs) {
            fs.writeFileSync(path.join(dir, lang + '.lua'), luaFile(addon, lang));
            console.log(`${addon}/Locales/${lang}.lua: ${Object.keys(data[addon].tables[lang]).length} keys`);
        }
    }
    process.exit(0);
}

for (const addon of addons) {
    for (const lang of data[addon].langs) {
        const file = path.join(root, addon, 'Locales', lang + '.lua');
        const current = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n') : null;
        if (current !== luaFile(addon, lang)) error(`${addon}/Locales/${lang}.lua is not built from i18n/${addon}/${lang}.json: run node tools/i18n.mjs build`);
    }
}

// ---------------------------------------------------------------------------
// the code
// ---------------------------------------------------------------------------
// the code
// ---------------------------------------------------------------------------

// the Lua text with comments blanked (strings kept), so keys mentioned in comments do not count
function stripComments(s) {
    let out = '';
    for (let i = 0; i < s.length;) {
        const c = s[i];
        if (c === '"' || c === "'") {
            let j = i + 1;
            while (j < s.length && s[j] !== c && s[j] !== '\n') j += s[j] === '\\' ? 2 : 1;
            out += s.slice(i, j + 1); i = j + 1;
        } else if (c === '[' && /^\[=*\[/.test(s.slice(i))) {
            const open = s.slice(i).match(/^\[(=*)\[/);
            const end = s.indexOf(']' + open[1] + ']', i);
            const j = end < 0 ? s.length : end + open[0].length;
            out += s.slice(i, j); i = j;
        } else if (c === '-' && s[i + 1] === '-') {
            const long = s.slice(i + 2).match(/^\[(=*)\[/);
            let j;
            if (long) { const end = s.indexOf(']' + long[1] + ']', i); j = end < 0 ? s.length : end + long[0].length; }
            else { j = s.indexOf('\n', i); if (j < 0) j = s.length; }
            out += s.slice(i, j).replace(/[^\n]/g, ' '); i = j;
        } else { out += c; i++; }
    }
    return out;
}

// from `open` (a '(' or '{'), the index of its closing bracket
function closing(s, open) {
    let depth = 0;
    for (let i = open; i < s.length; i++) {
        const c = s[i];
        if (c === '"' || c === "'") { i++; while (i < s.length && s[i] !== c) i += s[i] === '\\' ? 2 : 1; continue; }
        if ('({['.includes(c)) depth++;
        else if (')}]'.includes(c) && --depth === 0) return i;
    }
    return -1;
}

// the names of a table constructor's top-level `name = value` fields
function fieldNames(s, open) {
    const close = closing(s, open);
    const names = [];
    let depth = 0;
    for (let i = open + 1; i < close; i++) {
        const c = s[i];
        if (c === '"' || c === "'") { i++; while (i < close && s[i] !== c) i += s[i] === '\\' ? 2 : 1; continue; }
        if ('({['.includes(c)) depth++;
        else if (')}]'.includes(c)) depth--;
        else if (depth === 0) {
            const m = s.slice(i).match(/^([A-Za-z_]\w*)\s*=(?!=)/);
            if (m && /[{,\s]/.test(s[i - 1])) { names.push(m[1]); i += m[0].length - 1; }
        }
    }
    return names;
}


// an addon's code may use its own keys and PartyBot's
function checkCode(addon) {
    const ADDON = path.join(root, addon);
    const LOCALES = path.join(ADDON, 'Locales');
    const own = data[addon].base;
    const base = addon === CORE ? own : { ...data[CORE].base, ...own };

    const files = [];
    (function walk(dir) {
        for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
            const p = path.join(dir, e.name);
            if (e.isDirectory()) { if (p !== LOCALES) walk(p); }
            else if (e.name.endsWith('.lua')) files.push(p);
        }
    })(ADDON);

    const families = new Set(Object.keys(base).map(k => k.split('.')[0]));
    const used = new Set();
    for (const file of files) {
        const rel = addon + '/' + path.relative(ADDON, file).replace(/\\/g, '/');
        const text = stripComments(fs.readFileSync(file, 'utf8'));
        const where = index => `${rel}:${text.slice(0, index).split('\n').length}`;

        // any key-like string literal counts as used (also L(cond and "a" or "b", ...))
        for (const m of text.matchAll(/"([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)"/g)) {
            if (!families.has(m[1].split('.')[0])) continue;
            used.add(m[1]);
            if (!(m[1] in base)) error(`${where(m.index)}: "${m[1]}" is not in ${BASE}.json`);
        }
        // L["key"]: a fixed text
        for (const m of text.matchAll(/\bL\["([^"]+)"\]/g)) {
            if (m[1] in base && varsOf(base[m[1]]).length)
                error(`${where(m.index)}: L["${m[1]}"] has {${varsOf(base[m[1]]).join(', ')}}: use L("${m[1]}", { ... })`);
        }
        // L("key", { ... }): the variables
        for (const m of text.matchAll(/\bL\(\s*"([^"]+)"\s*(,\s*)?/g)) {
            if (!(m[1] in base)) continue;
            const want = varsOf(base[m[1]]);
            const after = m.index + m[0].length;
            const given = m[2] && text[after] === '{' ? fieldNames(text, after) : null;
            if (given === null) {
                if (m[2]) continue;     // a table built elsewhere: not checked
                if (want.length) error(`${where(m.index)}: L("${m[1]}") without {${want.join(', ')}}`);
                continue;
            }
            const missing = want.filter(v => !given.includes(v)), extra = given.filter(v => !want.includes(v));
            if (missing.length) error(`${where(m.index)}: L("${m[1]}", ...) misses {${missing.join(', ')}}`);
            if (extra.length) warn(`${where(m.index)}: L("${m[1]}", ...) passes ${extra.join(', ')}, the text has no such variable`);
        }
    }
    return used;
}

const usedAnywhere = new Set();
for (const addon of addons) for (const key of checkCode(addon)) usedAnywhere.add(key);
for (const addon of addons) {
    const unused = Object.keys(data[addon].base).filter(k => !usedAnywhere.has(k));
    if (unused.length) warn(`${unused.length} keys of ${addon}/${BASE}.json not found in the code: ${unused.join(', ')}`);
}

// ---------------------------------------------------------------------------
// coverage
// ---------------------------------------------------------------------------
for (const addon of addons) {
    const { langs, tables, base } = data[addon];
    const total = Object.keys(base).length;
    for (const lang of langs.filter(l => l !== BASE)) {
        const missing = Object.keys(base).filter(k => !(k in tables[lang]));
        console.log(`${addon} ${lang}: ${total - missing.length} / ${total} keys translated`);
        if (listAll && missing.length) console.log('  missing: ' + missing.join(', '));
    }
}
console.log(errors ? `${errors} error(s)` : 'ok');
process.exit(errors ? 1 : 0);