import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import type { FocusSession } from '../../domain/types';
import { FocusPanel } from './FocusPanel';

const session: FocusSession = {
  session_id: 'session',
  space_id: 'space',
  member_id: 'member',
  task_name: '准备法考',
  category: 'study',
  task_history: [],
  status: 'focusing',
  started_at: '2026-08-15T08:00:00.000Z',
  timezone_snapshot: 'Asia/Shanghai',
  accumulated_focus_seconds: 60,
  active_segment_started_at: '2026-08-15T08:00:00.000Z',
  paused_at: null,
  auto_settle_at: '2026-08-15T12:00:00.000Z',
  completed_at: null,
  completion_reason: null,
  credited_focus_seconds: null,
  counts_toward_stats: null,
};

describe('FocusPanel', () => {
  it('keeps the lamp overlay separate from the task zone', () => {
    const { container } = render(
      <MemoryRouter>
        <FocusPanel
          session={session}
          now={Date.parse('2026-08-15T08:01:00.000Z')}
          connection="connected"
          pending={false}
          onPause={vi.fn()}
          onResume={vi.fn()}
          onEnd={vi.fn()}
          onEdit={vi.fn()}
          onDismiss={vi.fn()}
          lampOverlay={<div data-testid="lamp-overlay" />}
        />
      </MemoryRouter>,
    );

    const lampZone = container.querySelector('.focus-panel__lamp-zone');
    const taskZone = container.querySelector('.focus-panel__task-zone');

    expect(lampZone).toContainElement(screen.getByTestId('lamp-overlay'));
    expect(lampZone?.querySelector('.lamp')).toBeInTheDocument();
    expect(taskZone).toHaveTextContent('准备法考');
    expect(taskZone).toHaveTextContent('00:02:00');
    expect(taskZone).not.toContainElement(screen.getByTestId('lamp-overlay'));
  });

  it('switches the entertainment lamp with the authoritative session state', () => {
    const props = {
      now: Date.parse('2026-08-15T08:01:00.000Z'),
      connection: 'connected' as const,
      pending: false,
      onPause: vi.fn(),
      onResume: vi.fn(),
      onEnd: vi.fn(),
      onEdit: vi.fn(),
      onDismiss: vi.fn(),
    };
    const entertainment = {
      ...session,
      category: 'entertainment' as const,
    };
    const { container, rerender } = render(
      <MemoryRouter>
        <FocusPanel session={entertainment} {...props} />
      </MemoryRouter>,
    );
    expect(container.querySelector('.lamp')).toHaveAttribute(
      'data-lamp-variant',
      'entertainment-focusing',
    );

    rerender(
      <MemoryRouter>
        <FocusPanel
          session={{ ...entertainment, status: 'paused' }}
          {...props}
        />
      </MemoryRouter>,
    );
    expect(container.querySelector('.lamp')).toHaveAttribute(
      'data-lamp-variant',
      'paused',
    );
  });
});
