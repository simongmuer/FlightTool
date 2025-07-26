#!/usr/bin/env node

/**
 * Production build script for FlightTool
 * This script compiles TypeScript and builds the frontend for deployment
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

console.log('🚀 Starting FlightTool production build...\n');

try {
  // Clean previous builds
  console.log('🧹 Cleaning previous builds...');
  if (fs.existsSync('dist')) {
    execSync('rm -rf dist', { stdio: 'inherit' });
  }
  if (fs.existsSync('server/dist')) {
    execSync('rm -rf server/dist', { stdio: 'inherit' });
  }

  // Install dependencies
  console.log('📦 Installing dependencies...');
  execSync('npm install --production=false', { stdio: 'inherit' });

  // Build frontend
  console.log('🏗️  Building frontend...');
  execSync('npx vite build', { stdio: 'inherit' });

  // Compile TypeScript server code
  console.log('⚙️  Compiling server TypeScript...');
  execSync('npx tsc --project tsconfig.json --outDir server/dist', { stdio: 'inherit' });

  // Copy necessary files
  console.log('📋 Copying configuration files...');
  const filesToCopy = [
    'package.json',
    'package-lock.json',
    'drizzle.config.ts',
    '.env.example'
  ];

  filesToCopy.forEach(file => {
    if (fs.existsSync(file)) {
      fs.copyFileSync(file, path.join('dist', file));
      console.log(`✓ Copied ${file}`);
    }
  });

  // Create production start script
  console.log('📝 Creating production start script...');
  const startScript = `#!/usr/bin/env node

const { spawn } = require('child_process');
const path = require('path');

// Start the server
const server = spawn('node', ['server/dist/server/index.js'], {
  stdio: 'inherit',
  env: {
    ...process.env,
    NODE_ENV: 'production'
  }
});

server.on('error', (err) => {
  console.error('Failed to start server:', err);
  process.exit(1);
});

server.on('close', (code) => {
  console.log(\`Server process exited with code \${code}\`);
  process.exit(code);
});

// Handle graceful shutdown
process.on('SIGTERM', () => {
  server.kill('SIGTERM');
});

process.on('SIGINT', () => {
  server.kill('SIGINT');
});
`;

  fs.writeFileSync('start.js', startScript);
  fs.chmodSync('start.js', '755');

  console.log('\n✅ Build completed successfully!');
  console.log('\n📁 Build output:');
  console.log('   - Frontend: dist/');
  console.log('   - Server: server/dist/');
  console.log('   - Start script: start.js');
  console.log('\n🚀 To start in production: node start.js');

} catch (error) {
  console.error('\n❌ Build failed:', error.message);
  process.exit(1);
}