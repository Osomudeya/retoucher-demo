const express = require('express');
const { Pool } = require('pg');
const { updateVisitorCount } = require('./metrics');
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

// Initialize visitor counter table if it doesn't exist
const initializeDatabase = async () => {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS visitors (
        id SERIAL PRIMARY KEY,
        count BIGINT NOT NULL DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    
    // Insert initial record if table is empty
    const result = await pool.query('SELECT COUNT(*) FROM visitors');
    if (parseInt(result.rows[0].count) === 0) {
      await pool.query('INSERT INTO visitors (count) VALUES (0)');
    }
    
    console.log('Visitor counter database initialized');
  } catch (error) {
    console.error('Error initializing visitor database:', error);
  }
};

// Initialize on startup
initializeDatabase();

// GET current visitor count
router.get('/', async (req, res) => {
  try {
    const result = await pool.query('SELECT count FROM visitors ORDER BY id DESC LIMIT 1');
    const count = result.rows.length > 0 ? parseInt(result.rows[0].count) : 0;
    
    // Update Prometheus metric
    updateVisitorCount(count);
    
    res.json({ 
      count,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Error fetching visitor count:', error);
    res.status(500).json({ 
      error: 'Failed to fetch visitor count',
      count: 0 
    });
  }
});

// POST to increment visitor count
router.post('/', async (req, res) => {
  try {
    // Get current count and increment
    const result = await pool.query(`
      UPDATE visitors 
      SET count = count + 1, updated_at = CURRENT_TIMESTAMP 
      WHERE id = (SELECT id FROM visitors ORDER BY id DESC LIMIT 1)
      RETURNING count
    `);
    
    const newCount = result.rows.length > 0 ? parseInt(result.rows[0].count) : 1;
    
    // Update Prometheus metric
    updateVisitorCount(newCount);
    
    // Log visitor increment
    console.log(`Visitor count incremented to: ${newCount}`);
    
    res.json({ 
      count: newCount,
      timestamp: new Date().toISOString(),
      incremented: true
    });
  } catch (error) {
    console.error('Error incrementing visitor count:', error);
    
    // Try to get current count as fallback
    try {
      const fallbackResult = await pool.query('SELECT count FROM visitors ORDER BY id DESC LIMIT 1');
      const fallbackCount = fallbackResult.rows.length > 0 ? parseInt(fallbackResult.rows[0].count) : 0;
      
      res.status(500).json({ 
        error: 'Failed to increment visitor count',
        count: fallbackCount,
        incremented: false
      });
    } catch (fallbackError) {
      res.status(500).json({ 
        error: 'Failed to increment visitor count',
        count: 0,
        incremented: false
      });
    }
  }
});

// GET visitor statistics (additional endpoint for admin purposes)
router.get('/stats', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT 
        count,
        created_at,
        updated_at,
        (updated_at - created_at) as active_duration
      FROM visitors 
      ORDER BY id DESC 
      LIMIT 1
    `);
    
    if (result.rows.length === 0) {
      return res.json({
        count: 0,
        created_at: null,
        updated_at: null,
        active_duration: null
      });
    }
    
    const stats = result.rows[0];
    
    res.json({
      count: parseInt(stats.count),
      created_at: stats.created_at,
      updated_at: stats.updated_at,
      active_duration: stats.active_duration,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Error fetching visitor stats:', error);
    res.status(500).json({ 
      error: 'Failed to fetch visitor statistics' 
    });
  }
});

// Reset visitor count (admin endpoint)
router.delete('/', async (req, res) => {
  try {
    // Check for admin authentication (in production, add proper auth)
    const adminKey = req.headers['x-admin-key'];
    if (adminKey !== process.env.ADMIN_KEY) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    
    await pool.query(`
      UPDATE visitors 
      SET count = 0, updated_at = CURRENT_TIMESTAMP 
      WHERE id = (SELECT id FROM visitors ORDER BY id DESC LIMIT 1)
    `);
    
    // Update Prometheus metric
    updateVisitorCount(0);
    
    console.log('Visitor count reset to 0');
    
    res.json({ 
      count: 0,
      reset: true,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Error resetting visitor count:', error);
    res.status(500).json({ 
      error: 'Failed to reset visitor count' 
    });
  }
});

module.exports = router;