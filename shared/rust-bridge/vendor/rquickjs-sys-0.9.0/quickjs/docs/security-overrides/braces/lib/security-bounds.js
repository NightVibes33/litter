'use strict';

// Root-owned limits for the unpatched braces 3.0.3 recursion advisory.
const MAX_DEPTH = 64;
const MAX_NODES = 100000;

exports.assertSafeInput = input => {
  if (typeof input === 'string') {
    if (input.length > 65536) throw new RangeError('Brace pattern is too long');
    let depth = 0;
    let escaped = false;
    let characterClass = false;
    for (const character of input) {
      if (escaped) { escaped = false; continue; }
      if (character === '\\') { escaped = true; continue; }
      if (character === '[') { characterClass = true; continue; }
      if (character === ']') { characterClass = false; continue; }
      if (characterClass) continue;
      if (character === '{' && ++depth > MAX_DEPTH) {
        throw new RangeError('Brace pattern exceeds safe nesting depth');
      }
      if (character === '}') depth = Math.max(0, depth - 1);
    }
    return;
  }
  if (!input || typeof input !== 'object') return;
  const pending = [{ node: input, depth: 0 }];
  const seen = new WeakSet();
  let count = 0;
  while (pending.length) {
    const { node, depth } = pending.pop();
    if (!node || typeof node !== 'object') continue;
    if (depth > MAX_DEPTH || ++count > MAX_NODES || seen.has(node)) {
      throw new RangeError('Brace AST exceeds safe traversal bounds');
    }
    seen.add(node);
    if (Array.isArray(node.nodes)) {
      for (const child of node.nodes) pending.push({ node: child, depth: depth + 1 });
    }
  }
};
