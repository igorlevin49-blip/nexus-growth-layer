import { cn } from "@/lib/utils";

interface SimpleTabsProps {
  value: string;
  onValueChange: (value: string) => void;
  children: React.ReactNode;
}

interface TabsListProps {
  children: React.ReactNode;
  className?: string;
}

interface TabsTriggerProps {
  value: string;
  children: React.ReactNode;
  className?: string;
  onClick?: () => void;
  isActive?: boolean;
}

interface TabsContentProps {
  value: string;
  activeValue: string;
  children: React.ReactNode;
  className?: string;
}

export function SimpleTabs({ value, onValueChange, children }: SimpleTabsProps) {
  return (
    <div data-tabs-value={value} data-on-change={onValueChange as any}>
      {children}
    </div>
  );
}

export function SimpleTabsList({ children, className }: TabsListProps) {
  return (
    <div
      className={cn(
        "inline-flex h-auto items-center justify-center rounded-md bg-muted p-1 text-muted-foreground w-full",
        className
      )}
    >
      {children}
    </div>
  );
}

export function SimpleTabsTrigger({ 
  value, 
  children, 
  className, 
  onClick, 
  isActive 
}: TabsTriggerProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "inline-flex items-center justify-center whitespace-nowrap rounded-sm px-3 py-1.5 text-sm font-medium ring-offset-background transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50",
        isActive
          ? "bg-background text-foreground shadow-sm"
          : "hover:bg-background/50",
        className
      )}
      data-state={isActive ? "active" : "inactive"}
    >
      {children}
    </button>
  );
}

export function SimpleTabsContent({ 
  value, 
  activeValue, 
  children, 
  className 
}: TabsContentProps) {
  if (value !== activeValue) return null;
  
  return (
    <div
      className={cn(
        "mt-2 ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
        className
      )}
    >
      {children}
    </div>
  );
}
