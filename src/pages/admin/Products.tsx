import { useState, useEffect } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { Plus, Pencil, Trash2, Upload, X, Star } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { useAuth } from "@/hooks/useAuth";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";

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
  product_id: string;
  storage_path: string;
  url: string;
  is_main: boolean;
  display_order: number;
};

export default function AdminProducts() {
  const { userRole } = useAuth();
  const isSuperAdmin = userRole === 'superadmin';
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);
  const [formData, setFormData] = useState({
    title: "",
    slug: "",
    description: "",
    price_usd: "",
    price_kzt: "",
    is_activation: false,
    is_popular: false,
    is_new: false,
    image_url: "",
    stock: "",
  });
  const [productImages, setProductImages] = useState<ProductImage[]>([]);
  const [uploadingFiles, setUploadingFiles] = useState<File[]>([]);
  const [uploadPreviews, setUploadPreviews] = useState<string[]>([]);

  useEffect(() => {
    fetchProducts();
  }, []);

  const fetchProducts = async () => {
    try {
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

  const handleOpenDialog = async (product?: Product) => {
    if (product) {
      setEditingProduct(product);
      setFormData({
        title: product.title,
        slug: product.slug,
        description: product.description || "",
        price_usd: product.price_usd.toString(),
        price_kzt: product.price_kzt.toString(),
        is_activation: product.is_activation,
        is_popular: product.is_popular,
        is_new: product.is_new,
        image_url: product.image_url || "",
        stock: product.stock?.toString() || "",
      });
      
      // Load existing images
      const { data: images } = await supabase
        .from('product_images')
        .select('*')
        .eq('product_id', product.id)
        .order('display_order');
      
      setProductImages(images || []);
    } else {
      setEditingProduct(null);
      setFormData({
        title: "",
        slug: "",
        description: "",
        price_usd: "",
        price_kzt: "",
        is_activation: false,
        is_popular: false,
        is_new: false,
        image_url: "",
        stock: "",
      });
      setProductImages([]);
    }
    setUploadingFiles([]);
    setUploadPreviews([]);
    setDialogOpen(true);
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    handleFiles(files);
  };

  const handleFiles = (files: File[]) => {
    const validFiles = files.filter(file => {
      const validTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
      const maxSize = 10 * 1024 * 1024; // 10MB
      
      if (!validTypes.includes(file.type)) {
        toast({
          title: "Ошибка",
          description: `${file.name}: неподдерживаемый формат`,
          variant: "destructive",
        });
        return false;
      }
      
      if (file.size > maxSize) {
        toast({
          title: "Ошибка",
          description: `${file.name}: размер превышает 10 МБ`,
          variant: "destructive",
        });
        return false;
      }
      
      return true;
    });

    if (uploadingFiles.length + validFiles.length + productImages.length > 5) {
      toast({
        title: "Ошибка",
        description: "Максимум 5 изображений на товар",
        variant: "destructive",
      });
      return;
    }

    setUploadingFiles(prev => [...prev, ...validFiles]);
    
    // Create previews
    validFiles.forEach(file => {
      const reader = new FileReader();
      reader.onload = (e) => {
        setUploadPreviews(prev => [...prev, e.target?.result as string]);
      };
      reader.readAsDataURL(file);
    });
  };

  const handleRemoveUploadingFile = (index: number) => {
    setUploadingFiles(prev => prev.filter((_, i) => i !== index));
    setUploadPreviews(prev => prev.filter((_, i) => i !== index));
  };

  const handleRemoveProductImage = async (imageId: string) => {
    const image = productImages.find(img => img.id === imageId);
    if (!image) return;

    try {
      // Delete from storage
      const { error: storageError } = await supabase.storage
        .from('products')
        .remove([image.storage_path]);

      if (storageError) console.error("Storage delete error:", storageError);

      // Delete from database
      const { error: dbError } = await supabase
        .from('product_images')
        .delete()
        .eq('id', imageId);

      if (dbError) throw dbError;

      setProductImages(prev => prev.filter(img => img.id !== imageId));
      toast({ title: "Изображение удалено" });
    } catch (error: any) {
      console.error("Error removing image:", error);
      toast({
        title: "Ошибка",
        description: "Не удалось удалить изображение",
        variant: "destructive",
      });
    }
  };

  const handleSetMainImage = async (imageId: string) => {
    if (!editingProduct) return;

    try {
      // Set all images to not main
      await supabase
        .from('product_images')
        .update({ is_main: false })
        .eq('product_id', editingProduct.id);

      // Set selected image as main
      const { error } = await supabase
        .from('product_images')
        .update({ is_main: true })
        .eq('id', imageId);

      if (error) throw error;

      setProductImages(prev =>
        prev.map(img => ({ ...img, is_main: img.id === imageId }))
      );
      toast({ title: "Главное изображение установлено" });
    } catch (error: any) {
      console.error("Error setting main image:", error);
      toast({
        title: "Ошибка",
        description: "Не удалось установить главное изображение",
        variant: "destructive",
      });
    }
  };

  const uploadImages = async (productId: string) => {
    for (let i = 0; i < uploadingFiles.length; i++) {
      const file = uploadingFiles[i];
      const fileExt = file.name.split('.').pop();
      const fileName = `${productId}/${Date.now()}-${i}.${fileExt}`;

      try {
        // Upload to storage
        const { error: uploadError } = await supabase.storage
          .from('products')
          .upload(fileName, file);

        if (uploadError) throw uploadError;

        // Get public URL
        const { data: { publicUrl } } = supabase.storage
          .from('products')
          .getPublicUrl(fileName);

        // Save to database
        const { error: dbError } = await supabase
          .from('product_images')
          .insert({
            product_id: productId,
            storage_path: fileName,
            url: publicUrl,
            is_main: productImages.length === 0 && i === 0,
            display_order: productImages.length + i
          });

        if (dbError) throw dbError;
      } catch (error: any) {
        console.error("Error uploading image:", error);
        toast({
          title: "Ошибка",
          description: `Ошибка загрузки ${file.name}`,
          variant: "destructive",
        });
      }
    }
  };

  const handleSave = async () => {
    try {
      // Валидация: название обязательно
      if (!formData.title.trim()) {
        toast({
          title: "Ошибка",
          description: "Необходимо указать название товара",
          variant: "destructive",
        });
        return;
      }

      // Валидация: slug обязателен
      if (!formData.slug.trim()) {
        toast({
          title: "Ошибка",
          description: "Необходимо указать Slug (URL) товара",
          variant: "destructive",
        });
        return;
      }

      // Валидация: хотя бы одна цена должна быть заполнена
      if (!formData.price_usd && !formData.price_kzt) {
        toast({
          title: "Ошибка",
          description: "Необходимо указать хотя бы одну цену (USD или KZT)",
          variant: "destructive",
        });
        return;
      }

      const productData = {
        title: formData.title.trim(),
        slug: formData.slug.trim(),
        description: formData.description || null,
        price_usd: formData.price_usd ? parseFloat(formData.price_usd) : null,
        price_kzt: formData.price_kzt ? parseFloat(formData.price_kzt) : null,
        is_activation: formData.is_activation,
        is_popular: formData.is_popular,
        is_new: formData.is_new,
        image_url: formData.image_url || null,
        stock: formData.stock ? parseInt(formData.stock) : null,
      };

      let productId = editingProduct?.id;

      if (editingProduct) {
        const { error } = await supabase
          .from("products")
          .update(productData)
          .eq("id", editingProduct.id);
        if (error) throw error;
        toast({ title: "Товар обновлен" });
      } else {
        const { data, error } = await supabase
          .from("products")
          .insert(productData)
          .select()
          .single();
        if (error) throw error;
        productId = data.id;
        toast({ title: "Товар добавлен" });
      }

      // Upload new images
      if (uploadingFiles.length > 0 && productId) {
        await uploadImages(productId);
      }

      setDialogOpen(false);
      fetchProducts();
    } catch (error: any) {
      console.error("Error saving product:", error);
      
      // Обрабатываем различные типы ошибок
      let errorMessage = 'Не удалось сохранить товар';
      
      if (error.message?.includes('хотя бы одну цену')) {
        errorMessage = error.message;
      } else if (error.message?.includes('duplicate key') && error.message?.includes('products_slug_key')) {
        errorMessage = 'Товар с таким Slug (URL) уже существует. Пожалуйста, используйте уникальный slug.';
      } else if (error.message?.includes('duplicate key')) {
        errorMessage = 'Такой товар уже существует. Проверьте уникальность данных.';
      } else if (error.message) {
        errorMessage = error.message;
      }
      
      toast({
        title: "Ошибка",
        description: errorMessage,
        variant: "destructive",
      });
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm("Удалить этот товар?")) return;

    try {
      // Delete associated images first
      const { data: images } = await supabase
        .from('product_images')
        .select('storage_path')
        .eq('product_id', id);

      if (images && images.length > 0) {
        const paths = images.map(img => img.storage_path);
        await supabase.storage.from('products').remove(paths);
      }

      const { error } = await supabase.from("products").delete().eq("id", id);
      if (error) throw error;
      toast({ title: "Товар удален" });
      fetchProducts();
    } catch (error) {
      console.error("Error deleting product:", error);
      toast({
        title: "Ошибка",
        description: "Не удалось удалить товар",
        variant: "destructive",
      });
    }
  };

  if (loading) {
    return <div className="p-8">Загрузка...</div>;
  }

  return (
    <div className="p-8">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-3xl font-bold">Управление товарами</h1>
        {isSuperAdmin && (
          <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
            <DialogTrigger asChild>
              <Button onClick={() => handleOpenDialog()}>
                <Plus className="w-4 h-4 mr-2" />
                Добавить товар
              </Button>
            </DialogTrigger>
          <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>
                {editingProduct ? "Редактировать товар" : "Новый товар"}
              </DialogTitle>
              <p className="text-sm text-muted-foreground mt-2">
                Можно заполнить одну валюту — вторая рассчитается автоматически при сохранении
              </p>
            </DialogHeader>
            <div className="space-y-4">
              <div>
                <Label>Название *</Label>
                <Input
                  value={formData.title}
                  onChange={(e) =>
                    setFormData({ ...formData, title: e.target.value })
                  }
                  placeholder="Название товара"
                  required
                />
              </div>
              <div>
                <Label>Slug (URL) *</Label>
                <Input
                  value={formData.slug}
                  onChange={(e) =>
                    setFormData({ ...formData, slug: e.target.value })
                  }
                  placeholder="unique-product-slug"
                  required
                />
                <p className="text-xs text-muted-foreground mt-1">
                  Уникальный идентификатор для URL (например: activation-pack-1)
                </p>
              </div>
              <div>
                <Label>Описание</Label>
                <Textarea
                  value={formData.description}
                  onChange={(e) =>
                    setFormData({ ...formData, description: e.target.value })
                  }
                />
              </div>

              {/* Image Upload Section */}
              <div className="space-y-2">
                <Label>Фотографии товара (до 5)</Label>
                <div className="border-2 border-dashed border-border rounded-lg p-4 hover:border-primary/50 transition-colors">
                  <input
                    type="file"
                    accept="image/jpeg,image/jpg,image/png,image/webp"
                    multiple
                    onChange={handleFileSelect}
                    className="hidden"
                    id="file-upload"
                  />
                  <label
                    htmlFor="file-upload"
                    className="flex flex-col items-center justify-center gap-2 cursor-pointer"
                  >
                    <Upload className="w-8 h-8 text-muted-foreground" />
                    <p className="text-sm text-muted-foreground">
                      Нажмите для выбора или перетащите файлы
                    </p>
                    <p className="text-xs text-muted-foreground">
                      JPG, PNG, WEBP до 10 МБ
                    </p>
                  </label>
                </div>

                {/* Preview existing images */}
                {productImages.length > 0 && (
                  <div className="grid grid-cols-3 gap-2">
                    {productImages.map((image) => (
                      <div key={image.id} className="relative group">
                        <img
                          src={image.url}
                          alt="Product"
                          className="w-full h-24 object-cover rounded border"
                        />
                        <div className="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity rounded flex items-center justify-center gap-1">
                          <Button
                            size="sm"
                            variant={image.is_main ? "default" : "secondary"}
                            onClick={() => handleSetMainImage(image.id)}
                            className="h-7 px-2"
                            title="Сделать главным"
                          >
                            <Star className={`w-3 h-3 ${image.is_main ? 'fill-current' : ''}`} />
                          </Button>
                          <Button
                            size="sm"
                            variant="destructive"
                            onClick={() => handleRemoveProductImage(image.id)}
                            className="h-7 px-2"
                            title="Удалить"
                          >
                            <X className="w-3 h-3" />
                          </Button>
                        </div>
                        {image.is_main && (
                          <div className="absolute top-1 left-1 bg-primary text-primary-foreground text-xs px-1.5 py-0.5 rounded">
                            Главное
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                )}

                {/* Preview uploading images */}
                {uploadPreviews.length > 0 && (
                  <div className="grid grid-cols-3 gap-2">
                    {uploadPreviews.map((preview, index) => (
                      <div key={index} className="relative group">
                        <img
                          src={preview}
                          alt="Upload preview"
                          className="w-full h-24 object-cover rounded border border-primary"
                        />
                        <div className="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity rounded flex items-center justify-center">
                          <Button
                            size="sm"
                            variant="destructive"
                            onClick={() => handleRemoveUploadingFile(index)}
                            className="h-7 px-2"
                            title="Удалить"
                          >
                            <X className="w-3 h-3" />
                          </Button>
                        </div>
                        <div className="absolute top-1 left-1 bg-secondary text-secondary-foreground text-xs px-1.5 py-0.5 rounded">
                          Новое
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <Label>Цена USD</Label>
                  <Input
                    type="number"
                    step="0.01"
                    value={formData.price_usd}
                    onChange={(e) =>
                      setFormData({ ...formData, price_usd: e.target.value })
                    }
                  />
                </div>
                <div>
                  <Label>Цена KZT</Label>
                  <Input
                    type="number"
                    step="0.01"
                    value={formData.price_kzt}
                    onChange={(e) =>
                      setFormData({ ...formData, price_kzt: e.target.value })
                    }
                  />
                </div>
              </div>
              <div>
                <Label>Количество на складе (оставьте пустым для неограниченного)</Label>
                <Input
                  type="number"
                  value={formData.stock}
                  onChange={(e) =>
                    setFormData({ ...formData, stock: e.target.value })
                  }
                />
              </div>
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <Label>Активационный товар</Label>
                  <Switch
                    checked={formData.is_activation}
                    onCheckedChange={(checked) =>
                      setFormData({ ...formData, is_activation: checked })
                    }
                  />
                </div>
                <div className="flex items-center justify-between">
                  <Label>Популярный</Label>
                  <Switch
                    checked={formData.is_popular}
                    onCheckedChange={(checked) =>
                      setFormData({ ...formData, is_popular: checked })
                    }
                  />
                </div>
                <div className="flex items-center justify-between">
                  <Label>Новинка</Label>
                  <Switch
                    checked={formData.is_new}
                    onCheckedChange={(checked) =>
                      setFormData({ ...formData, is_new: checked })
                    }
                  />
                </div>
              </div>
              <Button 
                onClick={handleSave} 
                className="w-full"
                disabled={
                  !formData.title.trim() || 
                  !formData.slug.trim() || 
                  (!formData.price_usd && !formData.price_kzt)
                }
              >
                {editingProduct ? "Сохранить" : "Добавить"}
              </Button>
            </div>
          </DialogContent>
        </Dialog>
        )}
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Каталог товаров</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Название</TableHead>
                <TableHead>Цена (₸)</TableHead>
                <TableHead>Склад</TableHead>
                <TableHead>Статус</TableHead>
                <TableHead>Действия</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {products.map((product) => (
                <TableRow key={product.id}>
                  <TableCell className="font-medium">{product.title}</TableCell>
                  <TableCell>{product.price_kzt.toLocaleString('ru-RU')} ₸</TableCell>
                  <TableCell>
                    {product.stock !== null ? `${product.stock} шт.` : "∞"}
                  </TableCell>
                  <TableCell>
                    <div className="flex gap-1 flex-wrap">
                      {product.is_activation && (
                        <Badge variant="default">Активац.</Badge>
                      )}
                      {product.is_popular && (
                        <Badge variant="secondary">Популярн.</Badge>
                      )}
                      {product.is_new && (
                        <Badge variant="outline">Новинка</Badge>
                      )}
                    </div>
                  </TableCell>
                  <TableCell>
                    <div className="flex gap-2">
                      {isSuperAdmin && (
                        <>
                          <Button
                            size="icon"
                            variant="ghost"
                            onClick={() => handleOpenDialog(product)}
                          >
                            <Pencil className="w-4 h-4" />
                          </Button>
                          <Button
                            size="icon"
                            variant="ghost"
                            onClick={() => handleDelete(product.id)}
                          >
                            <Trash2 className="w-4 h-4" />
                          </Button>
                        </>
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
