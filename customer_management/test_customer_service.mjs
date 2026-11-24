import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';

const file = new URL('./crimson-admin-customers/index.ts', import.meta.url);
const source = readFileSync(file, 'utf8').replace(/^import .*;\s*/m, '');
let handler;
let currentRole = 'admin';
let userValid = true;
let profiles = [{ role: 'customer', display_name: 'Existing Person' }];
let accounts = [];
let authUsers = new Map();
function query(table) {
  let action = 'select', row = null, filter = null, patch = null;
  const q = {
    select() { action = 'select'; return q; },
    insert(value) { action = 'insert'; row = value; return q; },
    update(value) { action = 'update'; patch = value; return q; },
    delete() { action = 'delete'; return q; },
    eq(key, value) { filter = [key, value]; return q; },
    async maybeSingle() { return { data: { role: currentRole, is_active: true }, error: null }; },
    async order() { return { data: accounts, error: null }; },
    then(resolve, reject) { return Promise.resolve().then(() => {
      if (table === 'crimson_profiles') {
        if (action === 'select') return { data: profiles.filter(p => !filter || p[filter[0]] === filter[1]), error: null };
        if (action === 'insert') { profiles.push(row); return { error: null }; }
      }
      if (table === 'crimson_managed_customers') {
        if (action === 'insert') {
          if (accounts.some(a => a.login_id === row.login_id || a.display_name.toLowerCase() === row.display_name.toLowerCase())) return { error: { code: '23505' } };
          accounts.push(row); return { error: null };
        }
        if (action === 'update') { Object.assign(accounts.find(a => a.user_id === filter[1]), patch); return { error: null }; }
        if (action === 'delete') { accounts = accounts.filter(a => a.user_id !== filter[1]); return { error: null }; }
      }
      throw Error(`unexpected ${table} ${action}`);
    }).then(resolve, reject); },
  };
  return q;
}
const mock = {
  auth: {
    async getUser() { return userValid ? { data: { user: { id: 'admin-id' } }, error: null } : { data: {}, error: 'invalid' }; },
    admin: {
      async createUser(attrs) { authUsers.set(attrs.id, attrs); return { data: { user: { id: attrs.id } }, error: null }; },
      async deleteUser(id) { authUsers.delete(id); return { error: null }; },
    },
  },
  from: query,
};
const context = { Deno: { env: { get: () => 'configured' }, serve: f => { handler = f; } }, createClient: () => mock, Response, Request, TextEncoder, crypto: webcrypto, console };
runInNewContext(stripTypeScriptTypes(source, { mode: 'strip' }), context);
const request = body => new Request('https://example.test', { method: 'POST', headers: { Authorization: 'Bearer test', 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
const account = { action: 'create', name: 'Hemant', userId: 'hemant01', password: 'password123', role: 'customer' };
userValid = false;
assert.equal((await handler(request(account))).status, 401);
userValid = true; currentRole = 'customer';
assert.equal((await handler(request(account))).status, 403);
currentRole = 'admin';
assert.equal((await handler(request({ ...account, name: ' existing   person ' }))).status, 409);
assert.equal((await handler(request(account))).status, 201);
assert.equal(accounts[0].status, 'active');
assert.equal(profiles.at(-1).is_active, true);
assert.equal([...authUsers.values()][0].email, 'unbsw2ylooqydc@users.mycrimson.in');
assert.equal((await handler(request({ ...account, name: 'Rahul' }))).status, 409);
assert.equal((await handler(request({ ...account, userId: 'other123' }))).status, 409);
assert.equal((await handler(request({ action: 'list' }))).status, 200);
console.log('Customer service authorization, duplicate checks and account creation passed.');
