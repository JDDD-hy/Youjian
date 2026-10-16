import { type PointerEvent, useEffect, useRef, useState } from 'react';

export function AchievementCondition({ text }: { text: string }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const previous = useRef<{ x: number; y: number } | null>(null);
  const [revealed, setRevealed] = useState(false);

  useEffect(() => {
    const element = canvas.current;
    if (!element || revealed) return;
    const draw = () => {
      const width = element.clientWidth;
      const height = element.clientHeight;
      const ratio = window.devicePixelRatio || 1;
      element.width = Math.round(width * ratio);
      element.height = Math.round(height * ratio);
      const ctx = element.getContext('2d');
      if (!ctx) {
        setRevealed(true);
        return;
      }
      ctx.scale(ratio, ratio);
      ctx.fillStyle = '#eeeae2';
      ctx.fillRect(0, 0, width, height);
      let seed = 31241;
      const random = () => {
        seed = (seed * 16807) % 2147483647;
        return (seed - 1) / 2147483646;
      };
      for (let i = 0; i < width * height * 0.9; i++) {
        const x = random() * width;
        const y = random() * height;
        const radius = 0.12 + random() * 0.28;
        ctx.fillStyle = `rgba(105,100,90,${0.2 + random() * 0.4})`;
        ctx.beginPath();
        ctx.arc(x, y, radius, 0, Math.PI * 2);
        ctx.fill();
      }
      previous.current = null;
    };
    draw();
    if (typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(draw);
    observer.observe(element);
    return () => observer.disconnect();
  }, [revealed, text]);

  function wipe(event: PointerEvent<HTMLDivElement>) {
    if (revealed || (event.pointerType !== 'mouse' && !event.buttons)) return;
    const element = canvas.current;
    const ctx = element?.getContext('2d');
    if (!element || !ctx) return;
    const rect = element.getBoundingClientRect();
    const point = { x: event.clientX - rect.left, y: event.clientY - rect.top };
    const start = previous.current ?? point;
    const steps = Math.max(
      1,
      Math.ceil(Math.hypot(point.x - start.x, point.y - start.y) / 3),
    );
    ctx.globalCompositeOperation = 'destination-out';
    for (let i = 0; i <= steps; i++) {
      const x = start.x + ((point.x - start.x) * i) / steps;
      const y = start.y + ((point.y - start.y) * i) / steps;
      const brush = ctx.createRadialGradient(x, y, 4, x, y, 19);
      brush.addColorStop(0, 'rgba(0,0,0,1)');
      brush.addColorStop(0.65, 'rgba(0,0,0,.85)');
      brush.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = brush;
      ctx.fillRect(x - 19, y - 19, 38, 38);
    }
    previous.current = point;
  }

  return (
    <section className="achievement-condition-reveal">
      <div className="achievement-condition-reveal__heading">
        <span>达成条件</span>
        {!revealed && (
          <button type="button" onClick={() => setRevealed(true)}>
            直接显示
          </button>
        )}
      </div>
      <div
        className="achievement-condition-reveal__surface"
        onPointerDown={(event) => {
          previous.current = null;
          event.currentTarget.setPointerCapture(event.pointerId);
          wipe(event);
        }}
        onPointerMove={wipe}
        onPointerLeave={() => {
          previous.current = null;
        }}
        onPointerUp={() => {
          previous.current = null;
        }}
        onPointerCancel={() => {
          previous.current = null;
        }}
      >
        <p aria-hidden={!revealed}>{text}</p>
        {!revealed && <canvas ref={canvas} aria-hidden="true" />}
      </div>
      {!revealed && (
        <div className="achievement-condition-reveal__caption">
          在细尘上左右抹动
        </div>
      )}
    </section>
  );
}
