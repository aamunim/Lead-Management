import { Redirect } from 'expo-router';
import { useCallback, useState } from 'react';

import { AmountInput, PhoneInput } from '@/components/fields/inputs';
import { DateField } from '@/components/fields/pickers';
import { devToolsEnabled } from '@/dev/flags';
import { useTranslation } from '@/i18n';
import { FormScreen, TextField, useDraft, useSnackbar, useSubmit } from '@/ui/components';

type Values = { name: string; email: string; phone: string | null; amount: string | null; date: string | null; address: string;
  city: string; school: string; comment: string };
const EMPTY: Values = { name: '', email: '', phone: null, amount: null, date: null, address: '', city: '', school: '', comment: '' };

// Long form demo (0A.13-T4/T5): focused field above the keyboard, Save bar above the keyboard, Next/Done, draft that
// survives a call or app kill, "Discard changes?" on Back, and Save that cannot run twice (idempotency key).
export default function LongFormDemo() {
  const { t } = useTranslation('gallery');
  const { t: tUi } = useTranslation('ui');
  const snackbar = useSnackbar();
  const [values, setValues] = useState<Values>(EMPTY);
  const [saves, setSaves] = useState(0);
  const draft = useDraft<Values>('dev.long_form', values, setValues);
  const dirty = JSON.stringify(values) !== JSON.stringify(EMPTY);
  const set = <K extends keyof Values>(key: K) => (value: Values[K]) => setValues((v) => ({ ...v, [key]: value }));

  const { submit, submitting } = useSubmit(useCallback(async (idempotencyKey: string) => {
    // A real form calls its RPC here with p_idempotency_key = idempotencyKey.
    await new Promise((resolve) => setTimeout(resolve, 800));
    setSaves((n) => n + 1);
    return idempotencyKey;
  }, []));
  const save = async () => {
    if (await submit()) {
      await draft.clear();
      setValues(EMPTY);
      snackbar.show({ text: tUi('form.saved') });
    }
  };

  if (!devToolsEnabled) return <Redirect href="/" />;
  return (
    <FormScreen title={t('form.title')} onSave={() => void save()} saving={submitting} dirty={dirty} testID="long-form"
      notice={draft.restored ? tUi('form.draftRestored') : saves > 0 ? t('form.submitted', { n: saves }) : null}>
      <TextField label={t('fields.name')} kind="name" value={values.name} onChangeText={set('name')} required testID="lf-name" />
      <TextField label={t('fields.email')} kind="email" value={values.email} onChangeText={set('email')} testID="lf-email" />
      <PhoneInput label={t('fields.phone')} value={values.phone} onChange={set('phone')} testID="lf-phone" />
      <AmountInput label={t('fields.amount')} value={values.amount} onChange={set('amount')} testID="lf-amount" />
      <DateField label={t('fields.date')} value={values.date} onChange={set('date')} testID="lf-date" />
      <TextField label={t('form.address')} value={values.address} onChangeText={set('address')} testID="lf-address" />
      <TextField label={t('form.city')} value={values.city} onChangeText={set('city')} testID="lf-city" />
      <TextField label={t('form.school')} value={values.school} onChangeText={set('school')} testID="lf-school" />
      <TextField label={t('form.comment')} kind="multiline" value={values.comment} onChangeText={set('comment')} last onDone={() => void save()}
        testID="lf-comment" />
    </FormScreen>
  );
}
