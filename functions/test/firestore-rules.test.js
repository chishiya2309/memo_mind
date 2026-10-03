const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
test('Firestore enforces owner, verified email, and denies all client metadata writes', { skip: !process.env.FIRESTORE_EMULATOR_HOST }, async () => {
  const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
  const { doc, getDoc, setDoc } = require('firebase/firestore');
  const environment = await initializeTestEnvironment({ projectId: 'demo-memomind', firestore: { rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') } });
  try {
    await environment.withSecurityRulesDisabled(async context => setDoc(doc(context.firestore(), 'users/A/backups/one'), { ownerUid: 'A', status: 'ready' }));
    const owner = environment.authenticatedContext('A', { email_verified: true }).firestore();
    const other = environment.authenticatedContext('B', { email_verified: true }).firestore();
    const unverified = environment.authenticatedContext('A', { email_verified: false }).firestore();
    await assertSucceeds(getDoc(doc(owner, 'users/A/backups/one')));
    await assertFails(getDoc(doc(other, 'users/A/backups/one')));
    await assertFails(getDoc(doc(unverified, 'users/A/backups/one')));
    await assertFails(getDoc(doc(environment.unauthenticatedContext().firestore(), 'users/A/backups/one')));
    await assertFails(setDoc(doc(owner, 'users/A/backups/fake-ready'), { ownerUid: 'A', status: 'ready' }));
    await assertFails(getDoc(doc(owner, 'users/A/backupWorkspaces/one')));
  } finally { await environment.cleanup(); }
});
