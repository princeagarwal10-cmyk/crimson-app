// Deploy only after isolated-project tests and after the account table exists.
// This endpoint never returns passwords or exposes the service key to clients.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8';

const url = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const client = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const reply = (status: number, body: object) => Response.json(body, { status });
const clean = (v: unknown) => typeof v === 'string' ? v.trim() : '';
const syntheticEmail = (id: string) => {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
  let buffer = 0, bits = 0, encoded = '';
  for (const byte of new TextEncoder().encode(id)) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) { bits -= 5; encoded += alphabet[(buffer >> bits) & 31]; }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) encoded += alphabet[(buffer << (5 - bits)) & 31];
  return `u${encoded}@users.mycrimson.in`;
};

Deno.serve(async (req) => {
  if (req.method !== 'POST') return reply(405, { error: 'Method not allowed' });
  try {
    const token = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '') ?? '';
    const { data: auth, error: authError } = await client.auth.getUser(token);
    if (authError || !auth.user) return reply(401, { error: 'Please sign in again.' });
    const { data: profile, error: profileError } = await client.from('crimson_profiles').select('role,is_active').eq('user_id', auth.user.id).maybeSingle();
    if (profileError || !profile || profile.role !== 'admin' || profile.is_active !== true) return reply(403, { error: 'Only an active admin can manage accounts.' });
    const body = await req.json();
    if (body.action === 'list') {
      const { data, error } = await client.from('crimson_managed_customers').select('user_id,login_id,display_name,role,phone,address,city,status').order('display_name');
      if (error) throw error;
      const { data: profiles, error: profilesError } = await client.from('crimson_profiles').select('user_id,display_name,role,is_active').eq('role', 'customer');
      if (profilesError) throw profilesError;
      const managedIds = new Set((data ?? []).map((account) => account.user_id));
      const existing = (profiles ?? []).filter((p) => !managedIds.has(p.user_id)).map((p) => ({
        user_id: p.user_id, display_name: p.display_name, login_id: 'Existing email login',
        role: p.role, status: p.is_active ? 'active' : 'disabled', phone: '', address: '', city: '',
      }));
      return reply(200, { customers: [...(data ?? []), ...existing] });
    }
    if (body.action !== 'create') return reply(400, { error: 'Unsupported action.' });
    const name = clean(body.name).replace(/\s+/g, ' ');
    const loginId = clean(body.userId).toLowerCase();
    const password = typeof body.password === 'string' ? body.password : '';
    const role = clean(body.role);
    if (!name || name.length > 120 || !/^[a-z0-9][a-z0-9._-]{2,31}$/.test(loginId) || password.length < 8 || password.length > 128 || !['customer','owner','admin'].includes(role)) return reply(400, { error: 'Check name, user ID, password and role.' });
    if (role === 'customer') {
      const { data: profiles, error: existingError } = await client.from('crimson_profiles').select('display_name').eq('role', 'customer');
      if (existingError) throw existingError;
      const normalizedName = name.toLowerCase();
      if ((profiles ?? []).some((p) => clean(p.display_name).replace(/\s+/g, ' ').toLowerCase() === normalizedName)) return reply(409, { error: 'This customer name is already in use.' });
    }
    const id = crypto.randomUUID();
    const { error: reserveError } = await client.from('crimson_managed_customers').insert({ user_id: id, login_id: loginId, display_name: name, role, phone: clean(body.phone), address: clean(body.address), city: clean(body.city), status: 'provisioning' });
    if (reserveError) {
      if (reserveError.code === '23505') return reply(409, { error: 'This customer name or user ID is already in use.' });
      throw reserveError;
    }
    let createdAuthId = '';
    try {
      // Auth supports a caller-supplied UUID; keep it consistent with the
      // reserved row so uniqueness is enforced before credentials are made.
      const attributes = { id, email: syntheticEmail(loginId), password, email_confirm: true };
      const { data: createdUser, error: createError } = await client.auth.admin.createUser(attributes);
      if (createError) throw createError;
      createdAuthId = createdUser.user?.id ?? '';
      if (createdUser.user?.id !== id) throw new Error('Auth returned an unexpected user ID');
      // Deploy this version only after customer catalogue privacy is enforced.
      const enabled = true;
      const { error: profileInsertError } = await client.from('crimson_profiles').insert({ user_id: id, display_name: name, role, is_active: enabled });
      if (profileInsertError) throw profileInsertError;
      const { error: updateError } = await client.from('crimson_managed_customers').update({ status: enabled ? 'active' : 'pending_privacy' }).eq('user_id', id);
      if (updateError) throw updateError;
      return reply(201, { userId: id, loginId, name, role });
    } catch (_) {
      if (createdAuthId) {
        const { error: cleanupError } = await client.auth.admin.deleteUser(createdAuthId);
        if (cleanupError) return reply(500, { error: 'Account setup did not complete. Contact the administrator before retrying.' });
      }
      await client.from('crimson_managed_customers').delete().eq('user_id', id);
      return reply(500, { error: 'Account could not be created. Check server logs.' });
    }
  } catch (_) {
    return reply(500, { error: 'Customer service is unavailable.' });
  }
});
