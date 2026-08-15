import { describe, expect, it } from 'vitest';
import {
  FOCUS_POLICY_CONTRACT,
  SUPPORTED_HEALTH_POLICY_VERSION,
  focusPolicyAcknowledgementParams,
  focusPolicyStartParams,
  supportsHealthPolicy,
} from './focusPolicy';

describe('focus policy client contract', () => {
  it('pins the copy and start contract to max-four-hour policy v2', () => {
    expect(SUPPORTED_HEALTH_POLICY_VERSION).toBe(2);
    expect(FOCUS_POLICY_CONTRACT).toBe('max_focus_seconds=14400');
    expect(supportsHealthPolicy(2)).toBe(true);
  });

  it('does not silently acknowledge an unknown server policy version', () => {
    expect(supportsHealthPolicy(1)).toBe(false);
    expect(supportsHealthPolicy(3)).toBe(false);
  });

  it('sends the pinned v2 contract through both policy RPCs', () => {
    expect(focusPolicyAcknowledgementParams()).toEqual({
      policy_version: 2,
      policy_contract: 'max_focus_seconds=14400',
    });
    expect(focusPolicyStartParams()).toEqual({
      health_check_policy_version: 2,
      policy_contract: 'max_focus_seconds=14400',
    });
  });
});
