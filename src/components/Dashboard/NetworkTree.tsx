import { useState, useMemo } from "react";
import { ChevronDown, ChevronRight, User, Crown, Users2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import { NetworkMember } from "@/hooks/useNetworkTree";

interface NetworkNode extends NetworkMember {
  children: NetworkNode[];
}

interface NetworkTreeProps {
  members: NetworkMember[];
}

function buildTree(members: NetworkMember[]): NetworkNode[] {
  const nodeMap = new Map<string, NetworkNode>();
  const rootNodes: NetworkNode[] = [];

  // First pass: create nodes
  members.forEach(member => {
    nodeMap.set(member.partner_id, { ...member, children: [] });
  });

  // Second pass: build tree structure based on levels
  members.forEach(member => {
    const node = nodeMap.get(member.partner_id)!;
    
    if (member.level === 1) {
      rootNodes.push(node);
    } else {
      // Find parent (first member with level - 1)
      const parent = members.find(m => 
        m.level === member.level - 1 && 
        m.partner_id !== member.partner_id
      );
      if (parent) {
        const parentNode = nodeMap.get(parent.partner_id);
        if (parentNode) {
          parentNode.children.push(node);
        }
      }
    }
  });

  return rootNodes;
}

interface NetworkNodeProps {
  node: NetworkNode;
  isRoot?: boolean;
}

function NetworkNodeComponent({ node, isRoot = false }: NetworkNodeProps) {
  const [isExpanded, setIsExpanded] = useState(isRoot || node.level <= 2);

  const status = node.subscription_status === 'active' || node.monthly_activation_met 
    ? 'active' 
    : node.subscription_status === 'frozen' 
    ? 'frozen' 
    : 'inactive';

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
        status === "active" ? "active" : 
        status === "frozen" ? "frozen" : ""
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
              {getStatusIcon(status)}
              {isRoot ? (
                <Crown className="h-4 w-4 text-primary" />
              ) : (
                <User className="h-4 w-4 text-muted-foreground" />
              )}
              <span className="font-medium">{node.full_name || 'Без имени'}</span>
              {getStatusBadge(status)}
            </div>
          </div>

          <div className="flex items-center space-x-4 text-sm text-muted-foreground">
            <div className="flex items-center space-x-1">
              <Users2 className="h-3 w-3" />
              <span>{node.direct_referrals}</span>
            </div>
            <div className="text-right">
              <div className="font-medium text-foreground">
                ${node.monthly_volume.toFixed(2)}
              </div>
              <div className="text-xs">
                Команда: {node.total_team}
              </div>
            </div>
          </div>
        </div>

        <div className="mt-2 flex items-center space-x-4 text-xs text-muted-foreground">
          <span>Уровень {node.level}</span>
          <span>•</span>
          <span>ID: {node.partner_id.substring(0, 8)}</span>
        </div>
      </div>

      {isExpanded && node.children.length > 0 && (
        <div className="ml-6 space-y-2 border-l-2 border-border pl-4">
          {node.children.map((child) => (
            <NetworkNodeComponent key={child.partner_id} node={child} />
          ))}
        </div>
      )}
    </div>
  );
}

export function NetworkTree({ members }: NetworkTreeProps) {
  const treeData = useMemo(() => buildTree(members), [members]);
  
  if (members.length === 0) {
    return (
      <div className="text-center py-12">
        <Users2 className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
        <p className="text-lg font-medium mb-2">Структура пуста</p>
        <p className="text-sm text-muted-foreground">Пригласите первых партнёров</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="border-t border-border pt-4 space-y-2">
        {treeData.map((node) => (
          <NetworkNodeComponent key={node.partner_id} node={node} isRoot />
        ))}
      </div>
    </div>
  );
}