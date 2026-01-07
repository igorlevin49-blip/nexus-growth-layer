import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow, TableFooter } from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { DollarSign, Search, Users, AlertTriangle, TrendingUp, TrendingDown, Wallet, Loader2 } from "lucide-react";
import { formatKZT } from "@/utils/formatMoney";

export interface Partner {
  id: string;
  full_name: string | null;
  email: string | null;
  phone: string | null;
  available_kzt: number;
  frozen_kzt: number;
}

export type BalanceFilter = "all" | "has_payout" | "no_payout" | "negative";

interface PartnersTableProps {
  partners: Partner[];
  filteredPartners: Partner[];
  totals: { available: number; frozen: number };
  stats: { all: number; has_payout: number; no_payout: number; negative: number };
  searchQuery: string;
  onSearchChange: (value: string) => void;
  balanceFilter: BalanceFilter;
  onBalanceFilterChange: (value: BalanceFilter) => void;
  isRefreshing: boolean;
  isSuperAdmin: boolean;
  onOpenPayoutDialog: (partner: Partner) => void;
  onOpenAdjustmentDialog: (partner: Partner) => void;
  showActions?: boolean;
}

export function PartnersTable({
  partners,
  filteredPartners,
  totals,
  stats,
  searchQuery,
  onSearchChange,
  balanceFilter,
  onBalanceFilterChange,
  isRefreshing,
  isSuperAdmin,
  onOpenPayoutDialog,
  onOpenAdjustmentDialog,
  showActions = true,
}: PartnersTableProps) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="flex items-center gap-2">
          <Wallet className="h-5 w-5" />
          Балансы партнёров
        </CardTitle>
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          {isRefreshing && <Loader2 className="h-4 w-4 animate-spin" />}
          <span>Показано: {filteredPartners.length} из {partners.length}</span>
        </div>
      </CardHeader>
      <CardContent>
        {/* Search and Filter Bar */}
        <div className="mb-4 flex flex-col sm:flex-row gap-3">
          <div className="relative flex-1">
            {isRefreshing ? (
              <Loader2 className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground animate-spin" />
            ) : (
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            )}
            <Input
              placeholder="Поиск по имени или email..."
              value={searchQuery}
              onChange={(e) => onSearchChange(e.target.value)}
              className="pl-9"
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="off"
              spellCheck={false}
            />
          </div>
          <Select value={balanceFilter} onValueChange={(v) => onBalanceFilterChange(v as BalanceFilter)}>
            <SelectTrigger className="w-full sm:w-[220px]">
              <SelectValue placeholder="Фильтр по балансу" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">
                <div className="flex items-center gap-2">
                  <Users className="h-4 w-4" />
                  Все партнёры ({stats.all})
                </div>
              </SelectItem>
              <SelectItem value="has_payout">
                <div className="flex items-center gap-2">
                  <TrendingUp className="h-4 w-4 text-green-500" />
                  На выдачу ({stats.has_payout})
                </div>
              </SelectItem>
              <SelectItem value="no_payout">
                <div className="flex items-center gap-2">
                  <TrendingDown className="h-4 w-4 text-muted-foreground" />
                  Без выдачи ({stats.no_payout})
                </div>
              </SelectItem>
              <SelectItem value="negative">
                <div className="flex items-center gap-2">
                  <AlertTriangle className="h-4 w-4 text-destructive" />
                  Отрицательный ({stats.negative})
                </div>
              </SelectItem>
            </SelectContent>
          </Select>
        </div>

        {/* Negative balance warning */}
        {stats.negative > 0 && balanceFilter !== "negative" && (
          <div className="mb-4 p-3 bg-destructive/10 border border-destructive/20 rounded-lg flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-destructive" />
            <span className="text-sm">
              <strong>{stats.negative}</strong> партнёров с отрицательным балансом. 
              <Button 
                variant="link" 
                className="h-auto p-0 pl-1 text-destructive"
                onClick={() => onBalanceFilterChange("negative")}
              >
                Показать
              </Button>
            </span>
          </div>
        )}

        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Партнёр</TableHead>
                <TableHead>Email</TableHead>
                <TableHead>Телефон</TableHead>
                <TableHead>Доступно</TableHead>
                <TableHead>Заморожено</TableHead>
                {showActions && <TableHead className="text-right">Действия</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {filteredPartners.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={showActions ? 6 : 5} className="text-center text-muted-foreground py-8">
                    {balanceFilter === "negative" 
                      ? "Нет партнёров с отрицательным балансом" 
                      : balanceFilter === "has_payout"
                      ? "Нет партнёров с доступными средствами"
                      : "Партнёры не найдены"}
                  </TableCell>
                </TableRow>
              ) : (
                filteredPartners.map((partner) => (
                  <TableRow key={partner.id} className={partner.available_kzt < 0 ? "bg-destructive/5" : ""}>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        {partner.full_name || 'Без имени'}
                        {partner.available_kzt < 0 && (
                          <Badge variant="destructive" className="text-xs">Долг</Badge>
                        )}
                      </div>
                    </TableCell>
                    <TableCell>{partner.email || '—'}</TableCell>
                    <TableCell>{partner.phone || '—'}</TableCell>
                    <TableCell>
                      <Badge 
                        variant={partner.available_kzt < 0 ? "destructive" : "default"} 
                        className="font-mono"
                      >
                        {formatKZT(partner.available_kzt, 'KZT')}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <Badge variant="secondary" className="font-mono">
                        {formatKZT(partner.frozen_kzt, 'KZT')}
                      </Badge>
                    </TableCell>
                    {showActions && (
                      <TableCell className="text-right">
                        {isSuperAdmin ? (
                          <div className="flex justify-end gap-2">
                            {partner.available_kzt > 0 && (
                              <Button
                                variant="outline"
                                size="sm"
                                onClick={() => onOpenPayoutDialog(partner)}
                              >
                                <DollarSign className="h-4 w-4 mr-1" />
                                Выдать
                              </Button>
                            )}
                            <Button
                              variant={partner.available_kzt < 0 ? "destructive" : "ghost"}
                              size="sm"
                              onClick={() => onOpenAdjustmentDialog(partner)}
                            >
                              {partner.available_kzt < 0 ? (
                                <>
                                  <AlertTriangle className="h-4 w-4 mr-1" />
                                  Исправить
                                </>
                              ) : (
                                "Корректировка"
                              )}
                            </Button>
                          </div>
                        ) : (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </TableCell>
                    )}
                  </TableRow>
                ))
              )}
            </TableBody>
            {filteredPartners.length > 0 && (
              <TableFooter>
                <TableRow className="bg-muted/50 font-semibold">
                  <TableCell colSpan={3}>Итого ({filteredPartners.length})</TableCell>
                  <TableCell>
                    <Badge 
                      variant={totals.available < 0 ? "destructive" : "default"} 
                      className="font-mono"
                    >
                      {formatKZT(totals.available, 'KZT')}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <Badge variant="secondary" className="font-mono">
                      {formatKZT(totals.frozen, 'KZT')}
                    </Badge>
                  </TableCell>
                  {showActions && <TableCell></TableCell>}
                </TableRow>
              </TableFooter>
            )}
          </Table>
        </div>
      </CardContent>
    </Card>
  );
}
