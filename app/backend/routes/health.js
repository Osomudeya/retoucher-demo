const express = require('express');
const { Pool } = require('pg');
const router = express.Router();

// Database connection pool
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'webapp',
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000,
});

// Basic health check
router.get('/', async (req, res) => {
  const healthCheck = {
    status: 'OK',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    service: 'retoucherirving-backend',
    version: '1.0.0'
  };

  try {
    // Test database connection
    const dbStart = Date.now();
    const result = await pool.query('SELECT 1');
    const dbTime = Date.now() - dbStart;
    
    healthCheck.database = {
      status: 'connected',
      responseTime: `${dbTime}ms`
    };
    
    res.status(200).json(healthCheck);
  } catch (error) {
    healthCheck.status = 'ERROR';
    healthCheck.database = {
      status: 'disconnected',
      error: error.message
    };
    
    res.status(503).json(healthCheck);
  }
});

// Detailed health check with dependency status
router.get('/detailed', async (req, res) => {
  const healthCheck = {
    status: 'OK',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    service: 'retoucherirving-backend',
    version: '1.0.0',
    dependencies: {}
  };

  let allHealthy = true;

  // Check database
  try {
    const dbStart = Date.now();
    await pool.query('SELECT 1');
    const dbTime = Date.now() - dbStart;
    
    healthCheck.dependencies.database = {
      status: 'healthy',
      responseTime: `${dbTime}ms`,
      type: 'postgresql'
    };
  } catch (error) {
    allHealthy = false;
    healthCheck.dependencies.database = {
      status: 'unhealthy',
      error: error.message,
      type: 'postgresql'
    };
  }

  // Check memory usage
  const memUsage = process.memoryUsage();
  healthCheck.dependencies.memory = {
    status: memUsage.heapUsed < 500 * 1024 * 1024 ? 'healthy' : 'warning', // 500MB threshold
    heapUsed: `${Math.round(memUsage.heapUsed / 1024 / 1024)}MB`,
    heapTotal: `${Math.round(memUsage.heapTotal / 1024 / 1024)}MB`
  };

  if (!allHealthy) {
    healthCheck.status = 'DEGRADED';
    res.status(503);
  }

  res.json(healthCheck);
});

// Readiness probe (for Kubernetes)
router.get('/ready', async (req, res) => {
  try {
    // Check if we can connect to database
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ 
      status: 'not ready', 
      error: error.message 
    });
  }
});

// Liveness probe (for Kubernetes)
router.get('/live', (req, res) => {
  res.status(200).json({ 
    status: 'alive',
    timestamp: new Date().toISOString()
  });
});

module.exports = router;