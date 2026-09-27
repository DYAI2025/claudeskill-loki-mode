// S-46 / BACKLOG 115: the historical-view fallback used to default an
// unrecognized detail.status to 'completed', and the checklist was shown for
// a historical session even though the endpoint it comes from always reads
// the globally-running project.
//
// useCockpitState.ts imports ../api/client, which reads window.location at
// module load time (browser-only), so this cannot run under a plain
// `node --test <file>`. Run it with:
//   node web-app/src/cockpit/run-derive-view-test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { deriveHistoricalView, scopeChecklistToLive } from './useCockpitState.ts';

test('deriveHistoricalView: an unrecognized status is unknown, not completed', () => {
  assert.equal(deriveHistoricalView({ status: 'bogus', prd: 'x' }, false), 'unknown');
});

test('deriveHistoricalView: a missing status with real content is unknown, not completed', () => {
  assert.equal(deriveHistoricalView({ status: '', prd: '# spec' }, false), 'unknown');
});

test('deriveHistoricalView: server "unknown" status maps through as unknown', () => {
  assert.equal(deriveHistoricalView({ status: 'unknown' }, false), 'unknown');
});

test('deriveHistoricalView: explicit completed status is honored', () => {
  assert.equal(deriveHistoricalView({ status: 'completed' }, false), 'completed');
});

test('deriveHistoricalView: explicit failed status is honored', () => {
  assert.equal(deriveHistoricalView({ status: 'failed' }, false), 'failed');
});

test('deriveHistoricalView: explicit paused status is honored (not swallowed by the fallback)', () => {
  assert.equal(deriveHistoricalView({ status: 'paused' }, false), 'paused');
});

test('deriveHistoricalView: no status, no prd, no changes, no files is empty', () => {
  assert.equal(deriveHistoricalView({ status: '' }, false), 'empty');
});

test('deriveHistoricalView: no status but git changes present is unknown, not completed', () => {
  assert.equal(deriveHistoricalView({ status: '' }, true), 'unknown');
});

test('scopeChecklistToLive: hides the checklist for a non-live (historical) session', () => {
  const checklist = { total: 3, passed: 3, failed: 0, skipped: 0, pending: 0, items: [] };
  assert.equal(scopeChecklistToLive(checklist, false), null);
});

test('scopeChecklistToLive: shows the checklist only for the live session', () => {
  const checklist = { total: 3, passed: 3, failed: 0, skipped: 0, pending: 0, items: [] };
  assert.equal(scopeChecklistToLive(checklist, true), checklist);
});

test('scopeChecklistToLive: a null checklist while live stays null (not swallowed)', () => {
  assert.equal(scopeChecklistToLive(null, true), null);
});
