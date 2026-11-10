// 0A.06 end-to-end: Storage paths and Realtime private channels through the real Supabase services.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { adminSql, INSTITUTION, signInAs } from './helpers.mjs';

const BUCKET = 'institution-files';
const fileName = `e2e-${Date.now()}.txt`;
const pathA = `${INSTITUTION.A}/documents/${fileName}`;

async function subscribe(client, topic) {
  await client.realtime.setAuth();
  return await new Promise((resolve) => {
    const channel = client.channel(topic, { config: { private: true } });
    const timer = setTimeout(() => resolve({ status: 'TIMED_OUT', channel }), 8000);
    channel.subscribe((status, err) => {
      if (status === 'SUBSCRIBED' || status === 'CHANNEL_ERROR' || status === 'CLOSED') {
        clearTimeout(timer);
        resolve({ status, err, channel });
      }
    });
  });
}

describe('storage isolation (institution folder)', () => {
  let a;
  let b;
  before(async () => {
    adminSql("update public.profiles set last_active_institution_id = null where email like '%@example.test'");
    a = await signInAs('a.member@example.test');
    b = await signInAs('b.member@example.test');
  });
  after(async () => {
    await a.client.storage.from(BUCKET).remove([pathA]);
  });

  it('a member uploads into their active institution\'s folder', async () => {
    const { error } = await a.client.storage.from(BUCKET).upload(pathA, new Blob(['hello A']), { contentType: 'text/plain' });
    assert.equal(error, null);
  });

  it('a member cannot upload into another institution\'s folder or outside any institution folder', async () => {
    const intoB = await a.client.storage.from(BUCKET).upload(`${INSTITUTION.B}/documents/${fileName}`, new Blob(['x']));
    assert.ok(intoB.error, 'upload into B must fail');
    const noFolder = await a.client.storage.from(BUCKET).upload(`loose/${fileName}`, new Blob(['x']));
    assert.ok(noFolder.error, 'upload without an institution folder must fail');
  });

  it('a member of B cannot download or list A\'s files', async () => {
    const download = await b.client.storage.from(BUCKET).download(pathA);
    assert.ok(download.error, 'download must fail');
    const list = await b.client.storage.from(BUCKET).list(`${INSTITUTION.A}/documents`);
    assert.deepEqual(list.data ?? [], []);
    const signed = await b.client.storage.from(BUCKET).createSignedUrl(pathA, 60);
    assert.ok(signed.error, 'signing a URL for A\'s file must fail');
  });

  it('a person in A and B sees A\'s files only while A is active (D25)', async () => {
    const both = await signInAs('both.member@example.test');
    await both.client.rpc('set_active_institution', { p_institution_id: INSTITUTION.B });
    await both.client.auth.refreshSession();
    const whileB = await both.client.storage.from(BUCKET).download(pathA);
    assert.ok(whileB.error, 'with B active, A\'s file is not readable');
    await both.client.rpc('set_active_institution', { p_institution_id: INSTITUTION.A });
    await both.client.auth.refreshSession();
    const whileA = await both.client.storage.from(BUCKET).download(pathA);
    assert.equal(whileA.error, null);
    assert.equal(await whileA.data.text(), 'hello A');
  });
});

describe('realtime private channels (inst:<institution_id>:<topic>)', () => {
  const opened = [];
  after(async () => {
    for (const { client, channel } of opened) await client.removeChannel(channel);
  });

  it('a member joins their own institution\'s channel', async () => {
    const { client } = await signInAs('a.member@example.test');
    const result = await subscribe(client, `inst:${INSTITUTION.A}:e2e`);
    opened.push({ client, channel: result.channel });
    assert.equal(result.status, 'SUBSCRIBED');
  });

  it('a member of B cannot join A\'s channel', async () => {
    const { client } = await signInAs('b.member@example.test');
    const result = await subscribe(client, `inst:${INSTITUTION.A}:e2e`);
    opened.push({ client, channel: result.channel });
    assert.notEqual(result.status, 'SUBSCRIBED');
  });

  it('a channel name without an institution is refused', async () => {
    const { client } = await signInAs('a.member@example.test');
    const result = await subscribe(client, 'everyone:e2e');
    opened.push({ client, channel: result.channel });
    assert.notEqual(result.status, 'SUBSCRIBED');
  });
});
