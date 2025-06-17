const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const winston = require('winston');
const { Pool } = require('pg');
require('dotenv').config();

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.simple(),
  transports: [new winston.transports.Console()]
});

const app = express();
const PORT = process.env.PORT || 3001;

const pool = new Pool({
  host: process.env.DB_HOST || 'postgres',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'webapp',
  user: process.env.DB_USER || 'adminuser',
  password: process.env.DB_PASSWORD || 'localdevpassword',
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
});

app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({ origin: process.env.FRONTEND_URL || 'http://localhost:3000' }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use((req, res, next) => {
  logger.info(`${req.method} ${req.url}`);
  next();
});

async function initDb() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS visitors (
        id SERIAL PRIMARY KEY,
        count BIGINT NOT NULL DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    
    const result = await pool.query('SELECT COUNT(*) FROM visitors');
    if (parseInt(result.rows[0].count) === 0) {
      await pool.query('INSERT INTO visitors (count) VALUES (0)');
    }
    
    await pool.query(`
      CREATE TABLE IF NOT EXISTS contacts (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        email VARCHAR(255) NOT NULL,
        project VARCHAR(100) NOT NULL,
        message TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    
    logger.info('✅ Database initialized');
  } catch (error) {
    logger.error('❌ Database error:', error.message);
  }
}

initDb();

// Health check
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({
      status: 'OK',
      timestamp: new Date().toISOString(),
      database: 'connected'
    });
  } catch (error) {
    res.status(503).json({
      status: 'ERROR',
      database: 'disconnected',
      error: error.message
    });
  }
});

app.get('/healthz', (req, res) => res.json({ status: 'alive' }));
app.get('/ready', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ status: 'not ready' });
  }
});

// Visitor counter
app.get('/api/visitors', async (req, res) => {
  try {
    const result = await pool.query('SELECT count FROM visitors ORDER BY id DESC LIMIT 1');
    const count = result.rows.length > 0 ? parseInt(result.rows[0].count) : 0;
    res.json({ count, timestamp: new Date().toISOString() });
  } catch (error) {
    res.status(500).json({ error: 'Database error', count: 0 });
  }
});

app.post('/api/visitors', async (req, res) => {
  try {
    const result = await pool.query(`
      UPDATE visitors 
      SET count = count + 1, updated_at = CURRENT_TIMESTAMP 
      WHERE id = (SELECT id FROM visitors ORDER BY id DESC LIMIT 1)
      RETURNING count
    `);
    const newCount = result.rows.length > 0 ? parseInt(result.rows[0].count) : 1;
    res.json({ count: newCount, incremented: true });
  } catch (error) {
    res.status(500).json({ error: 'Database error', count: 0 });
  }
});

// Contact form
app.post('/api/contact', async (req, res) => {
  try {
    const { name, email, project, message } = req.body;
    if (!name || !email || !project || !message) {
      return res.status(400).json({ error: 'All fields required' });
    }
    
    await pool.query(
      'INSERT INTO contacts (name, email, project, message) VALUES ($1, $2, $3, $4)',
      [name, email, project, message]
    );
    
    logger.info('Contact form:', { name, email, project });
    res.json({ success: true, message: 'Contact form submitted' });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
});

// Metrics
app.get('/metrics', (req, res) => {
  res.set('Content-Type', 'text/plain');
  res.send(`# HELP nodejs_info Node.js info\nnodejs_info{version="${process.version}"} 1\n`);
});

app.get('/', (req, res) => {
  res.json({
    service: 'Retoucher Irving Backend API',
    version: '1.0.0',
    status: 'running',
    timestamp: new Date().toISOString()
  });
});

app.use('*', (req, res) => {
  res.status(404).json({ error: 'Route not found', path: req.originalUrl });
});

app.use((err, req, res, next) => {
  logger.error('Error:', err.message);
  res.status(500).json({ error: 'Internal server error' });
});

const server = app.listen(PORT, '0.0.0.0', () => {
  logger.info(`🚀 Server running on port ${PORT}`);
});

module.exports = app;


// const express = require('express');
// const cors = require('cors');
// const helmet = require('helmet');
// const winston = require('winston');
// const appInsights = require('applicationinsights');
// require('dotenv').config();

// // Import routes
// const healthRoutes = require('./routes/health');
// const metricsRoutes = require('./routes/metrics');
// const visitorRoutes = require('./routes/visitors');

// // Initialize Application Insights if instrumentation key is provided
// if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
//   appInsights.setup(process.env.APPLICATIONINSIGHTS_CONNECTION_STRING);
//   appInsights.start();
//   console.log('Application Insights initialized');
// }

// // Configure Winston logger
// const logger = winston.createLogger({
//   level: process.env.LOG_LEVEL || 'info',
//   format: winston.format.combine(
//     winston.format.timestamp(),
//     winston.format.errors({ stack: true }),
//     winston.format.json()
//   ),
//   defaultMeta: { service: 'retoucherirving-backend' },
//   transports: [
//     new winston.transports.File({ filename: 'error.log', level: 'error' }),
//     new winston.transports.File({ filename: 'combined.log' }),
//     new winston.transports.Console({
//       format: winston.format.simple()
//     })
//   ],
// });

// const app = express();
// const PORT = process.env.PORT || 3001;

// // Security middleware
// app.use(helmet({
//   contentSecurityPolicy: false, // Allow for development
//   crossOriginEmbedderPolicy: false
// }));

// // CORS configuration
// app.use(cors({
//   origin: process.env.FRONTEND_URL || 'http://localhost:3000',
//   credentials: true
// }));

// // Body parsing middleware
// app.use(express.json({ limit: '10mb' }));
// app.use(express.urlencoded({ extended: true }));

// // Request logging middleware
// app.use((req, res, next) => {
//   logger.info(`${req.method} ${req.url}`, {
//     ip: req.ip,
//     userAgent: req.get('User-Agent')
//   });
//   next();
// });

// // Routes
// app.use('/health', healthRoutes);
// app.use('/healthz', healthRoutes); // Kubernetes health check
// app.use('/metrics', metricsRoutes);
// app.use('/api/visitors', visitorRoutes);

// // Contact form endpoint
// app.post('/api/contact', async (req, res) => {
//   try {
//     const { name, email, project, message } = req.body;
    
//     // Validate required fields
//     if (!name || !email || !project || !message) {
//       return res.status(400).json({ 
//         error: 'All fields are required' 
//       });
//     }
    
//     // Log the contact form submission
//     logger.info('Contact form submission', {
//       name,
//       email,
//       project,
//       timestamp: new Date().toISOString()
//     });
    
//     // In a real application, you would:
//     // 1. Store in database
//     // 2. Send email notification
//     // 3. Add to CRM system
    
//     res.status(200).json({ 
//       success: true,
//       message: 'Contact form submitted successfully' 
//     });
    
//   } catch (error) {
//     logger.error('Error processing contact form', { error: error.message });
//     res.status(500).json({ 
//       error: 'Internal server error' 
//     });
//   }
// });

// // Root endpoint
// app.get('/', (req, res) => {
//   res.json({
//     service: 'Retoucher Irving Backend API',
//     version: '1.0.0',
//     status: 'running',
//     timestamp: new Date().toISOString()
//   });
// });

// // 404 handler
// app.use('*', (req, res) => {
//   res.status(404).json({ 
//     error: 'Route not found',
//     path: req.originalUrl 
//   });
// });

// // Global error handler
// app.use((err, req, res, next) => {
//   logger.error('Unhandled error', { 
//     error: err.message, 
//     stack: err.stack,
//     url: req.url,
//     method: req.method
//   });
  
//   res.status(500).json({ 
//     error: 'Internal server error',
//     ...(process.env.NODE_ENV === 'development' && { message: err.message })
//   });
// });

// // Graceful shutdown
// process.on('SIGTERM', () => {
//   logger.info('SIGTERM received, shutting down gracefully');
//   server.close(() => {
//     logger.info('Server closed');
//     process.exit(0);
//   });
// });

// process.on('SIGINT', () => {
//   logger.info('SIGINT received, shutting down gracefully');
//   server.close(() => {
//     logger.info('Server closed');
//     process.exit(0);
//   });
// });

// const server = app.listen(PORT, '0.0.0.0', () => {
//   logger.info(`Server running on port ${PORT}`);
// });

// module.exports = app;