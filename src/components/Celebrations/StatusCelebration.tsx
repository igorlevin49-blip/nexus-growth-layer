import { useEffect, useState } from "react";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Trophy } from "lucide-react";

interface StatusCelebrationProps {
  isOpen: boolean;
  onClose: () => void;
  statusLevel: number;
  statusName: string;
}

export function StatusCelebration({ isOpen, onClose, statusLevel, statusName }: StatusCelebrationProps) {
  const [showFireworks, setShowFireworks] = useState(false);

  useEffect(() => {
    if (isOpen) {
      setShowFireworks(true);
      // Stop fireworks after 5 seconds
      const timer = setTimeout(() => setShowFireworks(false), 5000);
      return () => clearTimeout(timer);
    }
  }, [isOpen]);

  return (
    <>
      {showFireworks && <Fireworks />}
      <Dialog open={isOpen} onOpenChange={onClose}>
        <DialogContent className="max-w-md">
          <div className="flex flex-col items-center justify-center space-y-6 py-8">
            <div className="relative">
              <Trophy className="w-24 h-24 text-yellow-500 animate-bounce" />
              <div className="absolute -top-2 -right-2 bg-primary text-primary-foreground rounded-full w-8 h-8 flex items-center justify-center font-bold">
                {statusLevel}
              </div>
            </div>
            
            <div className="text-center space-y-2">
              <h2 className="text-3xl font-bold">Поздравляем!</h2>
              <p className="text-xl text-muted-foreground">
                Вы достигли нового статуса:
              </p>
              <p className="text-2xl font-bold text-primary">
                {statusName}
              </p>
            </div>

            <Button onClick={onClose} size="lg" className="mt-4">
              Отлично!
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}

function Fireworks() {
  return (
    <div className="fixed inset-0 pointer-events-none z-[100]" style={{ overflow: 'hidden' }}>
      <canvas id="fireworks-canvas" className="absolute inset-0 w-full h-full" />
      <FireworksScript />
    </div>
  );
}

function FireworksScript() {
  useEffect(() => {
    const canvas = document.getElementById('fireworks-canvas') as HTMLCanvasElement;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;

    const particles: Particle[] = [];
    const rockets: Rocket[] = [];

    class Particle {
      x: number;
      y: number;
      vx: number;
      vy: number;
      gravity: number;
      alpha: number;
      decay: number;
      color: string;

      constructor(x: number, y: number, color: string) {
        this.x = x;
        this.y = y;
        const angle = Math.random() * Math.PI * 2;
        const speed = Math.random() * 6 + 2;
        this.vx = Math.cos(angle) * speed;
        this.vy = Math.sin(angle) * speed;
        this.gravity = 0.15;
        this.alpha = 1;
        this.decay = Math.random() * 0.02 + 0.015;
        this.color = color;
      }

      update() {
        this.x += this.vx;
        this.y += this.vy;
        this.vy += this.gravity;
        this.alpha -= this.decay;
      }

      draw(ctx: CanvasRenderingContext2D) {
        ctx.save();
        ctx.globalAlpha = this.alpha;
        ctx.fillStyle = this.color;
        ctx.beginPath();
        ctx.arc(this.x, this.y, 3, 0, Math.PI * 2);
        ctx.fill();
        ctx.restore();
      }
    }

    class Rocket {
      x: number;
      y: number;
      targetY: number;
      vy: number;
      color: string;
      exploded: boolean;

      constructor() {
        this.x = Math.random() * canvas.width;
        this.y = canvas.height;
        this.targetY = Math.random() * (canvas.height * 0.4) + canvas.height * 0.1;
        this.vy = -8;
        this.color = `hsl(${Math.random() * 360}, 100%, 60%)`;
        this.exploded = false;
      }

      update() {
        this.y += this.vy;
        if (this.y <= this.targetY && !this.exploded) {
          this.explode();
          this.exploded = true;
        }
      }

      explode() {
        for (let i = 0; i < 100; i++) {
          particles.push(new Particle(this.x, this.y, this.color));
        }
      }

      draw(ctx: CanvasRenderingContext2D) {
        if (!this.exploded) {
          ctx.fillStyle = this.color;
          ctx.beginPath();
          ctx.arc(this.x, this.y, 3, 0, Math.PI * 2);
          ctx.fill();
        }
      }
    }

    function animate() {
      ctx!.fillStyle = 'rgba(0, 0, 0, 0.1)';
      ctx!.fillRect(0, 0, canvas.width, canvas.height);

      if (Math.random() < 0.1) {
        rockets.push(new Rocket());
      }

      rockets.forEach((rocket, index) => {
        rocket.update();
        rocket.draw(ctx!);
        if (rocket.exploded && rocket.y > canvas.height) {
          rockets.splice(index, 1);
        }
      });

      particles.forEach((particle, index) => {
        particle.update();
        particle.draw(ctx!);
        if (particle.alpha <= 0) {
          particles.splice(index, 1);
        }
      });

      requestAnimationFrame(animate);
    }

    animate();

    const handleResize = () => {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
    };

    window.addEventListener('resize', handleResize);

    return () => {
      window.removeEventListener('resize', handleResize);
      particles.length = 0;
      rockets.length = 0;
    };
  }, []);

  return null;
}
