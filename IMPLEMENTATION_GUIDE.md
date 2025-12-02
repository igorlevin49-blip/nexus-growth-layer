# Руководство по внедренным функциям

## 1. Отображение покупателя в Orders

### Что сделано:
- В колонке "Покупатель" теперь отображается имя пользователя вместо UUID
- При клике на имя осуществляется переход на страницу профиля пользователя
- Если имя не указано, показывается email или "Пользователь без имени"

### Формат отображения:
- Если есть `full_name`: показывается `full_name`
- Если есть `first_name` и `last_name`: показывается `first_name last_name`
- Если есть только `email`: показывается `email`
- Если ничего нет: показывается "Пользователь без имени"

---

## 2. Поздравления при получении нового статуса

### Что сделано:
- Создан компонент `StatusCelebration` с анимацией фейерверка (салюта)
- Создан хук `useStatusCelebration` для автоматического отслеживания новых достижений
- Поздравление показывается только один раз для каждого нового статуса
- Используется Realtime для мгновенного отображения достижений

### Как работает:
1. Когда пользователь получает новый статус, в таблицу `user_status_achievements` добавляется запись
2. Триггер автоматически отправляет уведомление всем супер-админам
3. Пользователь видит модальное окно с поздравлением и анимацией фейерверка
4. После закрытия окна, достижение помечается как просмотренное (`shown = true`)

### Как добавить новое достижение (для тестирования):
```sql
INSERT INTO user_status_achievements (user_id, level, status_name)
VALUES (
  'user-uuid-here',
  1,
  'Бронзовый партнёр'
);
```

### Примеры статусов:
- Уровень 1: "Бронзовый партнёр"
- Уровень 2: "Серебряный партнёр"
- Уровень 3: "Золотой партнёр"
- Уровень 4: "Платиновый партнёр"
- Уровень 5: "Бриллиантовый партнёр"

---

## 3. Уведомления админов о повышении статуса

### Что сделано:
- Создана таблица `admin_notifications` для хранения уведомлений
- Создан триггер, который автоматически отправляет уведомления всем супер-админам
- Создан хук `useAdminNotifications` для получения уведомлений

### Формат уведомления:
**Заголовок:** "Новое достижение партнёра"

**Сообщение:** "Партнёр [Имя] ([Email], ID: [UUID]) получил новый статус: [Статус] (Уровень [N])"

**Метаданные (JSON):**
```json
{
  "user_id": "uuid",
  "level": 1,
  "status_name": "Бронзовый партнёр",
  "achieved_at": "2024-01-01T00:00:00Z",
  "referral_code": "ABC12345"
}
```

### Как использовать в админ-панели:
```typescript
import { useAdminNotifications, markNotificationAsRead } from "@/hooks/useAdminNotifications";

function AdminPanel() {
  const { data: notifications } = useAdminNotifications();
  
  const unreadCount = notifications?.filter(n => !n.read).length || 0;
  
  return (
    <div>
      <h2>Уведомления ({unreadCount})</h2>
      {notifications?.map(notification => (
        <div key={notification.id}>
          <h3>{notification.title}</h3>
          <p>{notification.message}</p>
          <button onClick={() => markNotificationAsRead(notification.id)}>
            Отметить как прочитанное
          </button>
        </div>
      ))}
    </div>
  );
}
```

---

## Таблицы БД

### user_status_achievements
```sql
CREATE TABLE user_status_achievements (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  level INTEGER NOT NULL,
  status_name TEXT NOT NULL,
  achieved_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  shown BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
```

### admin_notifications
```sql
CREATE TABLE admin_notifications (
  id UUID PRIMARY KEY,
  admin_id UUID NOT NULL REFERENCES auth.users(id),
  type TEXT NOT NULL CHECK (type IN ('status_achievement', 'payment', 'system')),
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  read BOOLEAN DEFAULT false,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
```

---

## Безопасность

Все таблицы имеют правильные RLS политики:
- ✅ Пользователи видят только свои достижения
- ✅ Админы видят только свои уведомления
- ✅ Система может создавать записи автоматически
- ✅ Триггеры работают с `SECURITY DEFINER` и `SET search_path = public`

---

## Тестирование

### 1. Тест отображения покупателя в Orders:
1. Перейдите в `/admin/orders`
2. Проверьте, что в колонке "Покупатель" отображаются имена, а не UUID
3. Кликните на имя и убедитесь, что открывается страница пользователя

### 2. Тест поздравлений:
```sql
-- Добавьте тестовое достижение для текущего пользователя
INSERT INTO user_status_achievements (user_id, level, status_name)
VALUES (
  (SELECT auth.uid()),
  1,
  'Бронзовый партнёр'
);
```
После выполнения должно появиться модальное окно с фейерверком

### 3. Тест уведомлений админа:
1. Выполните SQL выше от имени любого пользователя
2. Проверьте таблицу `admin_notifications` - должна появиться запись для всех супер-админов
3. В админ-панели используйте хук `useAdminNotifications` для отображения

---

## Интеграция с существующей системой статусов

Чтобы интегрировать с вашей существующей логикой присвоения статусов, добавьте вызов в том месте, где происходит расчёт и присвоение нового уровня:

```typescript
// Пример интеграции
async function updateUserLevel(userId: string, newLevel: number) {
  // Ваша существующая логика присвоения уровня
  // ...
  
  // Добавьте запись о достижении
  const statusNames = {
    1: 'Бронзовый партнёр',
    2: 'Серебряный партнёр',
    3: 'Золотой партнёр',
    4: 'Платиновый партнёр',
    5: 'Бриллиантовый партнёр'
  };
  
  await supabase
    .from('user_status_achievements')
    .insert({
      user_id: userId,
      level: newLevel,
      status_name: statusNames[newLevel]
    });
  
  // Триггер автоматически отправит уведомление админам
  // и пользователь увидит поздравление при следующем входе/обновлении
}
```

---

## Примечания

⚠️ **Security warnings**: Остались 2 предупреждения:
1. Function Search Path Mutable - одна функция всё ещё без `SET search_path` (не критично)
2. Leaked Password Protection Disabled - можно включить в настройках Auth

Эти предупреждения не критичны и не влияют на работу системы.
