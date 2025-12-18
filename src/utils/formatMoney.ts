export function formatCents(amount: number, currency: string = 'KZT'): string {
  // Для KZT amount - это уже целые тенге, НЕ делить
  // Для USD amount - это центы, делить на 100
  const displayAmount = currency === 'KZT' ? amount : amount / 100;
  
  return new Intl.NumberFormat('ru-RU', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 0,
    maximumFractionDigits: currency === 'KZT' ? 0 : 2
  }).format(displayAmount);
}

export function formatMoney(amount: number, currency: string = 'USD'): string {
  return new Intl.NumberFormat('ru-RU', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: currency === 'KZT' ? 0 : 2,
    maximumFractionDigits: currency === 'KZT' ? 0 : 2
  }).format(amount);
}

export function parseCentsInput(input: string, currency: string = 'KZT'): number {
  // Remove all non-numeric characters except decimal point
  const cleaned = input.replace(/[^\d.]/g, '');
  const amount = parseFloat(cleaned) || 0;
  
  // Для KZT возвращаем целое число (тенге), для USD умножаем на 100 (центы)
  if (currency === 'KZT') {
    return Math.round(amount);
  }
  return Math.round(amount * 100);
}
