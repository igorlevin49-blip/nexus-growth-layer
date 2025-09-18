import { useState } from "react";
import { Search, Filter, ShoppingCart, Grid, List } from "lucide-react";
import { ProductCard } from "@/components/Shop/ProductCard";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

const mockProducts = [
  {
    id: "1",
    name: "Premium Nutrition Pack",
    price: 85.50,
    originalPrice: 120.00,
    image: "https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=400&h=300&fit=crop",
    rating: 4.8,
    reviewCount: 124,
    isActivation: true,
    description: "Комплекс витаминов и минералов премиум класса для активного образа жизни"
  },
  {
    id: "2",
    name: "Energy Boost Formula",
    price: 45.00,
    image: "https://images.unsplash.com/photo-1544787219-7f47ccb76574?w=400&h=300&fit=crop",
    rating: 4.5,
    reviewCount: 89,
    isActivation: true,
    description: "Натуральный энергетический комплекс для повышения работоспособности"
  },
  {
    id: "3",
    name: "Wellness Tea Collection",
    price: 32.00,
    image: "https://images.unsplash.com/photo-1594631661960-abeb4cb2cd2c?w=400&h=300&fit=crop",
    rating: 4.7,
    reviewCount: 156,
    isActivation: false,
    description: "Эксклюзивная коллекция оздоровительных чаёв из органических трав"
  },
  {
    id: "4",
    name: "Skin Care Essentials",
    price: 67.50,
    originalPrice: 89.00,
    image: "https://images.unsplash.com/photo-1556228453-efd6c1ff04f6?w=400&h=300&fit=crop",
    rating: 4.9,
    reviewCount: 203,
    isActivation: true,
    description: "Профессиональный набор для ухода за кожей с натуральными компонентами"
  }
];

export default function Shop() {
  const [cartItems, setCartItems] = useState<string[]>([]);
  const [searchQuery, setSearchQuery] = useState("");
  const [viewMode, setViewMode] = useState<"grid" | "list">("grid");
  const [sortBy, setSortBy] = useState("name");

  const handleAddToCart = (productId: string) => {
    setCartItems(prev => [...prev, productId]);
  };

  const cartTotal = cartItems.reduce((total, itemId) => {
    const product = mockProducts.find(p => p.id === itemId);
    return total + (product?.price || 0);
  }, 0);

  const activationProducts = cartItems.filter(itemId => {
    const product = mockProducts.find(p => p.id === itemId);
    return product?.isActivation;
  });

  const isActivationValid = activationProducts.reduce((total, itemId) => {
    const product = mockProducts.find(p => p.id === itemId);
    return total + (product?.price || 0);
  }, 0) >= 40;

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold">Магазин товаров</h1>
          <p className="text-muted-foreground">
            Выберите товары для покупки и активации
          </p>
        </div>
        
        {cartItems.length > 0 && (
          <Card className="financial-card">
            <CardContent className="p-4">
              <div className="flex items-center space-x-4">
                <ShoppingCart className="h-5 w-5 text-primary" />
                <div>
                  <p className="font-medium">Корзина: ${cartTotal.toFixed(2)}</p>
                  <p className="text-sm text-muted-foreground">
                    Товаров: {cartItems.length}
                  </p>
                </div>
                {!isActivationValid && (
                  <Badge className="pending-indicator">
                    Мин. активация: $40
                  </Badge>
                )}
                {isActivationValid && (
                  <Badge className="profit-indicator">
                    ✓ Активация
                  </Badge>
                )}
              </div>
            </CardContent>
          </Card>
        )}
      </div>

      {/* Filters and Search */}
      <Card className="financial-card">
        <CardContent className="p-4">
          <div className="flex flex-col md:flex-row gap-4">
            <div className="flex-1">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Поиск товаров..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="pl-10"
                />
              </div>
            </div>
            
            <div className="flex items-center space-x-2">
              <Select value={sortBy} onValueChange={setSortBy}>
                <SelectTrigger className="w-48">
                  <SelectValue placeholder="Сортировка" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="name">По названию</SelectItem>
                  <SelectItem value="price-low">Сначала дешёвые</SelectItem>
                  <SelectItem value="price-high">Сначала дорогие</SelectItem>
                  <SelectItem value="rating">По рейтингу</SelectItem>
                </SelectContent>
              </Select>

              <div className="flex items-center border border-border rounded-lg">
                <Button
                  variant={viewMode === "grid" ? "default" : "ghost"}
                  size="sm"
                  onClick={() => setViewMode("grid")}
                  className="rounded-r-none"
                >
                  <Grid className="h-4 w-4" />
                </Button>
                <Button
                  variant={viewMode === "list" ? "default" : "ghost"}
                  size="sm"
                  onClick={() => setViewMode("list")}
                  className="rounded-l-none"
                >
                  <List className="h-4 w-4" />
                </Button>
              </div>
            </div>
          </div>

          <div className="flex items-center space-x-2 mt-4">
            <Filter className="h-4 w-4 text-muted-foreground" />
            <Badge variant="outline">Все товары</Badge>
            <Badge className="profit-indicator">Активационные</Badge>
            <Badge variant="outline">Популярные</Badge>
            <Badge variant="outline">Новинки</Badge>
          </div>
        </CardContent>
      </Card>

      {/* Activation Info */}
      <Card className="border-primary/20 bg-primary/5">
        <CardHeader>
          <CardTitle className="text-primary">Информация об активации</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm mb-3">
            Для ежемесячной активации необходимо приобрести активационных товаров на сумму не менее $40.
          </p>
          <div className="flex items-center space-x-4 text-sm">
            <div className="flex items-center space-x-2">
              <Badge className="profit-indicator">✓</Badge>
              <span>Засчитывается в активацию</span>
            </div>
            <div className="flex items-center space-x-2">
              <Badge variant="outline">○</Badge>
              <span>Обычный товар</span>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Products Grid */}
      <div className={
        viewMode === "grid" 
          ? "grid gap-6 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
          : "space-y-4"
      }>
        {mockProducts.map((product) => (
          <ProductCard
            key={product.id}
            product={product}
            onAddToCart={handleAddToCart}
          />
        ))}
      </div>

      {/* Cart Summary */}
      {cartItems.length > 0 && (
        <Card className="financial-card border-primary/20">
          <CardHeader>
            <CardTitle>Корзина покупок</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              <div className="flex justify-between items-center">
                <span>Общая стоимость:</span>
                <span className="text-2xl font-bold">${cartTotal.toFixed(2)}</span>
              </div>
              
              <div className="flex justify-between items-center">
                <span>Активационные товары:</span>
                <span className="font-medium">
                  ${activationProducts.reduce((total, itemId) => {
                    const product = mockProducts.find(p => p.id === itemId);
                    return total + (product?.price || 0);
                  }, 0).toFixed(2)}
                </span>
              </div>

              {!isActivationValid && (
                <div className="bg-warning/10 border border-warning/20 rounded-lg p-3">
                  <p className="text-sm text-warning-foreground">
                    ⚠️ Добавьте активационных товаров на сумму не менее $40 для завершения месячной активации
                  </p>
                </div>
              )}

              <Button 
                className="w-full hero-gradient border-0" 
                size="lg"
                disabled={cartItems.length === 0}
              >
                Перейти к оплате
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}