#!/usr/bin/env node
/**
 * pet-waker - Wake-on-request proxy for pet-cli sleep functionality
 *
 * This lightweight service:
 * - Listens on port 3999
 * - Receives requests for sleeping projects (via nginx proxy)
 * - Wakes up the project using pet-cli
 * - Proxies the original request to the awakened service
 * - Client receives response without needing to retry
 */

const http = require('http');
const { spawn } = require('child_process');
const path = require('path');

const PORT = process.env.PET_WAKER_PORT || 3999;
const PET_DIR = process.env.PET_DIR || path.join(process.env.HOME, '.pet-cli');
const PET_CONFIG_DIR = process.env.PET_CONFIG_DIR || path.join(process.env.HOME, '.config/pet');

// Track projects currently being woken
const wakingProjects = new Map();

/**
 * Get project config
 */
function getProjectConfig(projectName) {
    const fs = require('fs');
    const configPath = path.join(PET_CONFIG_DIR, 'projects', `${projectName}.conf`);

    if (!fs.existsSync(configPath)) {
        return null;
    }

    const content = fs.readFileSync(configPath, 'utf8');
    const config = {};

    content.split('\n').forEach(line => {
        const match = line.match(/^([A-Z_]+)="([^"]*)"/);
        if (match) {
            config[match[1]] = match[2];
        }
    });

    return config;
}

/**
 * Wake up a project and return its port
 */
async function wakeProject(projectName) {
    // Check if already waking
    if (wakingProjects.has(projectName)) {
        return wakingProjects.get(projectName);
    }

    const wakePromise = new Promise((resolve, reject) => {
        const config = getProjectConfig(projectName);
        if (!config) {
            reject(new Error(`Project ${projectName} not found`));
            return;
        }

        const port = config.PROJECT_PORT;
        if (!port) {
            reject(new Error(`No port configured for ${projectName}`));
            return;
        }

        console.log(`[pet-waker] Waking project: ${projectName}`);

        // Use pet-wake-from-waker script
        const wakeScript = path.join(PET_DIR, 'bin', 'pet-wake-from-waker');
        const wakeProcess = spawn(wakeScript, [projectName], {
            env: {
                ...process.env,
                PET_DIR,
                PET_CONFIG_DIR,
                PATH: process.env.PATH
            }
        });

        let output = '';
        let errorOutput = '';

        wakeProcess.stdout.on('data', (data) => {
            output += data.toString();
        });

        wakeProcess.stderr.on('data', (data) => {
            errorOutput += data.toString();
        });

        wakeProcess.on('close', (code) => {
            if (code === 0) {
                // Parse port from output or use config port
                const outputPort = output.trim();
                const finalPort = outputPort || port;
                console.log(`[pet-waker] Project ${projectName} is awake on port ${finalPort}`);
                resolve(parseInt(finalPort, 10));
            } else {
                console.error(`[pet-waker] Failed to wake ${projectName}: ${errorOutput}`);
                reject(new Error(`Failed to wake project: ${errorOutput}`));
            }
        });

        // Timeout after 60 seconds
        setTimeout(() => {
            wakeProcess.kill();
            reject(new Error('Wake timeout exceeded'));
        }, 60000);
    });

    wakingProjects.set(projectName, wakePromise);

    try {
        const port = await wakePromise;
        return port;
    } finally {
        // Remove from waking map after a short delay to handle concurrent requests
        setTimeout(() => {
            wakingProjects.delete(projectName);
        }, 5000);
    }
}

/**
 * Wait for service to be ready
 */
function waitForService(port, maxAttempts = 10) {
    return new Promise((resolve, reject) => {
        let attempt = 0;

        const check = () => {
            const req = http.request({
                hostname: '127.0.0.1',
                port: port,
                path: '/',
                method: 'HEAD',
                timeout: 2000
            }, (res) => {
                resolve(true);
            });

            req.on('error', () => {
                attempt++;
                if (attempt < maxAttempts) {
                    setTimeout(check, 500);
                } else {
                    reject(new Error('Service not responding'));
                }
            });

            req.on('timeout', () => {
                req.destroy();
                attempt++;
                if (attempt < maxAttempts) {
                    setTimeout(check, 500);
                } else {
                    reject(new Error('Service timeout'));
                }
            });

            req.end();
        };

        check();
    });
}

/**
 * Proxy request to the target service
 */
function proxyRequest(req, res, targetPort, bodyBuffer) {
    const options = {
        hostname: '127.0.0.1',
        port: targetPort,
        path: req.url,
        method: req.method,
        headers: { ...req.headers }
    };

    // Remove waker-specific headers
    delete options.headers['x-pet-sleep-project'];

    // Fix content-length if we have buffered body
    if (bodyBuffer && bodyBuffer.length > 0) {
        options.headers['content-length'] = bodyBuffer.length;
    }

    const proxyReq = http.request(options, (proxyRes) => {
        res.writeHead(proxyRes.statusCode, proxyRes.headers);
        proxyRes.pipe(res);
    });

    proxyReq.on('error', (err) => {
        console.error(`[pet-waker] Proxy error: ${err.message}`);
        if (!res.headersSent) {
            res.writeHead(502, { 'Content-Type': 'text/plain' });
            res.end('Bad Gateway: Service unavailable');
        }
    });

    // Send buffered body
    if (bodyBuffer && bodyBuffer.length > 0) {
        proxyReq.write(bodyBuffer);
    }
    proxyReq.end();
}

/**
 * Buffer request body
 */
function bufferRequestBody(req) {
    return new Promise((resolve) => {
        const chunks = [];
        req.on('data', chunk => chunks.push(chunk));
        req.on('end', () => resolve(Buffer.concat(chunks)));
    });
}

/**
 * Main request handler
 */
async function handleRequest(req, res) {
    const projectName = req.headers['x-pet-sleep-project'];

    if (!projectName) {
        res.writeHead(400, { 'Content-Type': 'text/plain' });
        res.end('Bad Request: Missing X-Pet-Sleep-Project header');
        return;
    }

    console.log(`[pet-waker] Request for sleeping project: ${projectName} ${req.method} ${req.url}`);

    try {
        // Buffer request body first (so we can replay it after waking)
        const bodyBuffer = await bufferRequestBody(req);

        // Wake the project
        const port = await wakeProject(projectName);

        // Wait for service to be fully ready
        console.log(`[pet-waker] Waiting for service on port ${port}...`);
        await waitForService(port, 15);
        console.log(`[pet-waker] Service ready, proxying request`);

        // Proxy the original request
        proxyRequest(req, res, port, bodyBuffer);
    } catch (err) {
        console.error(`[pet-waker] Error: ${err.message}`);
        if (!res.headersSent) {
            res.writeHead(503, { 'Content-Type': 'text/plain' });
            res.end(`Service Unavailable: ${err.message}`);
        }
    }
}

// Create and start server
const server = http.createServer(handleRequest);

server.listen(PORT, '127.0.0.1', () => {
    console.log(`[pet-waker] Listening on 127.0.0.1:${PORT}`);
});

// Handle shutdown gracefully
process.on('SIGTERM', () => {
    console.log('[pet-waker] Shutting down...');
    server.close(() => {
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    console.log('[pet-waker] Shutting down...');
    server.close(() => {
        process.exit(0);
    });
});
