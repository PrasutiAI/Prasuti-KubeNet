/**
 * Config Sync Script
 * 
 * Synchronizes local environment variables to the Prasuti Central Registry.
 *
 * Usage: node sync-configs.js --service <service-name> --project-path <path> --env <env-file>
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const REGISTRY_URL = 'https://services.prasuti.ai/api';
const TOKEN = '229db44b-2bd1-4fc3-884d-815fad0f6824';

// Parse args
const args = process.argv.slice(2);
const serviceName = getArg('--service');
const projectPath = getArg('--project-path');
// We use .env from project root by default
const envFile = path.join(projectPath, '.env');

function getArg(name) {
  const index = args.indexOf(name);
  if (index === -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

if (!serviceName || !projectPath) {
  console.error('Usage: node sync-configs.js --service <service-name> --project-path <path>');
  process.exit(1);
}

// Helper to make requests
function request(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(REGISTRY_URL + path);
    const options = {
      method,
      headers: {
        'Authorization': `Bearer ${TOKEN}`,
        'Content-Type': 'application/json'
      }
    };

    const req = https.request(url, options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            resolve(data); // Handle empty or non-json response
          }
        } else {
          try {
            const error = JSON.parse(data);
            reject(new Error(error.message || error.error || `Status ${res.statusCode}`));
          } catch (e) {
            reject(new Error(`Status ${res.statusCode}: ${data}`));
          }
        }
      });
    });

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function syncConfigs() {
  console.log(`\n--- Syncing Configuration for ${serviceName} ---`);

  if (!fs.existsSync(envFile)) {
    console.warn(`Warning: .env file not found at ${envFile}. Skipping config sync.`);
    return;
  }

  const envContent = fs.readFileSync(envFile, 'utf8');
  const envVars = parseEnv(envContent);

  // Get existing configs first to avoid duplicates/errors if Create behaves strictly
  // Note: API might not support filtering by service in GET correctly without returning ALL, 
  // but we can just try to create and ignore "Already Exists" if that's the behavior,
  // OR fetch all and filter.
  // Using GET /api/configs?scope=service&scopeValue={serviceName} based on OpenAPI spec check
  let existingConfigs = [];
  try {
    // Note: Parameter names might vary slightly based on OpenAPI inspection (scope vs scopeLevel)
    // The OpenAPI said 'scope' and 'scopeValue' in GET parameters.
    existingConfigs = await request('GET', `/configs?scope=service&scopeValue=${serviceName}`);
    if (!Array.isArray(existingConfigs)) existingConfigs = [];
  } catch (error) {
    console.warn('Warning: Failed to fetch existing configs:', error.message);
    // Proceeding to attempt creation anyway
  }

  const existingKeys = new Set(existingConfigs.map(c => c.key));
  let createdCount = 0;
  let skippedCount = 0;

  for (const [key, value] of Object.entries(envVars)) {
    // Skip empty values or comments
    if (!key || !value) continue;
    
    // Skip if already exists
    if (existingKeys.has(key)) {
      skippedCount++;
      continue; 
    }

    try {
      // Create new config
      await request('POST', '/configs', {
        key,
        value, 
        scopeLevel: 'service',
        serviceName: serviceName,
        isActive: true
      });
      console.log(`✓ Created config: ${key}`);
      createdCount++;
    } catch (error) {
      if (error.message.includes('already exists') || error.message.includes('Duplicate')) {
        skippedCount++;
      } else {
        console.error(`✗ Failed to create ${key}:`, error.message);
      }
    }
  }

  console.log(`Sync Complete: ${createdCount} created, ${skippedCount} skipped.\n`);
}

// Simple .env parser
function parseEnv(content) {
  const result = {};
  const lines = content.split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    
    const idx = trimmed.indexOf('=');
    if (idx === -1) continue;

    const key = trimmed.substring(0, idx).trim();
    let val = trimmed.substring(idx + 1).trim();

    // Remove quotes
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    
    result[key] = val;
  }
  return result;
}

syncConfigs().catch(err => {
  console.error('Fatal Error:', err);
  process.exit(1);
});
