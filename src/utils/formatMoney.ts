export function formatCents(cents: number, currency: string = 'USD'): string {
  const amount = cents / 100;
  
  return new Intl.NumberFormat('ru-RU', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  }).format(amount);
}

export function parseCentsInput(input: string): number {
  // Remove all non-numeric characters except decimal point
  const cleaned = input.replace(/[^\d.]/g, '');
  const amount = parseFloat(cleaned) || 0;
  return Math.round(amount * 100);
}
