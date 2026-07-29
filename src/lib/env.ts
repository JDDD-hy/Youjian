import { z } from 'zod';

const publicEnvSchema = z.object({
  VITE_SUPABASE_URL: z.url(),
  VITE_SUPABASE_PUBLISHABLE_KEY: z.string().min(1),
  VITE_APP_ORIGIN: z.url(),
  VITE_TURNSTILE_SITE_KEY: z.preprocess(
    (value) => (value === '' ? undefined : value),
    z.string().min(1).optional(),
  ),
});

export type PublicEnv = z.infer<typeof publicEnvSchema>;

export function readPublicEnv(): PublicEnv {
  return publicEnvSchema.parse(import.meta.env);
}
