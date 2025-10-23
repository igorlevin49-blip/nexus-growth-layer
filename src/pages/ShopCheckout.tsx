import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { useAuth } from "@/hooks/useAuth";
import { CheckCircle } from "lucide-react";

type Product = {
  id: string;
  title: string;
  price_usd: number;
  price_kzt: number;
  is_activation: boolean;
};

type CartItem = {
  productId: string;
  quantity: number;
};

export default function ShopCheckout() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [cartItems, setCartItems] = useState<CartItem[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(false);
  const [rate, setRate] = useState(450);
  const [orderCompleted, setOrderCompleted] = useState(false);
  const [orderId, setOrderId] = useState<string | null>(null);

  useEffect(() => {
    if (!user) {
      navigate("/login");
      return;
    }
    loadCart();
    fetchProducts();
    fetchRate();
  }, [user, navigate]);

  const loadCart = () => {
    const savedCart = localStorage.getItem("cart");
    if (savedCart) {
      const items = JSON.parse(savedCart);
      if (items.length === 0) {
        navigate("/shop");
      }
      setCartItems(items);
    } else {
      navigate("/shop");
    }
  };

  const fetchProducts = async () => {
    try {
      const { data, error } = await supabase.from("products").select("*");
      if (error) throw error;
      setProducts(data || []);
    } catch (error) {
      console.error("Error fetching products:", error);
    }
  };

  const fetchRate = async () => {
    try {
      const { data, error } = await supabase
        .from("shop_settings")
        .select("rate_usd_kzt")
        .eq("id", 1)
        .single();
      if (error) throw error;
      if (data) setRate(Number(data.rate_usd_kzt));
    } catch (error) {
      console.error("Error fetching rate:", error);
    }
  };

  const handleCreateOrder = async () => {
    if (!user) return;

    setLoading(true);
    try {
      const totalUsd = cartItems.reduce((sum, item) => {
        const product = products.find((p) => p.id === item.productId);
        return sum + (product ? product.price_usd * item.quantity : 0);
      }, 0);

      const totalKzt = totalUsd * rate;

      // Create order
      const { data: order, error: orderError } = await supabase
        .from("orders")
        .insert({
          user_id: user.id,
          total_usd: totalUsd,
          total_kzt: totalKzt,
          status: "pending",
        })
        .select()
        .single();

      if (orderError) throw orderError;

      // Create order items
      const orderItems = cartItems.map((item) => {
        const product = products.find((p) => p.id === item.productId);
        return {
          order_id: order.id,
          product_id: item.productId,
          qty: item.quantity,
          price_usd: product?.price_usd || 0,
          price_kzt: product?.price_kzt || 0,
          is_activation_snapshot: product?.is_activation || false,
        };
      });

      const { error: itemsError } = await supabase
        .from("order_items")
        .insert(orderItems);

      if (itemsError) throw itemsError;

      setOrderId(order.id);
      toast.success("Заказ создан", {
        description: "Переходим к оплате...",
      });

      // Simulate payment (in real app, integrate with payment provider)
      setTimeout(() => handlePayment(order.id), 1000);
    } catch (error) {
      console.error("Error creating order:", error);
      toast.error("Ошибка", {
        description: "Не удалось создать заказ",
      });
    } finally {
      setLoading(false);
    }
  };

  const handlePayment = async (orderId: string) => {
    try {
      // Update order status to paid
      const { error } = await supabase
        .from("orders")
        .update({ status: "paid" })
        .eq("id", orderId);

      if (error) throw error;

      // Clear cart
      localStorage.removeItem("cart");
      setOrderCompleted(true);

      toast.success("Оплата успешна!", {
        description: "Спасибо за покупку",
      });
    } catch (error) {
      console.error("Error processing payment:", error);
      toast.error("Ошибка оплаты", {
        description: "Попробуйте еще раз",
      });
    }
  };

  const totalUsd = cartItems.reduce((sum, item) => {
    const product = products.find((p) => p.id === item.productId);
    return sum + (product ? product.price_usd * item.quantity : 0);
  }, 0);

  const totalKzt = totalUsd * rate;

  const activationTotal = cartItems.reduce((sum, item) => {
    const product = products.find((p) => p.id === item.productId);
    return sum + (product && product.is_activation ? product.price_usd * item.quantity : 0);
  }, 0);

  if (orderCompleted) {
    return (
      <div className="container mx-auto p-8">
        <Card className="max-w-2xl mx-auto p-8 text-center">
          <CheckCircle className="w-16 h-16 mx-auto mb-4 text-green-500" />
          <h2 className="text-2xl font-bold mb-2">Спасибо за покупку!</h2>
          <p className="text-muted-foreground mb-6">
            Ваш заказ успешно оформлен и оплачен
          </p>
          {activationTotal > 0 && (
            <p className="mb-6 text-lg">
              Активационные товары на сумму <strong>${activationTotal.toFixed(2)}</strong> учтены в вашем прогрессе
            </p>
          )}
          <div className="flex gap-4 justify-center">
            <Button onClick={() => navigate("/shop")}>
              Вернуться в магазин
            </Button>
            <Button variant="outline" onClick={() => navigate("/dashboard")}>
              Перейти в профиль
            </Button>
          </div>
        </Card>
      </div>
    );
  }

  return (
    <div className="container mx-auto p-8">
      <h1 className="text-3xl font-bold mb-6">Оформление заказа</h1>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2">
          <Card>
            <CardHeader>
              <CardTitle>Товары в заказе</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {cartItems.map((item) => {
                  const product = products.find((p) => p.id === item.productId);
                  if (!product) return null;

                  return (
                    <div
                      key={item.productId}
                      className="flex justify-between items-center p-4 border rounded-lg"
                    >
                      <div>
                        <h3 className="font-semibold">{product.title}</h3>
                        <p className="text-sm text-muted-foreground">
                          Количество: {item.quantity}
                        </p>
                        {product.is_activation && (
                          <span className="text-xs bg-primary/10 text-primary px-2 py-1 rounded mt-1 inline-block">
                            Активационный
                          </span>
                        )}
                      </div>
                      <div className="text-right">
                        <div className="font-bold">
                          ${(product.price_usd * item.quantity).toFixed(2)}
                        </div>
                        <div className="text-sm text-muted-foreground">
                          {(product.price_kzt * item.quantity).toFixed(2)} ₸
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </CardContent>
          </Card>
        </div>

        <div>
          <Card>
            <CardHeader>
              <CardTitle>Итого к оплате</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {activationTotal > 0 && (
                  <div className="bg-primary/10 p-4 rounded-lg">
                    <p className="text-sm font-medium">Активационные товары</p>
                    <p className="text-2xl font-bold text-primary">
                      ${activationTotal.toFixed(2)}
                    </p>
                  </div>
                )}
                <div className="border-t pt-4">
                  <div className="flex justify-between text-2xl font-bold mb-2">
                    <span>Итого:</span>
                    <span>${totalUsd.toFixed(2)}</span>
                  </div>
                  <div className="flex justify-between text-muted-foreground">
                    <span>В тенге:</span>
                    <span>{totalKzt.toFixed(2)} ₸</span>
                  </div>
                </div>
                <Button
                  onClick={handleCreateOrder}
                  className="w-full"
                  size="lg"
                  disabled={loading}
                >
                  {loading ? "Обработка..." : "Оплатить заказ"}
                </Button>
                <Button
                  variant="outline"
                  onClick={() => navigate("/shop/cart")}
                  className="w-full"
                  disabled={loading}
                >
                  Вернуться к корзине
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
