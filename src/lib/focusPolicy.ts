export const SUPPORTED_HEALTH_POLICY_VERSION = 2;
export const FOCUS_POLICY_CONTRACT = 'max_focus_seconds=14400';

export const supportsHealthPolicy = (currentVersion: number) =>
  currentVersion === SUPPORTED_HEALTH_POLICY_VERSION;

export const focusPolicyAcknowledgementParams = () => ({
  policy_version: SUPPORTED_HEALTH_POLICY_VERSION,
  policy_contract: FOCUS_POLICY_CONTRACT,
});

export const focusPolicyStartParams = () => ({
  health_check_policy_version: SUPPORTED_HEALTH_POLICY_VERSION,
  policy_contract: FOCUS_POLICY_CONTRACT,
});
