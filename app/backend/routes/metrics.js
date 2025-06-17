const express = require('express');
const client = require('prom-client');
const router = express.Router();

// Create a Registry which registers the metrics
const register = new client.Registry();

// Add a default label which is added to all metrics
register.setDefaultLabels({
  app: 'retoucherirving-backend'
});

// Enable the collection of default metrics
client.collectDefaultMetrics({ register });

// Create custom metrics
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
});

const httpRequestTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});

const visitorCount = new client.Gauge({
  name: 'website_visitors_total',
  help: 'Total number of website visitors'
});

const activeConnections = new client.Gauge({
  name: 'active_connections',
  help: 'Number of active connections'
});

// Register custom metrics
register.registerMetric(httpRequestDuration);
register.registerMetric(httpRequestTotal);
register.registerMetric(visitorCount);
register.registerMetric(activeConnections);

// Middleware to collect HTTP metrics
const collectHttpMetrics = (req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route = req.route ? req.route.path : req.path;
    
    httpRequestDuration
      .labels(req.method, route, res.statusCode)
      .observe(duration);
    
    httpRequestTotal
      .labels(req.method, route, res.statusCode)
      .inc();
  });
  
  next();
};

// Function to update visitor count (called from visitor routes)
const updateVisitorCount = (count) => {
  visitorCount.set(count);
};

// Function to update active connections
const updateActiveConnections = (count) => {
  activeConnections.set(count);
};

// Metrics endpoint
router.get('/', async (req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    const metrics = await register.metrics();
    res.end(metrics);
  } catch (error) {
    res.status(500).json({ error: 'Failed to generate metrics' });
  }
});

// Health metrics endpoint (JSON format for easier consumption)
router.get('/health', async (req, res) => {
  try {
    const metrics = await register.getMetricsAsJSON();
    
    // Transform metrics into a more readable format
    const healthMetrics = {
      timestamp: new Date().toISOString(),
      metrics: {}
    };
    
    metrics.forEach(metric => {
      if (metric.values && metric.values.length > 0) {
        healthMetrics.metrics[metric.name] = {
          help: metric.help,
          type: metric.type,
          values: metric.values.map(v => ({
            value: v.value,
            labels: v.labels
          }))
        };
      }
    });
    
    res.json(healthMetrics);
  } catch (error) {
    res.status(500).json({ error: 'Failed to generate health metrics' });
  }
});

module.exports = { 
  router, 
  collectHttpMetrics, 
  updateVisitorCount, 
  updateActiveConnections 
};