const { S3Client, PutObjectCommand, GetObjectCommand, HeadObjectCommand, CopyObjectCommand, DeleteObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { limits } = require('./validation');

class S3Objects {
  constructor({ bucket, region = 'ap-southeast-1', client } = {}) {
    this.bucket = bucket; this.client = client || new S3Client({ region });
  }
  async uploadUrl(key, job) {
    const checksum = Buffer.from(job.bundleHash, 'hex').toString('base64');
    const command = new PutObjectCommand({ Bucket: this.bucket, Key: key, ContentType: 'application/zip', ContentLength: job.sizeBytes, ChecksumSHA256: checksum, IfNoneMatch: '*' });
    const url = await getSignedUrl(this.client, command, { expiresIn: limits.urlSeconds, unhoistableHeaders: new Set(['x-amz-checksum-sha256']), signableHeaders: new Set(['content-type', 'content-length', 'if-none-match']) });
    return { url, headers: { 'Content-Type': 'application/zip', 'Content-Length': String(job.sizeBytes), 'x-amz-checksum-sha256': checksum, 'If-None-Match': '*' }, expiresAt: Date.now() + limits.urlSeconds * 1000 };
  }
  async head(key, { signal } = {}) {
    try { return await this.client.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key, ChecksumMode: 'ENABLED' }), { abortSignal: signal }); }
    catch (e) { if (e.$metadata?.httpStatusCode === 404) return null; throw e; }
  }
  async read(key, { signal } = {}) { return (await this.client.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }), { abortSignal: signal })).Body; }
  async promote(source, destination, { signal } = {}) {
    await this.client.send(new CopyObjectCommand({ Bucket: this.bucket, Key: destination, CopySource: `${this.bucket}/${source.split('/').map(encodeURIComponent).join('/')}`, IfNoneMatch: '*', ChecksumAlgorithm: 'SHA256' }), { abortSignal: signal });
  }
  async downloadUrl(key) { return getSignedUrl(this.client, new GetObjectCommand({ Bucket: this.bucket, Key: key }), { expiresIn: limits.urlSeconds }); }
  async delete(key) { await this.client.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key })); }
}

class FirestoreMetadata {
  constructor(db) { this.db = db; }
  job(uid, id) { return this.db.collection('users').doc(uid).collection('backups').doc(id); }
  workspace(uid, id) { return this.db.collection('users').doc(uid).collection('backupWorkspaces').doc(id); }
  async get(uid, id) { return (await this.job(uid, id).get()).data() || null; }
  async list(uid) { return (await this.db.collection('users').doc(uid).collection('backups').get()).docs.map(d => d.data()); }
  async change(uid, id, workspaceId, action) {
    return this.db.runTransaction(async txn => {
      const jr = this.job(uid, id), wr = this.workspace(uid, workspaceId);
      const [j, w] = await Promise.all([txn.get(jr), txn.get(wr)]);
      const result = action(j.data() || null, w.data() || { readyCount: 0, pendingId: null });
      if (result.job) txn.set(jr, result.job);
      if (result.workspace) txn.set(wr, result.workspace);
      return result.value;
    });
  }
}

function configuredAdapters() {
  if (!process.env.S3_BACKUP_BUCKET || !process.env.FIREBASE_PROJECT_ID) return null;
  const { getApps, initializeApp, applicationDefault } = require('firebase-admin/app');
  const { getAuth } = require('firebase-admin/auth');
  const { getFirestore } = require('firebase-admin/firestore');
  const app = getApps().find(a => a.name === 'fr18') || initializeApp({ credential: applicationDefault(), projectId: process.env.FIREBASE_PROJECT_ID }, 'fr18');
  return { verifyToken: token => getAuth(app).verifyIdToken(token, true), metadata: new FirestoreMetadata(getFirestore(app)), objects: new S3Objects({ bucket: process.env.S3_BACKUP_BUCKET, region: process.env.AWS_REGION || 'ap-southeast-1' }) };
}
module.exports = { S3Objects, FirestoreMetadata, configuredAdapters };
