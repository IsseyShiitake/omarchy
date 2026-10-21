#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The menu model is where both JSONC sources and the extension merge are
# decided. Each case here used to fail silently: one trailing comment made the
# whole menu parse to nothing, and an alias-only override wiped the default
# row's action (a childless menu, which is not shown at all).
run_node_test <<'JS'
const fs = require('fs')
const os = require('os')
const { execFileSync } = require('child_process')
const M = requireFromRoot('shell/plugins/menu/MenuModel.js')

// ---- JSONC: an annotated entry must not empty the file --------------------
const annotated = '{"items":{"a":{"label":"A"}, // note\n}}'
assertEqual(M.parseMenuJsonc(annotated).length, 1, 'a trailing comma before a line comment still parses')
assertEqual(M.parseMenuJsonc(annotated)[0].label, 'A', 'the annotated entry keeps its label')

assertEqual(M.parseMenuJsonc('{"items":{"a":{"label":"A"} /* note */,}}').length, 1, 'a block comment before a trailing comma parses')
assertEqual(M.parseMenuJsonc('\uFEFF{"items":{"a":{"label":"A"}}}').length, 1, 'a UTF-8 BOM does not empty the menu')

const comma = M.parseMenuJsonc('{"items":{"a":{"label":"x,}"}}}')
assertEqual(comma[0].label, 'x,}', 'a comma-brace inside a string survives')

// ---- merge: an alias-only override keeps the default row -------------------
const defaults = M.parseMenuJsonc('{"items":{"system":{"label":"System","action":"act","icon":"I","when":"true"}}}')
const aliasOnly = M.parseMenuJsonc('{"items":{"system":{"aliases":["x"]}}}')
const merged = M.mergeMenuSources(defaults, aliasOnly, 'Go').items.system
assertEqual(merged.action, 'act', 'an alias-only override keeps the default action')
assertEqual(merged.label, 'System', 'an alias-only override keeps the default label')
assertEqual(merged.icon, 'I', 'an alias-only override keeps the default icon')
assertEqual(merged.when, 'true', 'an alias-only override keeps the default guard')
assertEqual(merged.kind, 'action', 'the merged row is still an action')

const renamed = M.mergeMenuSources(defaults, M.parseMenuJsonc('{"items":{"system":{"label":"Mine"}}}'), 'Go').items.system
assertEqual(renamed.label, 'Mine', 'an explicit label still wins')
assertEqual(renamed.action, 'act', '... while the rest of the row survives')

const cleared = M.mergeMenuSources(defaults, M.parseMenuJsonc('{"items":{"system":{"action":""}}}'), 'Go').items.system
assertEqual(cleared.action, '', 'an explicit empty action clears it')
assertEqual(cleared.kind, 'menu', 'a row with no action becomes a submenu')

// ---- guards: the menu id is data, never shell ------------------------------
const marker = path.join(os.tmpdir(), 'omarchy-menu-guard-marker-' + process.pid)
fs.rmSync(marker, { force: true })
const hostile = 'x; touch ' + marker + '; #'
const script = M.guardScript({ [hostile]: { id: hostile, when: 'true' } })
const out = execFileSync('bash', ['-c', script], { encoding: 'utf8' })
assertEqual(out.trim(), hostile + ':w:1', 'a hostile id is answered verbatim')
assert(!fs.existsSync(marker), 'a hostile id does not run shell')
fs.rmSync(marker, { force: true })
JS
