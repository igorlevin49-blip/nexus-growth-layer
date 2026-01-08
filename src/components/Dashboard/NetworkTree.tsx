import { useState, useMemo } from "react";
import { ChevronDown, ChevronRight, User, Crown, Users2, AlertTriangle, Info, Lock, Clock, Gift, UserX, Calendar, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
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

// Get unlock requirements for each level (matches DB logic)
const UNLOCK_REQUIREMENTS: Record<number, number> = {
  2: 2,
  3: 3,
  4: 4,
  5: 5
};

type NoCommissionReason = 
  | 'not_activated' 
  | 'no_payment_this_month'
  | 'too_deep' 
  | 'level_not_unlocked'
  | 'level_2_locked'
  | 'level_3_locked'
  | 'level_4_locked'
  | 'level_5_locked'
  | 'marketing_free_access' 
  | 'sponsor_inactive'
  | 'sponsor_no_activation'
  | 'already_received_before'
  | 'no_active_subscription'
  | 'new_partner';

interface ReasonInfo {
  title: string;
  description: string;
  color: 'orange' | 'blue' | 'gray' | 'red';
  icon: typeof AlertTriangle;
}

const REASON_INFO: Record<NoCommissionReason, ReasonInfo> = {
  not_activated: {
    title: 'Партнёр не активирован',
    description: 'Партнёр ещё не оплатил годовую подписку. Он не учитывается как личник и комиссия за него не начисляется.',
    color: 'gray',
    icon: UserX
  },
  no_payment_this_month: {
    title: 'Нет активации в этом месяце',
    description: 'Партнёр не сделал ежемесячную активацию (закуп на 20 000 ₸). В этом месяце комиссия за него не начисляется.',
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
    description: 'Данный партнёр находится на уровне, который вам ещё не открыт. Нужно больше активных личников.',
    color: 'orange',
    icon: Lock
  },
  level_2_locked: {
    title: 'Уровень 2 закрыт',
    description: 'Для доступа к уровню 2 нужно минимум 2 активных личника на первой линии.',
    color: 'orange',
    icon: Lock
  },
  level_3_locked: {
    title: 'Уровень 3 закрыт',
    description: 'Для доступа к уровню 3 нужно минимум 3 активных личника на первой линии.',
    color: 'orange',
    icon: Lock
  },
  level_4_locked: {
    title: 'Уровень 4 закрыт',
    description: 'Для доступа к уровню 4 нужно минимум 4 активных личника на первой линии.',
    color: 'orange',
    icon: Lock
  },
  level_5_locked: {
    title: 'Уровень 5 закрыт',
    description: 'Для доступа к уровню 5 нужно минимум 5 активных личников на первой линии.',
    color: 'orange',
    icon: Lock
  },
  marketing_free_access: {
    title: 'Бесплатный маркетинговый доступ',
    description: 'Партнёр был зарегистрирован по бесплатному маркетинговому доступу, поэтому за него комиссия не начисляется.',
    color: 'blue',
    icon: Gift
  },
  sponsor_inactive: {
    title: 'Нет активной подписки спонсора',
    description: 'У спонсора нет активной подписки, поэтому комиссия за эту структуру не начисляется.',
    color: 'red',
    icon: AlertTriangle
  },
  sponsor_no_activation: {
    title: 'Спонсор не активирован',
    description: 'У спонсора не выполнена ежемесячная активация (закуп на 20 000 ₸). Комиссия за структуру в этом месяце закрыта.',
    color: 'orange',
    icon: Clock
  },
  already_received_before: {
    title: 'Реанимация партнёра',
    description: 'Комиссия за этого партнёра уже была получена ранее. При реанимации (повторной активации) комиссия не начисляется повторно.',
    color: 'blue',
    icon: Clock
  },
  new_partner: {
    title: 'Новый партнёр',
    description: 'Партнёр зарегистрирован в текущем месяце. Ежемесячная активация начнёт требоваться со следующего месяца.',
    color: 'blue',
    icon: Gift
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
      return 'bg-warning text-warning-foreground hover:bg-warning/90';
    case 'blue':
      return 'bg-primary text-primary-foreground hover:bg-primary/90';
    case 'red':
      return 'bg-destructive text-destructive-foreground hover:bg-destructive/90';
    default:
      return 'bg-muted text-muted-foreground hover:bg-muted/80';
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

  // Get additional info for level_not_unlocked or level_X_locked with dynamic message
  const getLevelUnlockInfo = (node: NetworkNode) => {
    const levelLockedReasons = ['level_2_locked', 'level_3_locked', 'level_4_locked', 'level_5_locked', 'level_not_unlocked'];
    if (!node.no_commission_reason || !levelLockedReasons.includes(node.no_commission_reason)) return null;
    
    // Parse level from reason like "level_3_locked"
    const levelMatch = node.no_commission_reason.match(/level_(\d)_locked/);
    if (levelMatch) {
      const level = parseInt(levelMatch[1]);
      return { level, required: level };
    }
    
    // Fallback for level_not_unlocked
    return { level: node.level, required: UNLOCK_REQUIREMENTS[node.level] || node.level };
  };

  const levelUnlockInfo = getLevelUnlockInfo(node);

  return (
    <div className="space-y-2">
      <div className={cn(
        "network-node",
        status === "active" ? "active" : 
        status === "frozen" ? "frozen" : "",
        hasNoCommission && reasonInfo?.color === 'orange' && "border-l-4 border-l-warning bg-warning/10",
        hasNoCommission && reasonInfo?.color === 'blue' && "border-l-4 border-l-primary bg-primary/10"
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
              
              {/* No commission indicator with click-to-open explanation */}
              {hasNoCommission && reasonInfo && (
                <Popover>
                  <PopoverTrigger>
                    <Badge 
                      className={cn(
                        "gap-1 cursor-pointer select-none",
                        getReasonBadgeClass(reasonInfo.color)
                      )}
                    >
                      <ReasonIcon className="h-3 w-3" />
                      <span>Нет начисления</span>
                    </Badge>
                  </PopoverTrigger>
                  <PopoverContent 
                    side="bottom" 
                    align="start"
                    className="w-80 z-[100]"
                  >
                    <div className="space-y-3">
                      <div className="flex items-start gap-3">
                        <div className={cn(
                          "p-2 rounded-lg",
                          reasonInfo.color === 'orange' && "bg-warning/20",
                          reasonInfo.color === 'blue' && "bg-primary/20",
                          reasonInfo.color === 'red' && "bg-destructive/20",
                          reasonInfo.color === 'gray' && "bg-muted"
                        )}>
                          <ReasonIcon className={cn(
                            "h-5 w-5",
                            reasonInfo.color === 'orange' && "text-warning",
                            reasonInfo.color === 'blue' && "text-primary",
                            reasonInfo.color === 'red' && "text-destructive",
                            reasonInfo.color === 'gray' && "text-muted-foreground"
                          )} />
                        </div>
                        <div className="flex-1">
                          <p className="font-semibold text-foreground">{reasonInfo.title}</p>
                          <p className="text-sm text-muted-foreground mt-1">{reasonInfo.description}</p>
                        </div>
                      </div>
                      {levelUnlockInfo && (
                        <div className="p-3 bg-warning/10 border border-warning/20 rounded-lg">
                          <p className="text-sm text-warning font-medium">
                            💡 Для открытия уровня {levelUnlockInfo.level} нужно {levelUnlockInfo.required} активных личников на 1-й линии
                          </p>
                        </div>
                      )}
                    </div>
                  </PopoverContent>
                </Popover>
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
          {/* Показываем статус комиссии только если нет причины отсутствия */}
          {node.has_commission_received === true && !node.no_commission_reason && (
            <>
              <span>•</span>
              {node.commission_status === 'frozen' && node.commission_frozen_until ? (
                <span className="text-warning">
                  ⏳ Комиссия заморожена до {new Date(node.commission_frozen_until).toLocaleDateString('ru-RU')}
                </span>
              ) : (
                <span className="text-success">✓ Комиссия начислена</span>
              )}
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

export function NetworkTree({ members, filterCommission = 'all', isError, onRetry }: NetworkTreeProps) {
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
      {/* Missed commission warning - only for actionable reasons */}
      {missedCommissionStats.total > 0 && filterCommission === 'all' && (
        <div className="flex items-center gap-2 p-3 bg-warning/10 border border-warning/20 rounded-lg text-sm">
          <AlertTriangle className="h-4 w-4 text-warning flex-shrink-0" />
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
