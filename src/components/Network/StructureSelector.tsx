import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Users, ShoppingBag } from "lucide-react";

interface StructureSelectorProps {
  value: 1 | 2;
  onChange: (value: 1 | 2) => void;
}

export function StructureSelector({ value, onChange }: StructureSelectorProps) {
  return (
    <Tabs value={value.toString()} onValueChange={(v) => onChange(parseInt(v) as 1 | 2)}>
      <TabsList className="grid w-full grid-cols-2">
        <TabsTrigger value="1" className="flex items-center gap-2">
          <Users className="h-4 w-4" />
          <span className="hidden sm:inline">Структура 1</span>
          <span className="sm:hidden">Стр. 1</span>
        </TabsTrigger>
        <TabsTrigger value="2" className="flex items-center gap-2">
          <ShoppingBag className="h-4 w-4" />
          <span className="hidden sm:inline">Структура 2</span>
          <span className="sm:hidden">Стр. 2</span>
        </TabsTrigger>
      </TabsList>
    </Tabs>
  );
}
