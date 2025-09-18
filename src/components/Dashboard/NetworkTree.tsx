import { useState } from "react";
import { ChevronDown, ChevronRight, User, Crown, Users2 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

interface NetworkNode {
  id: string;
  name: string;
  level: number;
  status: "active" | "frozen" | "inactive";
  children: NetworkNode[];
  directReferrals: number;
  totalTeam: number;
  monthlyVolume: number;
}

const mockNetworkData: NetworkNode = {
  id: "1",
  name: "Иван Иванов (Вы)",
  level: 1,
  status: "active",
  directReferrals: 3,
  totalTeam: 47,
  monthlyVolume: 2847.50,
  children: [
    {
      id: "2",
      name: "Анна Смирнова",
      level: 2,
      status: "active",
      directReferrals: 2,
      totalTeam: 15,
      monthlyVolume: 1250.00,
      children: [
        {
          id: "4",
          name: "Петр Козлов",
          level: 3,
          status: "active",
          directReferrals: 1,
          totalTeam: 8,
          monthlyVolume: 680.00,
          children: []
        },
        {
          id: "5",
          name: "Елена Волкова",
          level: 3,
          status: "frozen",
          directReferrals: 0,
          totalTeam: 5,
          monthlyVolume: 0,
          children: []
        }
      ]
    },
    {
      id: "3",
      name: "Михаил Попов",
      level: 2,
      status: "active",
      directReferrals: 4,
      totalTeam: 20,
      monthlyVolume: 1850.00,
      children: []
    }
  ]
};

interface NetworkNodeProps {
  node: NetworkNode;
  isRoot?: boolean;
}

function NetworkNodeComponent({ node, isRoot = false }: NetworkNodeProps) {
  const [isExpanded, setIsExpanded] = useState(isRoot || node.level <= 2);

  const getStatusIcon = (status: string) => {
    switch (status) {
      case "active":
        return <div className="w-2 h-2 bg-success rounded-full" />;
      case "frozen":
        return <div className="w-2 h-2 bg-warning rounded-full" />;
      default:
        return <div className="w-2 h-2 bg-muted rounded-full" />;
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case "active":
        return <Badge className="profit-indicator">Активен</Badge>;
      case "frozen":
        return <Badge className="pending-indicator">Заморожен</Badge>;
      default:
        return <Badge className="frozen-indicator">Неактивен</Badge>;
    }
  };

  return (
    <div className="space-y-2">
      <div className={cn(
        "network-node",
        node.status === "active" ? "active" : 
        node.status === "frozen" ? "frozen" : ""
      )}>
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-3">
            {node.children.length > 0 && (
              <Button
                variant="ghost"
                size="sm"
                className="h-6 w-6 p-0"
                onClick={() => setIsExpanded(!isExpanded)}
              >
                {isExpanded ? (
                  <ChevronDown className="h-4 w-4" />
                ) : (
                  <ChevronRight className="h-4 w-4" />
                )}
              </Button>
            )}
            
            <div className="flex items-center space-x-2">
              {getStatusIcon(node.status)}
              {isRoot ? (
                <Crown className="h-4 w-4 text-primary" />
              ) : (
                <User className="h-4 w-4 text-muted-foreground" />
              )}
              <span className="font-medium">{node.name}</span>
              {getStatusBadge(node.status)}
            </div>
          </div>

          <div className="flex items-center space-x-4 text-sm text-muted-foreground">
            <div className="flex items-center space-x-1">
              <Users2 className="h-3 w-3" />
              <span>{node.directReferrals}</span>
            </div>
            <div className="text-right">
              <div className="font-medium text-foreground">
                ${node.monthlyVolume.toFixed(2)}
              </div>
              <div className="text-xs">
                Команда: {node.totalTeam}
              </div>
            </div>
          </div>
        </div>

        <div className="mt-2 flex items-center space-x-4 text-xs text-muted-foreground">
          <span>Уровень {node.level}</span>
          <span>•</span>
          <span>ID: {node.id}</span>
        </div>
      </div>

      {isExpanded && node.children.length > 0 && (
        <div className="ml-6 space-y-2 border-l-2 border-border pl-4">
          {node.children.map((child) => (
            <NetworkNodeComponent key={child.id} node={child} />
          ))}
        </div>
      )}
    </div>
  );
}

export function NetworkTree() {
  return (
    <Card className="financial-card">
      <CardHeader>
        <CardTitle className="flex items-center space-x-2">
          <Users2 className="h-5 w-5" />
          <span>Структура сети</span>
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
            <div className="text-center">
              <div className="text-2xl font-bold text-primary">3</div>
              <div className="text-sm text-muted-foreground">Прямых рефералов</div>
            </div>
            <div className="text-center">
              <div className="text-2xl font-bold text-primary">47</div>
              <div className="text-sm text-muted-foreground">Общая команда</div>
            </div>
            <div className="text-center">
              <div className="text-2xl font-bold text-success">42</div>
              <div className="text-sm text-muted-foreground">Активные</div>
            </div>
            <div className="text-center">
              <div className="text-2xl font-bold text-warning">5</div>
              <div className="text-sm text-muted-foreground">Заморожены</div>
            </div>
          </div>

          <div className="border-t border-border pt-4">
            <NetworkNodeComponent node={mockNetworkData} isRoot />
          </div>
        </div>
      </CardContent>
    </Card>
  );
}