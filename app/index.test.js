const request = require('supertest');

// Mock pg Pool
jest.mock('pg', () => {
  const mPool = {
    query: jest.fn(),
  };
  return { Pool: jest.fn(() => mPool) };
});

const { Pool } = require('pg');
const pool = new Pool();

// Mock initDB to resolve immediately
pool.query.mockResolvedValueOnce({ rows: [] }); // CREATE TABLE

const app = require('./index');

describe('API Endpoints', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('GET / returns welcome message', async () => {
    const res = await request(app).get('/');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('message');
    expect(res.body.version).toBe('1.0.0');
  });

  test('GET /health - healthy', async () => {
    pool.query.mockResolvedValueOnce({ rows: [{ '?column?': 1 }] });
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('healthy');
  });

  test('GET /health - unhealthy when DB fails', async () => {
    pool.query.mockRejectedValueOnce(new Error('Connection refused'));
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(503);
    expect(res.body.status).toBe('unhealthy');
  });

  test('GET /users returns list', async () => {
    pool.query.mockResolvedValueOnce({
      rows: [{ id: 1, name: 'Alice', email: 'alice@test.com', created_at: new Date() }],
    });
    const res = await request(app).get('/users');
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.count).toBe(1);
  });

  test('POST /users creates a user', async () => {
    pool.query.mockResolvedValueOnce({
      rows: [{ id: 2, name: 'Bob', email: 'bob@test.com', created_at: new Date() }],
    });
    const res = await request(app)
      .post('/users')
      .send({ name: 'Bob', email: 'bob@test.com' });
    expect(res.statusCode).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.data.name).toBe('Bob');
  });

  test('POST /users returns 400 if fields missing', async () => {
    const res = await request(app).post('/users').send({ name: 'NoEmail' });
    expect(res.statusCode).toBe(400);
  });

  test('GET /metrics returns prometheus metrics', async () => {
    const res = await request(app).get('/metrics');
    expect(res.statusCode).toBe(200);
    expect(res.text).toContain('http_requests_total');
  });
});
