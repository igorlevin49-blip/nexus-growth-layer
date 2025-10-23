import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ShoppingCart, Plus, Minus } from "lucide-react";

type Product = {
  id: string;
  title: string;
  description: string | null;
  price_usd: number;
  price_kzt: number;
  is_activation: boolean;
  is_popular: boolean;
  is_new: boolean;
  image_url: string | null;
  stock: number | null;
};

interface ProductCardProps {
  product: Product;
  onAddToCart: (productId: string) => void;
  viewMode?: "grid" | "list";
  cartQuantity?: number;
  onUpdateQuantity?: (productId: string, quantity: number) => void;
  currency?: "USD" | "KZT";
}

export function ProductCard({ 
  product, 
  onAddToCart, 
  viewMode = "grid",
  cartQuantity = 0,
  onUpdateQuantity,
  currency = "USD"
}: ProductCardProps) {
  const isOutOfStock = product.stock !== null && product.stock === 0;
  
  const displayPrice = currency === "USD" ? product.price_usd : product.price_kzt;
  const displayCurrencySymbol = currency === "USD" ? "$" : "₸";
  const secondaryPrice = currency === "USD" ? product.price_kzt : product.price_usd;
  const secondaryCurrencySymbol = currency === "USD" ? "₸" : "$";

  if (viewMode === "list") {
    return (
      <Card className="overflow-hidden">
        <div className="flex flex-col md:flex-row">
          <div className="md:w-48 h-48 bg-muted flex items-center justify-center">
            {product.image_url ? (
              <img
                src={product.image_url}
                alt={product.title}
                className="w-full h-full object-cover"
              />
            ) : (
              <ShoppingCart className="w-12 h-12 text-muted-foreground" />
            )}
          </div>
          <div className="flex-1 p-6">
            <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-4">
              <div className="flex-1">
                <div className="flex gap-2 mb-2 flex-wrap">
                  {product.is_activation && (
                    <Badge variant="default">Активационный</Badge>
                  )}
                  {product.is_popular && (
                    <Badge variant="secondary">Популярный</Badge>
                  )}
                  {product.is_new && (
                    <Badge variant="outline">Новинка</Badge>
                  )}
                  {isOutOfStock && (
                    <Badge variant="destructive">Нет в наличии</Badge>
                  )}
                </div>
                <h3 className="text-xl font-semibold mb-2">{product.title}</h3>
                {product.description && (
                  <p className="text-muted-foreground mb-4">{product.description}</p>
                )}
                <div className="flex gap-4">
                  <div>
                    <span className="text-2xl font-bold">{displayCurrencySymbol}{displayPrice}</span>
                  </div>
                  <div className="text-muted-foreground">
                    <span className="text-lg">{secondaryCurrencySymbol}{secondaryPrice}</span>
                  </div>
                </div>
                {product.stock !== null && product.stock > 0 && (
                  <p className="text-sm text-muted-foreground mt-2">
                    В наличии: {product.stock} шт.
                  </p>
                )}
              </div>
              <div className="flex flex-col gap-2 items-end">
                {cartQuantity > 0 && onUpdateQuantity ? (
                  <div className="flex items-center gap-2">
                    <Button
                      size="icon"
                      variant="outline"
                      onClick={() => onUpdateQuantity(product.id, cartQuantity - 1)}
                    >
                      <Minus className="w-4 h-4" />
                    </Button>
                    <span className="w-12 text-center font-semibold">{cartQuantity}</span>
                    <Button
                      size="icon"
                      variant="outline"
                      onClick={() => onUpdateQuantity(product.id, cartQuantity + 1)}
                      disabled={product.stock !== null && cartQuantity >= product.stock}
                    >
                      <Plus className="w-4 h-4" />
                    </Button>
                  </div>
                ) : (
                  <Button
                    onClick={() => onAddToCart(product.id)}
                    disabled={isOutOfStock}
                    className="w-full md:w-auto"
                  >
                    <ShoppingCart className="w-4 h-4 mr-2" />
                    {isOutOfStock ? "Нет в наличии" : "В корзину"}
                  </Button>
                )}
              </div>
            </div>
          </div>
        </div>
      </Card>
    );
  }

  return (
    <Card className="overflow-hidden flex flex-col">
      <div className="aspect-square bg-muted flex items-center justify-center">
        {product.image_url ? (
          <img
            src={product.image_url}
            alt={product.title}
            className="w-full h-full object-cover"
          />
        ) : (
          <ShoppingCart className="w-12 h-12 text-muted-foreground" />
        )}
      </div>
      <CardHeader>
        <div className="flex gap-2 mb-2 flex-wrap">
          {product.is_activation && (
            <Badge variant="default">Активационный</Badge>
          )}
          {product.is_popular && (
            <Badge variant="secondary">Популярный</Badge>
          )}
          {product.is_new && (
            <Badge variant="outline">Новинка</Badge>
          )}
          {isOutOfStock && (
            <Badge variant="destructive">Нет в наличии</Badge>
          )}
        </div>
        <h3 className="font-semibold text-lg">{product.title}</h3>
      </CardHeader>
      <CardContent className="flex-1 flex flex-col">
        {product.description && (
          <p className="text-sm text-muted-foreground mb-4 line-clamp-2">
            {product.description}
          </p>
        )}
        <div className="mb-4">
          <div className="text-2xl font-bold">{displayCurrencySymbol}{displayPrice}</div>
          <div className="text-sm text-muted-foreground">{secondaryCurrencySymbol}{secondaryPrice}</div>
        </div>
        {product.stock !== null && product.stock > 0 && (
          <p className="text-xs text-muted-foreground mb-4">
            В наличии: {product.stock} шт.
          </p>
        )}
        <div className="mt-auto">
          {cartQuantity > 0 && onUpdateQuantity ? (
            <div className="flex items-center gap-2">
              <Button
                size="icon"
                variant="outline"
                onClick={() => onUpdateQuantity(product.id, cartQuantity - 1)}
              >
                <Minus className="w-4 h-4" />
              </Button>
              <span className="flex-1 text-center font-semibold">{cartQuantity}</span>
              <Button
                size="icon"
                variant="outline"
                onClick={() => onUpdateQuantity(product.id, cartQuantity + 1)}
                disabled={product.stock !== null && cartQuantity >= product.stock}
              >
                <Plus className="w-4 h-4" />
              </Button>
            </div>
          ) : (
            <Button
              onClick={() => onAddToCart(product.id)}
              disabled={isOutOfStock}
              className="w-full"
            >
              <ShoppingCart className="w-4 h-4 mr-2" />
              {isOutOfStock ? "Нет в наличии" : "В корзину"}
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
