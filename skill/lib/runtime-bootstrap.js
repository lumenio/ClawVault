import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const DAEMON_LABEL = 'com.monolith.daemon';
const DAEMON_BINARY =
  process.env.MONOLITH_DAEMON_BIN || '/usr/local/bin/MonolithDaemon';

const LAUNCH_AGENT_PATHS = [
  process.env.MONOLITH_DAEMON_PLIST || '',
  `${process.env.HOME}/Library/LaunchAgents/com.monolith.daemon.plist`,
  '/Library/LaunchAgents/com.monolith.daemon.plist',
].filter(Boolean);

const COMPANION_PATHS = [
  process.env.MONOLITH_COMPANION_APP || '',
  '/Applications/MonolithCompanion.app',
  `${process.env.HOME}/Applications/MonolithCompanion.app`,
].filter(Boolean);

function runCommand(command, args) {
  try {
    const stdout = execFileSync(command, args, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    return { ok: true, stdout: (stdout || '').trim(), stderr: '' };
  } catch (err) {
    const stderr = err?.stderr ? String(err.stderr).trim() : String(err.message || '');
    const stdout = err?.stdout ? String(err.stdout).trim() : '';
    return { ok: false, stdout, stderr };
  }
}

function isAlreadyLoadedError(stderr) {
  const lower = String(stderr || '').toLowerCase();
  return lower.includes('service already loaded') || lower.includes('in progress');
}

/**
 * Best-effort local runtime bootstrap for setup flow.
 * Attempts to start daemon LaunchAgent and open the companion app.
 */
export function attemptRuntimeBootstrap() {
  const result = {
    attempted: true,
    daemonStartAttempted: false,
    daemonStartSucceeded: false,
    companionLaunchAttempted: false,
    companionLaunchSucceeded: false,
    messages: [],
  };

  if (process.platform !== 'darwin') {
    result.messages.push('Automatic startup is only supported on macOS.');
    return result;
  }

  if (!fs.existsSync(DAEMON_BINARY)) {
    result.messages.push(
      `Daemon binary not found at ${DAEMON_BINARY}. Install MonolithDaemon.pkg and retry setup.`
    );
    return result;
  }

  if (typeof process.getuid !== 'function') {
    result.messages.push('Cannot determine local user id for launchctl startup.');
    return result;
  }

  const launchAgentPath = LAUNCH_AGENT_PATHS.find((path) => fs.existsSync(path));
  if (!launchAgentPath) {
    result.messages.push(
      `LaunchAgent plist not found. Expected one of: ${LAUNCH_AGENT_PATHS.join(', ')}.`
    );
    return result;
  }

  const domain = `gui/${process.getuid()}`;
  const service = `${domain}/${DAEMON_LABEL}`;
  result.daemonStartAttempted = true;

  const printResult = runCommand('/bin/launchctl', ['print', service]);
  if (!printResult.ok) {
    const bootstrapResult = runCommand('/bin/launchctl', [
      'bootstrap',
      domain,
      launchAgentPath,
    ]);
    if (!bootstrapResult.ok && !isAlreadyLoadedError(bootstrapResult.stderr)) {
      result.messages.push(
        `Failed to bootstrap daemon LaunchAgent from ${launchAgentPath}: ${bootstrapResult.stderr}`
      );
    }
  }

  const enableResult = runCommand('/bin/launchctl', ['enable', service]);
  if (!enableResult.ok && !isAlreadyLoadedError(enableResult.stderr)) {
    result.messages.push(`Failed to enable daemon LaunchAgent: ${enableResult.stderr}`);
  }

  const kickstartResult = runCommand('/bin/launchctl', ['kickstart', '-k', service]);
  if (kickstartResult.ok) {
    result.daemonStartSucceeded = true;
  } else {
    result.messages.push(`Failed to start daemon service: ${kickstartResult.stderr}`);
  }

  const companionPath = COMPANION_PATHS.find((path) => fs.existsSync(path));
  if (companionPath) {
    result.companionLaunchAttempted = true;
    const openResult = runCommand('/usr/bin/open', ['-g', companionPath]);
    if (openResult.ok) {
      result.companionLaunchSucceeded = true;
    } else {
      result.messages.push(`Failed to launch companion app (${companionPath}): ${openResult.stderr}`);
    }
  } else {
    result.messages.push(
      `Companion app not found. Expected one of: ${COMPANION_PATHS.join(', ')}.`
    );
  }

  return result;
}
