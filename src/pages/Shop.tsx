import { useState, useEffect } from "react";
import { useSearchParams } from "react-router-dom";
import { Search, Grid, List, ShoppingCart } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { supabase } from "@/integrations/supabase/client";
import { ProductCard } from "@/components/Shop/ProductCard";
import { toast } from "@/hooks/use-toast";
import { useAuth } from "@/hooks/useAuth";

type Product = {
  id: string;
  title: string;
  slug: string;
  description: string | null;
  price_usd: number;
  price_kzt: number;
  is_activation: boolean;
  is_popular: boolean;
  is_new: boolean;
  image_url: string | null;
  stock: number | null;
  created_at?: string;
};

type CartItem = {
  productId: string;
  quantity: number;
};

type FilterType = "all" | "activation" | "popular" | "new";

export default function Shop() {
  const [searchParams, setSearchParams] = useSearchParams();
  const { user } = useAuth();
  
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [cartItems, setCartItems] = useState<CartItem[]>([]);
  const [searchQuery, setSearchQuery] = useState(searchParams.get("search") || "");
  const [viewMode, setViewMode] = useState<"grid" | "list">((searchParams.get("view") as "grid" | "list") || "grid");
  const [sortBy, setSortBy] = useState(searchParams.get("sort") || "title-asc");
  const [filter, setFilter] = useState<FilterType>((searchParams.get("filter") as FilterType) || "all");

  // Load cart from localStorage
  useEffect(() => {
    const savedCart = localStorage.getItem("cart");
    if (savedCart) {
      setCartItems(JSON.parse(savedCart));
    }
  }, []);

  // Save cart to localStorage
  useEffect(() => {
    localStorage.setItem("cart", JSON.stringify(cartItems));
  }, [cartItems]);

  // Load products
  useEffect(() => {
    fetchProducts();
  }, []);

  // Update URL params
  useEffect(() => {
    const params: Record<string, string> = {};
    if (searchQuery) params.search = searchQuery;
    if (viewMode !== "grid") params.view = viewMode;
    if (sortBy !== "title-asc") params.sort = sortBy;
    if (filter !== "all") params.filter = filter;
    setSearchParams(params);
  }, [searchQuery, viewMode, sortBy, filter, setSearchParams]);

  const fetchProducts = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from("products")
        .select("*")
        .order("created_at", { ascending: false });

      if (error) throw error;
      setProducts(data || []);
    } catch (error) {
      console.error("Error fetching products:", error);
      toast({
        title: "Ошибка",
        description: "Не удалось загрузить товары",
        variant: "destructive",
      });
    } finally {
      setLoading(false);
    }
  };

  const handleAddToCart = (productId: string) => {
    const product = products.find((p) => p.id === productId);
    if (!product) return;

    const existingItem = cartItems.find((item) => item.productId === productId);
    const currentQty = existingItem ? existingItem.quantity : 0;

    if (product.stock !== null && currentQty >= product.stock) {
      toast({
        title: "Недостаточно товара",
        description: `В наличии только ${product.stock} шт.`,
        variant: "destructive",
      });
      return;
    }

    if (existingItem) {
      setCartItems(
        cartItems.map((item) =>
          item.productId === productId
            ? { ...item, quantity: item.quantity + 1 }
            : item
        )
      );
    } else {
      setCartItems([...cartItems, { productId, quantity: 1 }]);
    }

    toast({
      title: "Добавлено в корзину",
      description: product.title,
    });
  };

  const handleRemoveFromCart = (productId: string) => {
    setCartItems(cartItems.filter((item) => item.productId !== productId));
  };

  const handleUpdateQuantity = (productId: string, quantity: number) => {
    if (quantity <= 0) {
      handleRemoveFromCart(productId);
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

    setCartItems(
      cartItems.map((item) =>
        item.productId === productId ? { ...item, quantity } : item
      )
    );
  };

  // Filter products
  let filteredProducts = products;

  if (filter === "activation") {
    filteredProducts = filteredProducts.filter((p) => p.is_activation);
  } else if (filter === "popular") {
    filteredProducts = filteredProducts.filter((p) => p.is_popular);
  } else if (filter === "new") {
    filteredProducts = filteredProducts.filter((p) => p.is_new);
  }

  if (searchQuery) {
    filteredProducts = filteredProducts.filter((p) =>
      p.title.toLowerCase().includes(searchQuery.toLowerCase())
    );
  }

  // Sort products
  filteredProducts = [...filteredProducts].sort((a, b) => {
    switch (sortBy) {
      case "title-asc":
        return a.title.localeCompare(b.title);
      case "title-desc":
        return b.title.localeCompare(a.title);
      case "price-asc":
        return a.price_usd - b.price_usd;
      case "price-desc":
        return b.price_usd - a.price_usd;
      case "date-new":
        return new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime();
      case "date-old":
        return new Date(a.created_at || 0).getTime() - new Date(b.created_at || 0).getTime();
      default:
        return 0;
    }
  });

  // Calculate cart totals
  const cartTotal = cartItems.reduce((sum, item) => {
    const product = products.find((p) => p.id === item.productId);
    return sum + (product ? product.price_usd * item.quantity : 0);
  }, 0);

  const cartItemsCount = cartItems.reduce((sum, item) => sum + item.quantity, 0);

  if (loading) {
    return (
      <div className="container mx-auto p-8">
        <div className="text-center">Загрузка...</div>
      </div>
    );
  }

  return (
    <div className="container mx-auto p-8">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-3xl font-bold">Магазин</h1>
        <Button
          onClick={() => window.location.href = "/shop/cart"}
          variant="outline"
          className="relative"
        >
          <ShoppingCart className="w-4 h-4 mr-2" />
          Корзина
          {cartItemsCount > 0 && (
            <Badge className="ml-2" variant="secondary">
              {cartItemsCount}
            </Badge>
          )}
        </Button>
      </div>

      {/* Filters */}
      <div className="flex gap-2 mb-6 flex-wrap">
        <Button
          variant={filter === "all" ? "default" : "outline"}
          onClick={() => setFilter("all")}
        >
          Все товары
        </Button>
        <Button
          variant={filter === "activation" ? "default" : "outline"}
          onClick={() => setFilter("activation")}
        >
          Активационные
        </Button>
        <Button
          variant={filter === "popular" ? "default" : "outline"}
          onClick={() => setFilter("popular")}
        >
          Популярные
        </Button>
        <Button
          variant={filter === "new" ? "default" : "outline"}
          onClick={() => setFilter("new")}
        >
          Новинки
        </Button>
      </div>

      {/* Search and controls */}
      <div className="flex gap-4 mb-6 flex-wrap items-center">
        <div className="flex-1 min-w-[250px]">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground w-4 h-4" />
            <Input
              placeholder="Поиск товаров..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10"
            />
          </div>
        </div>

        <Select value={sortBy} onValueChange={setSortBy}>
          <SelectTrigger className="w-[200px]">
            <SelectValue placeholder="Сортировка" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="title-asc">По названию (А-Я)</SelectItem>
            <SelectItem value="title-desc">По названию (Я-А)</SelectItem>
            <SelectItem value="price-asc">По цене (возр.)</SelectItem>
            <SelectItem value="price-desc">По цене (убыв.)</SelectItem>
            <SelectItem value="date-new">Сначала новые</SelectItem>
            <SelectItem value="date-old">Сначала старые</SelectItem>
          </SelectContent>
        </Select>

        <div className="flex gap-2">
          <Button
            variant={viewMode === "grid" ? "default" : "outline"}
            size="icon"
            onClick={() => setViewMode("grid")}
          >
            <Grid className="w-4 h-4" />
          </Button>
          <Button
            variant={viewMode === "list" ? "default" : "outline"}
            size="icon"
            onClick={() => setViewMode("list")}
          >
            <List className="w-4 h-4" />
          </Button>
        </div>
      </div>

      {/* Products */}
      {filteredProducts.length === 0 ? (
        <Card className="p-8 text-center">
          <p className="text-muted-foreground mb-4">Товары не найдены</p>
          {filter !== "all" && (
            <Button onClick={() => setFilter("all")}>
              Показать все товары
            </Button>
          )}
        </Card>
      ) : (
        <div
          className={
            viewMode === "grid"
              ? "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"
              : "flex flex-col gap-4"
          }
        >
          {filteredProducts.map((product) => (
            <ProductCard
              key={product.id}
              product={product}
              onAddToCart={handleAddToCart}
              viewMode={viewMode}
              cartQuantity={
                cartItems.find((item) => item.productId === product.id)
                  ?.quantity || 0
              }
              onUpdateQuantity={handleUpdateQuantity}
            />
          ))}
        </div>
      )}
    </div>
  );
}
