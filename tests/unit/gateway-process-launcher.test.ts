import { EventEmitter } from 'node:events';
import { describe, expect, it, vi } from 'vitest';

const {
  mockFork,
} = vi.hoisted(() => ({
  mockFork: vi.fn(),
}));

vi.mock('electron', () => ({
  app: {
    isPackaged: true,
  },
  utilityProcess: {
    fork: mockFork,
  },
}));

vi.mock('@electron/utils/logger', () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  },
}));

class MockUtilityChild extends EventEmitter {
  pid = 4242;
  stderr = new EventEmitter();
}

describe('gateway process launcher', () => {
  it('spawns the gateway from the user workspace cwd', async () => {
    const child = new MockUtilityChild();
    mockFork.mockReturnValue(child);

    const { launchGatewayProcess } = await import('@electron/gateway/process-launcher');

    const launchPromise = launchGatewayProcess({
      port: 18789,
      launchContext: {
        appSettings: {} as never,
        openclawDir: 'C:\\Program Files\\老驴\\resources\\openclaw',
        processCwd: 'C:\\Users\\evan\\.openclaw\\workspace',
        entryScript: 'C:\\Program Files\\老驴\\resources\\openclaw\\openclaw.mjs',
        gatewayArgs: ['gateway', '--port', '18789'],
        forkEnv: {},
        mode: 'packaged',
        binPathExists: true,
        loadedProviderKeyCount: 0,
        proxySummary: 'disabled',
        channelStartupSummary: 'skipped(no configured channels)',
      },
      sanitizeSpawnArgs: (args) => args,
      getCurrentState: () => 'starting',
      getShouldReconnect: () => true,
      onStderrLine: vi.fn(),
      onSpawn: vi.fn(),
      onExit: vi.fn(),
      onError: vi.fn(),
    });

    child.emit('spawn');

    const result = await launchPromise;
    expect(mockFork).toHaveBeenCalledWith(
      'C:\\Program Files\\老驴\\resources\\openclaw\\openclaw.mjs',
      ['gateway', '--port', '18789'],
      expect.objectContaining({
        cwd: 'C:\\Users\\evan\\.openclaw\\workspace',
      }),
    );
    expect(result.lastSpawnSummary).toContain('cwd="C:\\Users\\evan\\.openclaw\\workspace"');
    expect(result.lastSpawnSummary).toContain('packageRoot="C:\\Program Files\\老驴\\resources\\openclaw"');
  });
});
