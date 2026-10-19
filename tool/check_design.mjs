import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Script, createContext } from 'node:vm';

const root = fileURLToPath(new URL('../design/JANITRA_Complete_Polished_UI/', import.meta.url));
const screens = readdirSync(root).filter(name => existsSync(resolve(root, name, 'code.html')));
assert.equal(screens.length, 23);
for (const name of screens) {
  const file = resolve(root, name, 'code.html');
  const html = readFileSync(file, 'utf8');
  assert(!/href=["']#["']/.test(html), `${name}: placeholder navigation`);
  for (const [, target] of html.matchAll(/(?:href|src)=["']([^"']+)["']/g)) {
    if (/^(?:https?:|data:|#)/.test(target)) continue;
    assert(existsSync(resolve(dirname(file), target)), `${name}: missing ${target}`);
  }
  for (const [, source] of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)) {
    new Script(source, { filename: file });
  }
}
for (const name of readdirSync(resolve(root, 'assets')).filter(name => name.endsWith('.js'))) {
  new Script(readFileSync(resolve(root, 'assets', name), 'utf8'));
}
const verification = readFileSync(resolve(root, 'janitra_confirm_work_pin_verification/code.html'), 'utf8');
assert(/<div hidden aria-hidden="true"[^>]*id="success-modal"/.test(verification));
assert(readFileSync(resolve(root, 'assets/janitra-polish.css'), 'utf8').includes('[hidden]{display:none!important;}'));
const tasks = readFileSync(resolve(root, 'janitra_my_tasks_simplified/code.html'), 'utf8');
assert(tasks.includes('href="../janitra_task_details_simplified/code.html"'));
assert(!tasks.includes('role="button"'));
assert(!tasks.includes('handleCardClick'));
assert(!readFileSync(resolve(root, 'janitra_task_details_simplified/code.html'), 'utf8').includes('proceedNextScreen'));

const nodes = new Map();
const listeners = new Map();
const document = {
  activeElement: null,
  getElementById(id) {
    if (!nodes.has(id)) nodes.set(id, {
      textContent: '',
      get innerText() { return this.textContent; },
      set innerText(value) { this.textContent = value; },
      classList: {
        values: new Set(['hidden']),
        add(value) { this.values.add(value); },
        remove(value) { this.values.delete(value); },
        contains(value) { return this.values.has(value); },
      },
      focus() { document.activeElement = this; },
      querySelector() { return document.getElementById(`${id}-button`); },
    });
    return nodes.get(id);
  },
  querySelector() { return document.getElementById('modal-step-result-button'); },
  addEventListener(type, callback) { listeners.set(type, callback); },
};
const context = createContext({ document, crypto: { getRandomValues(sample) { sample[0] = 1; } }, setTimeout() {} });
const management = readFileSync(resolve(root, 'janitra_employee_pin_management/code.html'), 'utf8');
new Script(management.match(/<script>([\s\S]*?)<\/script>/)[1]).runInContext(context);
context.openPinResetModal();
context.confirmPinGeneration();
assert.equal(document.getElementById('generated-pin-display').textContent, '0001');
context.closePinResetModal();
assert.equal(document.getElementById('generated-pin-display').textContent, '••••');
assert.equal(document.activeElement, document.getElementById('reset-pin-trigger'));
context.openPinResetModal();
listeners.get('keydown')({ key: 'Escape' });
assert(document.getElementById('reset-modal').classList.contains('hidden'));
console.log('PASS: 23 screens, local links, syntax, native task navigation, hidden success, PIN erasure and Escape.');
