import { useState, useMemo } from "react";
import { ChevronDown, ChevronRight, User, Crown, Users2, AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import { NetworkMember } from "@/hooks/useNetworkTree";

interface NetworkNode extends NetworkMember {
  children: NetworkNode[];
}

interface NetworkTreeProps {
  members: NetworkMember[];
  filterCommission?: 'all' | 'with_commission' | 'without_commission';
}

function buildTree(members: NetworkMember[]): NetworkNode[] {
  const nodeMap = new Map<string, NetworkNode>();
  const rootNodes: NetworkNode[] = [];

  // First pass: create nodes
  members.forEach(member => {
    nodeMap.set(member.partner_id, { ...member, children: [] });
  });

  // Second pass: build tree structure using parent_partner_id
  members.forEach(member => {
    const node = nodeMap.get(member.partner_id)!;
    
    if (member.level === 1) {
      // Level 1 members are direct referrals of root user
      rootNodes.push(node);
    } else if (member.parent_partner_id) {
      // Use actual parent_partner_id for proper parent-child relationship
      const parentNode = nodeMap.get(member.parent_partner_id);
      if (parentNode) {
        parentNode.children.push(node);
      } else {
        // If parent not in current view, treat as root
        rootNodes.push(node);
      }
    }
  });

  return rootNodes;
}

const getNoCommissionReasonText = (reason: string | null): string => {
  switch (reason) {
    case 'not_activated':
      return 'Партнёр не активирован';
    case 'too_deep':
      return 'Глубже 5 уровня (S1)';
    case 'sponsor_inactive':
      return 'Спонсор был неактивен при активации партнёра';
    default:
      return 'Причина неизвестна';
  }
};

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

  // Commission status - only relevant when partner is active but no commission received
  const hasMissedCommission = status === 'active' && 
    node.has_commission_received === false && 
    node.no_commission_reason === 'sponsor_inactive';

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
        return <Badge className="frozen-indicator">Ожидает активации</Badge>;
    }
  };

  return (
    <div className="space-y-2">
      <div className={cn(
        "network-node",
        status === "active" ? "active" : 
        status === "frozen" ? "frozen" : "",
        hasMissedCommission && "border-l-4 border-l-orange-500 bg-orange-500/5"
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
              
              {/* Missed commission indicator */}
              {hasMissedCommission && (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Badge className="bg-orange-500 hover:bg-orange-600 text-white gap-1">
                      <AlertTriangle className="h-3 w-3" />
                      Без начисления
                    </Badge>
                  </TooltipTrigger>
                  <TooltipContent>
                    <p>{getNoCommissionReasonText(node.no_commission_reason)}</p>
                  </TooltipContent>
                </Tooltip>
              )}
            </div>
          </div>

          <div className="flex items-center space-x-4 text-sm text-muted-foreground">
            <div className="flex items-center space-x-1">
              <Users2 className="h-3 w-3" />
              <span>{node.direct_referrals}</span>
            </div>
            <div className="text-right">
              <div className="font-medium text-foreground">
                {node.monthly_volume.toLocaleString('ru-RU')} ₸
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
          {node.has_commission_received === true && status === 'active' && (
            <>
              <span>•</span>
              <span className="text-success">✓ Комиссия начислена</span>
            </>
          )}
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

export function NetworkTree({ members, filterCommission = 'all' }: NetworkTreeProps) {
  // Apply commission filter
  const filteredMembers = useMemo(() => {
    if (filterCommission === 'all') return members;
    
    return members.filter(member => {
      const isActive = member.subscription_status === 'active' || member.monthly_activation_met;
      
      if (filterCommission === 'with_commission') {
        return member.has_commission_received === true;
      }
      
      if (filterCommission === 'without_commission') {
        // Show active partners without commission (missed commissions)
        return isActive && member.has_commission_received === false;
      }
      
      return true;
    });
  }, [members, filterCommission]);

  const treeData = useMemo(() => buildTree(filteredMembers), [filteredMembers]);
  
  // Count missed commissions for stats
  const missedCommissionCount = useMemo(() => {
    return members.filter(m => {
      const isActive = m.subscription_status === 'active' || m.monthly_activation_met;
      return isActive && m.has_commission_received === false && m.no_commission_reason === 'sponsor_inactive';
    }).length;
  }, [members]);
  
  if (members.length === 0) {
    return (
      <div className="text-center py-12">
        <Users2 className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
        <p className="text-lg font-medium mb-2">Структура пуста</p>
        <p className="text-sm text-muted-foreground">Пригласите первых партнёров</p>
      </div>
    );
  }

  if (filteredMembers.length === 0 && filterCommission !== 'all') {
    return (
      <div className="text-center py-12">
        <Users2 className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
        <p className="text-lg font-medium mb-2">
          {filterCommission === 'with_commission' 
            ? 'Нет партнёров с начислениями' 
            : 'Нет партнёров без начислений'}
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Missed commission warning */}
      {missedCommissionCount > 0 && filterCommission === 'all' && (
        <div className="flex items-center gap-2 p-3 bg-orange-500/10 border border-orange-500/20 rounded-lg text-sm">
          <AlertTriangle className="h-4 w-4 text-orange-500" />
          <span>
            <strong>{missedCommissionCount}</strong> партнёр(ов) без начисления комиссии (S1)
          </span>
        </div>
      )}
      
      <div className="border-t border-border pt-4 space-y-2">
        {treeData.map((node) => (
          <NetworkNodeComponent key={node.partner_id} node={node} isRoot />
        ))}
      </div>
    </div>
  );
}
