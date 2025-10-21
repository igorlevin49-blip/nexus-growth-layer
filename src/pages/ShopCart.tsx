import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Trash2, Plus, Minus, ShoppingBag } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { useAuth } from "@/hooks/useAuth";

type Product = {
  id: string;
  title: string;
  price_usd: number;
  price_kzt: number;
  image_url: string | null;
  stock: number | null;
};

type CartItem = {
  productId: string;
  quantity: number;
};

export default function ShopCart() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [cartItems, setCartItems] = useState<CartItem[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [rate, setRate] = useState(450);

  useEffect(() => {
    loadCart();
    fetchProducts();
    fetchRate();
  }, []);

  const loadCart = () => {
    const savedCart = localStorage.getItem("cart");
    if (savedCart) {
      setCartItems(JSON.parse(savedCart));
    }
  };

  const saveCart = (items: CartItem[]) => {
    setCartItems(items);
    localStorage.setItem("cart", JSON.stringify(items));
  };

  const fetchProducts = async () => {
    try {
      const { data, error } = await supabase.from("products").select("*");
      if (error) throw error;
      setProducts(data || []);
    } catch (error) {
      console.error("Error fetching products:", error);
    } finally {
      setLoading(false);
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

  const handleUpdateQuantity = (productId: string, quantity: number) => {
    if (quantity <= 0) {
      handleRemoveItem(productId);
      return;
    }

    const product = products.find((p) => p.id === productId);
    if (product && product.stock !== null && quantity > product.stock) {
      toast({
        title: "Недостаточно товара",
        description: `В наличии только ${product.stock} шт.`,
        variant: "destructive",
      });
      return;
    }

    const updatedItems = cartItems.map((item) =>
      item.productId === productId ? { ...item, quantity } : item
    );
    saveCart(updatedItems);
  };

  const handleRemoveItem = (productId: string) => {
    const updatedItems = cartItems.filter((item) => item.productId !== productId);
    saveCart(updatedItems);
    toast({
      title: "Удалено из корзины",
    });
  };

  const handleClearCart = () => {
    saveCart([]);
    toast({
      title: "Корзина очищена",
    });
  };

  const handleCheckout = () => {
    if (!user) {
      toast({
        title: "Требуется авторизация",
        description: "Для оформления заказа необходимо войти в систему",
        variant: "destructive",
      });
      navigate("/login");
      return;
    }
    navigate("/shop/checkout");
  };

  const totalUsd = cartItems.reduce((sum, item) => {
    const product = products.find((p) => p.id === item.productId);
    return sum + (product ? product.price_usd * item.quantity : 0);
  }, 0);

  const totalKzt = totalUsd * rate;

  if (loading) {
    return (
      <div className="container mx-auto p-8">
        <div className="text-center">Загрузка...</div>
      </div>
    );
  }

  if (cartItems.length === 0) {
    return (
      <div className="container mx-auto p-8">
        <Card className="p-8 text-center">
          <ShoppingBag className="w-16 h-16 mx-auto mb-4 text-muted-foreground" />
          <h2 className="text-2xl font-bold mb-2">Корзина пуста</h2>
          <p className="text-muted-foreground mb-6">
            Добавьте товары, чтобы продолжить покупки
          </p>
          <Button onClick={() => navigate("/shop")}>
            Перейти в магазин
          </Button>
        </Card>
      </div>
    );
  }

  return (
    <div className="container mx-auto p-8">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-3xl font-bold">Корзина</h1>
        <Button variant="outline" onClick={() => navigate("/shop")}>
          Продолжить покупки
        </Button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between">
              <CardTitle>Товары в корзине</CardTitle>
              <Button variant="ghost" size="sm" onClick={handleClearCart}>
                Очистить корзину
              </Button>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {cartItems.map((item) => {
                  const product = products.find((p) => p.id === item.productId);
                  if (!product) return null;

                  return (
                    <div
                      key={item.productId}
                      className="flex gap-4 p-4 border rounded-lg"
                    >
                      <div className="w-20 h-20 bg-muted rounded flex items-center justify-center flex-shrink-0">
                        {product.image_url ? (
                          <img
                            src={product.image_url}
                            alt={product.title}
                            className="w-full h-full object-cover rounded"
                          />
                        ) : (
                          <ShoppingBag className="w-8 h-8 text-muted-foreground" />
                        )}
                      </div>
                      <div className="flex-1">
                        <h3 className="font-semibold mb-1">{product.title}</h3>
                        <div className="text-sm text-muted-foreground mb-2">
                          ${product.price_usd} / {product.price_kzt} ₸
                        </div>
                        <div className="flex items-center gap-2">
                          <Button
                            size="icon"
                            variant="outline"
                            onClick={() =>
                              handleUpdateQuantity(product.id, item.quantity - 1)
                            }
                          >
                            <Minus className="w-4 h-4" />
                          </Button>
                          <span className="w-12 text-center font-semibold">
                            {item.quantity}
                          </span>
                          <Button
                            size="icon"
                            variant="outline"
                            onClick={() =>
                              handleUpdateQuantity(product.id, item.quantity + 1)
                            }
                            disabled={
                              product.stock !== null &&
                              item.quantity >= product.stock
                            }
                          >
                            <Plus className="w-4 h-4" />
                          </Button>
                          <Button
                            size="icon"
                            variant="ghost"
                            onClick={() => handleRemoveItem(product.id)}
                            className="ml-auto"
                          >
                            <Trash2 className="w-4 h-4" />
                          </Button>
                        </div>
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
              <CardTitle>Итого</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                <div className="flex justify-between text-lg">
                  <span>Товаров:</span>
                  <span>{cartItems.reduce((sum, item) => sum + item.quantity, 0)}</span>
                </div>
                <div className="border-t pt-4">
                  <div className="flex justify-between text-2xl font-bold mb-2">
                    <span>Сумма:</span>
                    <span>${totalUsd.toFixed(2)}</span>
                  </div>
                  <div className="flex justify-between text-muted-foreground">
                    <span>В тенге:</span>
                    <span>{totalKzt.toFixed(2)} ₸</span>
                  </div>
                </div>
                <Button onClick={handleCheckout} className="w-full" size="lg">
                  Оформить заказ
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
