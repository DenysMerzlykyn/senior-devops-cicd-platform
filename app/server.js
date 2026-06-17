const express = require('express');

const app = express();

const PORT = process.env.PORT || 3000;
const APP_VERSION = process.env.APP_VERSION || 'local';
const ENVIRONMENT = process.env.ENVIRONMENT || 'development';
const APP_SLOT = process.env.APP_SLOT || 'local';

app.get('/', (req, res) => {
  res.json({
    message: 'Hello from Production-Style DevOps CI/CD Platform',
    service: 'senior-devops-cicd-app',
    environment: ENVIRONMENT,
    version: APP_VERSION,
    slot: APP_SLOT,
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    service: 'senior-devops-cicd-app',
    environment: ENVIRONMENT,
    version: APP_VERSION,
    slot: APP_SLOT,
  });
});

app.get('/version', (req, res) => {
  res.json({
    version: APP_VERSION,
    environment: ENVIRONMENT,
    slot: APP_SLOT,
  });
});

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`App listening on port ${PORT}`);
  });
}

module.exports = app;
