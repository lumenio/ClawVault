import net from 'node:net';
import { createInterface } from 'node:readline';

const SOCKET_PATH =
  process.env.CLAWVAULT_SOCKET ||
  `${process.env.HOME}/.clawvault/daemon.sock`;

/**
 * Unix socket HTTP client for E2E tests.
 * Mirrors skill/lib/daemon-client.js but adds test-oriented helpers.
 */
export class TestClient {
  constructor(socketPath = SOCKET_PATH) {
    this.socketPath = socketPath;
  }

  /**
   * Send an HTTP request over the Unix socket.
   * @param {string} method
   * @param {string} path
   * @param {object} [body]
   * @returns {Promise<{status: number, data: object}>}
   */
  async request(method, path, body = null) {
    return new Promise((resolve, reject) => {
      const socket = net.createConnection({ path: this.socketPath });
      let responseData = '';

      socket.on('connect', () => {
        let req = `${method} ${path} HTTP/1.1\r\n`;
        req += 'Host: localhost\r\n';

        if (body) {
          const bodyStr = JSON.stringify(body);
          req += 'Content-Type: application/json\r\n';
          req += `Content-Length: ${Buffer.byteLength(bodyStr)}\r\n`;
          req += '\r\n';
          req += bodyStr;
        } else {
          req += '\r\n';
        }

        socket.write(req);
      });

      socket.on('data', (chunk) => {
        responseData += chunk.toString();
      });

      socket.on('end', () => {
        try {
          resolve(parseHTTPResponse(responseData));
        } catch (err) {
          reject(new Error(`Failed to parse response: ${err.message}`));
        }
      });

      socket.on('error', (err) => {
        if (err.code === 'ENOENT') {
          reject(new Error('Daemon not running — socket not found'));
        } else if (err.code === 'ECONNREFUSED') {
          reject(new Error('Daemon refused connection'));
        } else {
          reject(new Error(`Socket error: ${err.message}`));
        }
      });

      socket.setTimeout(30000, () => {
        socket.destroy();
        reject(new Error('Request timed out (30s)'));
      });
    });
  }

  // ── Convenience methods ────────────────────────────────────────────────────

  health() {
    return this.request('GET', '/health');
  }

  capabilities() {
    return this.request('GET', '/capabilities');
  }

  address() {
    return this.request('GET', '/address');
  }

  setup(params) {
    return this.request('POST', '/setup', params);
  }

  deploy() {
    return this.request('POST', '/setup/deploy');
  }

  sign(intent) {
    return this.request('POST', '/sign', intent);
  }

  decode(intent) {
    return this.request('POST', '/decode', intent);
  }

  panic() {
    return this.request('POST', '/panic');
  }

  auditLog() {
    return this.request('GET', '/audit-log');
  }

  policy() {
    return this.request('GET', '/policy');
  }

  policyUpdate(changes) {
    return this.request('POST', '/policy/update', changes);
  }

  allowlistUpdate(changes) {
    return this.request('POST', '/allowlist', changes);
  }

  unfreeze() {
    return this.request('POST', '/unfreeze');
  }
}

/**
 * Parse raw HTTP response into {status, data}.
 */
function parseHTTPResponse(raw) {
  const headerEnd = raw.indexOf('\r\n\r\n');
  if (headerEnd === -1) throw new Error('Invalid HTTP response');

  const headerPart = raw.substring(0, headerEnd);
  const bodyPart = raw.substring(headerEnd + 4);

  const statusLine = headerPart.split('\r\n')[0];
  const statusMatch = statusLine.match(/HTTP\/[\d.]+ (\d+)/);
  const status = statusMatch ? parseInt(statusMatch[1], 10) : 0;

  let data = null;
  if (bodyPart.trim()) {
    try {
      data = JSON.parse(bodyPart);
    } catch {
      data = { raw: bodyPart };
    }
  }

  return { status, data };
}

/**
 * Prompt user for input on the terminal (for interactive tests).
 */
export function prompt(question) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

/**
 * Wait for a condition to become true, polling periodically.
 * @param {Function} fn - Async function returning truthy when ready.
 * @param {number} timeoutMs - Max wait time.
 * @param {number} intervalMs - Poll interval.
 */
export async function waitFor(fn, timeoutMs = 30000, intervalMs = 1000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const result = await fn();
    if (result) return result;
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  throw new Error(`waitFor timed out after ${timeoutMs}ms`);
}

/** Shared test client instance */
export const client = new TestClient();
