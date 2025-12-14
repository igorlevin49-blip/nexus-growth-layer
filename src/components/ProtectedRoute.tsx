import { Navigate } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';

interface ProtectedRouteProps {
  children: React.ReactNode;
  requireAdmin?: boolean;
  requireSuperAdmin?: boolean;
}

export const ProtectedRoute = ({ 
  children, 
  requireAdmin = false,
  requireSuperAdmin = false 
}: ProtectedRouteProps) => {
  const { user, userRole, loading } = useAuth();

  if (loading) {
    return null;
  }

  if (!user || !userRole) {
    return <Navigate to="/login" replace />;
  }

  if (requireSuperAdmin && userRole !== 'superadmin') {
    return <Navigate to="/" replace />;
  }

  if (requireAdmin && userRole !== 'admin' && userRole !== 'superadmin') {
    return <Navigate to="/" replace />;
  }

  return <>{children}</>;
};
