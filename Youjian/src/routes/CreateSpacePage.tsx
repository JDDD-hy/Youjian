import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { z } from 'zod';
import type { Membership, SpaceSummary } from '../domain/types';
import { ensureAnonymousSession, rpc } from '../lib/api';
import { getDeviceTimezone } from '../lib/format';
import { cacheActiveMembership } from '../lib/membership';
import { Icon } from '../components/Icons';
import { TurnstileField } from '../components/TurnstileField';
import { useIntentKey } from '../hooks/useIntentKey';
import { useOnlineStatus } from '../hooks/useOnlineStatus';

const schema = z.object({
  displayName: z
    .string()
    .trim()
    .min(1, '请输入你的昵称')
    .max(20, '昵称最多 20 个字符'),
  spaceName: z
    .string()
    .trim()
    .min(1, '请输入友间名称')
    .max(30, '友间名称最多 30 个字符'),
  timezone: z.string().min(1, '请选择时区'),
  memberLimit: z.number().int().min(2).max(12),
  consent: z.literal(true, { error: '请确认你已了解匿名身份的保存方式' }),
});

type FormErrors = Partial<
  Record<
    'displayName' | 'spaceName' | 'timezone' | 'memberLimit' | 'consent',
    string
  >
>;

export function CreateSpacePage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const deviceTimezone = useMemo(() => getDeviceTimezone(), []);
  const [values, setValues] = useState({
    displayName: '',
    spaceName: '我们的友间',
    timezone: deviceTimezone,
    memberLimit: 3,
    consent: false,
  });
  const [errors, setErrors] = useState<FormErrors>({});
  const [captchaToken, setCaptchaToken] = useState<string>();
  const intent = useIntentKey();
  const online = useOnlineStatus();
  const mutation = useMutation({
    mutationFn: async (input: typeof values) => {
      await ensureAnonymousSession(captchaToken);
      return rpc<{
        space: SpaceSummary;
        membership: Membership;
        invite: { invite_url: string };
      }>('create_space', {
        display_name: input.displayName.trim(),
        space_name: input.spaceName.trim(),
        space_timezone: input.timezone,
        profile_timezone: deviceTimezone,
        member_limit: input.memberLimit,
        idempotency_key: intent.get(JSON.stringify(input)),
      });
    },
    onSuccess: ({ data }) => {
      intent.clear();
      cacheActiveMembership(queryClient, {
        ...data.membership,
        space_id: data.space.id,
      });
      localStorage.setItem(
        `youjian:invite:${data.space.id}`,
        data.invite.invite_url,
      );
      void navigate(`/space/${data.space.id}`, {
        replace: true,
        state: { justCreated: true },
      });
    },
  });
  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    const result = schema.safeParse(values);
    if (!result.success) {
      const next: FormErrors = {};
      for (const issue of result.error.issues)
        next[issue.path[0] as keyof FormErrors] = issue.message;
      setErrors(next);
      return;
    }
    setErrors({});
    mutation.mutate(result.data);
  };
  return (
    <main className="form-page">
      <section className="form-card" aria-labelledby="create-title">
        <Link className="back-link" to="/">
          <Icon name="arrow-left" />
          返回
        </Link>
        <p className="eyebrow">先为彼此留一盏灯</p>
        <h1 id="create-title">创建友间</h1>
        <p className="lead">设置一个只属于固定好友的小空间。</p>
        <form onSubmit={submit} noValidate>
          <label className="field">
            <span>你的昵称</span>
            <input
              autoComplete="nickname"
              maxLength={20}
              value={values.displayName}
              onChange={(e) =>
                setValues({ ...values, displayName: e.target.value })
              }
              aria-invalid={Boolean(errors.displayName)}
            />
            {errors.displayName && (
              <small className="field-error">{errors.displayName}</small>
            )}
          </label>
          <label className="field">
            <span>友间名称</span>
            <input
              maxLength={30}
              value={values.spaceName}
              onChange={(e) =>
                setValues({ ...values, spaceName: e.target.value })
              }
              aria-invalid={Boolean(errors.spaceName)}
            />
            {errors.spaceName && (
              <small className="field-error">{errors.spaceName}</small>
            )}
          </label>
          <div className="form-grid">
            <label className="field">
              <span>房间时区</span>
              <input
                value={values.timezone}
                onChange={(e) =>
                  setValues({ ...values, timezone: e.target.value })
                }
                aria-invalid={Boolean(errors.timezone)}
              />
              {errors.timezone && (
                <small className="field-error">{errors.timezone}</small>
              )}
            </label>
            <label className="field">
              <span>人数上限</span>
              <select
                value={values.memberLimit}
                onChange={(e) =>
                  setValues({ ...values, memberLimit: Number(e.target.value) })
                }
              >
                {Array.from({ length: 11 }, (_, index) => index + 2).map(
                  (n) => (
                    <option key={n} value={n}>
                      {n} 人
                    </option>
                  ),
                )}
              </select>
            </label>
          </div>
          <label className="consent">
            <input
              type="checkbox"
              checked={values.consent}
              onChange={(e) =>
                setValues({ ...values, consent: e.target.checked })
              }
            />
            <span>
              我了解：身份只保存在当前设备。清除浏览器数据、更换设备或删除 PWA
              数据后将无法恢复，历史记录也不能转移。
            </span>
          </label>
          {errors.consent && <p className="field-error">{errors.consent}</p>}
          <TurnstileField onToken={setCaptchaToken} />
          {mutation.error && (
            <div className="inline-notice inline-notice--error" role="alert">
              {mutation.error.message}
            </div>
          )}
          <button
            className="button button--primary button--full"
            disabled={mutation.isPending || !online}
          >
            {mutation.isPending ? '正在创建…' : '创建友间'}
          </button>
        </form>
      </section>
    </main>
  );
}
