/**
 * ВАЖНО: Все суммы в базе данных хранятся в ЦЕЛЫХ ТЕНГЕ (KZT), НЕ в центах!
 * Колонки с суффиксом _cents (amount_cents, threshold_cents и т.д.) - это историческое
 * название, которое сохранено для обратной совместимости.
 * 
 * НЕ ДЕЛИТЬ на 100 при отображении!
 * НЕ УМНОЖАТЬ на 100 при сохранении!
 */

/**
 * Форматирует сумму в KZT (тенге) для отображения.
 * Для KZT: amount уже в целых тенге, НЕ делить.
 * Для USD: amount в центах, делить на 100.
 */
export function formatKZT(amount: number, currency: string = 'KZT'): string {
  const displayAmount = currency === 'KZT' ? amount : amount / 100;
  
  return new Intl.NumberFormat('ru-RU', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 0,
    maximumFractionDigits: currency === 'KZT' ? 0 : 2
  }).format(displayAmount);
}

/**
 * @deprecated Используйте formatKZT вместо этой функции
 * Оставлена для обратной совместимости
 */
export function formatCents(amount: number, currency: string = 'KZT'): string {
  return formatKZT(amount, currency);
}

export function formatMoney(amount: number, currency: string = 'KZT'): string {
  return new Intl.NumberFormat('ru-RU', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: currency === 'KZT' ? 0 : 2,
    maximumFractionDigits: currency === 'KZT' ? 0 : 2
  }).format(amount);
}

/**
 * Парсит строковый ввод в целое число KZT.
 * Для KZT возвращает целое число (тенге).
 * Для USD умножает на 100 (центы).
 */
export function parseKZTInput(input: string, currency: string = 'KZT'): number {
  // Remove all non-numeric characters except decimal point
  const cleaned = input.replace(/[^\d.]/g, '');
  const amount = parseFloat(cleaned) || 0;
  
  // Для KZT возвращаем целое число (тенге), для USD умножаем на 100 (центы)
  if (currency === 'KZT') {
    return Math.round(amount);
  }
  return Math.round(amount * 100);
}

/**
 * @deprecated Используйте parseKZTInput вместо этой функции
 * Оставлена для обратной совместимости
 */
export function parseCentsInput(input: string, currency: string = 'KZT'): number {
  return parseKZTInput(input, currency);
}
