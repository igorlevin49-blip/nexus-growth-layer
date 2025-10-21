import { NetworkMember } from "@/hooks/useNetworkTree";

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
