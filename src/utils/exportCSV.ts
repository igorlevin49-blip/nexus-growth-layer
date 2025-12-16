import { NetworkMember } from "@/hooks/useNetworkTree";
import { ActivationReportItem } from "@/hooks/useMonthlyActivations";
import { format } from "date-fns";
import { ru } from "date-fns/locale";

export function downloadCSV(data: any[], filename: string) {
  if (!data || data.length === 0) return;
  
  const headers = Object.keys(data[0]);
  const rows = data.map(row => headers.map(h => row[h]));
  
  const csvContent = [
    headers.join(','),
    ...rows.map(row => row.map(cell => `"${cell}"`).join(','))
  ].join('\n');

  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const link = document.createElement('a');
  const url = URL.createObjectURL(blob);
  
  link.setAttribute('href', url);
  link.setAttribute('download', filename);
  link.style.visibility = 'hidden';
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}

export function exportNetworkToCSV(members: NetworkMember[], filename: string = 'network-export.csv') {
  const headers = [
    'Name',
    'Email',
    'Level',
    'Status',
    'Sponsor Email',
    'Registered At',
    'Last Activation Amount',
    'Team Size'
  ];

  const rows = members.map(member => [
    member.full_name || 'N/A',
    member.email || 'N/A',
    member.level.toString(),
    member.subscription_status || 'inactive',
    '', // sponsor_email would require additional query
    new Date(member.created_at).toLocaleDateString(),
    member.monthly_volume.toFixed(2),
    member.total_team.toString()
  ]);

  const csvContent = [
    headers.join(','),
    ...rows.map(row => row.map(cell => `"${cell}"`).join(','))
  ].join('\n');

  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const link = document.createElement('a');
  const url = URL.createObjectURL(blob);
  
  link.setAttribute('href', url);
  link.setAttribute('download', filename);
  link.style.visibility = 'hidden';
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}

export function exportActivationsToCSV(
  data: ActivationReportItem[], 
  month: number, 
  year: number,
  filename?: string
) {
  if (!data || data.length === 0) return;

  const monthNames = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
  ];

  const headers = [
    'ФИО',
    'Email',
    'Реферальный код',
    'Сумма (KZT)',
    'Порог (KZT)',
    'Статус',
    'Дата начала активации',
    'Последний заказ',
    'Кол-во заказов'
  ];

  const rows = data.map(item => [
    item.full_name || 'Без имени',
    item.email || '',
    item.referral_code || '',
    item.total_amount_kzt.toString(),
    item.threshold_kzt.toString(),
    item.is_activated ? 'Активирован' : 'Не активирован',
    item.activation_due_from 
      ? format(new Date(item.activation_due_from), 'dd.MM.yyyy', { locale: ru })
      : '',
    item.last_order_date 
      ? format(new Date(item.last_order_date), 'dd.MM.yyyy HH:mm', { locale: ru })
      : '',
    item.orders_count.toString()
  ]);

  const csvContent = '\uFEFF' + [
    headers.join(';'),
    ...rows.map(row => row.map(cell => `"${cell}"`).join(';'))
  ].join('\n');

  const defaultFilename = `activations_${monthNames[month - 1]}_${year}.csv`;
  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const link = document.createElement('a');
  const url = URL.createObjectURL(blob);
  
  link.setAttribute('href', url);
  link.setAttribute('download', filename || defaultFilename);
  link.style.visibility = 'hidden';
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}