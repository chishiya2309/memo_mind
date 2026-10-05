const express = require('../../functions/node_modules/express');
const crypto = require('node:crypto');
const { createApp } = require('../../functions/src/app');
const { MemorySyncStore } = require('../../functions/test/sync-support.cjs');
const files = new Map(); let origin;
const objects = {
  async uploadUrl(key, job) { return {url:`${origin}/objects/${encodeURIComponent(key)}`,headers:{'Content-Type':job.mimeType},expiresAt:Date.now()+600000}; },
  async head(key) { const b=files.get(key);return b?{ContentLength:b.length,ChecksumSHA256:crypto.createHash('sha256').update(b).digest('base64')}:null; },
  async downloadUrl(key) { return `${origin}/objects/${encodeURIComponent(key)}`; },
};
const app=createApp({sync:{store:new MemorySyncStore(),objects,verifyToken:async token=>({uid:token==='B'?'B':'A',email_verified:true})}});
app.put('/objects/:key',express.raw({type:()=>true,limit:'100mb'}),(req,res)=>{files.set(req.params.key,req.body);res.sendStatus(200);});
app.get('/objects/:key',(req,res)=>{const b=files.get(req.params.key);if(!b)return res.sendStatus(404);res.end(b);});
const server=app.listen(0,'127.0.0.1',()=>{origin=`http://127.0.0.1:${server.address().port}`;process.stdout.write(`${origin}\n`);});
