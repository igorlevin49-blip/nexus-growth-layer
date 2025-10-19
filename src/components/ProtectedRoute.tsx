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
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
      </div>
    );
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
