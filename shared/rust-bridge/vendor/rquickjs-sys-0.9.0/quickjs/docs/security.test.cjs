'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const braces = require('braces');
const bounds = require('./security-overrides/braces/lib/security-bounds');

test('local brace implementation preserves compile, expand and stringify APIs', () => {
  assert.deepEqual(braces.expand('assets/{app,icon}.png'), ['assets/app.png', 'assets/icon.png']);
  const pattern = 'assets/{app,icon}.png';
  assert.equal(braces.stringify(braces.parse(pattern)), pattern);
  assert.match(braces.compile(pattern), /app\|icon/);
});

test('recursion bounds validate input before recursive operations', () => {
  bounds.assertSafeInput('assets/{app,icon}.png');
  assert.throws(() => bounds.assertSafeInput('x'.repeat(65537)), RangeError);
  let tree = { type: 'text', value: 'leaf' };
  for (let level = 0; level < 66; level++) tree = { nodes: [tree] };
  assert.throws(() => bounds.assertSafeInput(tree), RangeError);
});
