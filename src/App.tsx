import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { AppLayout } from "@/components/Layout/AppLayout";
import { AuthProvider } from "@/hooks/useAuth";
import { ProtectedRoute } from "@/components/ProtectedRoute";
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
import ShopCart from "./pages/ShopCart";
import ShopCheckout from "./pages/ShopCheckout";
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <AuthProvider>
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route path="/register" element={<Register />} />
            <Route path="/" element={<ProtectedRoute><AppLayout /></ProtectedRoute>}>
              <Route index element={<Dashboard />} />
              <Route path="dashboard" element={<Dashboard />} />
              <Route path="shop" element={<Shop />} />
              <Route path="network" element={<Network />} />
              <Route path="finances" element={<Finances />} />
              <Route path="settings" element={<Settings />} />
              <Route path="admin/users" element={<ProtectedRoute requireAdmin><AdminUsers /></ProtectedRoute>} />
              <Route path="admin/products" element={<ProtectedRoute requireAdmin><Products /></ProtectedRoute>} />
              <Route path="admin/orders" element={<ProtectedRoute requireAdmin><Orders /></ProtectedRoute>} />
              <Route path="admin/shop-settings" element={<ProtectedRoute requireSuperAdmin><ShopSettings /></ProtectedRoute>} />
              <Route path="shop/cart" element={<ShopCart />} />
              <Route path="shop/checkout" element={<ShopCheckout />} />
              <Route path="admin/reports" element={<ProtectedRoute requireAdmin><AdminReports /></ProtectedRoute>} />
              <Route path="admin/roles" element={<ProtectedRoute requireSuperAdmin><RoleManagement /></ProtectedRoute>} />
            </Route>
            {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
            <Route path="*" element={<NotFound />} />
          </Routes>
        </AuthProvider>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
