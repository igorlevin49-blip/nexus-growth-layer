import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { Users, ShoppingBag } from "lucide-react";

interface StructureSelectorProps {
  value: 1 | 2;
  onChange: (value: 1 | 2) => void;
}

export function StructureSelector({ value, onChange }: StructureSelectorProps) {
  return (
    <ToggleGroup 
      type="single" 
      value={value.toString()} 
      onValueChange={(v) => v && onChange(parseInt(v) as 1 | 2)}
      className="justify-start"
    >
      <ToggleGroupItem value="1" className="flex items-center gap-2">
        <Users className="h-4 w-4" />
        <span className="hidden sm:inline">Структура 1</span>
        <span className="sm:hidden">Стр. 1</span>
      </ToggleGroupItem>
      <ToggleGroupItem value="2" className="flex items-center gap-2">
        <ShoppingBag className="h-4 w-4" />
        <span className="hidden sm:inline">Структура 2</span>
        <span className="sm:hidden">Стр. 2</span>
      </ToggleGroupItem>
    </ToggleGroup>
  );
}
