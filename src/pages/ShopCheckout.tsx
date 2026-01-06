import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Label } from "@/components/ui/label";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { useAuth } from "@/hooks/useAuth";
import { CheckCircle, CreditCard, Building2, Wallet, Banknote } from "lucide-react";

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
  const [orderCompleted, setOrderCompleted] = useState(false);
  const [orderId, setOrderId] = useState<string | null>(null);
  const [paymentType, setPaymentType] = useState<"online" | "manual" | "cash">("online");

  useEffect(() => {
    if (!user) {
      navigate("/login");
      return;
    }
    loadCart();
    fetchProducts();
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

  const handleCreateOrder = async () => {
    if (!user) return;

    setLoading(true);
    try {
      const totalUsd = cartItems.reduce((sum, item) => {
        const product = products.find((p) => p.id === item.productId);
        return sum + (product ? product.price_usd * item.quantity : 0);
      }, 0);

      // Use actual KZT prices from products, not converted from USD
      const totalKzt = cartItems.reduce((sum, item) => {
        const product = products.find((p) => p.id === item.productId);
        return sum + (product ? product.price_kzt * item.quantity : 0);
      }, 0);

      // Create order with selected payment type
      const { data: order, error: orderError } = await supabase
        .from("orders")
        .insert({
          user_id: user.id,
          total_usd: totalUsd,
          total_kzt: totalKzt,
          status: "pending",
          payment_type: paymentType
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
      
      // Show appropriate message based on payment type
      const messages = {
        online: "Ожидается оплата онлайн",
        manual: "Загрузите чек после оплаты переводом",
        cash: "Оплатите наличными в кассе офиса"
      };
      
      toast.info("Заказ создан", {
        description: messages[paymentType],
      });

      // Clear cart and show success
      localStorage.removeItem("cart");
      setOrderCompleted(true);
      
    } catch (error) {
      console.error("Error creating order:", error);
      toast.error("Ошибка", {
        description: "Не удалось создать заказ",
      });
    } finally {
      setLoading(false);
    }
  };

  const totalKzt = cartItems.reduce((sum, item) => {
    const product = products.find((p) => p.id === item.productId);
    return sum + (product ? product.price_kzt * item.quantity : 0);
  }, 0);

  const activationTotal = cartItems.reduce((sum, item) => {
    const product = products.find((p) => p.id === item.productId);
    if (!product || !product.is_activation) return sum;
    return sum + product.price_kzt * item.quantity;
  }, 0);

  if (orderCompleted) {
    const completionMessages = {
      online: "Ожидается оплата. После оплаты заказ будет обработан.",
      manual: "Оплатите заказ переводом и загрузите чек в личном кабинете для подтверждения.",
      cash: "Оплатите заказ наличными в кассе нашего офиса. После оплаты заказ будет обработан."
    };

    return (
      <div className="container mx-auto p-8">
        <Card className="max-w-2xl mx-auto p-8 text-center">
          <CheckCircle className="w-16 h-16 mx-auto mb-4 text-yellow-500" />
          <h2 className="text-2xl font-bold mb-2">Заказ создан!</h2>
          <p className="text-muted-foreground mb-6">
            {completionMessages[paymentType]}
          </p>
          {activationTotal > 0 && (
            <p className="mb-6 text-lg">
              Активационные товары на сумму <strong>{activationTotal.toLocaleString('ru-RU')} ₸</strong> будут учтены после одобрения
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
        <div className="lg:col-span-2 space-y-6">
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
                          {(product.price_kzt * item.quantity).toLocaleString('ru-RU')} ₸
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </CardContent>
          </Card>

          {/* Payment Method Selection */}
          <Card>
            <CardHeader>
              <CardTitle>Способ оплаты</CardTitle>
            </CardHeader>
            <CardContent>
              <RadioGroup value={paymentType} onValueChange={(v) => setPaymentType(v as any)} className="space-y-3">
                <div className="flex items-center space-x-3 p-4 border rounded-lg cursor-pointer hover:bg-muted/50" onClick={() => setPaymentType("online")}>
                  <RadioGroupItem value="online" id="online" />
                  <CreditCard className="h-5 w-5 text-primary" />
                  <Label htmlFor="online" className="flex-1 cursor-pointer">
                    <div className="font-medium">Оплата онлайн</div>
                    <div className="text-sm text-muted-foreground">Банковской картой через платёжную систему</div>
                  </Label>
                </div>
                
                <div className="flex items-center space-x-3 p-4 border rounded-lg cursor-pointer hover:bg-muted/50" onClick={() => setPaymentType("manual")}>
                  <RadioGroupItem value="manual" id="manual" />
                  <Building2 className="h-5 w-5 text-primary" />
                  <Label htmlFor="manual" className="flex-1 cursor-pointer">
                    <div className="font-medium">Перевод на реквизиты</div>
                    <div className="text-sm text-muted-foreground">Банковский перевод с загрузкой чека</div>
                  </Label>
                </div>
                
                <div className="flex items-center space-x-3 p-4 border rounded-lg cursor-pointer hover:bg-muted/50" onClick={() => setPaymentType("cash")}>
                  <RadioGroupItem value="cash" id="cash" />
                  <Banknote className="h-5 w-5 text-primary" />
                  <Label htmlFor="cash" className="flex-1 cursor-pointer">
                    <div className="font-medium">Наличными в кассе</div>
                    <div className="text-sm text-muted-foreground">Оплата наличными в офисе компании</div>
                  </Label>
                </div>
              </RadioGroup>
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
                      {activationTotal.toLocaleString('ru-RU')} ₸
                    </p>
                  </div>
                )}
                <div className="border-t pt-4">
                  <div className="flex justify-between text-2xl font-bold mb-2">
                    <span>Итого:</span>
                    <span>{totalKzt.toLocaleString('ru-RU')} ₸</span>
                  </div>
                </div>
                <Button
                  onClick={handleCreateOrder}
                  className="w-full"
                  size="lg"
                  disabled={loading}
                >
                  {loading ? "Обработка..." : "Оформить заказ"}
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
