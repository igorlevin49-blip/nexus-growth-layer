import { useState, useMemo } from "react";
import { ChevronDown, ChevronRight, User, Crown, Users2, AlertTriangle, Clock, Gift, Calendar, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import { NetworkMember } from "@/hooks/useNetworkTree";

interface NetworkNode extends NetworkMember {
  children: NetworkNode[];
}

interface NetworkTreeProps {
  members: NetworkMember[];
  filterCommission?: 'all' | 'with_commission' | 'without_commission';
  isError?: boolean;
  onRetry?: () => void;
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

// Simplified: Removed all REASON_INFO and popover logic - keeping only free access badge

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

  // Show "free access" badge only for marketing_free_access
  const isFreeAccess = node.no_commission_reason === 'marketing_free_access';

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
              
              {/* Frozen commission badge - show prominently when commission exists but is frozen */}
              {node.has_commission_received === true && node.commission_status === 'frozen' && node.commission_frozen_until && (
                <Badge className="gap-1 bg-warning text-warning-foreground">
                  <Clock className="h-3 w-3" />
                  <span>Заморожена до {new Date(node.commission_frozen_until).toLocaleDateString('ru-RU')}</span>
                </Badge>
              )}
              
              {/* Commission received badge - show when commission is not frozen */}
              {node.has_commission_received === true && node.commission_status !== 'frozen' && (
                <Badge className="gap-1 bg-success text-success-foreground">
                  ✓ Начислено
                </Badge>
              )}
              
              {/* Free access badge - only for marketing_free_access */}
              {isFreeAccess && (
                <Badge className="gap-1 bg-primary text-primary-foreground">
                  <Gift className="h-3 w-3" />
                  <span>Бесплатник</span>
                </Badge>
              )}
            </div>
          </div>

          <div className="flex items-center space-x-4 text-sm text-muted-foreground">
            <div className="flex items-center space-x-1.5 text-xs">
              <Calendar className="h-3 w-3" />
              <span>{new Date(node.created_at).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' })}</span>
              <span className="text-muted-foreground/60">{new Date(node.created_at).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' })}</span>
            </div>
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

export function NetworkTree({ members, filterCommission = 'all', isError, onRetry }: NetworkTreeProps) {
  // Apply commission filter
  const filteredMembers = useMemo(() => {
    if (filterCommission === 'all') return members;
    
    return members.filter(member => {
      if (filterCommission === 'with_commission') {
        return member.has_commission_received === true;
      }
      
      if (filterCommission === 'without_commission') {
        // Show partners without commission - don't require reason to be set
        return member.has_commission_received === false;
      }
      
      return true;
    });
  }, [members, filterCommission]);

  const treeData = useMemo(() => buildTree(filteredMembers), [filteredMembers]);
  
  // Count missed commissions by reason
  const missedCommissionStats = useMemo(() => {
    const stats: Record<string, number> = {};
    let total = 0;
    
    members.forEach(m => {
      if (m.has_commission_received === false && m.no_commission_reason) {
        const reason = m.no_commission_reason;
        stats[reason] = (stats[reason] || 0) + 1;
        // Only count "actionable" missed commissions (including level_X_locked)
        if (['sponsor_inactive', 'level_not_unlocked', 'level_2_locked', 'level_3_locked', 'level_4_locked', 'level_5_locked'].includes(reason)) {
          total++;
        }
      }
    });
    
    return { stats, total };
  }, [members]);
  
  // Show error state first
  if (isError) {
    return (
      <div className="text-center py-12">
        <AlertTriangle className="h-12 w-12 text-destructive mx-auto mb-4" />
        <p className="text-lg font-medium mb-2">Не удалось загрузить структуру</p>
        <p className="text-sm text-muted-foreground mb-4">Произошла ошибка при загрузке данных</p>
        {onRetry && (
          <Button variant="outline" onClick={() => onRetry()}>
            <RefreshCw className="h-4 w-4 mr-2" />
            Повторить
          </Button>
        )}
      </div>
    );
  }
  
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
      
      <div className="border-t border-border pt-4 space-y-2">
        {treeData.map((node) => (
          <NetworkNodeComponent key={node.partner_id} node={node} isRoot />
        ))}
      </div>
    </div>
  );
}
