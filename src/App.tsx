import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { AppLayout } from "@/components/Layout/AppLayout";
import { AuthProvider } from "@/hooks/useAuth";
import { useReferralBind } from "@/hooks/useReferralBind";
import { useReferralCapture } from "@/hooks/useReferralCapture";
import { ProtectedRoute } from "@/components/ProtectedRoute";
import Index from "./pages/Index";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import Shop from "./pages/Shop";
import Network from "./pages/Network";
import Finances from "./pages/Finances";
import Settings from "./pages/Settings";
import Register from "./pages/Register";
import AdminUsers from "./pages/admin/Users";
import AdminReports from "./pages/admin/Reports";
import RoleManagement from "./pages/admin/RoleManagement";
import Products from "./pages/admin/Products";
import Orders from "./pages/admin/Orders";
import ShopSettings from "./pages/admin/ShopSettings";
import MLMSettings from "./pages/admin/MLMSettings";
import AdminPayments from "./pages/admin/Payments";
import ShopCart from "./pages/ShopCart";
import ShopCheckout from "./pages/ShopCheckout";
import NotFound from "./pages/NotFound";
import Docs from "./pages/Docs";
import DocView from "./pages/DocView";
import Documents from "./pages/admin/Documents";
import TestDataCleanup from "./pages/admin/TestDataCleanup";
import ProductDetail from "./pages/ProductDetail";

import ForgotPassword from "./pages/ForgotPassword";
import ResetPassword from "./pages/ResetPassword";

const queryClient = new QueryClient();

function AppContent() {
  useReferralCapture(); // Capture ?ref= from any route
  useReferralBind(); // Auto-bind referral from cookie on first login
  return (
    <Routes>
            <Route path="/" element={<Index />} />
            <Route path="/login" element={<Login />} />
            <Route path="/register" element={<Register />} />
            <Route path="/forgot-password" element={<ForgotPassword />} />
            <Route path="/reset-password" element={<ResetPassword />} />
            <Route path="/docs" element={<Docs />} />
            <Route path="/docs/:slug" element={<DocView />} />
            <Route path="/product/:slug" element={<ProductDetail />} />
            <Route path="/" element={<ProtectedRoute><AppLayout /></ProtectedRoute>}>
              <Route path="dashboard" element={<Dashboard />} />
              <Route path="shop" element={<Shop />} />
              <Route path="network" element={<Network />} />
              <Route path="finances" element={<Finances />} />
              <Route path="settings" element={<Settings />} />
              <Route path="admin/users" element={<ProtectedRoute requireAdmin><AdminUsers /></ProtectedRoute>} />
              <Route path="admin/products" element={<ProtectedRoute requireAdmin><Products /></ProtectedRoute>} />
              <Route path="admin/orders" element={<ProtectedRoute requireAdmin><Orders /></ProtectedRoute>} />
              <Route path="admin/shop-settings" element={<ProtectedRoute requireSuperAdmin><ShopSettings /></ProtectedRoute>} />
              <Route path="admin/mlm-settings" element={<ProtectedRoute requireSuperAdmin><MLMSettings /></ProtectedRoute>} />
              <Route path="admin/payments" element={<ProtectedRoute requireAdmin><AdminPayments /></ProtectedRoute>} />
              <Route path="shop/cart" element={<ShopCart />} />
              <Route path="shop/checkout" element={<ShopCheckout />} />
              <Route path="admin/reports" element={<ProtectedRoute requireAdmin><AdminReports /></ProtectedRoute>} />
              <Route path="admin/roles" element={<ProtectedRoute requireSuperAdmin><RoleManagement /></ProtectedRoute>} />
              <Route path="admin/documents" element={<ProtectedRoute requireAdmin><Documents /></ProtectedRoute>} />
              <Route path="admin/test-data-cleanup" element={<ProtectedRoute requireSuperAdmin><TestDataCleanup /></ProtectedRoute>} />
            </Route>
            {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
            <Route path="*" element={<NotFound />} />
          </Routes>
  );
}

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <AuthProvider>
          <AppContent />
        </AuthProvider>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
