import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ShoppingCart, Plus, Minus, ImageOff } from "lucide-react";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Link } from "react-router-dom";

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
};

type ProductImage = {
  id: string;
  url: string;
  is_main: boolean;
};

interface ProductCardProps {
  product: Product;
  onAddToCart: (productId: string) => void;
  viewMode?: "grid" | "list";
  cartQuantity?: number;
  onUpdateQuantity?: (productId: string, quantity: number) => void;
}

export function ProductCard({ 
  product, 
  onAddToCart, 
  viewMode = "grid",
  cartQuantity = 0,
  onUpdateQuantity,
}: ProductCardProps) {
  const [productImages, setProductImages] = useState<ProductImage[]>([]);
  const [mainImage, setMainImage] = useState<string | null>(null);
  
  useEffect(() => {
    const fetchImages = async () => {
      const { data } = await supabase
        .from('product_images')
        .select('id, url, is_main')
        .eq('product_id', product.id)
        .order('display_order');
      
      if (data && data.length > 0) {
        setProductImages(data);
        const main = data.find(img => img.is_main);
        setMainImage(main ? main.url : data[0].url);
      } else if (product.image_url) {
        setMainImage(product.image_url);
      }
    };
    
    fetchImages();
  }, [product.id, product.image_url]);

  const isOutOfStock = product.stock !== null && product.stock === 0;

  const ImageDisplay = () => {
    if (mainImage) {
      return (
        <img
          src={mainImage}
          alt={product.title}
          className="w-full h-full object-cover"
        />
      );
    }
    return (
      <div className="flex flex-col items-center justify-center gap-2">
        <ImageOff className="w-12 h-12 text-muted-foreground" />
        <span className="text-sm text-muted-foreground">Нет изображения</span>
      </div>
    );
  };

  if (viewMode === "list") {
    return (
      <Card className="overflow-hidden hover:shadow-lg transition-shadow">
        <div className="flex flex-col md:flex-row">
          <Link to={`/product/${product.slug}`} className="md:w-48 h-48 bg-muted flex items-center justify-center">
            <ImageDisplay />
          </Link>
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
                <Link to={`/product/${product.slug}`}>
                  <h3 className="text-xl font-semibold mb-2 hover:text-primary transition-colors">{product.title}</h3>
                </Link>
                {product.description && (
                  <p className="text-muted-foreground mb-4">{product.description}</p>
                )}
                <div className="flex gap-4">
                  <div>
                    <span className="text-2xl font-bold">{product.price_kzt.toLocaleString('ru-RU')} ₸</span>
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
    <Card className="overflow-hidden flex flex-col hover:shadow-lg transition-shadow">
      <Link to={`/product/${product.slug}`} className="aspect-square bg-muted flex items-center justify-center">
        <ImageDisplay />
      </Link>
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
        <Link to={`/product/${product.slug}`}>
          <h3 className="font-semibold text-lg hover:text-primary transition-colors">{product.title}</h3>
        </Link>
      </CardHeader>
      <CardContent className="flex-1 flex flex-col">
        {product.description && (
          <p className="text-sm text-muted-foreground mb-4 line-clamp-2">
            {product.description}
          </p>
        )}
        <div className="mb-4">
          <div className="text-2xl font-bold">{product.price_kzt.toLocaleString('ru-RU')} ₸</div>
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