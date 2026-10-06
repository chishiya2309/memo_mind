const { randomUUID } = require('node:crypto');
const { fail } = require('./backup/validation');

// Never turn an infrastructure failure into a request to sign in again.
async function authenticate(req, res, verifyToken) {
  const requestId = randomUUID();
  res.setHeader('X-Request-ID', requestId);
  const token = /^Bearer (\S+)$/.exec(req.headers.authorization || '')?.[1];
  if (!token) fail('token_invalid', 'Thiếu thông tin xác thực.', 401);
  let identity;
  try {
    identity = await verifyToken(token);
  } catch (error) {
    const code = typeof error.code === 'string' && /^[a-z/-]+$/.test(error.code) ? error.code : 'unknown';
    console.warn(JSON.stringify({ event: 'auth_verification_failed', requestId, code }));
    if (code === 'auth/id-token-expired') fail('token_expired', 'Phiên cần được làm mới.', 401);
    if (code === 'auth/id-token-revoked') fail('reauth_required', 'Phiên đã kết thúc. Xác thực lại để tiếp tục đồng bộ.', 401);
    if (code === 'auth/user-not-found') fail('account_deleted', 'Tài khoản không còn tồn tại. Dữ liệu trên thiết bị được giữ nguyên.', 403);
    if (code === 'auth/user-disabled') fail('account_disabled', 'Tài khoản đã bị vô hiệu hóa.', 403);
    if (['auth/invalid-credential', 'auth/insufficient-permission', 'app/invalid-credential'].includes(code) ||
        (code === 'auth/argument-error' && /audience|issuer|project id/i.test(error.message || ''))) {
      fail('auth_configuration_error', 'Dịch vụ xác thực chưa được cấu hình đúng. Vui lòng thử lại sau.', 503);
    }
    if (['auth/argument-error', 'auth/invalid-id-token'].includes(code)) fail('token_invalid', 'Không xác minh được thông tin đăng nhập.', 401);
    fail('auth_service_unavailable', 'Chưa kết nối được dịch vụ xác thực. Hãy thử lại sau.', 503);
  }
  if (!identity?.uid) fail('token_invalid', 'Không xác minh được thông tin đăng nhập.', 401);
  if (identity.email_verified !== true) fail('email_unverified', 'Xác minh email để đồng bộ.', 403);
  req.uid = identity.uid;
}

module.exports = { authenticate };
