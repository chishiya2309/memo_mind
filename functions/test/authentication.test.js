const test = require('node:test');
const assert = require('node:assert/strict');
const { createApp } = require('../src/app');

for (const api of ['sync', 'backups']) {
  test(`${api}: classifies authentication failures without blaming the session for service errors`, async () => {
    let failure, failureMessage;
    const dependencies = { verifyToken: async () => { throw Object.assign(new Error(failureMessage || 'secret-token-must-not-be-logged'), { code: failure }); } };
    const app = createApp({ [api === 'sync' ? 'sync' : 'backup']: dependencies });
    const server = app.listen(0, '127.0.0.1');
    await new Promise(resolve => server.once('listening', resolve));
    try {
      for (const [code, status, expected, message] of [
        ['auth/id-token-expired', 401, 'token_expired'],
        ['auth/invalid-id-token', 401, 'token_invalid'],
        ['auth/id-token-revoked', 401, 'reauth_required'],
        ['auth/user-not-found', 403, 'account_deleted'],
        ['auth/user-disabled', 403, 'account_disabled'],
        ['auth/insufficient-permission', 503, 'auth_configuration_error'],
        ['auth/argument-error', 503, 'auth_configuration_error', 'Firebase ID token has incorrect audience claim.'],
        ['auth/argument-error', 401, 'token_invalid', 'Malformed token.'],
        ['app/network-error', 503, 'auth_service_unavailable'],
        [undefined, 503, 'auth_service_unavailable'],
      ]) {
        failure = code;
        failureMessage = message;
        const response = await fetch(`http://127.0.0.1:${server.address().port}/api/v1/${api}${api === 'sync' ? '/status' : ''}`, { headers: { Authorization: 'Bearer test' } });
        assert.equal(response.status, status, code);
        assert.equal((await response.json()).error, expected, code);
        assert.match(response.headers.get('x-request-id'), /^[a-f0-9-]{36}$/);
      }
    } finally {
      await new Promise(resolve => server.close(resolve));
    }
  });
}
