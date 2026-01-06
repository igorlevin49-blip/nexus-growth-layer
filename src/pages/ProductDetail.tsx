import { useParams, Link, useNavigate } from 'react-router-dom';
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { ArrowLeft, ShoppingCart, ImageOff, Package, Info } from 'lucide-react';
import { Helmet } from 'react-helmet';
import { toast } from 'sonner';
import { useAuth } from '@/hooks/useAuth';
import { Alert, AlertDescription } from '@/components/ui/alert';

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
  created_at: string;
};

type ProductImage = {
  id: string;
  url: string;
  is_main: boolean;
  display_order: number;
};

type CartItem = {
  productId: string;
  quantity: number;
};

export default function ProductDetail() {
  const { slug } = useParams<{ slug: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [product, setProduct] = useState<Product | null>(null);
  const [images, setImages] = useState<ProductImage[]>([]);
  const [selectedImage, setSelectedImage] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [cartItems, setCartItems] = useState<CartItem[]>([]);

  // Load cart from localStorage
  useEffect(() => {
    const savedCart = localStorage.getItem('cart');
    if (savedCart) {
      setCartItems(JSON.parse(savedCart));
    }
  }, []);

  // Fetch product
  useEffect(() => {
    if (slug) {
      fetchProduct();
    }
  }, [slug]);

  const fetchProduct = async () => {
    try {
      setLoading(true);
      const { data: productData, error: productError } = await supabase
        .from('products')
        .select('*')
        .eq('slug', slug)
        .single();

      if (productError) throw productError;
      if (!productData) {
        navigate('/404');
        return;
      }

      setProduct(productData);

      // Fetch images
      const { data: imagesData } = await supabase
        .from('product_images')
        .select('*')
        .eq('product_id', productData.id)
        .order('display_order');

      if (imagesData && imagesData.length > 0) {
        setImages(imagesData);
        const mainImage = imagesData.find(img => img.is_main);
        setSelectedImage(mainImage ? mainImage.url : imagesData[0].url);
      } else if (productData.image_url) {
        setSelectedImage(productData.image_url);
      }
    } catch (error) {
      console.error('Error fetching product:', error);
      navigate('/404');
    } finally {
      setLoading(false);
    }
  };

  const handleAddToCart = () => {
    if (!product) return;

    const existingItem = cartItems.find(item => item.productId === product.id);
    const currentQty = existingItem ? existingItem.quantity : 0;

    if (product.stock !== null && currentQty >= product.stock) {
      toast.error('Недостаточно товара', {
        description: `В наличии только ${product.stock} шт.`,
      });
      return;
    }

    let updatedCart: CartItem[];
    if (existingItem) {
      updatedCart = cartItems.map(item =>
        item.productId === product.id
          ? { ...item, quantity: item.quantity + 1 }
          : item
      );
    } else {
      updatedCart = [...cartItems, { productId: product.id, quantity: 1 }];
    }

    setCartItems(updatedCart);
    localStorage.setItem('cart', JSON.stringify(updatedCart));

    toast.success('Добавлено в корзину', {
      description: product.title,
    });
  };

  const handleBuyNow = () => {
    if (!user) {
      toast.error('Необходима авторизация', {
        description: 'Войдите в систему для совершения покупки',
      });
      navigate('/login');
      return;
    }

    handleAddToCart();
    navigate('/shop/cart');
  };

  if (loading) {
    return null;
  }

  if (!product) {
    return null;
  }

  const isOutOfStock = product.stock !== null && product.stock === 0;
  const cartQuantity = cartItems.find(item => item.productId === product.id)?.quantity || 0;

  return (
    <>
      <Helmet>
        <title>{product.title} - Магазин | Marseco Group</title>
        <meta 
          name="description" 
          content={product.description || `${product.title} - купить по цене ${product.price_kzt.toLocaleString('ru-RU')} ₸`} 
        />
        <meta property="og:title" content={`${product.title} - Магазин`} />
        <meta 
          property="og:description" 
          content={product.description || `${product.title} - купить по цене ${product.price_kzt.toLocaleString('ru-RU')} ₸`} 
        />
        {selectedImage && (
          <meta property="og:image" content={selectedImage} />
        )}
        <link rel="canonical" href={`${window.location.origin}/product/${product.slug}`} />
      </Helmet>

      <div className="min-h-screen bg-background">
        <div className="container mx-auto px-4 py-8 max-w-7xl">
          {/* Breadcrumbs */}
          <nav className="flex items-center gap-2 text-sm text-muted-foreground mb-6">
            <Link to="/shop" className="hover:text-foreground transition-colors">
              Магазин
            </Link>
            <span>/</span>
            <span className="text-foreground">{product.title}</span>
          </nav>

          <Link to="/shop">
            <Button variant="ghost" className="mb-6">
              <ArrowLeft className="mr-2 h-4 w-4" />
              Назад к каталогу
            </Button>
          </Link>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
            {/* Image Gallery */}
            <div className="space-y-4">
              <Card className="overflow-hidden">
                <div className="aspect-square bg-muted flex items-center justify-center">
                  {selectedImage ? (
                    <img
                      src={selectedImage}
                      alt={product.title}
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <div className="flex flex-col items-center justify-center gap-2">
                      <ImageOff className="w-16 h-16 text-muted-foreground" />
                      <span className="text-muted-foreground">Нет изображения</span>
                    </div>
                  )}
                </div>
              </Card>

              {/* Thumbnails */}
              {images.length > 1 && (
                <div className="grid grid-cols-4 gap-2">
                  {images.map((img) => (
                    <Card
                      key={img.id}
                      className={`cursor-pointer overflow-hidden transition-all ${
                        selectedImage === img.url ? 'ring-2 ring-primary' : ''
                      }`}
                      onClick={() => setSelectedImage(img.url)}
                    >
                      <div className="aspect-square bg-muted">
                        <img
                          src={img.url}
                          alt={`${product.title} - фото ${img.display_order + 1}`}
                          className="w-full h-full object-cover"
                        />
                      </div>
                    </Card>
                  ))}
                </div>
              )}
            </div>

            {/* Product Info */}
            <div className="space-y-6">
              <div>
                <div className="flex gap-2 mb-4 flex-wrap">
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

                <h1 className="text-3xl font-bold mb-4">{product.title}</h1>

                <div className="flex items-baseline gap-4 mb-6">
                  <span className="text-4xl font-bold">{product.price_kzt.toLocaleString('ru-RU')} ₸</span>
                </div>

                {product.stock !== null && (
                  <div className="flex items-center gap-2 text-muted-foreground mb-4">
                    <Package className="w-4 h-4" />
                    <span>
                      {product.stock > 0 ? `В наличии: ${product.stock} шт.` : 'Нет в наличии'}
                    </span>
                  </div>
                )}
              </div>

              {/* Activation Info */}
              {product.is_activation && (
                <Alert>
                  <Info className="h-4 w-4" />
                  <AlertDescription>
                    Покупка засчитывается в месячную активацию (S2) в вашем текущем периоде.
                    Активация начинает действовать через месяц после оплаты годовой подписки.
                  </AlertDescription>
                </Alert>
              )}

              {/* Actions */}
              <div className="space-y-3">
                {cartQuantity > 0 ? (
                  <div className="flex items-center gap-2 p-4 bg-muted rounded-lg">
                    <ShoppingCart className="w-5 h-5" />
                    <span className="font-semibold">В корзине: {cartQuantity} шт.</span>
                  </div>
                ) : null}

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <Button
                    onClick={handleAddToCart}
                    disabled={isOutOfStock}
                    variant="outline"
                    size="lg"
                    className="w-full"
                  >
                    <ShoppingCart className="w-5 h-5 mr-2" />
                    {isOutOfStock ? 'Нет в наличии' : 'В корзину'}
                  </Button>
                  <Button
                    onClick={handleBuyNow}
                    disabled={isOutOfStock}
                    size="lg"
                    className="w-full"
                  >
                    Купить сейчас
                  </Button>
                </div>
              </div>

              {/* Description */}
              {product.description && (
                <Card>
                  <CardContent className="pt-6">
                    <h2 className="text-xl font-semibold mb-3">Описание</h2>
                    <p className="text-muted-foreground whitespace-pre-wrap">{product.description}</p>
                  </CardContent>
                </Card>
              )}
            </div>
          </div>
        </div>
      </div>
    </>
  );
}
