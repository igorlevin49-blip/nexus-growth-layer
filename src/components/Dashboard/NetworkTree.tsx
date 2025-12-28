import { useState, useMemo } from "react";
import { ChevronDown, ChevronRight, User, Crown, Users2, AlertTriangle, Info, Lock, Clock, Gift, UserX } from "lucide-react";
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

// Get unlock requirements for each level
const UNLOCK_REQUIREMENTS: Record<number, number> = {
  2: 3,
  3: 5,
  4: 8,
  5: 10
};

type NoCommissionReason = 
  | 'not_activated' 
  | 'no_payment_this_month'
  | 'too_deep' 
  | 'level_not_unlocked' 
  | 'marketing_free_access' 
  | 'sponsor_inactive'
  | 'already_received_before'
  | 'no_active_subscription';

interface ReasonInfo {
  title: string;
  description: string;
  color: 'orange' | 'blue' | 'gray' | 'red';
  icon: typeof AlertTriangle;
}

const REASON_INFO: Record<NoCommissionReason, ReasonInfo> = {
  not_activated: {
    title: 'Партнёр не активен',
    description: 'Партнёр ещё не оплатил подписку или не прошёл активацию. Комиссия будет начислена после его активации.',
    color: 'gray',
    icon: UserX
  },
  no_payment_this_month: {
    title: 'Нет оплаты в этом месяце',
    description: 'Партнёр не оплачивал подписку в текущем месяце. Комиссия начисляется только за оплаты текущего месяца.',
    color: 'gray',
    icon: Clock
  },
  no_active_subscription: {
    title: 'Нет активной подписки',
    description: 'У партнёра нет активной подписки. Комиссия начисляется только за активных партнёров.',
    color: 'gray',
    icon: UserX
  },
  too_deep: {
    title: 'Глубже 5 уровня',
    description: 'Партнёр находится на уровне глубже 5-го. В структуре S1 комиссия начисляется только до 5-го уровня включительно.',
    color: 'blue',
    icon: Info
  },
  level_not_unlocked: {
    title: 'Уровень не открыт',
    description: 'Для получения комиссии с этого уровня требуется больше активных личных продаж на 1-й линии.',
    color: 'orange',
    icon: Lock
  },
  marketing_free_access: {
    title: 'Бесплатный доступ',
    description: 'Партнёр получил бесплатный маркетинговый доступ. За бесплатные подписки комиссия не начисляется.',
    color: 'blue',
    icon: Gift
  },
  sponsor_inactive: {
    title: 'Вы были неактивны',
    description: 'В момент активации этого партнёра вы были неактивны (не выполнена месячная активация). Комиссия не была начислена.',
    color: 'orange',
    icon: AlertTriangle
  },
  already_received_before: {
    title: 'Реанимация партнёра',
    description: 'Комиссия за этого партнёра уже была получена ранее. При реанимации (повторной активации) комиссия не начисляется повторно.',
    color: 'blue',
    icon: Clock
  }
};

const getReasonInfo = (reason: string | null): ReasonInfo | null => {
  if (!reason) return null;
  return REASON_INFO[reason as NoCommissionReason] || {
    title: 'Нет начисления',
    description: 'Причина неизвестна',
    color: 'gray' as const,
    icon: Info
  };
};

const getReasonBadgeClass = (color: 'orange' | 'blue' | 'gray' | 'red'): string => {
  switch (color) {
    case 'orange':
      return 'bg-orange-500 hover:bg-orange-600 text-white';
    case 'blue':
      return 'bg-blue-500 hover:bg-blue-600 text-white';
    case 'red':
      return 'bg-red-500 hover:bg-red-600 text-white';
    default:
      return 'bg-muted hover:bg-muted/80 text-muted-foreground';
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

  // Show "no commission" indicator when:
  // 1. Partner is active AND has a reason for no commission
  // 2. OR partner would be eligible but has a specific reason
  const hasNoCommission = node.has_commission_received === false && 
    node.no_commission_reason !== null;
  
  const reasonInfo = getReasonInfo(node.no_commission_reason);
  const ReasonIcon = reasonInfo?.icon || AlertTriangle;

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

  // Get additional info for level_not_unlocked
  const getLevelUnlockInfo = () => {
    if (node.no_commission_reason !== 'level_not_unlocked') return null;
    const required = UNLOCK_REQUIREMENTS[node.level] || node.level;
    return {
      level: node.level,
      required
    };
  };

  const levelUnlockInfo = getLevelUnlockInfo();

  return (
    <div className="space-y-2">
      <div className={cn(
        "network-node",
        status === "active" ? "active" : 
        status === "frozen" ? "frozen" : "",
        hasNoCommission && reasonInfo?.color === 'orange' && "border-l-4 border-l-orange-500 bg-orange-500/5",
        hasNoCommission && reasonInfo?.color === 'blue' && "border-l-4 border-l-blue-500 bg-blue-500/5"
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
              
              {/* No commission indicator with tooltip */}
              {hasNoCommission && reasonInfo && (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Badge className={cn("gap-1 cursor-pointer", getReasonBadgeClass(reasonInfo.color))}>
                      <ReasonIcon className="h-3 w-3" />
                      Нет начисления
                    </Badge>
                  </TooltipTrigger>
                  <TooltipContent side="bottom" className="max-w-xs p-3">
                    <div className="space-y-2">
                      <p className="font-semibold text-sm">{reasonInfo.title}</p>
                      <p className="text-xs text-muted-foreground">{reasonInfo.description}</p>
                      {levelUnlockInfo && (
                        <div className="mt-2 pt-2 border-t border-border">
                          <p className="text-xs text-orange-400">
                            Для открытия уровня {levelUnlockInfo.level} нужно {levelUnlockInfo.required} активных личников на 1-й линии
                          </p>
                        </div>
                      )}
                    </div>
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
      if (filterCommission === 'with_commission') {
        return member.has_commission_received === true;
      }
      
      if (filterCommission === 'without_commission') {
        // Show partners without commission (with any reason)
        return member.has_commission_received === false && member.no_commission_reason !== null;
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
        // Only count "actionable" missed commissions
        if (['sponsor_inactive', 'level_not_unlocked'].includes(reason)) {
          total++;
        }
      }
    });
    
    return { stats, total };
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
      {/* Missed commission warning - only for actionable reasons */}
      {missedCommissionStats.total > 0 && filterCommission === 'all' && (
        <div className="flex items-center gap-2 p-3 bg-orange-500/10 border border-orange-500/20 rounded-lg text-sm">
          <AlertTriangle className="h-4 w-4 text-orange-500 flex-shrink-0" />
          <span>
            <strong>{missedCommissionStats.total}</strong> партнёр(ов) без начисления комиссии.
            Нажмите на бейдж «Нет начисления» для подробностей.
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
