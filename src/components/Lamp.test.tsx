import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Lamp } from './Lamp';

describe('Lamp', () => {
  it('renders the focusing state as one scalable image', () => {
    const { container } = render(<Lamp state="focusing" compact />);
    const image = container.querySelector('img');

    expect(image?.getAttribute('src')).toMatch(/^data:image\/svg\+xml,/);
    expect(image).toHaveClass('lamp--focusing', 'lamp--compact');
    expect(container.querySelectorAll('span')).toHaveLength(0);
    expect(screen.queryByRole('img')).not.toBeInTheDocument();
  });
});
