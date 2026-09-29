const fs = require('node:fs');
const path = require('node:path');
const envPath = path.join(__dirname, '.env');
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const match = line.trim().match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);
    if (match && process.env[match[1]] === undefined) {
      process.env[match[1]] = match[2].trim().replace(/^(['"])(.*)\1$/, '$2');
    }
  }
}
const { createApp } = require('./src/app');
const app = createApp();
if (require.main === module) app.listen(process.env.PORT || 8080, process.env.HOST || '0.0.0.0');
module.exports = app;
