# План: Добавление даты и времени регистрации партнёров в дереве сети

## Проблема
В дереве партнёров (Network Tree) нет информации о дате и времени регистрации каждого партнёра. Администраторы и пользователи хотят видеть, когда именно был зарегистрирован каждый партнёр.

## Текущее состояние
- Поле `created_at` уже возвращается функцией `get_referral_network_from_table`
- Поле `created_at` уже определено в интерфейсе `NetworkMember` (строка 16 в `useNetworkTree.tsx`)
- Компонент `NetworkTree.tsx` используется в трёх местах:
  - `/pages/Network.tsx` - страница "Сеть" для пользователей
  - `/pages/Dashboard.tsx` - дашборд пользователя
  - `/components/Admin/UserNetworkDialog.tsx` - админ-панель просмотра сети пользователя

## Решение
Добавить отображение даты регистрации в правой части карточки партнёра, в области с "фисташковым фоном" (зона статистики).

## Изменения

### Файл: `src/components/Dashboard/NetworkTree.tsx`

**Местоположение изменений:** Строки 298-311 - блок с правой частью карточки

**Что добавить:**
1. Импортировать иконку `Calendar` из lucide-react (строка 2)
2. Создать функцию форматирования даты и времени
3. Добавить блок с датой регистрации в правую часть карточки (перед блоком со статистикой команды)

**Код изменений:**

1. В импорты добавить `Calendar`:
```tsx
import { ChevronDown, ChevronRight, User, Crown, Users2, AlertTriangle, Info, Lock, Clock, Gift, UserX, Calendar } from "lucide-react";
```

2. Добавить функцию форматирования даты (после строки 146):
```tsx
const formatRegistrationDate = (dateString: string) => {
  const date = new Date(dateString);
  return {
    date: date.toLocaleDateString('ru-RU', { 
      day: '2-digit', 
      month: '2-digit', 
      year: 'numeric' 
    }),
    time: date.toLocaleTimeString('ru-RU', { 
      hour: '2-digit', 
      minute: '2-digit' 
    })
  };
};
```

3. В правой части карточки (строки 298-311) добавить дату регистрации:
```tsx
<div className="flex items-center space-x-4 text-sm text-muted-foreground">
  {/* Дата и время регистрации */}
  <div className="flex items-center space-x-1 text-xs">
    <Calendar className="h-3 w-3" />
    <span>{formatRegistrationDate(node.created_at).date}</span>
    <span className="text-muted-foreground/60">{formatRegistrationDate(node.created_at).time}</span>
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
```

## Визуальный результат

До изменений (правая часть карточки):
```
[Личники: 3]  [20 000 ₸]
              [Команда: 15]
```

После изменений (правая часть карточки):
```
[📅 06.01.2026 14:30]  [Личники: 3]  [20 000 ₸]
                                      [Команда: 15]
```

## Затрагиваемые компоненты

| Файл | Изменения |
|------|-----------|
| `src/components/Dashboard/NetworkTree.tsx` | Добавление отображения даты регистрации |

## Примечания
- Изменения автоматически применятся ко всем местам использования `NetworkTree`
- Формат даты: ДД.ММ.ГГГГ ЧЧ:ММ (русская локаль)
- Дата регистрации берётся из `profiles.created_at`

## Критические файлы для реализации
- `src/components/Dashboard/NetworkTree.tsx` - Основной компонент дерева сети, здесь добавляется отображение даты
- `src/hooks/useNetworkTree.tsx` - Интерфейс NetworkMember (для справки, поле created_at уже есть)
- `src/pages/Network.tsx` - Страница сети пользователя (использует NetworkTree)
- `src/components/Admin/UserNetworkDialog.tsx` - Диалог просмотра сети в админке (использует NetworkTree)
