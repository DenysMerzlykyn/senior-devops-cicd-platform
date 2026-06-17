const test = require('node:test');
const assert = require('node:assert');
const app = require('./server');

test('GET /health returns status ok', async () => {
  const server = app.listen(0);
  const port = server.address().port;
  try {
    const response = await fetch(`http://127.0.0.1:${port}/health`);
    const body = await response.json();
    assert.strictEqual(response.status, 200);
    assert.strictEqual(body.status, 'ok');
    assert.strictEqual(body.service, 'senior-devops-cicd-app');
  } finally {
    server.close();
  }
});

test('GET / returns app info', async () => {
  const server = app.listen(0);
  const port = server.address().port;
  try {
    const response = await fetch(`http://127.0.0.1:${port}/`);
    const body = await response.json();
    assert.strictEqual(response.status, 200);
    assert.ok(body.message);
    assert.strictEqual(body.service, 'senior-devops-cicd-app');
  } finally {
    server.close();
  }
});

test('GET /version returns version info', async () => {
  const server = app.listen(0);
  const port = server.address().port;
  try {
    const response = await fetch(`http://127.0.0.1:${port}/version`);
    const body = await response.json();
    assert.strictEqual(response.status, 200);
    assert.ok(body.version);
  } finally {
    server.close();
  }
});
