const request = require('supertest');

// ─── Mock pg BEFORE requiring app ────────────────────────────────────────────
const mockQuery = jest.fn();

jest.mock('pg', () => {
  return {
    Pool: jest.fn().mockImplementation(() => ({
      query: mockQuery,
    })),
  };
});

// Mock initDB CREATE TABLE call
mockQuery.mockResolvedValueOnce({ rows: [] });

// Now load app AFTER mock is set
const app = require('./index');

// ─── Tests ───────────────────────────────────────────────────────────────────
describe('API Endpoints', () => {
  beforeEach(() => {
    mockQuery.mockReset();
  });

  describe('GET /', () => {
    it('returns welcome message with version', async () => {
      const res = await request(app).get('/');
      expect(res.statusCode).toBe(200);
      expect(res.body).toHaveProperty('message');
      expect(res.body.version).toBe('1.0.0');
      expect(res.body).toHaveProperty('timestamp');
    });
  });

  describe('GET /health', () => {
    it('returns healthy when DB is connected', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ '?column?': 1 }] });
      const res = await request(app).get('/health');
      expect(res.statusCode).toBe(200);
      expect(res.body.status).toBe('healthy');
      expect(res.body.database).toBe('connected');
    });

    it('returns 503 when DB is unreachable', async () => {
      mockQuery.mockRejectedValueOnce(new Error('Connection refused'));
      const res = await request(app).get('/health');
      expect(res.statusCode).toBe(503);
      expect(res.body.status).toBe('unhealthy');
      expect(res.body.database).toBe('disconnected');
    });
  });

  describe('GET /metrics', () => {
    it('returns prometheus metrics text', async () => {
      const res = await request(app).get('/metrics');
      expect(res.statusCode).toBe(200);
      expect(res.text).toContain('http_requests_total');
    });
  });

  describe('GET /users', () => {
    it('returns list of users', async () => {
      mockQuery.mockResolvedValueOnce({
        rows: [
          { id: 1, name: 'Alice', email: 'alice@test.com', created_at: new Date() },
          { id: 2, name: 'Bob',   email: 'bob@test.com',   created_at: new Date() },
        ],
      });
      const res = await request(app).get('/users');
      expect(res.statusCode).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.count).toBe(2);
      expect(res.body.data).toHaveLength(2);
    });

    it('returns 500 on DB error', async () => {
      mockQuery.mockRejectedValueOnce(new Error('DB error'));
      const res = await request(app).get('/users');
      expect(res.statusCode).toBe(500);
      expect(res.body.success).toBe(false);
    });
  });

  describe('POST /users', () => {
    it('creates a user and returns 201', async () => {
      mockQuery.mockResolvedValueOnce({
        rows: [{ id: 3, name: 'Carol', email: 'carol@test.com', created_at: new Date() }],
      });
      const res = await request(app)
        .post('/users')
        .send({ name: 'Carol', email: 'carol@test.com' });
      expect(res.statusCode).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data.name).toBe('Carol');
      expect(res.body.data.email).toBe('carol@test.com');
    });

    it('returns 400 when name is missing', async () => {
      const res = await request(app).post('/users').send({ email: 'no-name@test.com' });
      expect(res.statusCode).toBe(400);
      expect(res.body.success).toBe(false);
      expect(res.body.error).toMatch(/name and email are required/);
    });

    it('returns 400 when email is missing', async () => {
      const res = await request(app).post('/users').send({ name: 'NoEmail' });
      expect(res.statusCode).toBe(400);
      expect(res.body.success).toBe(false);
    });

    it('returns 400 when body is empty', async () => {
      const res = await request(app).post('/users').send({});
      expect(res.statusCode).toBe(400);
    });

    it('returns 500 on DB error', async () => {
      mockQuery.mockRejectedValueOnce(new Error('Unique constraint violation'));
      const res = await request(app)
        .post('/users')
        .send({ name: 'Dup', email: 'dup@test.com' });
      expect(res.statusCode).toBe(500);
      expect(res.body.success).toBe(false);
    });
  });

  describe('GET /users/:id', () => {
    it('returns user when found', async () => {
      mockQuery.mockResolvedValueOnce({
        rows: [{ id: 1, name: 'Alice', email: 'alice@test.com', created_at: new Date() }],
      });
      const res = await request(app).get('/users/1');
      expect(res.statusCode).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.id).toBe(1);
    });

    it('returns 404 when user not found', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [] });
      const res = await request(app).get('/users/999');
      expect(res.statusCode).toBe(404);
      expect(res.body.success).toBe(false);
      expect(res.body.error).toMatch(/not found/i);
    });
  });

  describe('DELETE /users/:id', () => {
    it('deletes user and returns it', async () => {
      mockQuery.mockResolvedValueOnce({
        rows: [{ id: 1, name: 'Alice', email: 'alice@test.com', created_at: new Date() }],
      });
      const res = await request(app).delete('/users/1');
      expect(res.statusCode).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.message).toMatch(/deleted/i);
    });

    it('returns 404 when user not found', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [] });
      const res = await request(app).delete('/users/999');
      expect(res.statusCode).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });
});
