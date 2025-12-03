import { Users, ShoppingBag } from "lucide-react";
import { cn } from "@/lib/utils";

interface StructureSelectorProps {
  value: 1 | 2;
  onChange: (value: 1 | 2) => void;
}

export function StructureSelector({ value, onChange }: StructureSelectorProps) {
  return (
    <div className="inline-flex items-center rounded-md border border-input bg-background p-1 gap-1">
      <button
        type="button"
        onClick={() => onChange(1)}
        className={cn(
          "inline-flex items-center gap-2 rounded-sm px-3 py-1.5 text-sm font-medium transition-colors",
          value === 1
            ? "bg-primary text-primary-foreground"
            : "hover:bg-muted text-muted-foreground"
        )}
      >
        <Users className="h-4 w-4" />
        <span className="hidden sm:inline">Структура 1</span>
        <span className="sm:hidden">Стр. 1</span>
      </button>
      <button
        type="button"
        onClick={() => onChange(2)}
        className={cn(
          "inline-flex items-center gap-2 rounded-sm px-3 py-1.5 text-sm font-medium transition-colors",
          value === 2
            ? "bg-primary text-primary-foreground"
            : "hover:bg-muted text-muted-foreground"
        )}
      >
        <ShoppingBag className="h-4 w-4" />
        <span className="hidden sm:inline">Структура 2</span>
        <span className="sm:hidden">Стр. 2</span>
      </button>
    </div>
  );
}
