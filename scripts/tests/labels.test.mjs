// Unit tests for 0A.12: label search (default words still match) and the label checks of check:i18n.
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import meta from '../../src/i18n/label-meta.json' with { type: 'json' };
import bnLabels from '../../src/i18n/locales/bn/labels.json' with { type: 'json' };
import enLabels from '../../src/i18n/locales/en/labels.json' with { type: 'json' };
import { searchLabels, toSearchable } from '../../src/lib/label-search.ts';
import { checkLabelReferences, compareLocales } from '../check-translations.mjs';

const value = (en_singular, en_plural, base) => ({ en_singular, en_plural, bn_forms: { base, plural: `${base}রা` } });
const ENTRIES = {
  client: { legacy_key: 'student', resolved: value('Trainee', 'Trainees', 'প্রশিক্ষণার্থী'), default: value('Student', 'Students', 'শিক্ষার্থী'), product: value('Client', 'Clients', 'ক্লায়েন্ট') },
  'module.clients': { legacy_key: 'module.students', resolved: value('Trainees', 'Trainees', 'প্রশিক্ষণার্থী'), default: value('Students', 'Students', 'শিক্ষার্থী'), product: value('Clients', 'Clients', 'ক্লায়েন্ট') },
  conversion: { legacy_key: 'admission', resolved: value('Admission', 'Admissions', 'ভর্তি'), default: value('Admission', 'Admissions', 'ভর্তি'), product: value('Enrolment', 'Enrolments', 'নিবন্ধন') },
  cohort: { legacy_key: 'batch', resolved: value('Batch', 'Batches', 'ব্যাচ'), default: value('Batch', 'Batches', 'ব্যাচ'), product: value('Session', 'Sessions', 'সেশন') },
  fee: { legacy_key: null, resolved: value('Fee', 'Fees', 'ফি'), default: value('Fee', 'Fees', 'ফি'), product: value('Fee', 'Fees', 'ফি') },
};
const LABELS = toSearchable(ENTRIES);

describe('label search (Ch 8.9 rule 5)', () => {
  it('"student" finds the module renamed "Trainees"', () => {
    const found = searchLabels('student', LABELS);
    assert.ok(found.includes('module.clients'));
    assert.ok(found.includes('client'));
  });
  it('the current word ranks first', () => {
    assert.deepEqual(searchLabels('trainee', LABELS).slice(0, 2).sort(), ['client', 'module.clients']);
  });
  it('matches plurals, Bangla words, product words and keys', () => {
    assert.ok(searchLabels('batches', LABELS).includes('cohort'));
    assert.ok(searchLabels('শিক্ষার্থী', LABELS).includes('client'));
    assert.ok(searchLabels('ভর্তি', LABELS).includes('conversion'));
    assert.ok(searchLabels('enrolment', LABELS).includes('conversion'));
    assert.ok(searchLabels('module.clients', LABELS).includes('module.clients'));
  });
  it('an empty query lists everything; nonsense lists nothing', () => {
    assert.equal(searchLabels('  ', LABELS).length, Object.keys(ENTRIES).length);
    assert.deepEqual(searchLabels('zzzq', LABELS), []);
  });
});

describe('bundled default labels', () => {
  it('every key has English singular/plural and all Bangla forms', () => {
    const locales = { en: { labels: enLabels }, bn: { labels: bnLabels } };
    assert.deepEqual(compareLocales(locales), []);
    assert.equal(Object.keys(meta).length, 41);
  });
  it('a missing Bangla form or word is reported', () => {
    const bn = structuredClone(bnLabels);
    delete bn.client.plural_oblique;
    delete bn.fee;
    const out = compareLocales({ en: { labels: enLabels }, bn: { labels: bn } }).join('\n');
    assert.match(out, /\[missing_label_form\] bn\/labels: "client\.plural_oblique"/);
    assert.match(out, /\[missing_label\] bn\/labels: "fee"/);
  });
  it('a sentence using an unknown label is reported', () => {
    const out = checkLabelReferences({
      en: { labels: enLabels, common: { a: 'Add $t(labels:client.singular)', b: 'All $t(labels:student.plural)' } },
    }).join('\n');
    assert.doesNotMatch(out, /client/);
    assert.match(out, /labels:student\.plural, which does not exist/);
  });
});
