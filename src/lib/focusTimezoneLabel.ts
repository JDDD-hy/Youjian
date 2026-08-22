export function focusTimezoneLabel(
  sessionTimezone: string,
  spaceTimezone: string,
) {
  return sessionTimezone !== spaceTimezone ? sessionTimezone : undefined;
}
