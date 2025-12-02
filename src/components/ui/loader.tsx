import { cn } from "@/lib/utils";
import "./loader.css";

interface LoaderProps {
  className?: string;
}

export function Loader({ className }: LoaderProps) {
  return (
    <div className={cn("loader-overlay", className)}>
      <div className="loader-container">
        <div className="cup">
          <div className="cup__handler"></div>
          <div className="cup__steam">
            <div className="cup__steam-flow"></div>
          </div>
        </div>
      </div>
    </div>
  );
}
